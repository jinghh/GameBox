import 'package:flutter/material.dart';

import '../app/games.dart';
import '../shared/best_score_store.dart';
import '../shared/sound_store.dart';

/// 合集主页：游戏列表网格，由 [kGames] 注册表驱动。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
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
              const _Header(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 响应式列数：以 ~190 为理想卡片宽度，限定 2~4 列。
                    final cols =
                        (constraints.maxWidth / 190).floor().clamp(2, 4);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: kGames.length,
                      itemBuilder: (context, i) => _GameCard(spec: kGames[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部品牌区：渐变大标题 + 标签胶囊 + 静音按钮。
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFFFFE082), Color(0xFFFFB300)],
                  ).createShader(b),
                  child: const Text(
                    'GAMEBOX',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(label: '🎮 ${kGames.length} 款游戏'),
                    const _Pill(label: '📶 含蓝牙联机'),
                  ],
                ),
              ],
            ),
          ),
          const _MuteButton(),
        ],
      ),
    );
  }
}

/// 顶部小标签胶囊。
class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFFB8B8C0)),
      ),
    );
  }
}

/// 圆形静音按钮，状态变化仅重建自身。
class _MuteButton extends StatelessWidget {
  const _MuteButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: kMuted,
      builder: (_, muted, child) => Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: SoundStore.toggle,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                  color: const Color(0xFFFFD54A).withValues(alpha: 0.4)),
            ),
            child: Icon(
              muted ? Icons.volume_off : Icons.volume_up,
              color: const Color(0xFFFFD54A),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameSpec spec;
  const _GameCard({required this.spec});

  void _open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: spec.builder));

  /// 副信息行：有成绩显示「🏆 最高/最佳」，无成绩显示 subtitle。
  (String text, bool hasBest) _subLine() {
    final key = spec.bestKey;
    if (key != null && BestScoreStore.has(key)) {
      final v = BestScoreStore.get(key);
      if (spec.bestIsTime) {
        final m = (v ~/ 60).toString().padLeft(2, '0');
        final s = (v % 60).toString().padLeft(2, '0');
        return ('🏆 最佳 $m:$s', true);
      }
      return ('🏆 最高 $v', true);
    }
    return (spec.subtitle, false);
  }

  @override
  Widget build(BuildContext context) {
    final (sub, hasBest) = _subLine();
    final accent = spec.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF212128),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.14), const Color(0xFF212128)],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.30), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: accent.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6)),
            const BoxShadow(
                color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(context),
            splashColor: accent.withValues(alpha: 0.22),
            highlightColor: accent.withValues(alpha: 0.10),
            child: Column(
              children: [
                // 顶部 accent 装饰条（被父级 ClipRRect 裁出圆角）
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0.35)],
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    accent,
                                    accent.withValues(alpha: 0.55),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                      color: accent.withValues(alpha: 0.45),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Center(
                                child: Text(spec.emoji,
                                    style: const TextStyle(fontSize: 32)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              spec.title,
                              style: const TextStyle(
                                color: Color(0xFFF2F2F5),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: hasBest
                                    ? accent
                                    : const Color(0xFF9A9AA2),
                                fontSize: 11.5,
                                fontWeight: hasBest
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 10,
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: accent.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
