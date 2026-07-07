// 俄罗斯方块 —— 经典 Tetris。方块下落、旋转、消行，等级提速，堆顶判负。
// 纯单机；最高分本地保存。CustomPainter 渲染（与坦克/蛇同款高效画法）。
// 控制：左/右/软降（长按连发）、旋转、硬降；按键有 click 音；支持暂停、震动、全局静音。

import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/best_score_store.dart';
import '../../shared/game_shell.dart';
import '../../shared/sound_store.dart';

const int _cols = 10;
const int _rows = 20;
const String _bestKey = 'best_tetris';

/// 一种 tetromino：在 size×size 盒内的初始（rot0）格子坐标 + 颜色。
class _KindDef {
  final int size;
  final List<List<int>> cells;
  final Color color;
  const _KindDef(this.size, this.cells, this.color);
}

const List<_KindDef> _kinds = [
  _KindDef(4, [[1, 0], [1, 1], [1, 2], [1, 3]], Color(0xFF4FC3F7)), // I 青
  _KindDef(2, [[0, 0], [0, 1], [1, 0], [1, 1]], Color(0xFFFFD54A)), // O 黄
  _KindDef(3, [[0, 1], [1, 0], [1, 1], [1, 2]], Color(0xFFBA68C8)), // T 紫
  _KindDef(3, [[0, 1], [0, 2], [1, 0], [1, 1]], Color(0xFF66BB6A)), // S 绿
  _KindDef(3, [[0, 0], [0, 1], [1, 1], [1, 2]], Color(0xFFEF5350)), // Z 红
  _KindDef(3, [[0, 0], [1, 0], [1, 1], [1, 2]], Color(0xFF42A5F5)), // J 蓝
  _KindDef(3, [[0, 2], [1, 0], [1, 1], [1, 2]], Color(0xFFFFA726)), // L 橙
];

/// 90° 顺时针旋转一次
List<List<int>> _rot(List<List<int>> cells, int size) =>
    cells.map((c) => [c[1], size - 1 - c[0]]).toList();

List<List<int>> _cellsOf(int kind, int rot) {
  var cells = _kinds[kind].cells;
  final size = _kinds[kind].size;
  for (int i = 0; i < rot; i++) {
    cells = _rot(cells, size);
  }
  return cells;
}

class _Piece {
  final int kind;
  int rot;
  int r, c;
  _Piece(this.kind, {this.rot = 0, this.r = 0, this.c = 3});
  _Piece copyWith({int? rot, int? r, int? c}) =>
      _Piece(kind, rot: rot ?? this.rot, r: r ?? this.r, c: c ?? this.c);
  List<List<int>> cells() => _cellsOf(kind, rot);
}

class TetrisPage extends StatefulWidget {
  const TetrisPage({super.key});
  @override
  State<TetrisPage> createState() => _TetrisPageState();
}

class _TetrisPageState extends State<TetrisPage> {
  late List<List<int>> _grid; // [row][col]，0 空 / kind+1 有色
  _Piece? _cur;
  int _next = 0;
  int _score = 0, _best = 0, _level = 1, _lines = 0;
  bool _over = false, _started = false, _paused = false;
  Timer? _gravity;
  Timer? _repInit; // 长按连发：首次延迟
  Timer? _repLoop; // 长按连发：周期
  final Random _rng = Random();
  final FocusNode _focus = FocusNode();

  // 按键音：单个预加载 AudioPlayer，seek+resume 复用（避开 AudioPool 崩溃路径）
  AudioPlayer? _click;
  final Stopwatch _clickWatch = Stopwatch();
  int _lastClickMs = -9999;
  int _lastHapticMs = -9999;

  int get _gravityMs => max(80, 820 - (_level - 1) * 72);

  @override
  void initState() {
    super.initState();
    _best = BestScoreStore.get(_bestKey);
    _reset();
    _initClick();
  }

  void _initClick() {
    final p = AudioPlayer();
    _click = p;
    p.setReleaseMode(ReleaseMode.stop);
    p.setVolume(0.5);
    p.setSource(AssetSource('sounds/click.wav')); // 异步预加载，失败忽略
  }

  @override
  void dispose() {
    _gravity?.cancel();
    _repInit?.cancel();
    _repLoop?.cancel();
    _click?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reset() {
    _gravity?.cancel();
    _grid = List.generate(_rows, (_) => List<int>.filled(_cols, 0));
    _score = 0;
    _level = 1;
    _lines = 0;
    _over = false;
    _started = false;
    _paused = false;
    _cur = null;
    _next = _rng.nextInt(7);
    _spawn();
  }

  void _newGame() {
    _playClick();
    setState(_reset);
  }

  void _start() {
    if (_started || _over) return;
    _playClick();
    _started = true;
    _rearmGravity();
    setState(() {});
  }

  void _togglePause() {
    if (!_started || _over) return;
    _paused = !_paused;
    _stopRepeat();
    if (_paused) {
      _gravity?.cancel();
    } else {
      _rearmGravity();
    }
    setState(() {});
  }

  void _rearmGravity() {
    _gravity?.cancel();
    _gravity = Timer.periodic(Duration(milliseconds: _gravityMs), (_) => _tick());
  }

  void _spawn() {
    _cur = _Piece(_next, c: (_cols - _kinds[_next].size) ~/ 2);
    _next = _rng.nextInt(7);
    if (_hit(_grid, _cur!)) {
      _over = true;
      _gravity?.cancel();
    }
  }

  bool _hit(List<List<int>> g, _Piece p) {
    for (final cell in p.cells()) {
      final r = p.r + cell[0];
      final c = p.c + cell[1];
      if (c < 0 || c >= _cols || r >= _rows) return true;
      if (r >= 0 && g[r][c] != 0) return true;
    }
    return false;
  }

  bool _canPlace(_Piece p) => !_hit(_grid, p);

  bool _tryMove(_Piece np) {
    if (_canPlace(np)) {
      setState(() => _cur = np);
      return true;
    }
    return false;
  }

  void _moveLR(int dc) {
    if (_cur == null || !_started || _over || _paused) return;
    _playClick();
    _pulse();
    _tryMove(_cur!.copyWith(c: _cur!.c + dc));
  }

  void _rotate() {
    if (_cur == null || !_started || _over || _paused) return;
    _playClick();
    _pulse();
    for (final dc in [0, -1, 1, -2, 2]) {
      if (_tryMove(_cur!.copyWith(rot: (_cur!.rot + 1) % 4, c: _cur!.c + dc))) {
        return;
      }
    }
  }

  void _softDrop() {
    if (_cur == null || !_started || _over || _paused) return;
    _playClick();
    _pulse();
    if (_tryMove(_cur!.copyWith(r: _cur!.r + 1))) {
      setState(() => _score += 1);
      _updateBest();
    } else {
      _lock();
    }
  }

  void _hardDrop() {
    if (_cur == null || !_started || _over || _paused) return;
    _playClick();
    int dist = 0;
    var p = _cur!;
    while (_canPlace(p.copyWith(r: p.r + 1))) {
      p = p.copyWith(r: p.r + 1);
      dist++;
    }
    if (dist > 0) HapticFeedback.heavyImpact();
    setState(() {
      _cur = p;
      _score += dist * 2;
    });
    _updateBest();
    _lock();
  }

  void _lock() {
    final p = _cur!;
    setState(() {
      for (final cell in p.cells()) {
        final r = p.r + cell[0], c = p.c + cell[1];
        if (r >= 0 && r < _rows && c >= 0 && c < _cols) {
          _grid[r][c] = p.kind + 1;
        }
      }
      _clearLines();
    });
    if (!_over) _spawn();
  }

  void _clearLines() {
    int cleared = 0;
    final kept = <List<int>>[];
    for (int r = 0; r < _rows; r++) {
      if (!_grid[r].any((v) => v == 0)) {
        cleared++;
      } else {
        kept.add(_grid[r]);
      }
    }
    if (cleared == 0) return;
    if (cleared >= 4) {
      HapticFeedback.heavyImpact(); // Tetris！
    } else {
      HapticFeedback.mediumImpact();
    }
    while (kept.length < _rows) {
      kept.insert(0, List<int>.filled(_cols, 0));
    }
    _grid = kept;
    const pts = [0, 100, 300, 500, 800];
    _score += pts[cleared] * _level;
    _lines += cleared;
    final newLevel = (_lines ~/ 10) + 1;
    if (newLevel != _level) {
      _level = newLevel;
      _rearmGravity();
    }
    _updateBest();
  }

  void _tick() {
    if (_over || !_started || _paused || _cur == null) return;
    if (_canPlace(_cur!.copyWith(r: _cur!.r + 1))) {
      setState(() => _cur = _cur!.copyWith(r: _cur!.r + 1));
    } else {
      _lock();
    }
  }

  /// 落点预影（ghost）的锚点行
  int _ghostR() {
    var p = _cur!;
    while (_canPlace(p.copyWith(r: p.r + 1))) {
      p = p.copyWith(r: p.r + 1);
    }
    return p.r;
  }

  void _updateBest() {
    if (_score > _best) {
      _best = _score;
      BestScoreStore.setIfGreater(_bestKey, _best);
    }
  }

  /// 按键音（节流 80ms；全局静音时不响）
  void _playClick() {
    if (kMuted.value) return;
    final c = _click;
    if (c == null) return;
    if (!_clickWatch.isRunning) _clickWatch.start();
    final now = _clickWatch.elapsedMilliseconds;
    if (now - _lastClickMs < 80) return;
    _lastClickMs = now;
    c.seek(Duration.zero);
    c.resume();
  }

  /// 按键轻震动（节流 90ms,长按连发时不会嗡嗡作响）
  void _pulse() {
    if (!_clickWatch.isRunning) _clickWatch.start();
    final now = _clickWatch.elapsedMilliseconds;
    if (now - _lastHapticMs < 90) return;
    _lastHapticMs = now;
    HapticFeedback.selectionClick();
  }

  // ---- 长按连发 ----
  void _startRepeat(VoidCallback action) {
    action();
    _repInit?.cancel();
    _repLoop?.cancel();
    _repInit = Timer(const Duration(milliseconds: 160), () {
      _repLoop = Timer.periodic(const Duration(milliseconds: 55), (_) => action());
    });
  }

  void _stopRepeat() {
    _repInit?.cancel();
    _repLoop?.cancel();
    _repInit = null;
    _repLoop = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_started) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _moveLR(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _moveLR(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      _softDrop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _rotate();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space) {
      _hardDrop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '俄罗斯方块',
      actions: [
        if (_started && !_over)
          IconButton(
            tooltip: _paused ? '继续' : '暂停',
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause,
                color: const Color(0xFFFFA726)),
            onPressed: _togglePause,
          ),
        TextButton(
          onPressed: _newGame,
          child:
              const Text('新游戏', style: TextStyle(color: Color(0xFFFFA726))),
        ),
      ],
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final maxBoardW = c.maxWidth - 24;
            final availH =
                c.maxHeight - 58 /*top*/ - 22 /*gaps*/ - 116 /*controls*/;
            var boardH = availH.clamp(240.0, 560.0);
            var boardW = boardH * _cols / _rows;
            if (boardW > maxBoardW) {
              boardW = maxBoardW;
              boardH = boardW * _rows / _cols;
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: c.maxWidth, child: _topBar()),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: boardW,
                    height: boardH,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(boardW, boardH),
                          painter: _TetrisPainter(
                            grid: _grid,
                            cur: _cur,
                            ghostR: (_started && !_over && _cur != null)
                                ? _ghostR()
                                : null,
                          ),
                        ),
                        if (!_started || _over || _paused) _overlay(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: c.maxWidth,
                    child: _controlsRow(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip('得分', '$_score', const Color(0xFFFFA726)),
              _chip('最高', '$_best', const Color(0xFFFFD54A)),
              _chip('等级', '$_level', const Color(0xFF66BB6A)),
              _chip('行数', '$_lines', const Color(0xFF42A5F5)),
            ],
          ),
        ),
        _nextBox(),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  Widget _nextBox() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('下一个',
            style: TextStyle(color: Color(0xFF999999), fontSize: 11)),
        const SizedBox(width: 6),
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF444444)),
          ),
          child: CustomPaint(painter: _NextPainter(_next)),
        ),
      ],
    );
  }

  Widget _overlay() {
    if (_paused) {
      return Positioned.fill(
        child: Container(
          color: const Color(0xCC000000),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('暂停',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _togglePause,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA726),
                ),
                child: const Text('继续游戏',
                    style: TextStyle(
                        color: Color(0xFF222222),
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }
    final over = _over;
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC000000),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              over ? '游戏结束' : '俄罗斯方块',
              style: TextStyle(
                color: over ? Colors.white : const Color(0xFFFFA726),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (over)
              Text('得分 $_score    最高 $_best',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: over ? _newGame : _start,
              style: TextButton.styleFrom(
                backgroundColor: over
                    ? const Color(0xFFFFD54A)
                    : const Color(0xFFFFA726),
              ),
              child: Text(over ? '再来一局' : '开始游戏',
                  style: const TextStyle(
                      color: Color(0xFF222222), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 屏幕控件(纯图标,加大)----
  Widget _controlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ctrlBtn(Icons.arrow_left, repeat: () => _moveLR(-1), tooltip: '左移'),
        _ctrlBtn(Icons.arrow_right, repeat: () => _moveLR(1), tooltip: '右移'),
        _ctrlBtn(Icons.arrow_downward, repeat: _softDrop, tooltip: '软降'),
        _ctrlBtn(Icons.rotate_right, tap: _rotate, tooltip: '旋转'),
        _ctrlBtn(Icons.vertical_align_bottom,
            tap: _hardDrop, primary: true, tooltip: '硬降'),
      ],
    );
  }

  Widget _ctrlBtn(IconData icon,
      {VoidCallback? tap, VoidCallback? repeat, bool primary = false, String? tooltip}) {
    const color = Color(0xFFFFA726);
    final size = primary ? 66.0 : 58.0;
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary ? color : const Color(0xFF262626),
        shape: BoxShape.circle,
        border: Border.all(
            color: color.withValues(alpha: primary ? 1 : 0.6), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon,
          color: primary ? const Color(0xFF222222) : color,
          size: primary ? 32 : 28),
    );
    final inner = repeat != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _startRepeat(repeat),
            onTapUp: (_) => _stopRepeat(),
            onTapCancel: _stopRepeat,
            child: box,
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: box,
          );
    return tooltip == null ? inner : Tooltip(message: tooltip, child: inner);
  }
}

/// 棋盘绘制：背景网格 + 落点预影 + 固定方块 + 当前方块。
class _TetrisPainter extends CustomPainter {
  final List<List<int>> grid;
  final _Piece? cur;
  final int? ghostR;
  _TetrisPainter({required this.grid, required this.cur, required this.ghostR});

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / _cols;
    final ch = size.height / _rows;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF121417));
    final linePaint = Paint()
      ..color = const Color(0xFF222733)
      ..strokeWidth = 0.6;
    for (int c = 1; c < _cols; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), linePaint);
    }
    for (int r = 1; r < _rows; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), linePaint);
    }
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        final v = grid[r][c];
        if (v != 0) {
          _drawCell(canvas, c * cw, r * ch, cw, ch, _kinds[v - 1].color);
        }
      }
    }
    if (cur != null && ghostR != null) {
      final color = _kinds[cur!.kind].color;
      for (final cell in cur!.cells()) {
        final r = ghostR! + cell[0];
        final c = cur!.c + cell[1];
        if (r >= 0 && r < _rows && c >= 0 && c < _cols) {
          _drawGhost(canvas, c * cw, r * ch, cw, ch, color);
        }
      }
    }
    if (cur != null) {
      final color = _kinds[cur!.kind].color;
      for (final cell in cur!.cells()) {
        final r = cur!.r + cell[0];
        final c = cur!.c + cell[1];
        if (r >= 0 && r < _rows && c >= 0 && c < _cols) {
          _drawCell(canvas, c * cw, r * ch, cw, ch, color);
        }
      }
    }
  }

  void _drawCell(
      Canvas canvas, double x, double y, double w, double h, Color color) {
    final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 0.8, y + 0.8, w - 1.6, h - 1.6),
        Radius.circular(min(w, h) * 0.16));
    canvas.drawRRect(rr, Paint()..color = color);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 0.8, y + 0.8, w - 1.6, (h - 1.6) * 0.42),
            Radius.circular(min(w, h) * 0.16)),
        Paint()..color = Colors.white.withValues(alpha: 0.18));
  }

  void _drawGhost(
      Canvas canvas, double x, double y, double w, double h, Color color) {
    final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1.4, y + 1.4, w - 2.8, h - 2.8),
        Radius.circular(min(w, h) * 0.16));
    canvas.drawRRect(
        rr,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill);
    canvas.drawRRect(
        rr,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant _TetrisPainter old) => true;
}

/// NEXT 预览：在 4×4 框内居中绘制下一个方块的 rot0 形态。
class _NextPainter extends CustomPainter {
  final int kind;
  _NextPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final cs = size.width / 4;
    final def = _kinds[kind];
    final off = (4 - def.size) * cs / 2;
    for (final cell in def.cells) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(
              off + cell[1] * cs + 1, off + cell[0] * cs + 1, cs - 2, cs - 2),
          Radius.circular(cs * 0.18));
      canvas.drawRRect(rr, Paint()..color = def.color);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(off + cell[1] * cs + 1, off + cell[0] * cs + 1,
                  cs - 2, (cs - 2) * 0.42),
              Radius.circular(cs * 0.18)),
          Paint()..color = Colors.white.withValues(alpha: 0.18));
    }
  }

  @override
  bool shouldRepaint(covariant _NextPainter old) => old.kind != kind;
}
