// 贪吃蛇 —— 横屏全屏。坦克同款虚拟摇杆(半透明悬浮),关卡制:吃够目标数量即过关,
// 过关后蛇身长度保留,新增障碍物 + 提速增加难度。初始较慢,逐级加快。
// 撞墙 / 撞身 / 撞障碍判负。纯单机;最高分本地保存。CustomPainter 渲染。

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/best_score_store.dart';
import '../../shared/swipe_detector.dart';

class SnakePage extends StatefulWidget {
  const SnakePage({super.key});
  @override
  State<SnakePage> createState() => _SnakePageState();
}

class _SnakePageState extends State<SnakePage> {
  static const int _cols = 29, _rows = 11;
  List<Point<int>> _snake = [];
  Point<int> _food = const Point(0, 0);
  final Set<Point<int>> _obstacles = {};
  SwipeDir _dir = SwipeDir.right;
  SwipeDir? _nextDir;
  int _score = 0, _best = 0;
  int _level = 1;
  int _levelEaten = 0;
  int get _levelTarget => 4 + _level;
  bool _over = false, _started = false, _paused = false, _leveling = false;
  Timer? _timer;
  Timer? _clock;
  Timer? _levelTimer;
  int _elapsed = 0;
  double _eatAnim = 0;
  final Random _rng = Random();

  static const String _bestKey = 'best_snake';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _best = BestScoreStore.get(_bestKey);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock?.cancel();
    _levelTimer?.cancel();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  int get _speedMs => max(85, (240 - (_level - 1) * 16) - _levelEaten * 4);

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _clock?.cancel();
    _clock = null;
    _levelTimer?.cancel();
    _levelTimer = null;
    _snake = [const Point(14, 5), const Point(13, 5), const Point(12, 5)];
    _dir = SwipeDir.right;
    _nextDir = null;
    _score = 0;
    _level = 1;
    _levelEaten = 0;
    _over = false;
    _started = false;
    _paused = false;
    _leveling = false;
    _elapsed = 0;
    _eatAnim = 0;
    _obstacles.clear();
    _placeFood();
    _regenObstacles();
  }

  void _newGame() => setState(_reset);

  void _start() {
    if (_started) return;
    _started = true;
    _armTimer();
    _startClock();
    setState(() {});
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  void _togglePause() {
    if (!_started || _over || _leveling) return;
    _paused = !_paused;
    if (_paused) {
      _timer?.cancel();
      _timer = null;
      _clock?.cancel();
      _clock = null;
    } else {
      _armTimer();
      _startClock();
    }
    setState(() {});
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _speedMs), (_) => _tick());
  }

  void _placeFood() {
    Point<int> p;
    do {
      p = Point(_rng.nextInt(_cols), _rng.nextInt(_rows));
    } while (_snake.contains(p) || _obstacles.contains(p));
    _food = p;
  }

  void _regenObstacles() {
    _obstacles.clear();
    final want = min((_level - 1) * 3, (_cols * _rows) ~/ 6);
    if (want <= 0) return;
    final occupied = <Point<int>>{..._snake, _food};
    final headFwd = _step(_snake.first, _dir);
    int tries = 0;
    while (_obstacles.length < want && tries < want * 25) {
      tries++;
      final p = Point(_rng.nextInt(_cols), _rng.nextInt(_rows));
      if (occupied.contains(p) || _obstacles.contains(p) || p == headFwd) {
        continue;
      }
      _obstacles.add(p);
      occupied.add(p);
    }
  }

  void _setDir(SwipeDir d) {
    if (_over || _paused || _leveling) return;
    if (_isOpposite(d, _dir)) return;
    _nextDir = d;
    if (!_started) _start();
  }

  bool _isOpposite(SwipeDir a, SwipeDir b) =>
      (a == SwipeDir.up && b == SwipeDir.down) ||
      (a == SwipeDir.down && b == SwipeDir.up) ||
      (a == SwipeDir.left && b == SwipeDir.right) ||
      (a == SwipeDir.right && b == SwipeDir.left);

  Point<int> _step(Point<int> p, SwipeDir d) {
    switch (d) {
      case SwipeDir.up:
        return Point(p.x, p.y - 1);
      case SwipeDir.down:
        return Point(p.x, p.y + 1);
      case SwipeDir.left:
        return Point(p.x - 1, p.y);
      case SwipeDir.right:
        return Point(p.x + 1, p.y);
    }
  }

  void _tick() {
    if (_over || !_started || _paused || _leveling) return;
    _eatAnim = max(0, _eatAnim - 0.3);
    if (_nextDir != null && !_isOpposite(_nextDir!, _dir)) {
      _dir = _nextDir!;
      _nextDir = null;
    }
    final head = _snake.first;
    final nh = _step(head, _dir);
    if (nh.x < 0 || nh.x >= _cols || nh.y < 0 || nh.y >= _rows ||
        _obstacles.contains(nh)) {
      _gameOver();
      return;
    }
    final willEat = nh == _food;
    final body = willEat ? _snake : _snake.sublist(0, _snake.length - 1);
    if (body.contains(nh)) {
      _gameOver();
      return;
    }
    setState(() {
      _snake.insert(0, nh);
      if (willEat) {
        HapticFeedback.mediumImpact();
        _eatAnim = 1.0;
        _score++;
        _levelEaten++;
        if (_score > _best) {
          _best = _score;
          BestScoreStore.setIfGreater(_bestKey, _best);
        }
        if (_levelEaten >= _levelTarget) {
          _levelUp();
        } else {
          _placeFood();
          _armTimer();
        }
      } else {
        _snake.removeLast();
      }
    });
  }

  void _levelUp() {
    _timer?.cancel();
    _timer = null;
    _clock?.cancel();
    _clock = null;
    _level++;
    _levelEaten = 0;
    _regenObstacles();
    _placeFood();
    _leveling = true;
    HapticFeedback.heavyImpact();
    _levelTimer?.cancel();
    _levelTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || _over) return;
      _leveling = false;
      _armTimer();
      _startClock();
      setState(() {});
    });
  }

  void _gameOver() {
    _timer?.cancel();
    _timer = null;
    _clock?.cancel();
    _clock = null;
    _levelTimer?.cancel();
    _levelTimer = null;
    HapticFeedback.heavyImpact();
    setState(() {
      _over = true;
      _leveling = false;
    });
  }

  String _fmtTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  void _exit() => Navigator.of(context).pop();

  // ---- UI (全屏 Stack,无 AppBar) ----
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0D14),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, c) {
              final cellW = c.maxWidth / _cols;
              final cellH = c.maxHeight / _rows;
              final cell = min(cellW, cellH);
              final bw = cell * _cols;
              final bh = cell * _rows;
              final boardLeft = (c.maxWidth - bw) / 2;
              return Stack(
                children: [
                  // 棋盘(全屏居中)
                  Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: bw,
                        height: bh,
                        child: CustomPaint(
                          painter: _SnakePainter(_snake, _food, _obstacles,
                              _cols, _rows, _dir, _eatAnim),
                        ),
                      ),
                    ),
                  ),
                  // 顶部半透明 HUD
                  Positioned(
                    top: 2,
                    left: 8,
                    right: 8,
                    child: _hud(),
                  ),
                  // 右上:暂停/退出
                  Positioned(
                    top: 2,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_started && !_over && !_leveling)
                          _floatBtn(
                              _paused ? Icons.play_arrow : Icons.pause,
                              _togglePause),
                        _floatBtn(Icons.close, _exit),
                      ],
                    ),
                  ),
                  // 摇杆:左下半区
                  Positioned(
                    left: boardLeft + 4,
                    bottom: 4,
                    child: SizedBox(
                      width: c.maxWidth * 0.38,
                      height: c.maxHeight * 0.55,
                      child: _Joystick(
                        onDir: (d) {
                          if (d != null) _setDir(d);
                        },
                      ),
                    ),
                  ),
                  // 遮罩(未开始 / 暂停 / 过关 / 结束)
                  if (!_started || _over || _paused || _leveling)
                    Positioned.fill(
                      child: Container(
                          color: const Color(0xCC000000),
                          alignment: Alignment.center,
                          child: _overlay()),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _hud() {
    return Row(
      children: [
        _chip('得分$_score', const Color(0xFF6EE060)),
        const SizedBox(width: 6),
        _chip('第$_level关', const Color(0xFFFFA726)),
        const SizedBox(width: 6),
        _chip('$_levelEaten/$_levelTarget', const Color(0xFFBA68C8)),
        const SizedBox(width: 6),
        _chip(_fmtTime(_elapsed), const Color(0xFF64B5F6)),
        const SizedBox(width: 6),
        _chip('🏆$_best', const Color(0xFFFFD54A)),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x88000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _floatBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0x55000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  Widget _overlay() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_leveling) ...[
          Text('🎉 第 $_level 关 通过!',
              style: const TextStyle(
                  color: Color(0xFFFFD54A),
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('蛇身长度 ${_snake.length} · 障碍 +${(_level - 1) * 3}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ] else if (_paused) ...[
          const Text('暂停',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _ovBtn('继续', const Color(0xFF6EE060), _togglePause),
        ] else if (_over) ...[
          const Text('游戏结束',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('得分 $_score · 第 $_level 关 · 最高 $_best',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 14),
          _ovBtn('再来一局', const Color(0xFFFFD54A), _newGame),
        ] else ...[
          const Text('贪吃蛇',
              style: TextStyle(
                  color: Color(0xFF6EE060),
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('摇杆控制方向 · 横屏全屏',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 14),
          _ovBtn('开始', const Color(0xFF6EE060), _start),
        ],
      ],
    );
  }

  Widget _ovBtn(String text, Color color, VoidCallback onTap) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 9),
      ),
      onPressed: onTap,
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF222222), fontWeight: FontWeight.bold)),
    );
  }
}

// ---- 虚拟摇杆(仿坦克,四向拖动) ----
class _Joystick extends StatefulWidget {
  final ValueChanged<SwipeDir?> onDir;
  const _Joystick({required this.onDir});

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  static const double _base = 56;
  static const double _dead = 12;

  Offset? _origin;
  Offset? _knob;

  void _update(Offset o, {required bool isNew}) {
    final origin = isNew ? o : (_origin ?? o);
    final dx = o.dx - origin.dx;
    final dy = o.dy - origin.dy;
    final len2 = dx * dx + dy * dy;
    SwipeDir? dir;
    Offset knob = origin;
    if (len2 >= _dead * _dead) {
      final len = sqrt(len2);
      final cl = len > _base ? _base / len : 1.0;
      knob = Offset(origin.dx + dx * cl, origin.dy + dy * cl);
      dir = dx.abs() > dy.abs()
          ? (dx > 0 ? SwipeDir.right : SwipeDir.left)
          : (dy > 0 ? SwipeDir.down : SwipeDir.up);
    }
    setState(() {
      _origin = origin;
      _knob = knob;
    });
    widget.onDir(dir);
  }

  void _reset() {
    setState(() {
      _origin = null;
      _knob = null;
    });
    widget.onDir(null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (d) => _update(d.localPosition, isNew: true),
      onPanUpdate: (d) => _update(d.localPosition, isNew: false),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: CustomPaint(
        painter: _JoystickPainter(_origin, _knob),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset? origin;
  final Offset? knob;
  _JoystickPainter(this.origin, this.knob);

  @override
  void paint(Canvas canvas, Size size) {
    if (origin == null) return;
    canvas.drawCircle(
        origin!, 56, Paint()..color = const Color(0x18FFFFFF));
    canvas.drawCircle(
      origin!,
      56,
      Paint()
        ..color = const Color(0x44FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
        knob ?? origin!, 24, Paint()..color = const Color(0x88FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---- 画蛇 ----
class _SnakePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final Set<Point<int>> obstacles;
  final int cols, rows;
  final SwipeDir dir;
  final double eatAnim;

  _SnakePainter(this.snake, this.food, this.obstacles, this.cols, this.rows,
      this.dir, this.eatAnim);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / cols;
    final ch = size.height / rows;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E1118));

    // 边框(微亮)
    canvas.drawRect(Offset.zero & size,
        Paint()
          ..color = const Color(0xFF2A303A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // 障碍物
    final obPaint = Paint()..color = const Color(0xFF414A58);
    for (final o in obstacles) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.x * cw + 2, o.y * ch + 2, cw - 4, ch - 4),
          Radius.circular(cw * 0.15),
        ),
        obPaint,
      );
    }

    // 食物
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            food.x * cw + 2, food.y * ch + 2, cw - 4, ch - 4),
        Radius.circular(cw * 0.28),
      ),
      Paint()..color = const Color(0xFFFF5252),
    );

    // 蛇
    for (int i = 0; i < snake.length; i++) {
      final p = snake[i];
      final isHead = i == 0;
      final rect = Rect.fromLTWH(p.x * cw + 2, p.y * ch + 2, cw - 4, ch - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cw * 0.25)),
        Paint()
          ..color = isHead ? const Color(0xFFFFD54A) : const Color(0xFF6EE060),
      );
      if (isHead) _drawHead(canvas, rect);
    }
  }

  void _drawHead(Canvas canvas, Rect r) {
    final (fx, fy) = switch (dir) {
      SwipeDir.up => (0.0, -1.0),
      SwipeDir.down => (0.0, 1.0),
      SwipeDir.left => (-1.0, 0.0),
      SwipeDir.right => (1.0, 0.0),
    };
    final (px, py) = (-fy, fx);
    final cx = r.center.dx, cy = r.center.dy;
    final w = r.width;
    final eye = Paint()..color = const Color(0xFFFFFFFF);
    final pup = Paint()..color = const Color(0xFF1A1A1A);
    final er = w * 0.13, pr = w * 0.065;
    final fwd = w * 0.10, sep = w * 0.20;
    for (final s in const [-1.0, 1.0]) {
      final ex = cx + fx * fwd + px * sep * s;
      final ey = cy + fy * fwd + py * sep * s;
      canvas.drawCircle(Offset(ex, ey), er, eye);
      canvas.drawCircle(Offset(ex + fx * pr, ey + fy * pr), pr, pup);
    }
    final e = eatAnim;
    if (e > 0.02) {
      final depth = w * 0.26 * e;
      final half = w * 0.16 * (0.4 + 0.6 * e);
      final tip = Offset(cx + fx * w * 0.34, cy + fy * w * 0.34);
      final b1 = Offset(cx - fx * depth + px * half, cy - fy * depth + py * half);
      final b2 =
          Offset(cx - fx * depth - px * half, cy - fy * depth - py * half);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(b1.dx, b1.dy)
          ..lineTo(b2.dx, b2.dy)
          ..close(),
        Paint()..color = const Color(0xFF5A1414),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter old) => true;
}
