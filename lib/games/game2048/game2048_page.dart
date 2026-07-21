// 2048 —— 经典数字合并。四向滑动合并相同数字，生成新块，目标 2048。
// 纯单机；最高分本地保存。
// 动画：瓦片用 AnimatedPositioned 平滑滑入目标格，新块缩放弹出，合并瓦片滑入后移除。

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../debug/game_debug_registry.dart';
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

class _Game2048PageState extends State<Game2048Page>
    with GameDebugMixin<Game2048Page> {
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

  // ---- 调试面板(GameDebug) ----
  @override
  String get id => 'g2048';

  @override
  int? get currentLevel => null; // 无关卡

  @override
  int? get maxLevel => null;

  @override
  Map<String, String> info() => {
        '得分': '$_score',
        '最高': '$_best',
        '达成2048': _won ? '是' : '否',
        '状态': _over
            ? '结束'
            : (_won && !_keepPlaying)
                ? '胜利'
                : '进行中',
      };

  @override
  void jumpToLevel(int n) {} // 无关卡

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
    if (gained > 0) HapticFeedback.selectionClick();
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
    const pad = 9.0;
    const gap = 9.0;
    final inner = side - 2 * pad;
    final cell = (inner - 3 * gap) / 4;
    double leftOf(int col) => pad + col * (cell + gap);
    double topOf(int row) => pad + row * (cell + gap);
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF21253A), Color(0xFF12141F)],
        ),
        border: Border.all(color: const Color(0xFF363C52), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          // 空格槽
          for (int i = 0; i < 16; i++)
            Positioned(
              left: leftOf(i % 4),
              top: topOf(i ~/ 4),
              width: cell,
              height: cell,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          // 瓦片：位置由 row/col 决定，AnimatedPositioned 平滑过渡
          for (final t in _tiles)
            if (t.consumed) const SizedBox.shrink() else
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
    // 被合并的瓦片:只画色块滑动到目标(不画数字,避免与幸存者文字重叠成黑影)
    if (t.consumed) {
      final (gradient, _) = _tileStyle(t.value);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: gradient,
        ),
      );
    }
    final (gradient, glow) = _tileStyle(t.value);
    final g = _glow(t.value);
    final box = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: gradient,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
        boxShadow: g > 0
            ? [
                BoxShadow(
                  color: glow.withValues(alpha: 0.30 + 0.45 * g),
                  blurRadius: 6 + 20 * g,
                  spreadRadius: 1 + 3 * g,
                  offset: const Offset(0, 3),
                ),
              ]
            : const [
                BoxShadow(
                    color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
      ),
      child: Stack(
        children: [
          // 顶部玻璃高光
          Positioned(
            left: 6,
            right: 6,
            top: 6,
            height: cell * 0.34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7), bottom: Radius.circular(9)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              '${t.value}',
              style: TextStyle(
                color: Colors.white,
                fontSize: _tileFont(t.value),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (t.justSpawned) return _scaleIn(box, 0.0, 180);
    if (t.justMerged) return _scaleIn(box, 0.80, 150); // 合并弹一下
    return box;
  }

  Widget _scaleIn(Widget child, double from, int ms) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: from, end: 1.0),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutBack,
      builder: (_, s, c) => Transform.scale(scale: s, child: c),
      child: child,
    );
  }

  Widget _scoreBar() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip('得分', '$_score', const Color(0xFFFFD54A)),
        const SizedBox(width: 8),
        _chip('最高', '$_best', const Color(0xFF6EE060)),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF999999), fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 每个数值的(渐变, 发光色)。冷→暖→金的演进,高数值霓虹感更强。
  (Gradient, Color) _tileStyle(int v) {
    final (colors, glow) = switch (v) {
      2 => (<Color>[const Color(0xFF6E7B9B), const Color(0xFF56638A)],
          const Color(0xFF6E7B9B)),
      4 => (<Color>[const Color(0xFF4FC3F7), const Color(0xFF2196F3)],
          const Color(0xFF4FC3F7)),
      8 => (<Color>[const Color(0xFF4DD0E1), const Color(0xFF00ACC1)],
          const Color(0xFF26C6DA)),
      16 => (<Color>[const Color(0xFF66BB6A), const Color(0xFF43A047)],
          const Color(0xFF66BB6A)),
      32 => (<Color>[const Color(0xFF9CCC65), const Color(0xFF7CB342)],
          const Color(0xFF9CCC65)),
      64 => (<Color>[const Color(0xFFFFB74D), const Color(0xFFFB8C00)],
          const Color(0xFFFFA726)),
      128 => (<Color>[const Color(0xFFFF8A65), const Color(0xFFF4511E)],
          const Color(0xFFFF7043)),
      256 => (<Color>[const Color(0xFFF06292), const Color(0xFFD81B60)],
          const Color(0xFFEC407A)),
      512 => (<Color>[const Color(0xFFBA68C8), const Color(0xFF8E24AA)],
          const Color(0xFFAB47BC)),
      1024 => (<Color>[const Color(0xFF9575CD), const Color(0xFF5E35B1)],
          const Color(0xFF7E57C2)),
      2048 => (<Color>[const Color(0xFFFFE082), const Color(0xFFFFB300)],
          const Color(0xFFFFD54A)),
      _ => (<Color>[const Color(0xFF26A69A), const Color(0xFF00897B)],
          const Color(0xFF4DB6AC)),
    };
    return (
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
      glow
    );
  }

  /// 发光强度(0..1),随 log2(value) 递增;2/4 不发光。
  double _glow(int v) {
    if (v <= 4) return 0.0;
    final p = log(v) / log(2);
    return ((p - 2) / 9).clamp(0.0, 1.0);
  }

  double _tileFont(int v) {
    if (v < 100) return 30;
    if (v < 1000) return 24;
    if (v < 10000) return 19;
    return 15;
  }

  Widget _overlay() {
    final won = _won && !_keepPlaying;
    final accent = won ? const Color(0xFFFFD54A) : const Color(0xFFFF8A4C);
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD000000),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              won ? '达成 2048！' : '游戏结束',
              style: TextStyle(
                color: accent,
                fontSize: 30,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                      color: accent.withValues(alpha: 0.6),
                      blurRadius: 16,
                      offset: Offset.zero),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('得分 $_score · 最高 $_best',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 18),
            if (won) ...[
              _ovBtn('继续挑战', const Color(0xFF6EE060),
                  () => setState(() => _keepPlaying = true)),
              const SizedBox(height: 10),
            ],
            _ovBtn('再来一局', const Color(0xFFFFD54A), _newGame),
          ],
        ),
      ),
    );
  }

  Widget _ovBtn(String text, Color color, VoidCallback onTap) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
      ),
      onPressed: onTap,
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF222222), fontWeight: FontWeight.bold)),
    );
  }
}
