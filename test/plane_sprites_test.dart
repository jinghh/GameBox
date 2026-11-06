// 精灵图资源回归测试：确保五组动画帧都能从 assets 加载并取到帧，
// 防止改素材时漏提交文件或拼错路径（加载失败会静默回退几何绘制）。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tank_app/games/plane/plane_constants.dart';
import 'package:tank_app/games/plane/plane_entities.dart';
import 'package:tank_app/games/plane/plane_painter.dart';
import 'package:tank_app/games/plane/plane_sprites.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('精灵图全部可加载且每组都能取帧', () async {
    final sprites = await PlaneSprites.load();
    try {
      expect(sprites.isEmpty, isFalse);
      expect(sprites.background, isNotNull, reason: '缺少星云背景');
      expect(sprites.explosions, hasLength(kExplosionFrameCount),
          reason: '爆炸序列帧数不完整');
      for (final id in ['player', 'scout', 'zigzag', 'heavy', 'boss']) {
        expect(sprites.pick(id, 0, 1), isNotNull, reason: '缺少 $id 的动画帧');
      }
    } finally {
      sprites.dispose();
    }
  });

  test('爆炸精灵可离屏绘制出暖色爆炸区域', () async {
    final sprites = await PlaneSprites.load();
    try {
      final scene = PlaneScene();
      scene.explosions.add(
        Explosion(180, 300, ExplosionKind.big, size: 120),
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final painter = PlanePainter(scene, repaint: ValueNotifier<int>(0))
        ..sprites = sprites;
      painter.paint(canvas, const ui.Size(360, 640));

      final image = await recorder.endRecording().toImage(360, 640);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(raw, isNotNull);
      final data = raw!.buffer.asUint8List();
      var warm = 0;
      for (var y = 250; y < 350; y++) {
        for (var x = 130; x < 230; x++) {
          final i = (y * 360 + x) * 4;
          if (data[i] > 170 && data[i + 1] > 70 && data[i + 2] < 140) {
            warm++;
          }
        }
      }
      expect(warm, greaterThan(30), reason: '爆炸帧未在画面中绘制');
    } finally {
      sprites.dispose();
    }
  });
}
