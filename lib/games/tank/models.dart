// 游戏实体：坦克、子弹、爆炸、道具

import 'dart:ui';

import 'constants.dart';

class Tank {
  /// 左上角世界坐标
  Offset pos;
  Dir dir;
  final bool isPlayer;
  final EnemyKind? kind;
  double speed;
  final int player; // 玩家编号：0=P1，1=P2（敌人忽略）

  bool alive = true;
  double fireCooldown = 0;
  double shieldTime = 0; // 无敌（开局/头盔）
  int bulletLevel = 0; // 玩家火力等级 0..3
  bool bonus = false; // 敌人：击毁掉落道具
  int armorHp = 1; // 装甲敌人血量
  double aiTimer = 0;
  Dir aiDir;
  bool spawning = true; // 出生动画
  double spawnAnim = 0;

  // ---- Boss:双首领 ----
  double size; // 边长(世界单位):普通=kTank,Boss=kBossSize
  bool isBoss = false;
  bool isMiniBoss = false; // 保留字段(旧分裂机制已移除,恒为 false)
  int hp = 1; // Boss 当前血量(其它种类忽略)
  int maxHp = 1; // Boss 总血量(用于血条比例显示)
  double bombTimer = 0; // Boss 阶段3 投弹倒计时
  double summonTimer = 0; // Boss 召唤僚机倒计时
  double hitFlashTime = 0; // 受击闪烁剩余时间(秒)

  Tank({
    required this.pos,
    required this.dir,
    required this.isPlayer,
    this.kind,
    required this.speed,
    this.bonus = false,
    this.player = 0,
    this.size = kTank,
  }) : aiDir = dir {
    if (kind == EnemyKind.armor) armorHp = 4;
    if (isPlayer) shieldTime = kPlayerShieldStart;
  }

  Rect get rect => Rect.fromLTWH(pos.dx, pos.dy, size, size);
  Offset get center => Offset(pos.dx + size / 2, pos.dy + size / 2);
}

class Bullet {
  Offset pos;
  Dir dir;
  final bool fromPlayer;
  final int? owner; // 玩家子弹所属玩家编号（0/1），敌方子弹为 null
  double speed;
  bool dead = false;
  final int power; // >=3 可破钢
  bool isBomb = false; // Boss 炸弹:落地范围爆炸

  Bullet({
    required this.pos,
    required this.dir,
    required this.fromPlayer,
    required this.speed,
    this.power = 0,
    this.owner,
    this.isBomb = false,
  });

  Rect get rect => Rect.fromLTWH(pos.dx, pos.dy, kBullet, kBullet);
  Offset get center => Offset(pos.dx + kBullet / 2, pos.dy + kBullet / 2);
}

class Explosion {
  Offset pos;
  double t = 0; // 已存在时间
  final double life;
  final double size;
  bool big;

  Explosion(this.pos, {this.life = 0.32, this.size = kTank, this.big = false});

  bool get done => t >= life;
}

class PowerUp {
  PowerKind kind;
  final Offset pos; // 左上角
  double life = kPowerupLife;
  PowerUp(this.kind, this.pos);
  Rect get rect => Rect.fromLTWH(pos.dx, pos.dy, kTank, kTank);
}
