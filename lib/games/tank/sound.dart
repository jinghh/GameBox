// 音效服务：每个音效预加载一组 AudioPlayer（默认 ReleaseMode.stop），
// 播放只走 setVolume + seek(0) + resume，永不重新 setSource。
//
// 为什么不用 audioplayers 的 AudioPool：
//  AudioPool 在部分 Android 设备（如 HyperOS）上，音效播完的 onCompletion 回调
//  会触发内部 prepareAsync，偶发 IllegalStateException 直接杀进程（越玩越易触发，
//  典型表现为「第二局闪退」）。该异常在 native 线程抛出，Dart 层 try-catch 抓不到。
//
// 自管池用默认 ReleaseMode.stop：播完后 player 保持 loaded、不 reset，
// 从而避开那条 native 崩溃路径。预加载一次、运行时无 setSource/解码，既不崩也不卡。

import 'package:audioplayers/audioplayers.dart';

import '../../shared/sound_store.dart';

class SoundService {
  final Map<String, List<AudioPlayer>> _pools = {};
  final Map<String, int> _cursor = {}; // 轮转游标（支持同名并发）
  final Map<String, double> _vol = {};
  bool muted = false;
  bool _ready = false;

  static const String _dir = 'sounds/';

  // 音效定义：文件名 -> (并发 player 数, 默认音量)
  static const Map<String, ({int max, double vol})> _defs = {
    'shoot': (max: 2, vol: 0.40),
    'enemy_shoot': (max: 3, vol: 0.18),
    'hit': (max: 3, vol: 0.30),
    'explosion': (max: 2, vol: 0.50),
    'big_explosion': (max: 1, vol: 0.60),
    'steel': (max: 2, vol: 0.25),
    'powerup': (max: 1, vol: 0.50),
    'start': (max: 1, vol: 0.55),
    'gameover': (max: 1, vol: 0.60),
  };

  // 同名音效节流计时
  final Stopwatch _watch = Stopwatch();
  final Map<String, int> _lastAt = {};

  Future<void> init() async {
    if (_ready) return;
    final loaded = <String, List<AudioPlayer>>{};
    try {
      for (final e in _defs.entries) {
        final name = e.key;
        final def = e.value;
        final list = <AudioPlayer>[];
        for (int i = 0; i < def.max; i++) {
          try {
            final p = AudioPlayer();
            await p.setReleaseMode(ReleaseMode.stop);
            await p.setVolume(def.vol);
            await p.setSource(AssetSource('$_dir$name.wav'));
            list.add(p);
          } on Object {
            // 单个 player 加载失败跳过（不影响其余）
          }
        }
        if (list.isNotEmpty) {
          loaded[name] = list;
          _cursor[name] = 0;
          _vol[name] = def.vol;
        }
      }
    } on Object {
      for (final list in loaded.values) {
        for (final p in list) {
          try {
            p.dispose();
          } on Object {
            // 忽略释放过程中的异常
          }
        }
      }
      _ready = false;
      return;
    }
    if (loaded.isNotEmpty) {
      _pools.addAll(loaded);
      _watch.start();
      _ready = true;
    }
  }

  void play(String name, {double? volume}) {
    if (muted || kMuted.value || !_ready) return;
    final pool = _pools[name];
    if (pool == null || pool.isEmpty) return;
    final now = _watch.elapsedMilliseconds;
    if (now - (_lastAt[name] ?? -9999) < 60) return; // 同名节流
    _lastAt[name] = now;
    final i = (_cursor[name] ?? 0) % pool.length;
    _cursor[name] = i + 1;
    _start(pool[i], volume ?? (_vol[name] ?? 0.5)); // 轮转，连发不打断
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
    _ready = false;
  }
}
