// 游戏主页：点击合集里的某个游戏后进入,在此选择「单人版 / 双人版 / 联机版」。
// 同一游戏的多个入口(旧菜单里分裂的 tank / tank_online、bomber / bomber_coop /
// bomber_online)在此合并为一张卡片 + 三个模式,逻辑集中在 _kGameConfigs。

import 'package:flutter/material.dart';

import '../games/bomberman/bomberman_page.dart';
import '../games/bomberman/net/bomber_bt_room_page.dart';
import '../games/tank/battle_city_game.dart';
import '../games/tank/net/bt_room_page.dart';
import '../shared/best_score_store.dart';

/// 支持「游戏主页(选模式)」的游戏类型。
enum GameType { tank, bomber }

/// 单个模式入口(单人 / 双人 / 联机)。
class _ModeEntry {
  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  const _ModeEntry(this.label, this.sub, this.icon, this.color, this.builder);
}

/// 一个游戏的全部配置(主页标题 + 模式列表)。
class _GameConfig {
  final String title;
  final String subtitle;
  final String emoji;
  final Color accent;
  final String? bestKey; // 最高分 key;null=不显示成绩
  final List<_ModeEntry> modes;
  const _GameConfig({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.accent,
    this.bestKey,
    required this.modes,
  });
}

/// 游戏主页配置表:新增游戏只需在此追加一项,并在 [kGames] 用 GameHomePage 指向它。
final Map<GameType, _GameConfig> _kGameConfigs = {
  GameType.tank: _GameConfig(
    title: '坦克大战',
    subtitle: 'Battle City · 守护基地',
    emoji: '🛡️',
    accent: const Color(0xFFFFD54A),
    modes: [
      _ModeEntry(
        '单人版',
        '一人闯关,守护基地',
        Icons.person_outline,
        const Color(0xFFE0A030),
        (_) => const BattleCityGame(twoPlayer: false),
      ),
      _ModeEntry(
        '双人版',
        '同一手机 · 双人对抗/合作',
        Icons.people_outline,
        const Color(0xFF4CAF50),
        (_) => const BattleCityGame(twoPlayer: true),
      ),
      _ModeEntry(
        '联机版',
        '蓝牙连接两台手机闯关',
        Icons.bluetooth,
        const Color(0xFF42A5F5),
        (_) => TankBtRoomPage(),
      ),
    ],
  ),
  GameType.bomber: _GameConfig(
    title: '泡泡堂',
    subtitle: '放雷炸敌 · 过关递增',
    emoji: '💣',
    accent: const Color(0xFFFF8A4C),
    bestKey: 'best_bomber',
    modes: [
      _ModeEntry(
        '单人版',
        '闯关炸敌,收集道具',
        Icons.person_outline,
        const Color(0xFFE0A030),
        (_) => const BomberPage(),
      ),
      _ModeEntry(
        '双人版',
        '同一手机 · 双人闯关',
        Icons.people_outline,
        const Color(0xFF66BB6A),
        (_) => const BomberPage(coop: true),
      ),
      _ModeEntry(
        '联机版',
        '蓝牙 · 1v1 对战',
        Icons.bluetooth,
        const Color(0xFFEF5350),
        (_) => BomberBtRoomPage(),
      ),
    ],
  ),
};

/// 游戏主页:标题 + 最高成绩 + 三个模式按钮,点击进入对应玩法。
class GameHomePage extends StatelessWidget {
  final GameType type;
  const GameHomePage({super.key, required this.type});

  String? _bestLine(_GameConfig cfg) {
    if (cfg.bestKey != null && BestScoreStore.has(cfg.bestKey!)) {
      final v = BestScoreStore.get(cfg.bestKey!);
      return '🏆 最高 $v';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _kGameConfigs[type]!;
    final bestText = _bestLine(cfg);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF201E1A), Color(0xFF141417)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(cfg: cfg, bestText: bestText),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  itemCount: cfg.modes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (ctx, i) => _ModeTile(
                    entry: cfg.modes[i],
                    onTap: () => Navigator.of(ctx).push(
                      MaterialPageRoute<void>(builder: cfg.modes[i].builder),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部:返回箭头 + 图标/标题/副标题 + 最高成绩胶囊。
class _Header extends StatelessWidget {
  final _GameConfig cfg;
  final String? bestText;
  const _Header({required this.cfg, this.bestText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              if (bestText != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cfg.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: cfg.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(bestText!,
                      style: TextStyle(
                          color: cfg.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cfg.accent, cfg.accent.withValues(alpha: 0.55)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: cfg.accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Center(child: Text(cfg.emoji, style: const TextStyle(fontSize: 32))),
          ),
          const SizedBox(height: 12),
          Text(cfg.title,
              style: const TextStyle(
                  color: Color(0xFFF2F2F5),
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(cfg.subtitle,
              style: const TextStyle(color: Color(0xFF9A9AA2), fontSize: 12)),
          const SizedBox(height: 6),
          const Text('选择模式开始',
              style: TextStyle(color: Color(0xFF6E6E78), fontSize: 12)),
        ],
      ),
    );
  }
}

/// 单个模式按钮:图标 + 标题 + 说明 + 右箭头。
class _ModeTile extends StatelessWidget {
  final _ModeEntry entry;
  final VoidCallback onTap;
  const _ModeTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: const Color(0xFF212128),
        child: InkWell(
          onTap: onTap,
          splashColor: entry.color.withValues(alpha: 0.2),
          highlightColor: entry.color.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              border: Border.all(
                  color: entry.color.withValues(alpha: 0.35), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: entry.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(entry.icon, color: entry.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(entry.sub,
                          style: const TextStyle(
                              color: Color(0xFF9A9AA2), fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: entry.color.withValues(alpha: 0.6), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
