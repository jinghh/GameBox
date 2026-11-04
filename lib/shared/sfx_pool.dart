/// 自管 AudioPlayer 池——坦克/吃豆人等游戏共用的音效底层。
///
/// 为什么不用 audioplayers 的 AudioPool：
///  AudioPool 在部分 Android 设备（如 HyperOS）上，音效播完的 onCompletion 回调
///  会触发内部 prepareAsync，偶发 IllegalStateException 直接杀进程（越玩越易触发，
///  典型表现为「第二局闪退」）。该异常在 native 线程抛出，Dart 层 try-catch 抓不到。
///
/// 本池用默认 ReleaseMode.stop：播完后 player 保持 loaded、不 reset，
/// 从而避开那条 native 崩溃路径。预加载一次、运行时无 setSource/解码，既不崩也不卡。
///
/// 加载支持两种来源：AssetSource（素材 wav）与 BytesSource（代码合成，零素材）。
/// 播放只走 setVolume + seek(0) + resume，永不重新 setSource。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'sound_store.dart';

/// 一个音效名对应一组预加载的 player，播放时轮转取用，连发不互相打断。
/// 同名节流由 [SfxPool.throttleMs] 控制。所有错误都被吞掉：音效绝不影响游戏逻辑。
class SfxPool {
  final Map<String, List<AudioPlayer>> _pools = {};
  final Map<String, int> _cursor = {}; // 轮转游标（支持同名并发）
  final Map<String, double> _vol = {};
  final Map<String, int> _lastAt = {};

  final Stopwatch _watch = Stopwatch();

  /// 生效静音：实例内静音（如客机强制静音）| 全局 kMuted。
  bool muted = false;

  /// 同名音效最小间隔（毫秒）。坦克 60ms、吃豆人 45ms 由各游戏构造时传入。
  int throttleMs = 60;

  bool _ready = false;

  bool get isReady => _ready;

  /// 加载一个 wav 素材。单个 player 失败只跳过该 player，不影响其余。
  Future<void> loadAsset(String name, String asset, int max, double vol) async {
    await _load(name, max, vol, (p) => p.setSource(AssetSource(asset)));
  }

  /// 加载一段代码合成的音频字节（零素材，用于经典芯片音）。
  Future<void> loadBytes(String name, Uint8List bytes, int max, double vol) async {
    await _load(name, max, vol, (p) => p.setSource(BytesSource(bytes)));
  }

  Future<void> _load(
      String name, int max, double vol,
      Future<void> Function(AudioPlayer) setSource) async {
    if (_pools.containsKey(name)) return;
    final list = <AudioPlayer>[];
    for (int i = 0; i < max; i++) {
      try {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(vol);
        await setSource(p);
        list.add(p);
      } on Object {
        // 单个 player 加载失败跳过（不影响其余）
      }
    }
    if (list.isEmpty) return;
    _pools[name] = list;
    _cursor[name] = 0;
    _vol[name] = vol;
  }

  /// 标记加载完成并启动节流计时。各游戏加载完所有音效后调用一次。
  void finish() {
    if (_ready) return;
    if (_pools.isEmpty) return;
    _watch.start();
    _ready = true;
  }

  /// 播放一个音效。可选 [volume] 覆盖该音效的默认音量（如受道具影响的开火音）。
  void play(String name, {double? volume}) {
    if (muted || kMuted.value || !_ready) return;
    final pool = _pools[name];
    if (pool == null || pool.isEmpty) return;
    final now = _watch.elapsedMilliseconds;
    if (now - (_lastAt[name] ?? -9999) < throttleMs) return; // 同名节流
    _lastAt[name] = now;
    final i = (_cursor[name] ?? 0) % pool.length;
    _cursor[name] = i + 1; // 轮转，连发不打断
    _start(pool[i], volume ?? (_vol[name] ?? 0.5));
  }

  Future<void> _start(AudioPlayer p, double vol) async {
    try {
      await p.setVolume(vol);
      await p.seek(Duration.zero);
      await p.resume();
    } on Object {
      // 忽略任何音频错误，绝不影响游戏
    }
  }

  void dispose() {
    for (final list in _pools.values) {
      for (final p in list) {
        try {
          p.dispose();
        } on Object {
          // 忽略释放过程中的异常
        }
      }
    }
    _pools.clear();
    _vol.clear();
    _cursor.clear();
    _lastAt.clear();
    _ready = false;
  }
}

// ---- 合成 wav 的公共工具（吃豆人 waka/死亡/水果等零素材音效）----

double _pulse(double phase) => sin(phase) >= 0 ? 1.0 : -1.0;

/// 线性起音、线性释音的包络：[p] 为 0..1 的进度。
double _env(double p) =>
    p < 0.05 ? p / 0.05 : (p > 0.8 ? (1 - p) / 0.2 : 1.0);

/// 把 16bit 单声道采样拼成一个 wav 文件字节。
Uint8List buildWav(Int16List samples, int sr) {
  final dataSize = samples.length * 2;
  final b = BytesBuilder();
  void s(String str) => b.add(str.codeUnits);
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  s('RIFF');
  u32(36 + dataSize);
  s('WAVE');
  s('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sr);
  u32(sr * 2);
  u16(2);
  u16(16);
  s('data');
  u32(dataSize);
  b.add(samples.buffer.asUint8List());
  return b.toBytes();
}

/// 合成一段「若干音节的方波」，每个音节可指定频率/时长/音量。
/// [notes] 为 (频率Hz, 时长秒, 音量) 序列，末尾自动留 50ms 静音间隔。
Uint8List synthNotes(
    List<({double f, double dur, double amp})> notes,
    [int sr = 22050]) {
  final n = notes
      .map((e) => (e.dur * sr).round() + (sr / 200).round())
      .reduce((a, b) => a + b);
  final out = Int16List(n);
  var i = 0;
  for (final e in notes) {
    final nn = (e.dur * sr).round();
    for (var k = 0; k < nn; k++) {
      final t = k / sr;
      final v = _pulse(2 * 3.14159265 * e.f * t) * e.amp * _env(k / nn.toDouble());
      out[i++] = (v * 32767).toInt();
    }
    for (var k = 0; k < (sr / 200).round(); k++) {
      out[i++] = 0;
    }
  }
  return buildWav(out, sr);
}

/// 合成一个短促方波 blip：[hi] 为高音音节，否则低音。经典「waka」吃豆声。
Uint8List synthWaka(bool hi) => synthNotes([
      (f: hi ? 200.0 : 150.0, dur: 0.045, amp: 0.45),
      (f: hi ? 200.0 : 150.0, dur: 0.045, amp: 0.45),
    ]);

/// 经典死亡音：下行三连音。
Uint8List synthDeath() => synthNotes([
      (f: 523.25, dur: 0.10, amp: 0.40),
      (f: 440.00, dur: 0.10, amp: 0.40),
      (f: 329.63, dur: 0.10, amp: 0.40),
      (f: 261.63, dur: 0.16, amp: 0.40),
      (f: 196.00, dur: 0.40, amp: 0.40),
    ]);

/// 经典水果音：上行两个短音节（樱桃）。
Uint8List synthFruit() => synthNotes([
      (f: 659.25, dur: 0.07, amp: 0.40),
      (f: 880.00, dur: 0.07, amp: 0.40),
      (f: 1046.50, dur: 0.12, amp: 0.40),
    ]);
