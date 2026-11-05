// 飞机大战 —— CustomPaint 手绘（零图片素材，与坦克/吃豆人同款画法）。
// 性能约定：Path / Paint 静态复用，shouldRepaint => false，
// 完全由外部 ValueNotifier 驱动逐帧重绘，画布不参与 widget 重建。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'plane_constants.dart';
import 'plane_entities.dart';
import 'plane_sprites.dart';

class PlanePainter extends CustomPainter {
  PlanePainter(this.scene, {required Listenable repaint}) : super(repaint: repaint);

  final PlaneScene scene;

  /// 素材加载完成后由页面赋值；为空时退回几何绘制。
  PlaneSprites? sprites;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景在实际像素坐标系铺满整个游戏区，不受 360x640 世界画布等比缩放影响，
    // 因此屏幕两侧不会出现黑边。
    _drawScreenBackground(canvas, size);

    final tr = planeTransform(size);
    if (tr.scale <= 0) return;
    canvas.save();
    canvas.translate(tr.origin.dx, tr.origin.dy);
    canvas.scale(tr.scale);

    _drawStars(canvas);
    _drawPowerUps(canvas);
    _drawBullets(canvas);
    _drawEnemies(canvas);
    _drawPlayer(canvas);
    _drawParticles(canvas);

    if (scene.flash > 0) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, kPlaneW, kPlaneH),
        _flashPaint
          ..color = Colors.white.withValues(
            alpha: (scene.flash * 0.5).clamp(0.0, 0.5),
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PlanePainter oldDelegate) => false;

  /// 页面销毁时释放文字排版缓存，避免 TextPainter 长期持有 Paragraph。
  void disposeIcons() {
    for (final tp in _iconCache.values) {
      tp.dispose();
    }
    _iconCache.clear();
  }

  // ---- 背景 ----
  /// cover：等比放大到铺满实际画布后居中裁剪，消除左右黑边且不变形。
  void _drawScreenBackground(Canvas canvas, Size size) {
    final bg = sprites?.background;
    if (bg == null) {
      canvas.drawRect(Offset.zero & size, _fallbackBgPaint);
      return;
    }
    final srcW = bg.image.width.toDouble();
    final srcH = bg.image.height.toDouble();
    final scale = math.max(size.width / srcW, size.height / srcH);
    final w = srcW * scale;
    final h = srcH * scale;
    canvas.drawImageRect(
      bg.image,
      bg.src,
      Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h),
      _bgImagePaint,
    );
    // 轻微压暗：星云较亮，保证子弹与飞机轮廓仍清晰
    canvas.drawRect(Offset.zero & size, _bgDimPaint);
  }

  void _drawStars(Canvas canvas) {
    for (final s in scene.stars) {
      // alpha 量化到 4 档预建 Paint：避免每帧为 72 颗星创建 Color 对象。
      final level = ((s.alpha - 0.25) / 0.2).floor().clamp(0, 3);
      canvas.drawCircle(Offset(s.x, s.y), s.r, _starPaints[level]);
    }
  }

  // ---- 子弹 ----
  void _drawBullets(Canvas canvas) {
    for (final b in scene.bullets) {
      final c = Offset(b.x, b.y);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: b.r * 3.2, height: b.r * 6.0),
          const Radius.circular(3),
        ),
        _bulletGlow,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: b.r * 1.2, height: b.r * 4.0),
          const Radius.circular(2),
        ),
        _bulletCore,
      );
    }
    for (final b in scene.enemyBullets) {
      final c = Offset(b.x, b.y);
      canvas.drawCircle(c, b.r + 2.5, _enemyBulletGlow);
      canvas.drawCircle(c, b.r, _enemyBulletCore);
    }
  }

  // ---- 敌机 ----
  void _drawEnemies(Canvas canvas) {
    for (final e in scene.enemies) {
      final sprite =
          sprites?.pick(_spriteId(e.kind), scene.time, _spriteFps(e.kind));
      if (sprite != null) {
        _drawSprite(
          canvas,
          sprite,
          e.x,
          e.y,
          _spriteHeight(e.kind),
          kEnemySpriteAnchor,
          paint: e.hitFlash > 0 ? _spriteHurtPaint : _spritePaint,
        );
      } else {
        _drawEnemyGeometry(canvas, e);
      }
      if (e.kind == EnemyKind.boss) _drawBossBar(canvas, e);
    }
  }

  static String _spriteId(EnemyKind kind) => switch (kind) {
        EnemyKind.scout => 'scout',
        EnemyKind.zigzag => 'zigzag',
        EnemyKind.heavy => 'heavy',
        EnemyKind.boss => 'boss',
      };

  static double _spriteFps(EnemyKind kind) => switch (kind) {
        EnemyKind.scout => 10,
        EnemyKind.zigzag => 12,
        EnemyKind.heavy => 10,
        EnemyKind.boss => 5,
      };

  static double _spriteHeight(EnemyKind kind) => switch (kind) {
        EnemyKind.scout => kScoutSpriteH,
        EnemyKind.zigzag => kZigzagSpriteH,
        EnemyKind.heavy => kHeavySpriteH,
        EnemyKind.boss => kBossSpriteH,
      };

  /// 以 [anchor] 处对准实体中心绘制精灵，火焰长短变化不会让机身漂移。
  void _drawSprite(
    Canvas canvas,
    SpriteFrame sprite,
    double cx,
    double cy,
    double height,
    double anchor, {
    Paint? paint,
  }) {
    final w = height * sprite.aspect;
    final dst = Rect.fromLTWH(cx - w / 2, cy - height * anchor, w, height);
    canvas.drawImageRect(
      sprite.image,
      sprite.src,
      dst,
      paint ?? _spritePaint,
    );
  }

  /// 素材未加载完成时的几何兜底绘制（也用于加载失败场景）。
  void _drawEnemyGeometry(Canvas canvas, Enemy e) {
    canvas.save();
    canvas.translate(e.x, e.y);
    final Path path = switch (e.kind) {
      EnemyKind.scout => _scoutPath,
      EnemyKind.zigzag => _zigzagPath,
      EnemyKind.heavy => _heavyPath,
      EnemyKind.boss => _bossPath,
    };
    final Color color = switch (e.kind) {
      EnemyKind.scout => const Color(0xFFEF5350),
      EnemyKind.zigzag => const Color(0xFFBA68C8),
      EnemyKind.heavy => const Color(0xFFFF8A3D),
      EnemyKind.boss => const Color(0xFF8C7AE6),
    };
    canvas.drawPath(path, _enemyFill..color = color);
    canvas.drawPath(path, _enemyStroke..color = color.withValues(alpha: 0.85));
    if (e.kind != EnemyKind.boss) {
      canvas.drawCircle(const Offset(0, -2), 3.2, _enemyCockpit);
      if (e.hitFlash > 0) {
        canvas.drawPath(
          path,
          _enemyHurt..color = Colors.white.withValues(alpha: 0.45),
        );
      }
    } else {
      canvas.drawCircle(const Offset(0, -12), 10, _enemyCockpit);
      canvas.drawCircle(const Offset(-38, 12), 6, _enemyCockpit);
      canvas.drawCircle(const Offset(38, 12), 6, _enemyCockpit);
    }
    canvas.restore();
  }

  void _drawBossBar(Canvas canvas, Enemy boss) {
    const x = 30.0;
    const y = 12.0;
    const w = kPlaneW - 60;
    const h = 8.0;
    final bar = RRect.fromRectAndRadius(
      const Rect.fromLTWH(x, y, w, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(bar, _barBg);
    final ratio = (boss.hp / boss.maxHp).clamp(0.0, 1.0);
    if (ratio > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w * ratio, h),
          const Radius.circular(4),
        ),
        _barFg,
      );
    }
  }

  // ---- 玩家 ----
  void _drawPlayer(Canvas canvas) {
    final p = scene.player;
    // 无敌期闪烁（用非整除频率避免与帧率同频）
    if (p.invuln > 0 && (scene.time * 11).floor().isEven) return;

    final sprite = sprites?.pick('player', scene.time, 12);
    if (sprite != null) {
      _drawSprite(canvas, sprite, p.x, p.y, kPlayerSpriteH,
          kPlayerSpriteAnchor);
    } else {
      _drawPlayerGeometry(canvas, p);
    }

    if (p.shield > 0) {
      final pulse = 0.5 + 0.5 * math.sin(scene.time * 8);
      canvas.drawCircle(
        Offset(p.x, p.y),
        23 + pulse * 2,
        _shieldPaint
          ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.35 + pulse * 0.3),
      );
    }
  }

  void _drawPlayerGeometry(Canvas canvas, PlayerPlane p) {
    canvas.save();
    canvas.translate(p.x, p.y);
    final flame = 8 + 4 * math.sin(scene.time * 30);
    canvas.drawOval(
      Rect.fromLTWH(-4, 14, 8, flame),
      _flamePaint,
    );
    canvas.drawPath(_playerBody, _playerFill);
    canvas.drawPath(_playerBody, _playerStroke);
    canvas.drawOval(const Rect.fromLTWH(-3.5, -11, 7, 12), _cockpitPaint);
    canvas.drawRect(const Rect.fromLTWH(-1, 8, 2, 8), _stripePaint);
    canvas.restore();
  }

  // ---- 道具 ----
  final Map<PowerKind, TextPainter> _iconCache = {};

  TextPainter _icon(PowerKind kind) => _iconCache.putIfAbsent(kind, () {
        final label = switch (kind) {
          PowerKind.power => 'P',
          PowerKind.shield => 'S',
          PowerKind.bomb => 'B',
          PowerKind.life => '+',
        };
        return TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });

  void _drawPowerUps(Canvas canvas) {
    for (final pu in scene.powerUps) {
      final color = switch (pu.kind) {
        PowerKind.power => const Color(0xFFFFCA28),
        PowerKind.shield => const Color(0xFF4FC3F7),
        PowerKind.bomb => const Color(0xFFEF5350),
        PowerKind.life => const Color(0xFF66BB6A),
      };
      final pulse = 1 + 0.08 * math.sin(scene.time * 6 + pu.t);
      canvas.save();
      canvas.translate(pu.x, pu.y);
      canvas.scale(pulse);
      canvas.drawCircle(
        Offset.zero,
        14,
        _puHalo..color = color.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        Offset.zero,
        11,
        _puFill..color = color.withValues(alpha: 0.9),
      );
      canvas.drawCircle(Offset.zero, 11, _puRing);
      final tp = _icon(pu.kind);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final p in scene.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.r * a,
        _particlePaint..color = p.color.withValues(alpha: a),
      );
    }
  }

  // ---- 复用 Paint ----
  static final Paint _fallbackBgPaint = Paint()..color = const Color(0xFF0A1734);
  static final Paint _bgImagePaint = Paint()
    ..filterQuality = FilterQuality.medium;
  static final Paint _bgDimPaint = Paint()..color = const Color(0x33081420);

  static final List<Paint> _starPaints = <Paint>[
    for (var i = 0; i < 4; i++)
      Paint()..color = Colors.white.withValues(alpha: 0.25 + i * 0.2),
  ];
  static final Paint _bulletGlow = Paint()..color = const Color(0x55FFE082);
  static final Paint _bulletCore = Paint()..color = const Color(0xFFFFF59D);
  static final Paint _enemyBulletGlow = Paint()..color = const Color(0x55FF5252);
  static final Paint _enemyBulletCore = Paint()..color = const Color(0xFFFF7043);

  static final Paint _enemyFill = Paint();
  static final Paint _enemyStroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _enemyHurt = Paint()..style = PaintingStyle.fill;
  static final Paint _enemyCockpit = Paint()..color = const Color(0xFFB3E5FC);

  static final Paint _barBg = Paint()..color = const Color(0xFF1B2440);
  static final Paint _barFg = Paint()..color = const Color(0xFFFF5252);

  static final Paint _playerFill = Paint()..color = const Color(0xFF4DD0E1);
  static final Paint _playerStroke = Paint()
    ..color = const Color(0xFFE0F7FA)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  static final Paint _cockpitPaint = Paint()..color = const Color(0xFF1565C0);
  static final Paint _stripePaint = Paint()..color = const Color(0xFF00838F);
  static final Paint _flamePaint = Paint()..color = const Color(0xCCFFB300);
  static final Paint _shieldPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  static final Paint _puHalo = Paint();
  static final Paint _puFill = Paint();
  static final Paint _puRing = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _particlePaint = Paint();
  static final Paint _flashPaint = Paint();

  // 精灵绘制：medium 缩放质量在移动端足够，成本远低于 high。
  static final Paint _spritePaint = Paint()
    ..filterQuality = FilterQuality.medium;
  static final Paint _spriteHurtPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = const ColorFilter.mode(
      Color(0x66FFFFFF),
      BlendMode.srcATop,
    );

  // ---- 复用 Path（原点在实体中心，绘制时 translate）----
  static final Path _playerBody = Path()
    ..moveTo(0, -20)
    ..lineTo(5, -5)
    ..lineTo(17, 6)
    ..lineTo(17, 12)
    ..lineTo(6, 9)
    ..lineTo(5, 16)
    ..lineTo(-5, 16)
    ..lineTo(-6, 9)
    ..lineTo(-17, 12)
    ..lineTo(-17, 6)
    ..lineTo(-5, -5)
    ..close();

  static final Path _scoutPath = Path()
    ..moveTo(0, 12)
    ..lineTo(-11, -8)
    ..lineTo(-4, -6)
    ..lineTo(0, -11)
    ..lineTo(4, -6)
    ..lineTo(11, -8)
    ..close();

  static final Path _zigzagPath = Path()
    ..moveTo(0, 13)
    ..lineTo(-13, -3)
    ..lineTo(-7, -10)
    ..lineTo(7, -10)
    ..lineTo(13, -3)
    ..close();

  static final Path _heavyPath = Path()
    ..moveTo(0, 18)
    ..lineTo(-9, 4)
    ..lineTo(-20, -4)
    ..lineTo(-20, -12)
    ..lineTo(-6, -9)
    ..lineTo(0, -16)
    ..lineTo(6, -9)
    ..lineTo(20, -12)
    ..lineTo(20, -4)
    ..lineTo(9, 4)
    ..close();

  static final Path _bossPath = Path()
    ..moveTo(0, 38)
    ..lineTo(-22, 20)
    ..lineTo(-64, 12)
    ..lineTo(-64, -6)
    ..lineTo(-28, -14)
    ..lineTo(-14, -34)
    ..lineTo(14, -34)
    ..lineTo(28, -14)
    ..lineTo(64, -6)
    ..lineTo(64, 12)
    ..lineTo(22, 20)
    ..close();
}
