// 背景音乐(BGM):代码实时合成循环芯片音乐(chiptune),生成 WAV 字节流,
// 用 audioplayers 循环播放。零音频素材、零版权、纯单机。
// 受全局静音(kMuted)控制。两个主题:进行曲风格(坦克)/ 弹跳风格(泡泡堂)。
//
// 为什么不用素材文件:assets 仅含短音效,无 BGM;本方案无需额外资源即可出声。

import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'sound_store.dart';

/// 生成一段短循环旋律的 WAV 字节(PCM16 / mono / 22050Hz)。
class BgmTheme {
  final int bpm;
  final List<List<int>> chords; // 每 4 拍一个和弦(midi)
  final List<int> bass; // 每和弦根音(midi,低八度)
  final int melodyOctave; // 旋律相对和弦的八度偏移
  final double melodyVol;
  final double bassVol;
  const BgmTheme({
    required this.bpm,
    required this.chords,
    required this.bass,
    this.melodyOctave = 0,
    this.melodyVol = 0.22,
    this.bassVol = 0.20,
  });

  /// 进行曲风格:稳健的 I–V–vi–IV,方波旋律 + 正弦低音。
  static const BgmTheme march = BgmTheme(
    bpm: 116,
    chords: [
      [60, 64, 67], // C
      [55, 59, 62], // G
      [57, 60, 64], // Am
      [53, 57, 60], // F
    ],
    bass: [36, 31, 33, 29],
    melodyOctave: 0,
    melodyVol: 0.22,
    bassVol: 0.22,
  );

  /// 弹跳风格:明快 C–F–G–C,高八度,更快。
  static const BgmTheme bounce = BgmTheme(
    bpm: 132,
    chords: [
      [60, 64, 67],
      [65, 69, 72],
      [67, 71, 74],
      [60, 64, 67],
    ],
    bass: [36, 41, 43, 36],
    melodyOctave: 12,
    melodyVol: 0.18,
    bassVol: 0.18,
  );
}

double _freq(int midi) => 440.0 * pow(2, (midi - 69) / 12);

// 方波(芯片味)
double _pulse(double phase) => (sin(phase)).sign == 0 ? 0 : ((sin(phase) > 0) ? 1.0 : -1.0);

// 单拍内的拨弦包络(快起、尾部收),消除音符边界咔哒声
double _env(double p) {
  if (p < 0.06) return p / 0.06;
  if (p > 0.86) return (1 - p) / 0.14;
  return 1.0;
}

Uint8List _buildWav(Int16List samples, int sr) {
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
  u16(1); // PCM
  u16(1); // mono
  u32(sr);
  u32(sr * 2);
  u16(2);
  u16(16);
  s('data');
  u32(dataSize);
  b.add(samples.buffer.asUint8List());
  return b.toBytes();
}

/// 合成并循环播放某个主题的 BGM。
class ChiptuneBgm {
  final BgmTheme theme;
  final double volume;
  ChiptuneBgm({required this.theme, this.volume = 0.32});

  final AudioPlayer _player = AudioPlayer();
  Uint8List? _wav;
  bool _started = false;
  bool _extMuted = false; // 外部(本游戏)静音开关

  bool get _muted => kMuted.value || _extMuted;

  void _applyVolume() {
    try {
      _player.setVolume(_muted ? 0.0 : volume);
    } on Object {
      // 忽略音频错误,绝不影响游戏
    }
  }

  /// 外部静音(如坦克的本地静音键),与全局 kMuted 取并集。
  void setExternalMute(bool m) {
    _extMuted = m;
    _applyVolume();
  }

  Future<void> init() async {
    _wav = _generate();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      _applyVolume();
    } on Object {
      // 忽略
    }
    kMuted.addListener(_applyVolume);
  }

  Future<void> start() async {
    final w = _wav;
    if (w == null || _started) return;
    _started = true;
    try {
      await _player.play(BytesSource(w));
    } on Object {
      _started = false;
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    try {
      await _player.stop();
    } on Object {
      // 忽略
    }
  }

  void dispose() {
    kMuted.removeListener(_applyVolume);
    _player.dispose();
  }

  Uint8List _generate() {
    const sr = 22050;
    final beat = 60.0 / theme.bpm;
    final beats = theme.chords.length * 4; // 每和弦 4 拍
    final total = beat * beats;
    final n = (total * sr).toInt();
    final out = Int16List(n);
    for (int i = 0; i < n; i++) {
      final t = i / sr;
      final beatIdx = (t / beat).floor();
      final pBeat = (t % beat) / beat; // 0..1 当前拍内
      final chordIdx = beatIdx ~/ 4;
      final chord = theme.chords[chordIdx % theme.chords.length];
      // 旋律:在和弦三个音里循环(0,1,2,1 模式),加八度偏移
      const pattern = [0, 1, 2, 1, 0, 2, 1, 2];
      final tone = chord[pattern[beatIdx % pattern.length] % chord.length] +
          theme.melodyOctave;
      final mf = _freq(tone);
      final mel = _pulse(2 * pi * mf * t) * theme.melodyVol * _env(pBeat);
      // 低音:每和弦根音,2 拍换一次包络
      final bf = _freq(theme.bass[chordIdx % theme.bass.length]);
      final pBass = (t % (beat * 2)) / (beat * 2);
      final bassW = sin(2 * pi * bf * t) * theme.bassVol * _env(pBass);
      var v = mel + bassW;
      if (v > 0.95) v = 0.95;
      if (v < -0.95) v = -0.95;
      out[i] = (v * 32767).toInt();
    }
    return _buildWav(out, sr);
  }
}
