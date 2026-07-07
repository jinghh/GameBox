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
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('经典小游戏',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 1),
            Text('${kGames.length} 款 · 纯单机离线',
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 11, height: 1.2)),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: kMuted,
            builder: (_, muted, __) => IconButton(
              tooltip: muted ? '取消静音' : '静音',
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up,
                  color: const Color(0xFFFFD54A)),
              onPressed: SoundStore.toggle,
            ),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.96,
        ),
        itemCount: kGames.length,
        itemBuilder: (context, i) => _GameCard(spec: kGames[i]),
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: spec.accent.withValues(alpha: 0.32), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: spec.accent.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 5)),
          const BoxShadow(
              color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(context),
            splashColor: spec.accent.withValues(alpha: 0.20),
            highlightColor: spec.accent.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          spec.accent,
                          spec.accent.withValues(alpha: 0.55),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: spec.accent.withValues(alpha: 0.45),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Center(
                      child: Text(spec.emoji,
                          style: const TextStyle(
                              fontSize: 30, decoration: TextDecoration.none)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    spec.title,
                    style: TextStyle(
                      color: spec.accent,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasBest ? spec.accent : const Color(0xFF999999),
                      fontSize: 11,
                      fontWeight:
                          hasBest ? FontWeight.bold : FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
