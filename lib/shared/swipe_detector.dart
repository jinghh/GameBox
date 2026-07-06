import 'package:flutter/material.dart';

/// 四向滑动方向。
enum SwipeDir { up, down, left, right }

/// 四向滑动手势检测，2048 与贪吃蛇共用。
///
/// - [continuous]=false（默认，适合 2048）：一次完整手势只触发一次，
///   在 [onPanEnd] 时按总位移判定方向。
/// - [continuous]=true（适合贪吃蛇）：拖动过程中每越过阈值即触发并重置基准，
///   支持一根手指连续转向。
class SwipeDetector extends StatelessWidget {
  final Widget child;
  final ValueChanged<SwipeDir>? onSwipe;
  final double threshold;
  final bool continuous;

  const SwipeDetector({
    super.key,
    required this.child,
    this.onSwipe,
    this.threshold = 24,
    this.continuous = false,
  });

  static SwipeDir _dirOf(double dx, double dy) => dx.abs() > dy.abs()
      ? (dx > 0 ? SwipeDir.right : SwipeDir.left)
      : (dy > 0 ? SwipeDir.down : SwipeDir.up);

  @override
  Widget build(BuildContext context) {
    Offset? start;
    Offset? current;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) {
        start = d.localPosition;
        current = d.localPosition;
      },
      onPanUpdate: (d) {
        current = d.localPosition;
        if (!continuous) return;
        final s = start;
        if (s == null) return;
        final dx = current!.dx - s.dx;
        final dy = current!.dy - s.dy;
        if (dx.abs() < threshold && dy.abs() < threshold) return;
        onSwipe?.call(_dirOf(dx, dy));
        start = current; // 重置基准，支持连续转向
      },
      onPanEnd: continuous
          ? null
          : (_) {
              final s = start;
              final c = current;
              if (s == null || c == null) return;
              final dx = c.dx - s.dx;
              final dy = c.dy - s.dy;
              if (dx.abs() < threshold && dy.abs() < threshold) return;
              onSwipe?.call(_dirOf(dx, dy));
            },
      onPanCancel: () {
        start = null;
        current = null;
      },
      child: child,
    );
  }
}
