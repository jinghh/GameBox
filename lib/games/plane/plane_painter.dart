// 飞机大战 —— CustomPaint 手绘（零图片素材，与坦克/吃豆人同款画法）。
// 性能约定：Path / Paint 静态复用，shouldRepaint => false，
// 完全由外部 ValueNotifier 驱动逐帧重绘，画布不参与 widget 重建。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'plane_constants.dart';
import 'plane_entities.dart';

class PlanePainter extends CustomPainter {
  PlanePainter(this.scene, {required Listenable repaint}) : super(repaint: repaint);

  final PlaneScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final tr = planeTransform(size);
    if (tr.scale <= 0) return;
    canvas.save();
    canvas.translate(tr.origin.dx, tr.origin.dy);
    canvas.scale(tr.scale);

    _drawBackground(canvas);
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
  void _drawBackground(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, kPlaneW, kPlaneH),
      _bgPaint,
    );
    final drift = (scene.time * 12) % (kPlaneH + 260);
    for (var i = 0; i < 3; i++) {
      final y = -130.0 + i * 260 + drift;
      if (y < -100 || y > kPlaneH + 100) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(kPlaneW * (0.2 + 0.3 * i), y),
          width: 280,
          height: 96,
        ),
        _nebulaPaint,
      );
    }
    final offset = (scene.time * 26) % 64;
    for (var y = -64 + offset; y < kPlaneH; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(kPlaneW, y), _gridPaint);
    }
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
        // 受击闪白
        if (e.hp < e.maxHp) {
          canvas.drawPath(
            path,
            _enemyHurt
              ..color = Colors.white.withValues(
                alpha: 0.15 + 0.15 * math.sin(scene.time * 20),
              ),
          );
        }
      } else {
        canvas.drawCircle(const Offset(0, -12), 10, _enemyCockpit);
        canvas.drawCircle(const Offset(-38, 12), 6, _enemyCockpit);
        canvas.drawCircle(const Offset(38, 12), 6, _enemyCockpit);
      }
      canvas.restore();
      if (e.kind == EnemyKind.boss) _drawBossBar(canvas, e);
    }
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
    if (p.shield > 0) {
      final pulse = 0.5 + 0.5 * math.sin(scene.time * 8);
      canvas.drawCircle(
        Offset.zero,
        23 + pulse * 2,
        _shieldPaint
          ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.35 + pulse * 0.3),
      );
    }
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
  static final Paint _bgPaint = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0xFF030816),
        Color(0xFF0A1734),
        Color(0xFF123054),
      ],
    ).createShader(const Rect.fromLTWH(0, 0, kPlaneW, kPlaneH));

  // 不用 MaskFilter.blur：大半径模糊椭圆每帧走 GPU 光栅化，
  // 在低端机上会明显掉帧；纯半透明椭圆已足够表现星云。
  static final Paint _nebulaPaint = Paint()..color = const Color(0x144FC3F7);

  static final Paint _gridPaint = Paint()
    ..color = const Color(0x104FC3F7)
    ..strokeWidth = 1;

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
