import 'dart:math';

import 'package:flutter/material.dart';

import 'pacman_entities.dart';
import 'pacman_map.dart';

class PacManPainter extends CustomPainter {
  final PacManView view;

  PacManPainter(this.view);

  static const Color _wall = Color(0xFF2121DE);
  static const Color _wallHi = Color(0xFF4A4AFF);
  static const Color _pellet = Color(0xFFF7C98A);
  static const Color _pac = Color(0xFFFFE100);
  static const Color _door = Color(0xFFFFB8DE);

  @override
  void paint(Canvas canvas, Size size) {
    final cols = PacManMap.cols;
    final tile = size.width / cols;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);

    _drawWalls(canvas, tile);
    _drawPellets(canvas, tile);
    _drawDoor(canvas, tile);
    for (final g in view.ghosts) {
      _drawGhost(canvas, g, tile);
    }
    _drawPac(canvas, tile);
  }

  void _drawWalls(Canvas canvas, double t) {
    final paint = Paint()..color = _wall;
    final hi = Paint()
      ..color = _wallHi
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, t * 0.06);
    final r = t * 0.28;
    for (int y = 0; y < PacManMap.rows; y++) {
      for (int x = 0; x < PacManMap.cols; x++) {
        if (view.grid[y][x] != Tile.wall) continue;
        final rect = Rect.fromLTWH(x * t, y * t, t, t).deflate(t * 0.04);
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(r));
        canvas.drawRRect(rr, paint);
        final inner = Rect.fromLTWH(x * t, y * t, t, t)
            .deflate(t * 0.20);
        canvas.drawRRect(
          RRect.fromRectAndRadius(inner, Radius.circular(r * 0.6)),
          hi,
        );
      }
    }
  }

  void _drawPellets(Canvas canvas, double t) {
    for (int y = 0; y < PacManMap.rows; y++) {
      for (int x = 0; x < PacManMap.cols; x++) {
        final cx = x * t + t / 2;
        final cy = y * t + t / 2;
        if (view.grid[y][x] == Tile.pellet) {
          canvas.drawCircle(
            Offset(cx, cy),
            t * 0.10,
            Paint()..color = _pellet,
          );
        } else if (view.grid[y][x] == Tile.energizer) {
          final pulse = 0.5 + 0.5 * sin(view.energizerPulse * 2 * pi);
          canvas.drawCircle(
            Offset(cx, cy),
            t * (0.26 + 0.06 * pulse),
            Paint()..color = _pellet,
          );
        }
      }
    }
  }

  void _drawDoor(Canvas canvas, double t) {
    for (int y = 0; y < PacManMap.rows; y++) {
      for (int x = 0; x < PacManMap.cols; x++) {
        if (view.grid[y][x] != Tile.door) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * t, y * t + t * 0.4, t, t * 0.2),
          Paint()..color = _door,
        );
      }
    }
  }

  void _drawPac(Canvas canvas, double t) {
    final cx = view.pac.x * t + t / 2;
    final cy = view.pac.y * t + t / 2;
    final r = t * 0.46 * (1 - 0.15 * view.dying);
    final base = switch (view.pac.dir) {
      Dir.up => -pi / 2,
      Dir.down => pi / 2,
      Dir.left => pi,
      Dir.right => 0,
      Dir.none => 0,
    };
    final mouth = 0.18 + 0.18 * sin(view.mouthPhase); // 常态张合
    final open = (mouth + view.dying * (2 * pi - mouth)).clamp(0.0, 2 * pi);
    if (open >= 2 * pi - 0.001) return; // 死亡收尾，已吃掉
    final start = base + open / 2;
    final sweep = 2 * pi - open;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      start,
      sweep,
      true,
      Paint()..color = _pac,
    );
  }

  Color _ghostColor(GhostName n) => switch (n) {
        GhostName.blinky => const Color(0xFFFF0000),
        GhostName.pinky => const Color(0xFFFFB8FF),
        GhostName.inky => const Color(0xFF00E5FF),
        GhostName.clyde => const Color(0xFFFFB852),
      };

  void _drawGhost(Canvas canvas, Ghost g, double t) {
    final cx = g.x * t + t / 2;
    final cy = g.y * t + t / 2;
    final r = t * 0.46;
    final left = cx - r * 0.92;
    final right = cx + r * 0.92;
    final top = cy - r;
    final bottom = cy + r * 0.92;

    final bodyPath = Path();
    bodyPath.moveTo(left, bottom);
    bodyPath.lineTo(left, top + r);
    bodyPath.arcToPoint(Offset(right, top + r),
        radius: Radius.circular(r), clockwise: false);
    bodyPath.lineTo(right, bottom);
    const humps = 3;
    final hw = (right - left) / humps;
    for (int i = 0; i < humps; i++) {
      final x1 = right - (i + 0.5) * hw;
      final x2 = right - (i + 1) * hw;
      bodyPath.quadraticBezierTo(x1, bottom - r * 0.28, x2, bottom);
    }
    bodyPath.close();

    if (g.mode == GhostMode.eyes) {
      // 仅眼睛
    } else {
      Color fill;
      if (g.mode == GhostMode.frightened) {
        fill = view.frightenedFlash ? Colors.white : _wall;
      } else {
        fill = _ghostColor(g.name);
      }
      canvas.drawPath(bodyPath, Paint()..color = fill);
    }

    if (g.mode == GhostMode.frightened) {
      _drawFrightFace(canvas, cx, cy, r);
    } else {
      _drawEyes(canvas, cx, cy, r, g.dir);
    }
  }

  void _drawEyes(Canvas canvas, double cx, double cy, double r, Dir dir) {
    final off = r * 0.34;
    final eyeR = r * 0.30;
    final pupR = r * 0.16;
    final ex = dir.dx * eyeR * 0.5;
    final ey = dir.dy * eyeR * 0.5;
    for (final sx in [-off, off]) {
      canvas.drawCircle(
        Offset(cx + sx, cy - r * 0.12),
        eyeR,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(cx + sx + ex, cy - r * 0.12 + ey),
        pupR,
        Paint()..color = const Color(0xFF1010FF),
      );
    }
  }

  void _drawFrightFace(Canvas canvas, double cx, double cy, double r) {
    final col = view.frightenedFlash ? _wall : Colors.white;
    final pr = Paint()..color = col;
    // 两只小眼
    for (final sx in [-r * 0.34, r * 0.34]) {
      canvas.drawCircle(Offset(cx + sx, cy - r * 0.12), r * 0.12, pr);
    }
    // 锯齿嘴
    final path = Path();
    final y0 = cy + r * 0.28;
    path.moveTo(cx - r * 0.4, y0);
    final seg = r * 0.4 / 3;
    for (int i = 0; i < 3; i++) {
      final x0 = cx - r * 0.4 + i * seg;
      path.lineTo(x0 + seg / 2, y0 + (i.isEven ? r * 0.12 : -r * 0.12));
      path.lineTo(x0 + seg, y0);
    }
    canvas.drawPath(path, pr);
  }

  @override
  bool shouldRepaint(covariant PacManPainter old) => true;
}
