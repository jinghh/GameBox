// 背景音乐(BGM):代码实时合成循环芯片音乐(chiptune),生成 WAV 字节流,
// 用 audioplayers 循环播放。零音频素材、零版权、纯单机。
// 受全局静音(kMuted)控制。两个主题:进行曲风格(坦克)/ 弹跳风格(泡泡堂)。
//
// 为什么不用素材文件:assets 仅含短音效,无 BGM;本方案无需额外资源即可出声。

import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'sfx_pool.dart';
import 'sound_store.dart';

/// 生成一段短循环旋律的 WAV 字节(PCM16 / mono / 22050Hz)。
class BgmTheme {
  final int bpm;
  final List<List<int>>? chords; // 和弦垫(每 4 拍一个和弦,midi);可选
  final List<int>? bass; // 旧式低音:每和弦根音(midi,低八度);可选
  final List<int?>? melody; // 显式旋律:每元素 = melodyStep 拍一个音,null=休止
  final double melodyStep; // 每个旋律音占的拍数(0.5 = 八分音符)
  final List<int?>? bassLine; // 显式低音:每元素 = bassStep 拍一个音,null=休止
  final double bassStep;
  final int melodyOctave; // 旋律相对偏移八度
  final double melodyVol;
  final double bassVol;
  final double chordVol; // 和弦垫音量(0 = 不加垫)

  const BgmTheme({
    required this.bpm,
    this.chords,
    this.bass,
    this.melody,
    this.melodyStep = 0.5,
    this.bassLine,
    this.bassStep = 0.5,
    this.melodyOctave = 0,
    this.melodyVol = 0.22,
    this.bassVol = 0.20,
    this.chordVol = 0.0,
  });

  /// 进行曲风格:稳健的 I–V–vi–IV,方波旋律 + 正弦低音(原坦克 BGM,保留备用)。
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

  /// 弹跳风格:明快 C–F–G–C,高八度,更快(泡泡堂)。
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

  /// 经典坦克大战风格:还原 FC《Battle City》开场循环旋律(8-bit 进行曲)。
  /// 旋律按八分音符栅格(melodyStep=0.5),低音每小节一个根音(Am–F–C–G)。
  static const BgmTheme battleCity = BgmTheme(
    bpm: 138,
    melodyStep: 0.5,
    bassStep: 0.5,
    melodyVol: 0.26,
    bassVol: 0.22,
    chordVol: 0.05,
    chords: [
      [57, 60, 64], // Am
      [53, 57, 60], // F
      [60, 64, 67], // C
      [55, 59, 62], // G
    ],
    melody: [
      76, 76, 76, 76, 69, 69, 69, 69, // E5×4  A4×4
      76, 76, 74, 74, 72, 72, 71, 71, // E5×2 D5×2  C5×2 B4×2
      76, 76, 76, 76, 69, 69, 69, 69, // E5×4  A4×4
      72, 72, 71, 71, 69, 69, 69, 69, // C5×2 B4×2  A4×4
      69, 69, 71, 71, 72, 72, 74, 74, // A4×2 B4×2  C5×2 D5×2
      76, 76, 74, 74, 72, 72, 71, 71, // E5×2 D5×2  C5×2 B4×2
      69, 69, 71, 71, 72, 72, 74, 74, // A4×2 B4×2  C5×2 D5×2
      76, 76, 74, 74, 72, 72, 71, 71, // E5×2 D5×2  C5×2 B4×2
    ],
    bassLine: [
      45, 45, 45, 45, 45, 45, 45, 45, // Am 根音 A2
      41, 41, 41, 41, 41, 41, 41, 41, // F
      48, 48, 48, 48, 48, 48, 48, 48, // C
      43, 43, 43, 43, 43, 43, 43, 43, // G
      45, 45, 45, 45, 45, 45, 45, 45, // Am
      41, 41, 41, 41, 41, 41, 41, 41, // F
      48, 48, 48, 48, 48, 48, 48, 48, // C
      43, 43, 43, 43, 43, 43, 43, 43, // G
    ],
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

/// 把 16bit 单声道采样拼成 wav。与音效合成共用 sfx_pool.dart 里的 [buildWav]。
Uint8List _buildWav(Int16List samples, int sr) => buildWav(samples, sr);

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
    // 总时长由旋律/低音序列决定;都没有则退回和弦长度。
    final melodyLen = theme.melody?.length ?? 0;
    final bassLen = theme.bassLine?.length ?? 0;
    final chordBeats = (theme.chords?.length ?? 1) * 4;
    final totalBeats = melodyLen > 0
        ? melodyLen * theme.melodyStep
        : (bassLen > 0 ? bassLen * theme.bassStep : chordBeats);
    final total = beat * totalBeats;
    final n = (total * sr).toInt();
    final out = Int16List(n);
    for (int i = 0; i < n; i++) {
      final t = i / sr;
      var v = 0.0;

      // ---- 旋律 ----
      if (theme.melody != null) {
        final stepDur = beat * theme.melodyStep;
        final p = (t % stepDur) / stepDur;
        final idx = (t / stepDur).floor();
        final tone = theme.melody![idx % theme.melody!.length];
        if (tone != null) {
          final mf = _freq(tone + theme.melodyOctave);
          v += _pulse(2 * pi * mf * t) * theme.melodyVol * _env(p);
        }
      } else if (theme.chords != null) {
        // 旧式:在和弦三音里循环(0,1,2,1 模式)
        final beatIdx = (t / beat).floor();
        final pBeat = (t % beat) / beat;
        final chordIdx = beatIdx ~/ 4;
        final chord = theme.chords![chordIdx % theme.chords!.length];
        const pattern = [0, 1, 2, 1, 0, 2, 1, 2];
        final tone =
            chord[pattern[beatIdx % pattern.length] % chord.length] +
                theme.melodyOctave;
        final mf = _freq(tone);
        v += _pulse(2 * pi * mf * t) * theme.melodyVol * _env(pBeat);
      }

      // ---- 低音 ----
      if (theme.bassLine != null) {
        final bstep = beat * theme.bassStep;
        final p = (t % bstep) / bstep;
        final bidx = (t / bstep).floor();
        final btone = theme.bassLine![bidx % theme.bassLine!.length];
        if (btone != null) {
          v += sin(2 * pi * _freq(btone) * t) * theme.bassVol * _env(p);
        }
      } else if (theme.bass != null && theme.chords != null) {
        // 旧式:每和弦根音,2 拍换一次包络
        final beatIdx = (t / beat).floor();
        final chordIdx = beatIdx ~/ 4;
        final bf = _freq(theme.bass![chordIdx % theme.bass!.length]);
        final pBass = (t % (beat * 2)) / (beat * 2);
        v += sin(2 * pi * bf * t) * theme.bassVol * _env(pBass);
      }

      // ---- 和弦垫(增加厚度,音量很低) ----
      if (theme.chords != null && theme.chordVol > 0) {
        final beatIdx = (t / beat).floor();
        final chordIdx = beatIdx ~/ 4;
        final chord = theme.chords![chordIdx % theme.chords!.length];
        for (final c in chord) {
          v += sin(2 * pi * _freq(c) * t) * theme.chordVol * 0.5;
        }
      }

      v = v.clamp(-0.95, 0.95);
      out[i] = (v * 32767).toInt();
    }
    return _buildWav(out, sr);
  }
}
