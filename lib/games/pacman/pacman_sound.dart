/// 吃豆人音效：基于共享的 [SfxPool]（自管 player 池）。
///
/// 素材复用项目的 tank 音效 wav（start/powerup/hit），经典 waka / 死亡 / 水果
/// 则代码合成，零素材、零版权。受全局 kMuted 控制。
library;

import '../../shared/sfx_pool.dart';

/// [SfxPool] 但吃豆人同名节流更紧（吃豆节奏快，45ms）。
class PacmanSound {
  final SfxPool _pool = SfxPool()..throttleMs = 45;

  // 吃豆音效高低音交替（经典「waka」双音）
  bool _wakaToggle = false;

  bool get muted => _pool.muted;
  set muted(bool v) => _pool.muted = v;

  Future<void> init() async {
    // 素材类：复用 tank 的 wav
    await _pool.loadAsset('start', 'sounds/start.wav', 1, 0.5);
    await _pool.loadAsset('energizer', 'sounds/powerup.wav', 2, 0.45);
    await _pool.loadAsset('eatGhost', 'sounds/hit.wav', 2, 0.35);

    // 合成类：经典街机音，避免与 tank 素材混同
    await _pool.loadBytes('waka0', synthWaka(false), 3, 0.32);
    await _pool.loadBytes('waka1', synthWaka(true), 3, 0.32);
    await _pool.loadBytes('death', synthDeath(), 1, 0.6);
    await _pool.loadBytes('fruit', synthFruit(), 1, 0.45);

    _pool.finish();
  }

  void _play(String name) => _pool.play(name);

  void eat() {
    _pool.play(_wakaToggle ? 'waka1' : 'waka0');
    _wakaToggle = !_wakaToggle;
  }

  void energizer() => _play('energizer');
  void eatGhost() => _play('eatGhost');
  void fruit() => _play('fruit');
  void death() => _play('death');
  void start() => _play('start');

  void dispose() => _pool.dispose();
}
