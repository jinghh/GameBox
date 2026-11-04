// 坦克音效：基于共享的 [SfxPool]（自管 player 池）。
//
// 池机制与「为什么不用 AudioPool」的说明见 shared/sfx_pool.dart，
// 此处只保留坦克自己的音效定义表与对外接口。

import '../../shared/sfx_pool.dart';

class SoundService {
  final SfxPool _pool = SfxPool()..throttleMs = 60;

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

  bool get muted => _pool.muted;
  set muted(bool v) => _pool.muted = v;

  Future<void> init() async {
    for (final e in _defs.entries) {
      await _pool.loadAsset(e.key, '$_dir${e.key}.wav', e.value.max, e.value.vol);
    }
    _pool.finish();
  }

  void play(String name, {double? volume}) => _pool.play(name, volume: volume);

  void dispose() => _pool.dispose();
}
