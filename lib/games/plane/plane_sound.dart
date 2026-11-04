// 飞机大战音效：基于共享 [SfxPool]，复用项目已有 wav 素材，零新增资源。
// 受全局 kMuted 控制（SfxPool 内部检查），无需本页额外监听。
library;

import '../../shared/sfx_pool.dart';

class PlaneSound {
  final SfxPool _pool = SfxPool()..throttleMs = 55;
  bool _disposed = false;

  static const Map<String, ({String asset, int max, double vol})> _defs = {
    'shoot': (asset: 'shoot.wav', max: 2, vol: 0.18),
    'enemyShoot': (asset: 'enemy_shoot.wav', max: 2, vol: 0.14),
    'hit': (asset: 'hit.wav', max: 3, vol: 0.22),
    'explode': (asset: 'explosion.wav', max: 3, vol: 0.35),
    'bigExplode': (asset: 'big_explosion.wav', max: 2, vol: 0.55),
    'power': (asset: 'powerup.wav', max: 2, vol: 0.42),
    'start': (asset: 'start.wav', max: 1, vol: 0.50),
    'over': (asset: 'gameover.wav', max: 1, vol: 0.60),
  };

  /// 异步加载。若页面在加载途中被销毁，finally 兜底回收「晚到」的 player，
  /// 避免 dispose 之后仍有 AudioPlayer 被加入池造成泄漏。
  Future<void> init() async {
    try {
      for (final e in _defs.entries) {
        if (_disposed) return;
        await _pool.loadAsset(
          e.key,
          'sounds/${e.value.asset}',
          e.value.max,
          e.value.vol,
        );
      }
      if (!_disposed) _pool.finish();
    } finally {
      if (_disposed) _pool.dispose();
    }
  }

  void shoot() => _pool.play('shoot');
  void enemyShoot() => _pool.play('enemyShoot');
  void hit() => _pool.play('hit');
  void explode() => _pool.play('explode');
  void bigExplode() => _pool.play('bigExplode');
  void power() => _pool.play('power');
  void start() => _pool.play('start');
  void over() => _pool.play('over');
  void bomb() => _pool.play('bigExplode', volume: 0.7);

  void dispose() {
    _disposed = true;
    _pool.dispose();
  }
}
