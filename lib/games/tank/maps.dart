// 关卡地图与敌人编成
// 地图按 13x13 的"整砖"设计，每个字符 = 1 整砖(=2x2 半格)。
// 字符: 空格/. = 空, B = 砖, S = 钢, W = 水, T = 树, I = 冰
// 基地与出生点由游戏逻辑在解析后覆盖，因此地图里可不画。

import 'dart:math';

import 'constants.dart';

class LevelMap {
  final String name;
  final List<String> tiles; // 13 行，每行约 13 字符

  const LevelMap(this.name, this.tiles);
}

const int kTileCount = 13;

final List<LevelMap> kLevels = [
  LevelMap('关卡 1 · 初阵', [
    '             ',
    ' B B B B B B ',
    ' B B B B B B ',
    '             ',
    ' BBBB   BBBB ',
    '      S      ',
    ' T T T T T T ',
    '      W      ',
    ' BBBB   BBBB ',
    '             ',
    ' B B B B B B ',
    ' B B B B B B ',
    '             ',
  ]),
  LevelMap('关卡 2 · 十字阵', [
    '      S      ',
    '  BBB B BBB  ',
    '  B       B  ',
    'BB B  W W  B ',
    'B    W   W  B',
    'BB B  W W  B ',
    '  B   T   B  ',
    'BB B  W W  B ',
    'B    W   W  B',
    'BB B  W W  B ',
    '  B       B  ',
    '  BBB B BBB  ',
    '      S      ',
  ]),
  LevelMap('关卡 3 · 哨塔阵地', [
    ' B B B B B B ',
    ' B S     S B ',
    ' B B B B B B ',
    '             ',
    '   B     B   ',
    '   B     B   ',
    ' T       T   ',
    '   B     B   ',
    '   B     B   ',
    '             ',
    ' B S     S B ',
    ' B B B B B B ',
    '             ',
  ]),
  LevelMap('关卡 4 · 迷宫', [
    'B B B B B B B',
    'B S B B B S B',
    'B B B W W B B',
    'B B  W   W  B',
    'B B W T T W B',
    'B   W T T W  ',
    'B B W T T W B',
    'B   W T T W  ',
    'B B W T T W B',
    'B B  W   W  B',
    'B B B W W B B',
    'B S B B B S B',
    'B B B B B B B',
  ]),
  // 关卡 5:开阔场地,便于机动缠斗。
  LevelMap('关卡 5 · 演练场', [
    '             ',
    '             ',
    '  S       S  ',
    '      B      ',
    '   B  B  B   ',
    '             ',
    ' B         B ',
    '             ',
    '   B  B  B   ',
    '      B      ',
    '  S       S  ',
    '             ',
    '             ',
  ]),
  LevelMap('关卡 6 · 钢铁防线', [
    '             ',
    '             ',
    ' B S     S B ',
    '             ',
    '  B  BBB  B  ',
    '     B B     ',
    ' S   B B   S ',
    '     B B     ',
    '  B  BBB  B  ',
    '             ',
    ' B S     S B ',
    '             ',
    '             ',
  ]),
  LevelMap('关卡 7 · 钢铁堡垒', [
    'S S S B S S S',
    'S B B B B B S',
    'S B W W W B S',
    'B B W T W B B',
    'B B W T W B B',
    'B B B T B B B',
    'B B W T W B B',
    'B B W T W B B',
    'S B W W W B S',
    'S B B B B B S',
    'S S S B S S S',
    ' B B B B B B ',
    '             ',
  ]),
  LevelMap('关卡 8 · 死亡走廊', [
    'B B     B B  ',
    'B S BBB S B  ',
    'B   B B   B  ',
    'BBB B B BBB  ',
    '    B B      ',
    'B B B B B B  ',
    'B     S     B',
    'B B B B B B  ',
    '    B B      ',
    'BBB B B BBB  ',
    'B   B B   B  ',
    'B S BBB S B  ',
    'B B     B B  ',
  ]),
  // 关卡 9:最终关,开阔竞技场。
  LevelMap('关卡 9 · 终章', [
    '             ',
    '             ',
    '  B   S   B  ',
    '             ',
    '   B B B B   ',
    '             ',
    ' B    T    B ',
    '             ',
    ' B    T    B ',
    '             ',
    '   B B B B   ',
    '  B   S   B  ',
    '             ',
  ]),
  ..._generatedLevels(),
];

/// 把整砖地图解析为 26x26 半格地形
List<List<Terrain>> parseTerrain(LevelMap map) {
  final grid = List.generate(
    kCells,
    (_) => List<Terrain>.filled(kCells, Terrain.empty),
  );
  for (int row = 0; row < kTileCount; row++) {
    final line = row < map.tiles.length ? map.tiles[row] : '';
    for (int col = 0; col < kTileCount; col++) {
      final ch = col < line.length ? line[col] : ' ';
      final t = _charToTerrain(ch);
      for (int dy = 0; dy < 2; dy++) {
        for (int dx = 0; dx < 2; dx++) {
          grid[row * 2 + dy][col * 2 + dx] = t;
        }
      }
    }
  }
  return grid;
}

Terrain _charToTerrain(String ch) {
  switch (ch) {
    case 'B':
    case 'b':
      return Terrain.brick;
    case 'S':
    case 's':
      return Terrain.steel;
    case 'W':
    case 'w':
      return Terrain.water;
    case 'T':
    case 't':
      return Terrain.trees;
    case 'I':
    case 'i':
      return Terrain.ice;
    default:
      return Terrain.empty;
  }
}

/// 某关的敌人配额（总数恒为 kEnemiesPerLevel）。
class _EnemyMix {
  final int basic;
  final int fast;
  final int power;
  final int armor;
  const _EnemyMix(this.basic, this.fast, this.power, this.armor);
  int get advanced => fast + power + armor;
}

/// 敌人配额：难度随关卡平滑递增（1-5 教学仅普通；6 关起每关 +1 高级敌人，
/// 并逐步引入快速/强化/重型，硬敌优先保留名额）。level 为 1-based。
_EnemyMix _enemyMixForLevel(int level) {
  if (level <= 5) {
    return const _EnemyMix(kEnemiesPerLevel, 0, 0, 0);
  }
  // 高级敌人总数：每关 +1，6 关起从 4 开始，封顶 16（保留至少 4 个普通坦克）。
  final advTotal = (4 + (level - 6)).clamp(4, 16);
  // 三类各自随关卡非减增长（封顶 8），硬敌(装甲 > 强化 > 快速)优先保留名额。
  var armor = (level >= 8 ? level - 7 : 0).clamp(0, 8);
  var power = (level >= 7 ? level - 6 : 0).clamp(0, 8);
  var fast = (level >= 6 ? 3 + (level - 6) : 0).clamp(0, 8);
  int sum = armor + power + fast;
  if (sum > advTotal) {
    // 先削减快速坦克，保住强化/装甲
    fast = (advTotal - armor - power).clamp(0, fast);
    if (armor + power > advTotal) {
      power = (advTotal - armor).clamp(0, power);
      if (power < 0) {
        power = 0;
        armor = advTotal;
      }
    }
  }
  // 保底：始终保留少量快速坦克（绕后威胁基地），从强化/装甲名额中借。
  if (fast < 2 && armor + power > 0) {
    final need = 2 - fast;
    final fromPower = need.clamp(0, power);
    power -= fromPower;
    final fromArmor = (need - fromPower).clamp(0, armor);
    armor -= fromArmor;
    fast += fromPower + fromArmor;
  }
  final basic = kEnemiesPerLevel - (armor + power + fast).clamp(0, kEnemiesPerLevel);
  return _EnemyMix(basic, fast, power, armor);
}

/// 根据关卡生成 20 个敌人的种类队列（难度随关卡递增）。
List<EnemyKind> enemyQueueForLevel(int level, Random rng) {
  final m = _enemyMixForLevel(level);
  final list = <EnemyKind>[];
  void add(EnemyKind k, int n) {
    for (int i = 0; i < n; i++) {
      list.add(k);
    }
  }
  add(EnemyKind.basic, m.basic);
  add(EnemyKind.fast, m.fast);
  add(EnemyKind.power, m.power);
  add(EnemyKind.armor, m.armor);
  list.shuffle(rng);
  return list;
}

/// 难度阶段标签（与 enemyQueueForLevel 同源，level 为 1-based）。
String levelStageLabel(int level) {
  final m = _enemyMixForLevel(level);
  if (m.advanced == 0) return '教学 · 仅普通坦克';
  final parts = <String>[];
  if (m.fast > 0) parts.add('快速');
  if (m.power > 0) parts.add('强化');
  if (m.armor > 0) parts.add('重型');
  return '含${parts.join('/')}坦克 ($m.advanced/$kEnemiesPerLevel)';
}

/// 程序化生成关卡 10-20 的地图（确定性：固定种子 → 每次构建一致）。
/// 保证 13x13、出生点与基地区通畅、保留十字主通道确保连通。
List<LevelMap> _generatedLevels() {
  final out = <LevelMap>[];
  for (int lv = 10; lv <= 20; lv++) {
    final tiles = <String>[];
    bool safe(int r, int c) {
      if (r <= 1) return true; // 顶部三出生点行
      if (r == 2 && (c <= 1 || c >= 11 || c == 6 || c == 7)) return true; // 出生列下方留空
      // 三条纵向出生通道（左/中/右）直达第 6 行横向主通道
      if (r >= 3 && r <= 5 && (c <= 1 || c == 6 || c >= 11)) return true;
      if (r == 12) return true; // 基地区（逻辑覆盖 + 加砖）
      if (r == 11 && c >= 4 && c <= 9) return true; // 基地保护 + 玩家双出生点
      return false;
    }

    for (int r = 0; r < kTileCount; r++) {
      final sb = StringBuffer();
      for (int c = 0; c < kTileCount; c++) {
        if (safe(r, c) || r == 6 || c == 6) {
          sb.write(' '); // 安全区 / 十字主通道留空
          continue;
        }
        // 左右镜像对称：用对称基列决定内容，保证对称且确定
        final cc = c <= 6 ? c : 12 - c;
        final rnd = Random(r * 73856093 ^ cc * 19349663 ^ lv * 83492791);
        final v = rnd.nextDouble();
        final pSteel = 0.10 + (lv - 10) * 0.02; // 钢墙随关卡增多
        final pWater = 0.05 + (lv - 10) * 0.01;
        final pIce = lv >= 13 ? 0.05 + (lv - 13) * 0.02 : 0.0; // 冰面 13 关起出现
        final pTree = 0.08;
        if (v < pSteel) {
          sb.write('S');
        } else if (v < pSteel + pWater) {
          sb.write('W');
        } else if (v < pSteel + pWater + pIce) {
          sb.write('I');
        } else if (v < pSteel + pWater + pIce + pTree) {
          sb.write('T');
        } else {
          sb.write('B');
        }
      }
      tiles.add(sb.toString());
    }
    out.add(LevelMap('关卡 $lv · ${_genName(lv)}', tiles));
  }
  return out;
}

/// 关卡 10-20 的主题名
String _genName(int lv) {
  const names = {
    10: '钢魄',
    11: '湍流',
    12: '密林',
    13: '寒霜',
    14: '砖狱',
    15: '铁壁',
    16: '冰河',
    17: '重围',
    18: '回廊',
    19: '绝地',
    20: '终焉',
  };
  return names[lv] ?? '战场';
}

/// 标记队列中哪几个是"闪烁奖励坦克"（击毁后掉落道具）
Set<int> bonusIndices(List<EnemyKind> queue) {
  return {
    queue.length ~/ 4,
    (queue.length * 3) ~/ 4,
  };
}

/// 击毁得分
int scoreForKind(EnemyKind k) {
  switch (k) {
    case EnemyKind.basic:
      return 100;
    case EnemyKind.fast:
      return 200;
    case EnemyKind.power:
      return 300;
    case EnemyKind.armor:
      return 400;
  }
}
