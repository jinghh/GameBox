// 贪吃蛇 —— 横屏。全屏滑动转向(移动端原生操控),关卡制:吃够目标数量即过关,
// 过关后蛇身长度保留,新增障碍物 + 提速增加难度。初始较慢,逐级加快。
// 撞墙 / 撞身 / 撞障碍判负。纯单机;最高分本地保存。CustomPainter 渲染。

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/best_score_store.dart';
import '../../shared/game_shell.dart';
import '../../shared/swipe_detector.dart';

class SnakePage extends StatefulWidget {
  const SnakePage({super.key});
  @override
  State<SnakePage> createState() => _SnakePageState();
}

class _SnakePageState extends State<SnakePage> {
  // 横屏网格:宽 > 高。逻辑格与像素格都按 cols/rows 比例缩放,保证每格是正方形。
  static const int _cols = 29, _rows = 11;
  List<Point<int>> _snake = [];
  Point<int> _food = const Point(0, 0);
  final Set<Point<int>> _obstacles = {};
  SwipeDir _dir = SwipeDir.right;
  SwipeDir? _nextDir;
  int _score = 0, _best = 0;
  int _level = 1;
  int _levelEaten = 0; // 当前关已吃数量
  int get _levelTarget => 4 + _level; // 过关所需(随关卡缓增)
  bool _over = false, _started = false, _paused = false, _leveling = false;
  Timer? _timer;
  Timer? _clock; // 游玩计时(秒)
  Timer? _levelTimer; // 过关横幅展示计时
  int _elapsed = 0;
  double _eatAnim = 0; // 张嘴吃食物动画(0..1,逐 tick 衰减)
  final Random _rng = Random();
  final FocusNode _focus = FocusNode();

  static const String _bestKey = 'best_snake';

  @override
  void initState() {
    super.initState();
    // 进页面锁横屏,退出时在 dispose 恢复竖屏
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
    _focus.dispose();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  /// 当前速度(ms/步):初始 240(较慢),每关 -16,关卡内每吃一个 -4,下限 85。
  int get _speedMs =>
      max(85, (240 - (_level - 1) * 16) - _levelEaten * 4);

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _clock?.cancel();
    _clock = null;
    _levelTimer?.cancel();
    _levelTimer = null;
    _snake = [
      const Point(14, 5),
      const Point(13, 5),
      const Point(12, 5),
    ];
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

  /// 按 _level 生成障碍物(数量随关卡累计上升),避开蛇身 / 食物 / 蛇头正前方一格。
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
    // 禁止 180° 反向
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
          _armTimer(); // 每吃一个略提速
        }
      } else {
        _snake.removeLast();
      }
    });
  }

  /// 过关:蛇身长度保留,障碍增加,提速,展示 1.5s 过关横幅后自动继续。
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

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _setDir(SwipeDir.up);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      _setDir(SwipeDir.down);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _setDir(SwipeDir.left);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _setDir(SwipeDir.right);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '贪吃蛇',
      actions: [
        if (_started && !_over)
          IconButton(
            tooltip: _paused ? '继续' : '暂停',
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause,
                color: const Color(0xFF6EE060)),
            onPressed: _togglePause,
          ),
        TextButton(
          onPressed: _newGame,
          child: const Text('新游戏',
              style: TextStyle(color: Color(0xFF6EE060))),
        ),
      ],
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SwipeDetector(
          continuous: true,
          onSwipe: _setDir,
          child: LayoutBuilder(
            builder: (ctx, c) {
              final maxW = c.maxWidth - 24;
              final maxH = c.maxHeight - 56; // 顶部状态行 + 间距
              final aspect = _cols / _rows;
              var bw = maxW;
              var bh = bw / aspect;
              if (bh > maxH) {
                bh = maxH;
                bw = bh * aspect;
              }
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: c.maxWidth, child: _scoreRow()),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: bw,
                      height: bh,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size(bw, bh),
                            painter: _SnakePainter(
                              _snake,
                              _food,
                              _obstacles,
                              _cols,
                              _rows,
                              _dir,
                              _eatAnim,
                            ),
                          ),
                          if (!_started || _over || _paused || _leveling)
                            _overlay(),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _scoreRow() {
    return Row(
      children: [
        _chip('得分', '$_score', const Color(0xFF6EE060)),
        const SizedBox(width: 8),
        _chip('关卡', '$_level', const Color(0xFFFFA726)),
        const SizedBox(width: 8),
        _chip('进度', '$_levelEaten/$_levelTarget', const Color(0xFFBA68C8)),
        const SizedBox(width: 8),
        _chip('最高', '$_best', const Color(0xFFFFD54A)),
        const SizedBox(width: 8),
        _chip('用时', _fmtTime(_elapsed), const Color(0xFF64B5F6)),
      ],
    );
  }

  String _fmtTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF999999), fontSize: 9)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _overlay() {
    if (_leveling) {
      return Container(
        color: const Color(0xAA000000),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎉 第 $_level 关 通过！',
                style: const TextStyle(
                    color: Color(0xFFFFD54A),
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('蛇身长度 ${_snake.length} · 障碍 +${(_level - 1) * 3}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            const Text('准备加速…',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    if (_paused) {
      return Container(
        color: const Color(0xCC000000),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂停',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _togglePause,
              child: const Text('继续游戏',
                  style: TextStyle(color: Color(0xFF6EE060), fontSize: 16)),
            ),
          ],
        ),
      );
    }
    final start = !_started;
    return Container(
      color: const Color(0xCC000000),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            start ? '贪吃蛇' : '游戏结束',
            style: TextStyle(
              color: start ? const Color(0xFF6EE060) : Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!start) ...[
            const SizedBox(height: 10),
            Text('得分 $_score · 第 $_level 关 · 最高 $_best',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          if (start)
            const Text('滑动方向开始（横屏）',
                style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14))
          else
            TextButton(
              onPressed: _newGame,
              child: const Text('再来一局',
                  style: TextStyle(color: Color(0xFFFFD54A), fontSize: 16)),
            ),
        ],
      ),
    );
  }
}

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
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1F2A20));

    // 障碍物(灰岩石块)
    final obPaint = Paint()..color = const Color(0xFF55605A);
    for (final o in obstacles) {
      final r = Rect.fromLTWH(o.x * cw + 1, o.y * ch + 1, cw - 2, ch - 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(cw * 0.18)), obPaint);
    }

    // 食物
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(food.x * cw + 1.5, food.y * ch + 1.5, cw - 3, ch - 3),
        Radius.circular(cw * 0.3),
      ),
      Paint()..color = const Color(0xFFFF5252),
    );

    // 蛇
    for (int i = 0; i < snake.length; i++) {
      final p = snake[i];
      final isHead = i == 0;
      final rect = Rect.fromLTWH(p.x * cw + 1, p.y * ch + 1, cw - 2, ch - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cw * 0.25)),
        Paint()
          ..color = isHead ? const Color(0xFFFFD54A) : const Color(0xFF6EE060),
      );
      if (isHead) _drawHead(canvas, rect);
    }
  }

  /// 蛇头:两眼朝行进方向,吃到食物时嘴张开。
  void _drawHead(Canvas canvas, Rect r) {
    final (fx, fy) = switch (dir) {
      SwipeDir.up => (0.0, -1.0),
      SwipeDir.down => (0.0, 1.0),
      SwipeDir.left => (-1.0, 0.0),
      SwipeDir.right => (1.0, 0.0),
    };
    final (px, py) = (-fy, fx); // 垂直方向
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
    // 嘴:前方张开的楔形,随吃食动画放大
    final e = eatAnim;
    if (e > 0.02) {
      final depth = w * 0.26 * e;
      final half = w * 0.16 * (0.4 + 0.6 * e);
      final tip = Offset(cx + fx * w * 0.34, cy + fy * w * 0.34);
      final b1 = Offset(cx - fx * depth + px * half, cy - fy * depth + py * half);
      final b2 = Offset(cx - fx * depth - px * half, cy - fy * depth - py * half);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(b2.dx, b2.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF5A1414));
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter old) => true;
}
