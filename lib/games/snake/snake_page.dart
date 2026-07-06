// 贪吃蛇 —— 经典蛇。四向滑动控制方向，吃食物变长并加速，撞墙/撞身判负。
// 纯单机；最高分本地保存。CustomPainter 渲染（与坦克同款高效画法）。

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
  static const int _cols = 17, _rows = 17;
  List<Point<int>> _snake = [];
  Point<int> _food = const Point(0, 0);
  SwipeDir _dir = SwipeDir.right;
  SwipeDir? _nextDir;
  int _score = 0, _best = 0;
  bool _over = false, _started = false;
  int _speedMs = 200;
  bool _boost = false;
  Timer? _timer;
  final Random _rng = Random();
  final FocusNode _focus = FocusNode();

  static const String _bestKey = 'best_snake';

  @override
  void initState() {
    super.initState();
    _best = BestScoreStore.get(_bestKey);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _snake = [const Point(8, 8), const Point(7, 8), const Point(6, 8)];
    _dir = SwipeDir.right;
    _nextDir = null;
    _score = 0;
    _over = false;
    _started = false;
    _speedMs = 200;
    _boost = false;
    _placeFood();
  }

  void _newGame() => setState(_reset);

  void _start() {
    if (_started) return;
    _started = true;
    _armTimer();
    setState(() {});
  }

  int get _effectiveMs => _boost ? max(40, _speedMs ~/ 2) : _speedMs;

  void _armTimer() {
    _timer?.cancel();
    _timer =
        Timer.periodic(Duration(milliseconds: _effectiveMs), (_) => _tick());
  }

  void _setBoost(bool v) {
    if (_boost == v) return;
    _boost = v;
    if (_started && !_over) _armTimer();
    setState(() {});
  }

  void _placeFood() {
    // 空格随机放食物
    Point<int> p;
    do {
      p = Point(_rng.nextInt(_cols), _rng.nextInt(_rows));
    } while (_snake.contains(p));
    _food = p;
  }

  void _setDir(SwipeDir d) {
    if (_over) return;
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
    if (_over || !_started) return;
    if (_nextDir != null && !_isOpposite(_nextDir!, _dir)) {
      _dir = _nextDir!;
      _nextDir = null;
    }
    final head = _snake.first;
    final nh = _step(head, _dir);
    // 撞墙
    if (nh.x < 0 || nh.x >= _cols || nh.y < 0 || nh.y >= _rows) {
      _gameOver();
      return;
    }
    final willEat = nh == _food;
    // 撞身：吃食物时尾巴不移动，故可撞到当前尾节，排除之
    final body = willEat ? _snake : _snake.sublist(0, _snake.length - 1);
    if (body.contains(nh)) {
      _gameOver();
      return;
    }
    setState(() {
      _snake.insert(0, nh);
      if (willEat) {
        _score++;
        if (_score > _best) {
          _best = _score;
          BestScoreStore.setIfGreater(_bestKey, _best);
        }
        _placeFood();
        // 提速：每 5 分 -10ms，下限 80ms
        final target = 200 - (_score ~/ 5) * 10;
        final newSpeed = min(200, max(80, target));
        if (newSpeed != _speedMs) {
          _speedMs = newSpeed;
          _armTimer();
        }
      } else {
        _snake.removeLast();
      }
    });
  }

  void _gameOver() {
    _timer?.cancel();
    _timer = null;
    setState(() => _over = true);
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
        TextButton(
          onPressed: _newGame,
          child: const Text('新游戏',
              style: TextStyle(color: Color(0xFFFFD54A))),
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
              final side =
                  min(c.maxWidth - 24, c.maxHeight - 200).clamp(190.0, 340.0);
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scoreRow(),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: side,
                      height: side,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size.square(side),
                            painter:
                                _SnakePainter(_snake, _food, _cols, _rows),
                          ),
                          if (!_started || _over) _overlay(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: c.maxWidth - 16,
                      child: _controlsRow(),
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
        _chip('最高', '$_best', const Color(0xFFFFD54A)),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF999999), fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _overlay() {
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
            Text('得分 $_score    最高 $_best',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          if (start)
            const Text('滑动方向开始',
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

  // ---- 屏幕控件：方向键 + 加速键 ----
  Widget _controlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _dpad(),
        _boostBtn(),
      ],
    );
  }

  Widget _dpad() {
    const s = 44.0;
    return SizedBox(
      width: s * 3,
      height: s * 3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              top: 0, child: _dirBtn(Icons.arrow_drop_up, SwipeDir.up, s)),
          Positioned(
              bottom: 0,
              child: _dirBtn(Icons.arrow_drop_down, SwipeDir.down, s)),
          Positioned(
              left: 0, child: _dirBtn(Icons.arrow_left, SwipeDir.left, s)),
          Positioned(
              right: 0, child: _dirBtn(Icons.arrow_right, SwipeDir.right, s)),
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF444444)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dirBtn(IconData icon, SwipeDir d, double s) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setDir(d),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          shape: BoxShape.circle,
          border:
              Border.all(color: const Color(0xFF6EE060).withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: const Color(0xFF6EE060), size: s * 0.9),
      ),
    );
  }

  Widget _boostBtn() {
    final on = _boost;
    const color = Color(0xFFFFD54A);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setBoost(true),
      onTapUp: (_) => _setBoost(false),
      onTapCancel: () => _setBoost(false),
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          color: on ? color : const Color(0xFF262626),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt,
                color: on ? const Color(0xFF222222) : color, size: 30),
            Text('加速',
                style: TextStyle(
                    color: on ? const Color(0xFF222222) : color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _SnakePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final int cols, rows;
  _SnakePainter(this.snake, this.food, this.cols, this.rows);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / cols;
    final ch = size.height / rows;
    // 棋盘背景
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1F2A20),
    );
    // 食物
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(food.x * cw + 1.5, food.y * ch + 1.5, cw - 3, ch - 3),
        Radius.circular(cw * 0.3),
      ),
      Paint()..color = const Color(0xFFFF5252),
    );
    // 蛇身
    for (int i = 0; i < snake.length; i++) {
      final p = snake[i];
      final isHead = i == 0;
      final paint = Paint()
        ..color = isHead ? const Color(0xFFFFD54A) : const Color(0xFF6EE060);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(p.x * cw + 1, p.y * ch + 1, cw - 2, ch - 2),
          Radius.circular(cw * 0.25),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter old) => true;
}
