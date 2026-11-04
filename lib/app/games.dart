import 'package:flutter/material.dart';

import '../games/game2048/game2048_page.dart';
import '../games/gomoku/gomoku_page.dart';
import '../games/minesweeper/minesweeper_page.dart';
import '../games/snake/snake_page.dart';
import '../games/tetris/tetris_page.dart';
import '../games/pacman/pacman_game.dart';
import '../home/game_home_page.dart';

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
  final String? bestKey; // 最高分/最佳成绩的本地 key，null=不显示成绩
  final bool bestIsTime; // true=通关时间(mm:ss)，false=分数

  const GameSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.accent,
    required this.builder,
    this.bestKey,
    this.bestIsTime = false,
  });
}

/// 合集游戏注册表——主页列表由此驱动。
/// 坦克/泡泡堂等「含多模式」的游戏在此各占一张卡片,点进去进入 [GameHomePage]
/// 选择 单人/双人/联机;其余游戏直接指向各自页面。
final List<GameSpec> kGames = [
  GameSpec(
    id: 'tank',
    title: '坦克大战',
    subtitle: 'Battle City · 守基地',
    emoji: '🛡️',
    accent: const Color(0xFFFFD54A),
    builder: (_) => const GameHomePage(type: GameType.tank),
  ),
  GameSpec(
    id: 'bomber',
    title: '泡泡堂',
    subtitle: '放雷炸敌,过关递增',
    emoji: '💣',
    accent: const Color(0xFFFF8A4C),
    builder: (_) => const GameHomePage(type: GameType.bomber),
    bestKey: 'best_bomber',
  ),
  GameSpec(
    id: 'g2048',
    title: '2048',
    subtitle: '合并到 2048',
    emoji: '🔢',
    accent: const Color(0xFFF2B179),
    builder: (_) => const Game2048Page(),
    bestKey: 'best_2048',
  ),
  GameSpec(
    id: 'snake',
    title: '贪吃蛇',
    subtitle: '吃食物变长加速',
    emoji: '🐍',
    accent: const Color(0xFF6EE060),
    builder: (_) => const SnakePage(),
    bestKey: 'best_snake',
  ),
  GameSpec(
    id: 'mine',
    title: '扫雷',
    subtitle: '避开地雷翻开全场',
    emoji: '💣',
    accent: const Color(0xFF4FC3F7),
    builder: (_) => const MinesweeperPage(),
    bestKey: 'best_mine_easy',
    bestIsTime: true,
  ),
  GameSpec(
    id: 'tetris',
    title: '俄罗斯方块',
    subtitle: '消行升级，堆顶判负',
    emoji: '🧱',
    accent: const Color(0xFFFFA726),
    builder: (_) => const TetrisPage(),
    bestKey: 'best_tetris',
  ),
  GameSpec(
    id: 'gomoku',
    title: '五子棋',
    subtitle: '人机对战 / 双人对弈',
    emoji: '⚫',
    accent: const Color(0xFFE0B040),
    builder: (_) => const GomokuPage(),
    bestKey: 'best_gomoku',
  ),
  GameSpec(
    id: 'pacman',
    title: '吃豆人',
    subtitle: 'Pac-Man · 经典街机复刻',
    emoji: '👻',
    accent: const Color(0xFFFFE100),
    builder: (_) => const PacManPage(),
    bestKey: 'pacman_best',
  ),
];
