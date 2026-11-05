// 精灵图资源回归测试：确保五组动画帧都能从 assets 加载并取到帧，
// 防止改素材时漏提交文件或拼错路径（加载失败会静默回退几何绘制）。

import 'package:flutter_test/flutter_test.dart';
import 'package:tank_app/games/plane/plane_sprites.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('精灵图全部可加载且每组都能取帧', () async {
    final sprites = await PlaneSprites.load();
    try {
      expect(sprites.isEmpty, isFalse);
      expect(sprites.background, isNotNull, reason: '缺少星云背景');
      for (final id in ['player', 'scout', 'zigzag', 'heavy', 'boss']) {
        expect(sprites.pick(id, 0, 1), isNotNull, reason: '缺少 $id 的动画帧');
      }
    } finally {
      sprites.dispose();
    }
  });
}
