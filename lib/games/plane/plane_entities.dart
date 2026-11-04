// 飞机大战 —— 纯逻辑实体（可变对象，不进 widget 树）。
// 所有列表由 PlaneScene 持有同一份引用，CustomPainter 每帧直接读取最新数据，
// 靠 ValueNotifier 触发重绘，无需 setState 重建整棵页面。
library;

import 'dart:math';
import 'dart:ui' show Color, Offset, Rect;

import 'plane_constants.dart';

class PlayerPlane {
  static const double r = 11.0;

  double x = kPlaneW / 2;
  double y = kPlaneH - 76;
  double invuln = 0; // 复活无敌时间
  double fireCd = 0;
  double shield = 0; // 护盾剩余时间
  int power = 1; // 1..4，决定弹道数量
  int bombs = 2;

  Rect get rect => Rect.fromCircle(center: Offset(x, y), radius: r);

  /// 开新局：全部重置。
  void reset() {
    x = kPlaneW / 2;
    y = kPlaneH - 76;
    invuln = 1.6;
    fireCd = 0;
    shield = 0;
    power = 1;
    bombs = 2;
  }

  /// 掉一条命后的复活：保留炸弹，火力降一级。
  void respawn() {
    x = kPlaneW / 2;
    y = kPlaneH - 76;
    invuln = 2.2;
    fireCd = 0;
    shield = 0;
    power = power > 1 ? power - 1 : 1;
  }
}

class Bullet {
  Bullet(this.x, this.y, this.vx, this.vy, {this.damage = 1, this.r = 3});

  double x, y, vx, vy, r;
  int damage;
  bool dead = false;

  Rect get rect => Rect.fromCircle(center: Offset(x, y), radius: r);
}

class Enemy {
  Enemy({
    required this.kind,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.w,
    required this.h,
    required int hp,
    required this.score,
    required this.fireCd,
    this.phase = 0,
  })  : hp = hp,
        maxHp = hp,
        baseX = x;

  final EnemyKind kind;
  double x, y, vx, vy;
  final double w, h, baseX, phase;
  int hp;
  final int maxHp, score;
  double t = 0;
  double fireCd;
  bool dead = false;

  Rect get rect => Rect.fromCenter(center: Offset(x, y), width: w, height: h);
}

class PowerUp {
  PowerUp(this.kind, this.x, this.y);

  final PowerKind kind;
  double x, y, t = 0;
  bool dead = false;

  Rect get rect => Rect.fromCircle(center: Offset(x, y), radius: 13);
}

class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.r,
    required this.color,
  }) : maxLife = life;

  double x, y, vx, vy, life, r;
  final double maxLife;
  final Color color;
}

class Star {
  Star({
    required this.x,
    required this.y,
    required this.speed,
    required this.r,
    required this.alpha,
  });

  double x, y;
  final double speed, r, alpha;
}

/// 场景容器：整局游戏只有一份，painter 与 State 共享引用。
class PlaneScene {
  final PlayerPlane player = PlayerPlane();
  final List<Bullet> bullets = [];
  final List<Bullet> enemyBullets = [];
  final List<Enemy> enemies = [];
  final List<PowerUp> powerUps = [];
  final List<Particle> particles = [];
  final List<Star> stars = [];
  final Random rng = Random();

  double time = 0;
  double flash = 0; // 炸弹全屏闪光

  PlaneScene() {
    _initStars();
  }

  void _initStars() {
    for (var i = 0; i < 72; i++) {
      stars.add(Star(
        x: rng.nextDouble() * kPlaneW,
        y: rng.nextDouble() * kPlaneH,
        speed: 18 + rng.nextDouble() * 72,
        r: 0.6 + rng.nextDouble() * 1.5,
        alpha: 0.25 + rng.nextDouble() * 0.6,
      ));
    }
  }

  void restart() {
    bullets.clear();
    enemyBullets.clear();
    enemies.clear();
    powerUps.clear();
    particles.clear();
    player.reset();
    time = 0;
    flash = 0;
  }

  void scrollStars(double dt, double factor) {
    for (final s in stars) {
      s.y += s.speed * dt * factor;
      if (s.y > kPlaneH + 2) {
        s.y = -2;
        s.x = rng.nextDouble() * kPlaneW;
      }
    }
  }
}
