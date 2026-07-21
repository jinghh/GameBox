// 扫雷 —— 经典扫雷。首次点击安全（点击后才布雷），0 邻格洪水填充，
// 长按或"旗帜模式"插旗，翻完所有非雷格通关。纯单机；最快通关时间本地保存。

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../debug/game_debug_registry.dart';
import '../../shared/best_score_store.dart';
import '../../shared/game_shell.dart';

class MinesweeperPage extends StatefulWidget {
  const MinesweeperPage({super.key});
  @override
  State<MinesweeperPage> createState() => _MinesweeperPageState();
}

/// 难度配置
class _DiffConf {
  final int rows, cols, mines;
  final String label;
  const _DiffConf(this.rows, this.cols, this.mines, this.label);
}

const _easyConf = _DiffConf(9, 9, 10, '简单');
const _mediumConf = _DiffConf(12, 12, 25, '中等');

class _MCell {
  bool mine = false;
  bool revealed = false;
  bool flagged = false;
  int adjacent = 0;
}

class _MinesweeperPageState extends State<MinesweeperPage>
    with GameDebugMixin<MinesweeperPage> {
  _DiffConf _conf = _easyConf;
  late List<_MCell> _cells;
  bool _started = false;
  bool _over = false;
  bool _won = false;
  int _flags = 0;
  int _revealed = 0;
  int _elapsed = 0; // 秒
  Timer? _timer;
  final Random _rng = Random();
  bool _flagMode = false;
  int _bestEasy = 0, _bestMed = 0;
  bool _hasBestEasy = false, _hasBestMed = false;

  @override
  void initState() {
    super.initState();
    _hasBestEasy = BestScoreStore.has('best_mine_easy');
    _bestEasy = BestScoreStore.get('best_mine_easy');
    _hasBestMed = BestScoreStore.has('best_mine_medium');
    _bestMed = BestScoreStore.get('best_mine_medium');
    _setup(_conf);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setup(_DiffConf c) {
    _timer?.cancel();
    _timer = null;
    _conf = c;
    _cells = [for (int i = 0; i < c.rows * c.cols; i++) _MCell()];
    _started = false;
    _over = false;
    _won = false;
    _flags = 0;
    _revealed = 0;
    _elapsed = 0;
  }

  void _newGame() => setState(() => _setup(_conf));

  void _setDiff(_DiffConf c) => setState(() => _setup(c));

  // ---- 调试面板(GameDebug) ----
  @override
  String get id => 'mine';

  @override
  int? get currentLevel => null; // 无关卡(难度切换)

  @override
  int? get maxLevel => null;

  @override
  Map<String, String> info() => {
        '难度': _conf.label,
        '雷数': '${_conf.mines}',
        '格子': '${_conf.rows}×${_conf.cols}',
        '用时': '$_elapsed s',
        '旗帜': '$_flags',
        '最佳': identical(_conf, _easyConf)
            ? (_hasBestEasy ? '$_bestEasy s' : '—')
            : (_hasBestMed ? '$_bestMed s' : '—'),
        '状态': _over
            ? '失败'
            : _won
                ? '通关'
                : _started
                    ? '进行中'
                    : '未开始',
      };

  @override
  void jumpToLevel(int n) {} // 无关卡

  // ---- 核心 ----
  List<int> _neighbors(int idx) {
    final r = idx ~/ _conf.cols, c = idx % _conf.cols;
    final out = <int>[];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (nr < 0 || nr >= _conf.rows || nc < 0 || nc >= _conf.cols) continue;
        out.add(nr * _conf.cols + nc);
      }
    }
    return out;
  }

  void _placeMines(int safeIdx) {
    final total = _conf.rows * _conf.cols;
    final exclude = <int>{safeIdx, ..._neighbors(safeIdx)};
    final candidates = <int>[];
    for (int i = 0; i < total; i++) {
      if (!exclude.contains(i)) candidates.add(i);
    }
    candidates.shuffle(_rng);
    final mineCount = min(_conf.mines, candidates.length);
    for (int i = 0; i < mineCount; i++) {
      _cells[candidates[i]].mine = true;
    }
    for (int i = 0; i < total; i++) {
      if (_cells[i].mine) continue;
      int cnt = 0;
      for (final n in _neighbors(i)) {
        if (_cells[n].mine) cnt++;
      }
      _cells[i].adjacent = cnt;
    }
  }

  void _flood(int idx) {
    final stack = <int>[idx];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final cell = _cells[i];
      if (cell.revealed || cell.flagged || cell.mine) continue;
      cell.revealed = true;
      _revealed++;
      if (cell.adjacent == 0) {
        for (final n in _neighbors(i)) {
          if (!_cells[n].revealed && !_cells[n].flagged) stack.add(n);
        }
      }
    }
  }

  void _reveal(int idx) {
    if (_over || _won) return;
    final cell = _cells[idx];
    if (cell.revealed || cell.flagged) return;
    if (!_started) {
      _placeMines(idx);
      _started = true;
      _startTimer();
    }
    if (cell.mine) {
      HapticFeedback.heavyImpact();
      setState(() {
        for (final c in _cells) {
          if (c.mine) c.revealed = true;
        }
        _over = true;
        _stopTimer();
      });
      return;
    }
    setState(() {
      _flood(idx);
      _checkWin();
    });
  }

  void _toggleFlag(int idx) {
    if (_over || _won) return;
    final cell = _cells[idx];
    if (cell.revealed) return;
    setState(() {
      if (cell.flagged) {
        cell.flagged = false;
        _flags--;
      } else {
        cell.flagged = true;
        _flags++;
      }
    });
  }

  void _checkWin() {
    final total = _conf.rows * _conf.cols;
    if (_revealed == total - _conf.mines) {
      _won = true;
      HapticFeedback.mediumImpact();
      _stopTimer();
      for (final c in _cells) {
        if (c.mine && !c.flagged) {
          c.flagged = true;
          _flags++;
        }
      }
      _recordBest();
    }
  }

  void _recordBest() {
    final isEasy = identical(_conf, _easyConf);
    final key = isEasy ? 'best_mine_easy' : 'best_mine_medium';
    BestScoreStore.setIfSmaller(key, _elapsed).then((_) {
      if (!mounted) return;
      setState(() {
        if (isEasy) {
          _bestEasy = BestScoreStore.get(key);
          _hasBestEasy = true;
        } else {
          _bestMed = BestScoreStore.get(key);
          _hasBestMed = true;
        }
      });
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '扫雷',
      actions: [
        IconButton(
          tooltip: '旗帜模式',
          icon: Icon(_flagMode ? Icons.flag : Icons.flag_outlined,
              color: _flagMode ? const Color(0xFFFF5252) : const Color(0xFFCCCCCC)),
          onPressed: () => setState(() => _flagMode = !_flagMode),
        ),
        PopupMenuButton<String>(
          tooltip: '难度',
          icon: const Icon(Icons.tune, color: Color(0xFFCCCCCC)),
          onSelected: (v) =>
              _setDiff(v == 'medium' ? _mediumConf : _easyConf),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'easy', child: Text('简单 9×9 / 10雷')),
            PopupMenuItem(value: 'medium', child: Text('中等 12×12 / 25雷')),
          ],
        ),
        IconButton(
          tooltip: '新局',
          icon: const Icon(Icons.refresh, color: Color(0xFFCCCCCC)),
          onPressed: _newGame,
        ),
      ],
      body: Column(
        children: [
          _topBar(),
          Expanded(child: _boardArea()),
          if (_over || _won) _resultBanner(),
        ],
      ),
    );
  }

  Widget _topBar() {
    final isEasy = identical(_conf, _easyConf);
    final best = isEasy
        ? (_hasBestEasy ? '$_bestEasy s' : '—')
        : (_hasBestMed ? '$_bestMed s' : '—');
    final remaining = _conf.mines - _flags;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('💣', '$remaining'),
          _stat('⏱', '${_elapsed}s'),
          _stat('🏆', best),
        ],
      ),
    );
  }

  Widget _stat(String icon, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Color(0xFFFFD54A),
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _boardArea() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final side = min(c.maxWidth - 12, c.maxHeight - 12);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GridView.count(
              crossAxisCount: _conf.cols,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (int i = 0; i < _conf.rows * _conf.cols; i++) _cellWidget(i)
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cellWidget(int idx) {
    final cell = _cells[idx];
    final revealed = cell.revealed;
    return GestureDetector(
      onTap: () => _flagMode ? _toggleFlag(idx) : _reveal(idx),
      onLongPress: () => _toggleFlag(idx),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: revealed
              ? const Color(0xFF2A2A2A)
              : const Color(0xFF555F6B),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: const Color(0xFF2E3640), width: 0.5),
        ),
        alignment: Alignment.center,
        child: _cellContent(cell),
      ),
    );
  }

  Widget _cellContent(_MCell cell) {
    if (!cell.revealed) {
      return cell.flagged
          ? const Text('🚩', style: TextStyle(fontSize: 14))
          : const SizedBox.shrink();
    }
    if (cell.mine) {
      return const Text('💥', style: TextStyle(fontSize: 14));
    }
    if (cell.adjacent == 0) return const SizedBox.shrink();
    return Text(
      '${cell.adjacent}',
      style: TextStyle(
        color: _numColor(cell.adjacent),
        fontSize: 15,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.none,
      ),
    );
  }

  Color _numColor(int n) {
    switch (n) {
      case 1:
        return const Color(0xFF4FC3F7);
      case 2:
        return const Color(0xFF6EE060);
      case 3:
        return const Color(0xFFFF5252);
      case 4:
        return const Color(0xFFB39DDB);
      case 5:
        return const Color(0xFFFFB74D);
      case 6:
        return const Color(0xFF4DB6AC);
      case 7:
        return const Color(0xFFE0E0E0);
      default:
        return Colors.white;
    }
  }

  Widget _resultBanner() {
    final won = _won;
    return Container(
      width: double.infinity,
      color: won ? const Color(0xCC1B5E20) : const Color(0xCCB71C1C),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            won ? '🎉 通关！用时 $_elapsed 秒' : '💥 踩雷了',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _newGame,
            child: const Text('再来一局',
                style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
