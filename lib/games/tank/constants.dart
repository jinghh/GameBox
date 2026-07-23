// 经典坦克大战 - 常量与基础类型
// 战场采用 26x26 个"半格"(cell)，每个半格 8 个世界单位，战场共 208x208。
// 坦克 = 2x2 半格(16 单位)，砖墙按半格逐块销毁，忠实还原原版手感。

import 'dart:math';
import 'dart:ui';

/// 方向
enum Dir { up, down, left, right }

extension DirX on Dir {
  /// 单位方向向量
  Offset get vector {
    switch (this) {
      case Dir.up:
        return const Offset(0, -1);
      case Dir.down:
        return const Offset(0, 1);
      case Dir.left:
        return const Offset(-1, 0);
      case Dir.right:
        return const Offset(1, 0);
    }
  }

  /// 弧度（用于旋转炮管绘制）
  double get radians {
    switch (this) {
      case Dir.up:
        return 0;
      case Dir.right:
        return pi / 2;
      case Dir.down:
        return pi;
      case Dir.left:
        return -pi / 2;
    }
  }

  bool get isHorizontal => this == Dir.left || this == Dir.right;
  Dir get opposite {
    switch (this) {
      case Dir.up:
        return Dir.down;
      case Dir.down:
        return Dir.up;
      case Dir.left:
        return Dir.right;
      case Dir.right:
        return Dir.left;
    }
  }
}

/// 地形（每个 cell 一种）
enum Terrain { empty, brick, steel, water, trees, ice }

extension TerrainX on Terrain {
  /// 是否阻挡坦克
  bool get blocksTank =>
      this == Terrain.brick ||
      this == Terrain.steel ||
      this == Terrain.water;

  /// 是否阻挡子弹
  bool get blocksBullet =>
      this == Terrain.brick || this == Terrain.steel;
}

/// 游戏阶段
enum Phase { start, playing, paused, levelClear, gameOver, victory }

/// 敌人种类
enum EnemyKind { basic, fast, power, armor }

/// 道具种类
enum PowerKind { star, helmet, grenade, tank, clock, shovel }

// ---- 尺寸常量 ----
const int kCells = 26;
const double kCell = 8.0;
const double kBattle = kCells * kCell; // 208

const double kTank = kCell * 2; // 16
const double kBullet = 6.0;

// 基地位于底部正中：2x2 cell，列 12-13 / 行 24-25
const int kBaseCol = 12;
const int kBaseRow = 24;

// 出生点（cell 坐标）
const int kEnemySpawnCols = 0; // 左
const List<int> kEnemySpawnColChoices = [0, 12, 24];
const int kPlayerSpawnCol = 8;
const int kPlayer2SpawnCol = 16; // 双人合作：P2 出生点（与 P1 关于基地对称）
const int kPlayerSpawnRow = 23;

// 过关结算展示时长（秒）
const double kLevelClearDuration = 3.4;

// ---- 速度（世界单位 / 秒）----
const double kPlayerSpeed = 52.0;
const double kEnemySpeedBasic = 38.0;
const double kEnemySpeedFast = 60.0;
const double kBulletSpeed = 130.0;
const double kBulletSpeedFast = 175.0;

// ---- 计时 ----
const double kPlayerFireCooldown = 0.45;
const double kEnemyFireCooldown = 1.6;
const double kPlayerShieldStart = 3.0;
const double kPowerupLife = 12.0;
const double kFreezeTime = 8.0;
const double kShovelTime = 15.0;
const double kHelmetTime = 10.0;

const int kMaxEnemiesOnField = 4;
const int kEnemiesPerLevel = 20;
const int kStartLives = 3;

// ---- Boss 系统:双首领(关卡 5 / 9,难度递进) ----
const double kBossSize = kTank * 1.5; // 24 世界单位(所有 Boss 统一尺寸,兼容网络编码)

/// 单个 Boss 的分级配置(数据驱动,避免散落的魔法数字)。
class BossTier {
  final String name; // Boss 名称
  final int hp; // 总血量(必须 <=255,受网络 u8 编码限制)
  final double speed1; // 阶段1(常规)移速
  final double speed2; // 阶段2(狂怒)移速
  final double speed3; // 阶段3(绝地)移速
  final double fireCd1; // 阶段1 开火冷却
  final double fireCd2; // 阶段2 开火冷却(双发)
  final double fireCd3; // 阶段3 开火冷却(三发)
  final bool canBomb; // 阶段3 是否投掷炸弹
  final bool canSummon; // 阶段2+ 是否召唤精英僚机
  final int killBonus; // 击破奖励分

  const BossTier({
    required this.name,
    required this.hp,
    required this.speed1,
    required this.speed2,
    required this.speed3,
    required this.fireCd1,
    required this.fireCd2,
    required this.fireCd3,
    required this.canBomb,
    required this.canSummon,
    required this.killBonus,
  });
}

/// 双首领:索引 0/1 → Tier 1/2,分别对应第 5 / 9 关。
/// 血量、火力、移速逐级递进;高阶追加炸弹与僚机召唤机制。
const List<BossTier> kBossTiers = [
  BossTier(
    name: '铁卫',
    hp: 14,
    speed1: 40, speed2: 46, speed3: 56,
    fireCd1: 1.5, fireCd2: 1.05, fireCd3: 0.75,
    canBomb: false, canSummon: false, killBonus: 2000,
  ),
  BossTier(
    name: '虎王',
    hp: 30,
    speed1: 44, speed2: 54, speed3: 72,
    fireCd1: 1.1, fireCd2: 0.78, fireCd3: 0.5,
    canBomb: true, canSummon: true, killBonus: 6000,
  ),
];

// 阶段血量分数阈值(按剩余血量比例划分,通用于各 Tier)
const double kBossPhase2Frac = 0.6; // 剩余 <=60% → 狂怒
const double kBossPhase3Frac = 0.3; // 剩余 <=30% → 绝地反击

// 炸弹(阶段3,仅 Tier2)
const double kBossBombInterval = 9; // 投弹间隔(秒)
const double kBossBombSpeed = 55;
const double kBossBombRadius = kTank * 1.7; // 炸弹爆炸伤害半径

// 精英僚机召唤(狂怒起,仅 Tier2)
const double kBossSummonInterval = 11; // 召唤间隔(秒)
const int kBossSummonCount = 2; // 每次召唤数量
const int kBossSummonMaxOnField = 3; // 场上僚机数量上限

/// cell 坐标 -> 世界坐标（左上角）
double cellToWorld(int c) => c * kCell;

/// 世界坐标 -> cell 坐标
int worldToCell(double v) => (v / kCell).floor();

/// 将世界坐标吸附到最近的 cell 边界
double snapToCell(double v) => (v / kCell).round() * kCell;
