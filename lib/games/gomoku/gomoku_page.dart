// 五子棋 —— 15×15,横/竖/斜任意方向先连成 5 子者胜。
// 模式:人机(启发式 AI,玩家执黑先手)/ 双人(同屏对弈)。纯单机离线。
// 人机模式记录连胜(best_gomoku)。CustomPainter 渲染,与坦克/蛇同款高效画法。

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../debug/game_debug_registry.dart';
import '../../shared/best_score_store.dart';
import '../../shared/game_shell.dart';

const int _size = 15;
const String _bestKey = 'best_gomoku';

class GomokuPage extends StatefulWidget {
  const GomokuPage({super.key});
  @override
  State<GomokuPage> createState() => _GomokuPageState();
}

class _GomokuPageState extends State<GomokuPage>
    with GameDebugMixin<GomokuPage> {
  late List<List<int>> _board; // 0 空 / 1 黑 / 2 白
  int _turn = 1; // 当前回合(1 黑先)
  bool _aiMode = true; // 人机模式:玩家执黑(1),AI 执白(2)
  bool _thinking = false; // AI 计算中
  bool _over = false;
  int _winner = 0; // 0 进行中或和棋 / 1 黑 / 2 白
  List<Point<int>> _winLine = [];
  final List<Point<int>> _history = [];
  int _moveCount = 0;
  Point<int>? _lastMove;
  int _streak = 0; // 当前连胜(人机)
  int _best = 0; // 历史最长连胜
  final Random _rng = Random();

  int get _playerColor => 1; // 玩家=黑
  int get _aiColor => 2; // AI=白

  @override
  void initState() {
    super.initState();
    _best = BestScoreStore.get(_bestKey);
    _reset();
  }

  void _reset() {
    _board = List.generate(_size, (_) => List<int>.filled(_size, 0));
    _turn = 1;
    _thinking = false;
    _over = false;
    _winner = 0;
    _winLine = [];
    _history.clear();
    _moveCount = 0;
    _lastMove = null;
  }

  void _newGame() => setState(_reset);

  // ---- 调试面板(GameDebug) ----
  @override
  String get id => 'gomoku';

  @override
  int? get currentLevel => null; // 无关卡概念

  @override
  int? get maxLevel => null;

  @override
  Map<String, String> info() => {
        '模式': _aiMode ? '人机' : '双人',
        '回合': _turn == 1 ? '黑' : '白',
        '手数': '$_moveCount',
        '连胜': '$_streak',
        '最高连胜': '$_best',
        '状态': _over
            ? (_winner == 0 ? '和棋' : (_winner == 1 ? '黑胜' : '白胜'))
            : _thinking
                ? 'AI思考'
                : '进行中',
      };

  @override
  void jumpToLevel(int n) {} // 无关卡

  void _toggleMode() {
    setState(() {
      _aiMode = !_aiMode;
      _reset();
    });
  }

  // ---- 落子 ----
  void _humanPlace(int r, int c) {
    if (_over || _thinking) return;
    if (r < 0 || r >= _size || c < 0 || c >= _size) return;
    if (_board[r][c] != 0) return;
    if (_aiMode && _turn != _playerColor) return; // 等 AI
    _doMove(r, c, _turn);
    if (_over) return;
    if (_aiMode) {
      _scheduleAi();
    } else {
      setState(() => _turn = _turn == 1 ? 2 : 1);
    }
  }

  void _doMove(int r, int c, int color) {
    setState(() {
      _board[r][c] = color;
      _history.add(Point(r, c));
      _moveCount++;
      _lastMove = Point(r, c);
      final line = _checkWin(r, c, color);
      if (line != null) {
        _winner = color;
        _winLine = line;
        _over = true;
        _onEnd(color);
      } else if (_moveCount >= _size * _size) {
        _over = true; // 和棋
      }
    });
  }

  void _scheduleAi() {
    setState(() => _thinking = true);
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || _over) return;
      final m = _aiMove();
      setState(() => _thinking = false);
      _doMove(m.x, m.y, _aiColor);
    });
  }

  void _onEnd(int winner) {
    HapticFeedback.mediumImpact();
    if (_aiMode) {
      if (winner == _playerColor) {
        _streak++;
        if (_streak > _best) {
          _best = _streak;
          BestScoreStore.setIfGreater(_bestKey, _best);
        }
      } else {
        _streak = 0; // 输给 AI,连胜清零
      }
    }
  }

  void _undo() {
    if (_over || _thinking || _history.isEmpty) return;
    setState(() {
      if (_aiMode) {
        // 撤销 玩家 + AI 两步(AI 已下则撤两步)
        final n = _history.length >= 2 ? 2 : 1;
        for (int i = 0; i < n; i++) {
          final m = _history.removeLast();
          _board[m.x][m.y] = 0;
          _moveCount--;
        }
        _turn = _playerColor;
      } else {
        final m = _history.removeLast();
        _board[m.x][m.y] = 0;
        _moveCount--;
        _turn = _turn == 1 ? 2 : 1;
      }
      _lastMove = _history.isEmpty ? null : _history.last;
    });
  }

  // ---- 胜负判定:从 (r,c) 向四方向数同色连续子,>=5 即胜 ----
  List<Point<int>>? _checkWin(int r, int c, int color) {
    const dirs = [
      [0, 1],
      [1, 0],
      [1, 1],
      [1, -1]
    ];
    for (final d in dirs) {
      final line = <Point<int>>[Point(r, c)];
      int rr = r + d[0], cc = c + d[1];
      while (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
          _board[rr][cc] == color) {
        line.add(Point(rr, cc));
        rr += d[0];
        cc += d[1];
      }
      rr = r - d[0];
      cc = c - d[1];
      while (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
          _board[rr][cc] == color) {
        line.add(Point(rr, cc));
        rr -= d[0];
        cc -= d[1];
      }
      if (line.length >= 5) return line;
    }
    return null;
  }

  // ---- AI:启发式打分。每个空点 = 进攻分(落 AI 子)+ 防守分(阻玩家子)----
  Point<int> _aiMove() {
    if (_moveCount == 0) return Point(_size ~/ 2, _size ~/ 2); // 天元
    int bestScore = -1;
    var bests = <Point<int>>[];
    for (int r = 0; r < _size; r++) {
      for (int c = 0; c < _size; c++) {
        if (_board[r][c] != 0 || !_nearStone(r, c)) continue;
        final off = _evalPoint(r, c, _aiColor);
        final def = _evalPoint(r, c, _playerColor);
        final sc = off + def + def ~/ 20; // 略偏防守
        if (sc > bestScore) {
          bestScore = sc;
          bests = [Point(r, c)];
        } else if (sc == bestScore) {
          bests.add(Point(r, c));
        }
      }
    }
    if (bests.isEmpty) return Point(_size ~/ 2, _size ~/ 2);
    return bests[_rng.nextInt(bests.length)];
  }

  bool _nearStone(int r, int c) {
    for (int dr = -2; dr <= 2; dr++) {
      for (int dc = -2; dc <= 2; dc++) {
        final rr = r + dr, cc = c + dc;
        if (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
            _board[rr][cc] != 0) {
          return true;
        }
      }
    }
    return false;
  }

  /// 假设 (r,c) 落 color 子后,该点四方向形成的威胁总分。
  int _evalPoint(int r, int c, int color) {
    int total = 0;
    const dirs = [
      [0, 1],
      [1, 0],
      [1, 1],
      [1, -1]
    ];
    for (final d in dirs) {
      int count = 1;
      int openA = 0, openB = 0;
      int rr = r + d[0], cc = c + d[1];
      while (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
          _board[rr][cc] == color) {
        count++;
        rr += d[0];
        cc += d[1];
      }
      if (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
          _board[rr][cc] == 0) {
        openA = 1;
      }
      rr = r - d[0];
      cc = c - d[1];
      while (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
          _board[rr][cc] == color) {
        count++;
        rr -= d[0];
        cc -= d[1];
      }
      if (rr >= 0 && rr < _size && cc >= 0 && cc < _size &&
          _board[rr][cc] == 0) {
        openB = 1;
      }
      total += _threat(count, openA + openB);
    }
    return total;
  }

  int _threat(int count, int opens) {
    if (count >= 5) return 1000000; // 成五
    if (count == 4) {
      if (opens == 2) return 100000; // 活四
      if (opens == 1) return 10000; // 冲四
      return 0;
    }
    if (count == 3) {
      if (opens == 2) return 8000; // 活三
      if (opens == 1) return 500;
      return 0;
    }
    if (count == 2) {
      if (opens == 2) return 300;
      if (opens == 1) return 50;
      return 0;
    }
    if (count == 1 && opens == 2) return 10;
    return 0;
  }

  bool get _canUndo => !_over && !_thinking && _history.isNotEmpty;

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '五子棋',
      actions: [
        IconButton(
          tooltip: _aiMode ? '当前:人机(点击切双人)' : '当前:双人(点击切人机)',
          icon: Icon(_aiMode ? Icons.smart_toy : Icons.people,
              color: const Color(0xFFE0B040)),
          onPressed: _toggleMode,
        ),
        IconButton(
          tooltip: '悔棋',
          icon: Icon(Icons.undo,
              color: _canUndo ? const Color(0xFFCCCCCC) : const Color(0xFF555555)),
          onPressed: _canUndo ? _undo : null,
        ),
        IconButton(
          tooltip: '新局',
          icon: const Icon(Icons.refresh, color: Color(0xFFCCCCCC)),
          onPressed: _newGame,
        ),
      ],
      body: Center(
        child: LayoutBuilder(
          builder: (ctx, c) {
            final side = min(c.maxWidth, c.maxHeight - 120).clamp(240.0, 520.0);
            final margin = side * 0.05;
            final step = (side - margin * 2) / (_size - 1);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusRow(),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final col = ((d.localPosition.dx - margin) / step).round();
                    final row = ((d.localPosition.dy - margin) / step).round();
                    _humanPlace(row, col);
                  },
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size.square(side),
                          painter: _GomokuPainter(
                              _board, _lastMove, _winLine, _turn),
                        ),
                        if (_over) _overlay(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _aiMode ? '点击交叉点落子(你执黑先手)' : '点击交叉点落子(黑先)',
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusRow() {
    String turn;
    Color turnColor;
    if (_over) {
      if (_winner == 0) {
        turn = '和棋';
        turnColor = const Color(0xFFCCCCCC);
      } else if (_winner == _playerColor) {
        turn = _aiMode ? '你赢了 🎉' : '黑方胜';
        turnColor = const Color(0xFF6EE060);
      } else {
        turn = _aiMode ? 'AI 胜' : '白方胜';
        turnColor = const Color(0xFFE0E0E0);
      }
    } else if (_thinking) {
      turn = 'AI 思考中…';
      turnColor = const Color(0xFFE0B040);
    } else {
      final who = _turn == 1 ? '黑方' : '白方';
      final tag = _aiMode ? (_turn == _playerColor ? '(你)' : '(AI)') : '';
      turn = '$who$tag 行棋';
      turnColor = _turn == 1 ? const Color(0xFF444444) : const Color(0xFFE0E0E0);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(_aiMode ? '人机' : '双人', const Color(0xFFE0B040)),
        const SizedBox(width: 8),
        _chip(turn, turnColor),
        if (_aiMode) ...[
          const SizedBox(width: 8),
          _chip('连胜 $_streak', const Color(0xFF6EE060)),
          const SizedBox(width: 6),
          _chip('🏆 $_best', const Color(0xFFFFD54A)),
        ],
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _overlay() {
    final win = _winner == _playerColor;
    final draw = _winner == 0;
    final title = draw
        ? '和棋'
        : (win ? '你赢了！' : (_aiMode ? 'AI 胜' : '白方胜'));
    final color = draw
        ? const Color(0xFFCCCCCC)
        : (win ? const Color(0xFF6EE060) : const Color(0xFFE0B040));
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC000000),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _newGame,
              style: TextButton.styleFrom(
                backgroundColor: color,
              ),
              child: const Text('再来一局',
                  style: TextStyle(
                      color: Color(0xFF222222), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 棋盘绘制:木质底 + 网格 + 星位 + 黑白子 + 末手标记 + 胜利连线高亮。
class _GomokuPainter extends CustomPainter {
  final List<List<int>> board;
  final Point<int>? lastMove;
  final List<Point<int>> winLine;
  final int turn;
  _GomokuPainter(this.board, this.lastMove, this.winLine, this.turn);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final margin = s * 0.05;
    final step = (s - margin * 2) / (_size - 1);
    Offset pos(int r, int c) => Offset(margin + c * step, margin + r * step);

    // 木质底
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFFE7C88A));
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0x22000000));

    // 网格
    final line = Paint()
      ..color = const Color(0xFF5A4326)
      ..strokeWidth = 1;
    for (int i = 0; i < _size; i++) {
      canvas.drawLine(pos(0, i), pos(_size - 1, i), line);
      canvas.drawLine(pos(i, 0), pos(i, _size - 1), line);
    }
    // 星位
    final star = Paint()..color = const Color(0xFF5A4326);
    for (final p in const [
      Point(3, 3),
      Point(3, 11),
      Point(11, 3),
      Point(11, 11),
      Point(7, 7)
    ]) {
      canvas.drawCircle(pos(p.x, p.y), step * 0.08, star);
    }

    final winSet = winLine.toSet();
    for (int r = 0; r < _size; r++) {
      for (int c = 0; c < _size; c++) {
        final v = board[r][c];
        if (v == 0) continue;
        final center = pos(r, c);
        final radius = step * 0.42;
        final hl = winSet.contains(Point(r, c));
        if (v == 1) {
          canvas.drawCircle(
              center,
              radius,
              Paint()
                ..color = hl ? const Color(0xFFFFD54A) : const Color(0xFF1A1A1A));
          canvas.drawCircle(
              center,
              radius,
              Paint()
                ..color = const Color(0xFF000000)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1);
        } else {
          canvas.drawCircle(center, radius,
              Paint()..color = hl ? const Color(0xFFFFE082) : const Color(0xFFF2F2F2));
          canvas.drawCircle(
              center,
              radius,
              Paint()
                ..color = const Color(0xFF888888)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1);
        }
      }
    }

    // 末手标记(红点)
    final lm = lastMove;
    if (lm != null && board[lm.x][lm.y] != 0 && winLine.isEmpty) {
      canvas.drawCircle(pos(lm.x, lm.y), step * 0.12,
          Paint()..color = const Color(0xFFFF5252));
    }

    // 胜利连线
    if (winLine.length >= 2) {
      final sorted = [...winLine]
        ..sort((a, b) {
          final d = (a.x - b.x);
          return d != 0 ? d : (a.y - b.y);
        });
      canvas.drawLine(
          pos(sorted.first.x, sorted.first.y),
          pos(sorted.last.x, sorted.last.y),
          Paint()
            ..color = const Color(0xFFFF5252)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _GomokuPainter old) => true;
}
