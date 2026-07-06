// 2048 —— 经典数字合并。四向滑动合并相同数字，生成新块，目标 2048。
// 纯单机；最高分本地保存。
// 动画：瓦片用 AnimatedPositioned 平滑滑入目标格，新块缩放弹出，合并瓦片滑入后移除。

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/best_score_store.dart';
import '../../shared/game_shell.dart';
import '../../shared/swipe_detector.dart';

const Duration kSlide = Duration(milliseconds: 110);

class Game2048Page extends StatefulWidget {
  const Game2048Page({super.key});
  @override
  State<Game2048Page> createState() => _Game2048PageState();
}

/// 一个稳定身份的瓦片：跨一次移动保持 id，从而可动画其位置。
class _Tile {
  final int id;
  int value;
  int row, col;
  bool consumed; // 本次移动中被合并消失（先滑入目标格，动画结束后移除）
  bool justMerged; // 本次移动是合并的存活方
  bool justSpawned; // 本次新生成（缩放弹出）
  _Tile(this.id, this.value, this.row, this.col)
      : consumed = false,
        justMerged = false,
        justSpawned = false;
}

class _Game2048PageState extends State<Game2048Page> {
  final List<_Tile> _tiles = [];
  int _nextId = 0;
  int _score = 0;
  int _best = 0;
  bool _over = false;
  bool _won = false;
  bool _keepPlaying = false;
  bool _animating = false; // 滑动动画期间锁定输入，避免连击竞态
  final Random _rng = Random();
  final FocusNode _focus = FocusNode();

  static const String _bestKey = 'best_2048';

  @override
  void initState() {
    super.initState();
    _best = BestScoreStore.get(_bestKey);
    _reset();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _reset() {
    _tiles.clear();
    _nextId = 0;
    _score = 0;
    _over = false;
    _won = false;
    _keepPlaying = false;
    _animating = false;
    _spawnTile(animate: false);
    _spawnTile(animate: false);
  }

  void _newGame() => setState(_reset);

  void _spawnTile({required bool animate}) {
    final occupied = <int>{};
    for (final t in _tiles) {
      occupied.add(t.row * 4 + t.col);
    }
    final empties = <int>[];
    for (int i = 0; i < 16; i++) {
      if (!occupied.contains(i)) empties.add(i);
    }
    if (empties.isEmpty) return;
    final idx = empties[_rng.nextInt(empties.length)];
    final t = _Tile(_nextId++, _rng.nextDouble() < 0.9 ? 2 : 4, idx ~/ 4, idx % 4);
    t.justSpawned = animate;
    _tiles.add(t);
  }

  void _move(SwipeDir dir) {
    if (_over || (_won && !_keepPlaying) || _animating) return;
    for (final t in _tiles) {
      t.justMerged = false;
      t.justSpawned = false;
    }
    final (moved, gained) = _applyMove(dir);
    if (!moved) return; // 本方向无变化
    _animating = true;
    setState(() {
      _score += gained;
      if (_score > _best) {
        _best = _score;
        BestScoreStore.setIfGreater(_bestKey, _best);
      }
      _spawnTile(animate: true);
      if (!_won && _hasValue(2048)) _won = true;
      if (!_canMove(_valueGrid())) _over = true;
    });
    // 滑动动画结束后移除被合并的瓦片并解锁
    Future.delayed(kSlide + const Duration(milliseconds: 30), () {
      if (!mounted) return;
      setState(() {
        _tiles.removeWhere((t) => t.consumed);
        _animating = false;
      });
    });
  }

  /// 计算每个瓦片的目标格；统一转换成"向左压缩"处理。
  (bool moved, int gained) _applyMove(SwipeDir dir) {
    int gained = 0;
    bool moved = false;

    int laneOf(_Tile t) => (dir == SwipeDir.left || dir == SwipeDir.right)
        ? t.row
        : t.col;
    // 离目标墙最近的瓦片排在前面
    int nearestKey(_Tile t) {
      switch (dir) {
        case SwipeDir.left:
          return t.col;
        case SwipeDir.right:
          return -t.col;
        case SwipeDir.up:
          return t.row;
        case SwipeDir.down:
          return -t.row;
      }
    }

    (int, int) cellOf(int lane, int pos) {
      switch (dir) {
        case SwipeDir.left:
          return (lane, pos);
        case SwipeDir.right:
          return (lane, 3 - pos);
        case SwipeDir.up:
          return (pos, lane);
        case SwipeDir.down:
          return (3 - pos, lane);
      }
    }

    final lanes = <int, List<_Tile>>{};
    for (final t in _tiles) {
      (lanes[laneOf(t)] ??= []).add(t);
    }
    for (final entry in lanes.entries) {
      final lane = entry.key;
      final tiles = entry.value
        ..sort((a, b) => nearestKey(a).compareTo(nearestKey(b)));
      final settled = <_Tile>[];
      int pos = 0;
      for (final t in tiles) {
        final last = settled.isNotEmpty ? settled.last : null;
        if (last != null && last.value == t.value && !last.justMerged) {
          final (r, c) = cellOf(lane, pos - 1);
          if (t.row != r || t.col != c) moved = true;
          t.row = r;
          t.col = c;
          t.consumed = true;
          last.value *= 2;
          last.justMerged = true;
          gained += last.value;
        } else {
          final (r, c) = cellOf(lane, pos);
          if (t.row != r || t.col != c) moved = true;
          t.row = r;
          t.col = c;
          settled.add(t);
          pos++;
        }
      }
    }
    return (moved, gained);
  }

  List<int> _valueGrid() {
    final g = List<int>.filled(16, 0);
    for (final t in _tiles) {
      if (!t.consumed) g[t.row * 4 + t.col] = t.value;
    }
    return g;
  }

  bool _hasValue(int v) {
    for (final t in _tiles) {
      if (!t.consumed && t.value == v) return true;
    }
    return false;
  }

  bool _canMove(List<int> b) {
    for (int i = 0; i < 16; i++) {
      if (b[i] == 0) return true;
    }
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
        final v = b[r * 4 + c];
        if (c + 1 < 4 && b[r * 4 + c + 1] == v) return true;
        if (r + 1 < 4 && b[(r + 1) * 4 + c] == v) return true;
      }
    }
    return false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _move(SwipeDir.up);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      _move(SwipeDir.down);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _move(SwipeDir.left);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _move(SwipeDir.right);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '2048',
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
          onSwipe: _move,
          child: LayoutBuilder(
            builder: (ctx, c) {
              final side =
                  min(c.maxWidth, c.maxHeight - 84).clamp(180.0, 460.0);
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scoreBar(),
                    const SizedBox(height: 12),
                    _board(side),
                    const SizedBox(height: 14),
                    const Text('滑动合并相同数字',
                        style: TextStyle(
                            color: Color(0xFF888888), fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _board(double side) {
    const pad = 8.0;
    const gap = 8.0;
    final inner = side - 2 * pad;
    final cell = (inner - 3 * gap) / 4;
    double leftOf(int col) => pad + col * (cell + gap);
    double topOf(int row) => pad + row * (cell + gap);
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        children: [
          // 棋盘底 + 空格槽
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFBBADA0),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          for (int i = 0; i < 16; i++)
            Positioned(
              left: leftOf(i % 4),
              top: topOf(i ~/ 4),
              width: cell,
              height: cell,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x22000000),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          // 瓦片：位置由 row/col 决定，AnimatedPositioned 平滑过渡
          for (final t in _tiles)
            AnimatedPositioned(
              key: ValueKey(t.id),
              duration: kSlide,
              curve: Curves.easeOutQuad,
              left: leftOf(t.col),
              top: topOf(t.row),
              width: cell,
              height: cell,
              child: _tileVisual(t, cell),
            ),
          if (_over || (_won && !_keepPlaying)) _overlay(),
        ],
      ),
    );
  }

  Widget _tileVisual(_Tile t, double cell) {
    final box = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _tileColor(t.value),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${t.value}',
        style: TextStyle(
          color: t.value <= 4 ? const Color(0xFF776E65) : Colors.white,
          fontSize: _tileFont(t.value),
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.none,
        ),
      ),
    );
    if (t.justSpawned) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (_, s, child) => Transform.scale(scale: s, child: child),
        child: box,
      );
    }
    return box;
  }

  Widget _scoreBar() {
    return Row(
      children: [
        _scoreBox('得分', '$_score'),
        const SizedBox(width: 8),
        _scoreBox('最高', '$_best'),
      ],
    );
  }

  Widget _scoreBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFBBADA0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFFEEE4DA), fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _tileColor(int v) {
    const c = <int, Color>{
      2: Color(0xFFEEE4DA),
      4: Color(0xFFEDE0C8),
      8: Color(0xFFF2B179),
      16: Color(0xFFF59563),
      32: Color(0xFFF67C5F),
      64: Color(0xFFF65E3B),
      128: Color(0xFFEDCF72),
      256: Color(0xFFEDCC61),
      512: Color(0xFFEDC850),
      1024: Color(0xFFEDC53F),
      2048: Color(0xFFEDC22E),
    };
    return c[v] ?? const Color(0xFF3C3A32);
  }

  double _tileFont(int v) {
    if (v < 100) return 30;
    if (v < 1000) return 24;
    if (v < 10000) return 19;
    return 15;
  }

  Widget _overlay() {
    final won = _won && !_keepPlaying;
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC000000),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              won ? '达成 2048！' : '游戏结束',
              style: TextStyle(
                color: won ? const Color(0xFFFFD54A) : Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('得分 $_score',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            if (won)
              TextButton(
                onPressed: () => setState(() => _keepPlaying = true),
                child: const Text('继续挑战',
                    style: TextStyle(color: Color(0xFF6EE060), fontSize: 16)),
              ),
            TextButton(
              onPressed: _newGame,
              child: const Text('再来一局',
                  style: TextStyle(color: Color(0xFFFFD54A), fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
