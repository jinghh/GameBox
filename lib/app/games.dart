import 'package:flutter/material.dart';

import '../games/game2048/game2048_page.dart';
import '../games/minesweeper/minesweeper_page.dart';
import '../games/snake/snake_page.dart';
import '../games/tank/battle_city_game.dart';
import '../games/tetris/tetris_page.dart';

/// 一个可插拔游戏的描述。
///
/// 扩展方式：新建 `lib/games/<新游戏>/xxx_page.dart`，
/// 然后在此 [kGames] 列表追加一行即可，主页列表会自动出现。
class GameSpec {
  final String id;
  final String title;
  final String subtitle;
  final String emoji; // 卡片图标，免图片素材
  final Color accent;
  final WidgetBuilder builder;

  const GameSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.accent,
    required this.builder,
  });
}

/// 合集游戏注册表——主页列表由此驱动。
final List<GameSpec> kGames = [
  GameSpec(
    id: 'tank',
    title: '坦克大战',
    subtitle: 'Battle City',
    emoji: '🛡️',
    accent: const Color(0xFFFFD54A),
    builder: (_) => const BattleCityGame(),
  ),
  GameSpec(
    id: 'g2048',
    title: '2048',
    subtitle: '合并数字到 2048',
    emoji: '🔢',
    accent: const Color(0xFFF2B179),
    builder: (_) => const Game2048Page(),
  ),
  GameSpec(
    id: 'snake',
    title: '贪吃蛇',
    subtitle: '吃食物变长加速',
    emoji: '🐍',
    accent: const Color(0xFF6EE060),
    builder: (_) => const SnakePage(),
  ),
  GameSpec(
    id: 'mine',
    title: '扫雷',
    subtitle: '避开地雷翻开全场',
    emoji: '💣',
    accent: const Color(0xFF4FC3F7),
    builder: (_) => const MinesweeperPage(),
  ),
  GameSpec(
    id: 'tetris',
    title: '俄罗斯方块',
    subtitle: '消行升级，堆顶判负',
    emoji: '🧱',
    accent: const Color(0xFFFFA726),
    builder: (_) => const TetrisPage(),
  ),
];
