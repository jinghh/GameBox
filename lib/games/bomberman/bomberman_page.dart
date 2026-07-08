// 泡泡堂 —— 经典炸弹人。网格步进移动,放炸弹十字爆炸,炸砖块/敌人,掉道具。
// 人 vs AI(多敌人,游走+追击+避炸弹),生命制,过关递增。纯单机;最高分本地保存。
// 实时引擎用 Ticker + CustomPainter(与坦克同款高效画法),复用坦克的 SoundService。

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../shared/best_score_store.dart';
import '../../shared/bgm_synth.dart';
import '../../shared/game_shell.dart';
import '../../shared/swipe_detector.dart';
import '../tank/sound.dart';

const int _cols = 13;
const int _rows = 13;
const String _bestKey = 'best_bomber';

// ---- 节奏参数 ----
const double _kFuse = 2.4; // 引信(秒)
const double _kFlameTime = 0.5; // 火焰存留(秒)
const double _kInvuln = 2.0; // 复活无敌(秒)
const double _kPlayerSpeed = 3.7; // 格/秒
const double _kCrateDropChance = 0.32; // 砖块掉道具概率

enum _Power { bomb, flame, speed }

/// 移动体基类:逻辑格 + 行进方向 + 到下一格的进度 t(0..1)。
class _Mover {
  int col, row;
  SwipeDir? dir; // null = 停止
  double t = 0;
  _Mover(this.col, this.row);
  Offset posOf(double cell) {
    if (dir == null) return Offset(col * cell + cell / 2, row * cell + cell / 2);
    final (dx, dy) = _delta(dir!);
    return Offset((col + dx * t) * cell + cell / 2,
        (row + dy * t) * cell + cell / 2);
  }
}

class _Player extends _Mover {
  int lives, maxBombs, flameRange, activeBombs;
  double speed, invuln = 0;
  bool alive = true;
  _Player()
      : lives = 3,
        maxBombs = 1,
        flameRange = 2,
        activeBombs = 0,
        speed = _kPlayerSpeed,
        super(1, 1);
}

class _Enemy extends _Mover {
  final double speed;
  final Color color;
  bool alive = true;
  _Enemy(super.col, super.row, this.color, this.speed);
}

class _Bomb {
  final int col, row, range;
  double fuse;
  _Bomb(this.col, this.row, this.range, this.fuse);
}

class _PowerUp {
  final int col, row;
  final _Power kind;
  _PowerUp(this.col, this.row, this.kind);
}

(int, int) _delta(SwipeDir d) => switch (d) {
      SwipeDir.up => (0, -1),
      SwipeDir.down => (0, 1),
      SwipeDir.left => (-1, 0),
      SwipeDir.right => (1, 0),
    };

SwipeDir _opp(SwipeDir d) => switch (d) {
      SwipeDir.up => SwipeDir.down,
      SwipeDir.down => SwipeDir.up,
      SwipeDir.left => SwipeDir.right,
      SwipeDir.right => SwipeDir.left,
    };

const List<SwipeDir> _allDirs = [
  SwipeDir.up,
  SwipeDir.down,
  SwipeDir.left,
  SwipeDir.right
];

class BomberPage extends StatefulWidget {
  const BomberPage({super.key});
  @override
  State<BomberPage> createState() => _BomberPageState();
}

class _BomberPageState extends State<BomberPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _lastElapsed = Duration.zero;

  late List<List<int>> _grid; // 0 空 / 1 砖 / 2 钢(含边界与柱)
  final _Player _player = _Player();
  final List<_Enemy> _enemies = [];
  final Map<int, _Bomb> _bombs = {}; // key = row*cols+col
  final Map<int, double> _flame = {}; // key -> 剩余秒
  final List<_PowerUp> _powers = [];

  int _level = 1;
  int _score = 0, _best = 0;
  bool _started = false, _paused = false, _over = false, _cleared = false;

  final List<SwipeDir> _held = []; // 按住的方向栈(支持多指/换向)
  final Random _rng = Random();
  final FocusNode _focus = FocusNode();
  final SoundService _snd = SoundService();
  late final ChiptuneBgm _bgm;

  static final List<Color> _enemyColors = [
    const Color(0xFFEF5350),
    const Color(0xFFAB47BC),
    const Color(0xFFEC407A),
    const Color(0xFFFF7043),
    const Color(0xFF5C6BC0),
  ];

  bool get _playing =>
      _started && !_paused && !_over && !_cleared && _player.alive;

  @override
  void initState() {
    super.initState();
    _best = BestScoreStore.get(_bestKey);
    _ticker = Ticker(_onTick);
    _buildArena(_level);
    _snd.init(); // 异步预加载,失败忽略
    _bgm = ChiptuneBgm(theme: BgmTheme.bounce);
    _bgm.init();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _focus.dispose();
    _snd.dispose();
    _bgm.dispose();
    super.dispose();
  }

  void _syncTicker() {
    if (_playing) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;
    if (dt <= 0 || !_playing) return;
    _update(dt);
    _repaint.value = (_repaint.value + 1) & 0x3fffffff;
  }

  // ---- 地图 ----
  bool _isBorder(int r, int c) =>
      r == 0 || c == 0 || r == _rows - 1 || c == _cols - 1;
  bool _isPillar(int r, int c) => r % 2 == 0 && c % 2 == 0;

  int _key(int c, int r) => r * _cols + c;

  bool _cellSolid(int c, int r) {
    if (r < 0 || c < 0 || r >= _rows || c >= _cols) return true;
    if (_grid[r][c] != 0) return true; // 砖/钢
    if (_bombs.containsKey(_key(c, r))) return true;
    return false;
  }

  void _buildArena(int level) {
    _grid = List.generate(_rows, (_) => List<int>.filled(_cols, 0));
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (_isBorder(r, c) || _isPillar(r, c)) _grid[r][c] = 2;
      }
    }
    // 砖块:内部非柱、且离玩家出生点(1,1)曼哈顿>2 的格随机放砖
    for (int r = 1; r < _rows - 1; r++) {
      for (int c = 1; c < _cols - 1; c++) {
        if (_grid[r][c] != 0) continue;
        if ((c - 1).abs() + (r - 1).abs() <= 2) continue; // 玩家安全区
        if (_rng.nextDouble() < 0.74) _grid[r][c] = 1;
      }
    }
    // 玩家复位
    _player
      ..col = 1
      ..row = 1
      ..dir = null
      ..t = 0
      ..invuln = _kInvuln
      ..activeBombs = 0;
    // 敌人:远角生成,数量随关卡
    _enemies.clear();
    _bombs.clear();
    _flame.clear();
    _powers.clear();
    final corners = <(int, int)>[
      (_cols - 2, _rows - 2),
      (_cols - 2, 1),
      (1, _rows - 2),
    ];
    final count = min(2 + level, 6);
    for (int i = 0; i < count; i++) {
      final (cc, rr) = corners[i % corners.length];
      _grid[rr][cc] = 0; // 清出生格
      // 偶尔清出一个邻居,保证能动
      _spawnClearNeighbor(cc, rr);
      final speed = min(3.3, 2.35 + level * 0.12);
      final e = _Enemy(cc, rr, _enemyColors[i % _enemyColors.length], speed);
      e.dir = _firstValidDir(cc, rr) ?? SwipeDir.right;
      _enemies.add(e);
    }
  }

  void _spawnClearNeighbor(int c, int r) {
    for (final d in _allDirs) {
      final (nc, nr) = _delta(d);
      final cc = c + nc, rr = r + nr;
      if (rr > 0 && cc > 0 && rr < _rows - 1 && cc < _cols - 1 &&
          !_isPillar(rr, cc)) {
        _grid[rr][cc] = 0;
        return;
      }
    }
  }

  SwipeDir? _firstValidDir(int c, int r) {
    for (final d in _allDirs) {
      final (dx, dy) = _delta(d);
      if (!_cellSolid(c + dx, r + dy)) return d;
    }
    return null;
  }

  // ---- 流程 ----
  void _start() {
    if (_started && !_over) return;
    if (_over) {
      // 从游戏结束重启:全清
      _level = 1;
      _score = 0;
      _player
        ..lives = 3
        ..maxBombs = 1
        ..flameRange = 2
        ..speed = _kPlayerSpeed
        ..alive = true;
      _buildArena(_level);
    }
    _started = true;
    _paused = false;
    _over = false;
    _cleared = false;
    _player.invuln = _kInvuln;
    _lastElapsed = Duration.zero;
    _snd.play('start');
    _syncTicker();
    _bgm.start();
    setState(() {});
  }

  void _togglePause() {
    if (!_started || _over || _cleared) return;
    _paused = !_paused;
    if (_paused) {
      _ticker.stop();
      _bgm.stop();
    } else {
      _lastElapsed = Duration.zero;
      _syncTicker();
      _bgm.start();
    }
    setState(() {});
  }

  void _newGame() {
    _ticker.stop();
    _bgm.stop();
    _level = 1;
    _score = 0;
    _player
      ..lives = 3
      ..maxBombs = 1
      ..flameRange = 2
      ..speed = _kPlayerSpeed
      ..alive = true;
    _started = false;
    _paused = false;
    _over = false;
    _cleared = false;
    _held.clear();
    _buildArena(_level);
    setState(() {});
  }

  void _nextLevel() {
    _level++;
    _cleared = false;
    _player.invuln = _kInvuln;
    _buildArena(_level);
    _lastElapsed = Duration.zero;
    _syncTicker();
    _bgm.start();
    setState(() {});
  }

  // ---- 输入 ----
  void _pressDir(SwipeDir d) {
    if (!_started && !_over) _start();
    if (_over || _cleared) return;
    _held.remove(d);
    _held.add(d);
    _applyInput(d);
  }

  void _releaseDir(SwipeDir d) {
    _held.remove(d);
    // 到下一格后再决定是否停(onArrive 读 _held)
  }

  void _applyInput(SwipeDir d) {
    if (!_playing) return;
    // 即时反向:把目标格变当前格,反向继续
    if (_player.dir != null && _opp(d) == _player.dir) {
      final (dx, dy) = _delta(_player.dir!);
      final nc = _player.col + dx, nr = _player.row + dy;
      if (!_cellSolid(nc, nr)) {
        _player.col = nc;
        _player.row = nr;
        _player.dir = _opp(_player.dir!);
        _player.t = 1 - _player.t;
      }
      return;
    }
    if (_player.dir == null) {
      if (!_cellSolidNeighbor(_player.col, _player.row, d)) _player.dir = d;
    }
    // 否则保持当前腿,onArrive 时取 _held.last
  }

  bool _cellSolidNeighbor(int c, int r, SwipeDir d) {
    final (dx, dy) = _delta(d);
    return _cellSolid(c + dx, r + dy);
  }

  void _placeBomb() {
    if (!_playing) {
      if (!_started && !_over) _start();
      return;
    }
    if (_player.activeBombs >= _player.maxBombs) return;
    final k = _key(_player.col, _player.row);
    if (_bombs.containsKey(k)) return;
    if (_grid[_player.row][_player.col] != 0) return;
    _bombs[k] = _Bomb(_player.col, _player.row, _player.flameRange, _kFuse);
    _player.activeBombs++;
    _snd.play('shoot');
    HapticFeedback.selectionClick();
  }

  // ---- 主更新 ----
  void _update(double dt) {
    // 引信 / 火焰 / 无敌 倒计时
    final exploded = <int>[];
    for (final e in _bombs.entries) {
      e.value.fuse -= dt;
      if (e.value.fuse <= 0) exploded.add(e.key);
    }
    for (final k in exploded) {
      final b = _bombs.remove(k);
      if (b != null) _explode(b);
    }
    if (_flame.isNotEmpty) {
      final dead = <int>[];
      _flame.forEach((k, v) {
        final nv = v - dt;
        if (nv <= 0) {
          dead.add(k);
        } else {
          _flame[k] = nv;
        }
      });
      for (final k in dead) {
        _flame.remove(k);
      }
    }
    if (_player.invuln > 0) _player.invuln = max(0, _player.invuln - dt);

    // 移动
    _advance(_player, dt, _player.speed, _playerArrive);
    for (final e in _enemies) {
      if (e.alive) _advance(e, dt, e.speed, () => _enemyArrive(e));
    }

    // 撞怪判负(无敌期除外):用连续格坐标算距离,同格或迎面穿过都算撞上
    _resolveEnemyContact();

    // 火焰伤害(当前格或半程后的目标格)
    if (_flame.isNotEmpty) _resolveFlameHits();

    // 清死亡敌人
    if (_enemies.any((e) => !e.alive)) {
      _enemies.removeWhere((e) => !e.alive);
      setState(() {});
    }

    // 道具拾取
    if (_player.alive) {
      final p = _powers;
      for (int i = p.length - 1; i >= 0; i--) {
        if (p[i].col == _player.col && p[i].row == _player.row) {
          _collect(p[i]);
          p.removeAt(i);
        }
      }
    }

    // 通关
    if (_enemies.isEmpty && !_over && !_cleared) {
      _onLevelClear();
    }
  }

  SwipeDir? _playerArrive() {
    if (_held.isNotEmpty) {
      final d = _held.last;
      if (!_cellSolidNeighbor(_player.col, _player.row, d)) return d;
    }
    return null;
  }

  SwipeDir? _enemyArrive(_Enemy e) {
    final valid = <SwipeDir>[];
    for (final d in _allDirs) {
      if (!_cellSolidNeighbor(e.col, e.row, d)) valid.add(d);
    }
    if (valid.isEmpty) return null;
    // 追击概率
    if (_player.alive && _rng.nextDouble() < 0.42) {
      valid.sort((a, b) {
        final (ax, ay) = _delta(a);
        final (bx, by) = _delta(b);
        final da = (_player.col - (e.col + ax)).abs() +
            (_player.row - (e.row + ay)).abs();
        final db = (_player.col - (e.col + bx)).abs() +
            (_player.row - (e.row + by)).abs();
        return da.compareTo(db);
      });
      return valid.first;
    }
    if (e.dir != null && valid.contains(e.dir) && _rng.nextDouble() < 0.6) {
      return e.dir;
    }
    return valid[_rng.nextInt(valid.length)];
  }

  void _advance(_Mover m, double dt, double speed, SwipeDir? Function() onArrive) {
    if (m.dir == null) return;
    var (dx, dy) = _delta(m.dir!);
    if (_cellSolid(m.col + dx, m.row + dy)) {
      m.dir = null;
      m.t = 0;
      return;
    }
    m.t += speed * dt;
    while (m.t >= 1) {
      m.t -= 1;
      m.col += dx;
      m.row += dy;
      m.dir = onArrive();
      if (m.dir == null) {
        m.t = 0;
        break;
      }
      final (ndx, ndy) = _delta(m.dir!);
      if (_cellSolid(m.col + ndx, m.row + ndy)) {
        m.dir = null;
        m.t = 0;
        break;
      }
      dx = ndx;
      dy = ndy;
    }
  }

  // ---- 爆炸 ----
  void _explode(_Bomb b) {
    _player.activeBombs = max(0, _player.activeBombs - 1);
    _snd.play('explosion');
    HapticFeedback.heavyImpact();
    final cells = <int>[_key(b.col, b.row)];
    for (final d in _allDirs) {
      final (dx, dy) = _delta(d);
      for (int i = 1; i <= b.range; i++) {
        final c = b.col + dx * i, r = b.row + dy * i;
        if (r < 0 || c < 0 || r >= _rows || c >= _cols) break;
        if (_grid[r][c] == 2) break; // 钢:火焰止步
        final k = _key(c, r);
        cells.add(k);
        if (_grid[r][c] == 1) {
          _grid[r][c] = 0;
          _score += 5;
          if (_rng.nextDouble() < _kCrateDropChance) {
            _powers.add(_PowerUp(c, r, _Power.values[_rng.nextInt(3)]));
          }
          break; // 砖:炸毁后火焰止步
        }
      }
    }
    for (final k in cells) {
      _flame[k] = _kFlameTime;
    }
    _updateBest();
    setState(() {}); // 砖块/分数变化
  }

  /// 玩家与敌人的连续格坐标(含行进插值),用于碰撞判定。
  (double, double) _cellPos(_Mover m) {
    if (m.dir == null) return (m.col.toDouble(), m.row.toDouble());
    final (dx, dy) = _delta(m.dir!);
    return (m.col + dx * m.t, m.row + dy * m.t);
  }

  /// 玩家撞到敌人 → 受伤(无敌期除外)。同格或迎面穿过都会触发。
  void _resolveEnemyContact() {
    if (!_player.alive || _player.invuln > 0) return;
    final (px, py) = _cellPos(_player);
    for (final e in _enemies) {
      if (!e.alive) continue;
      final (ex, ey) = _cellPos(e);
      final d2 = (px - ex) * (px - ex) + (py - ey) * (py - ey);
      if (d2 < 0.6 * 0.6) {
        _hurtPlayer();
        return;
      }
    }
  }

  void _resolveFlameHits() {
    bool hitPlayer = false;
    if (_player.alive && _player.invuln <= 0) {
      if (_flame.containsKey(_key(_player.col, _player.row))) {
        hitPlayer = true;
      } else if (_player.dir != null && _player.t > 0.5) {
        final (dx, dy) = _delta(_player.dir!);
        if (_flame.containsKey(_key(_player.col + dx, _player.row + dy))) {
          hitPlayer = true;
        }
      }
    }
    for (final e in _enemies) {
      if (!e.alive) continue;
      bool hit = _flame.containsKey(_key(e.col, e.row));
      if (!hit && e.dir != null && e.t > 0.5) {
        final (dx, dy) = _delta(e.dir!);
        hit = _flame.containsKey(_key(e.col + dx, e.row + dy));
      }
      if (hit) {
        e.alive = false;
        _score += 100;
        _snd.play('hit');
      }
    }
    if (hitPlayer) _hurtPlayer();
    if (hitPlayer || _score >= 0) _updateBest();
  }

  void _hurtPlayer() {
    _player.lives--;
    _snd.play('hit');
    HapticFeedback.heavyImpact();
    if (_player.lives <= 0) {
      _player.alive = false;
      _over = true;
      _snd.play('gameover');
      _ticker.stop();
      _bgm.stop();
      setState(() {});
      return;
    }
    // 复活到出生格(若被占则就近)
    int rc = 1, rr = 1;
    if (_cellSolid(rc, rr) || _flame.containsKey(_key(rc, rr))) {
      outer:
      for (int rad = 1; rad < 4; rad++) {
        for (int r = 1; r <= rad; r++) {
          for (int c = 1; c <= rad; c++) {
            if ((c == 1 && r == 1)) continue;
            if (!_cellSolid(c, r) && !_flame.containsKey(_key(c, r))) {
              rc = c;
              rr = r;
              break outer;
            }
          }
        }
      }
    }
    _player
      ..col = rc
      ..row = rr
      ..dir = null
      ..t = 0
      ..invuln = _kInvuln;
    _held.clear();
    setState(() {});
  }

  void _collect(_PowerUp p) {
    _snd.play('powerup');
    HapticFeedback.mediumImpact();
    setState(() {
      switch (p.kind) {
        case _Power.bomb:
          _player.maxBombs = min(6, _player.maxBombs + 1);
          break;
        case _Power.flame:
          _player.flameRange = min(8, _player.flameRange + 1);
          break;
        case _Power.speed:
          _player.speed = min(5.6, _player.speed + 0.5);
          break;
      }
    });
  }

  void _onLevelClear() {
    _cleared = true;
    _ticker.stop();
    _bgm.stop();
    _score += 500;
    _snd.play('powerup');
    _updateBest();
    setState(() {});
  }

  void _updateBest() {
    if (_score > _best) {
      _best = _score;
      BestScoreStore.setIfGreater(_bestKey, _best);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _pressDir(SwipeDir.up);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      _pressDir(SwipeDir.down);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _pressDir(SwipeDir.left);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _pressDir(SwipeDir.right);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
      _placeBomb();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '泡泡堂',
      actions: [
        if (_started && !_over && !_cleared)
          IconButton(
            tooltip: _paused ? '继续' : '暂停',
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause,
                color: const Color(0xFFFF8A4C)),
            onPressed: _togglePause,
          ),
        TextButton(
          onPressed: _newGame,
          child: const Text('新游戏',
              style: TextStyle(color: Color(0xFFFF8A4C))),
        ),
      ],
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final maxW = c.maxWidth - 12;
            final maxH = c.maxHeight - 8;
            // 控件尺寸独立于棋盘格,保证方向键够大好按
            final ctrl = (c.maxWidth * 0.155).clamp(54.0, 68.0);
            final reserveTop = 46.0; // HUD + 间距
            final reserveBottom = ctrl * 3 + 26; // 方向键 + 间距
            final cell =
                min(maxW / _cols, (maxH - reserveTop - reserveBottom) / _rows)
                    .clamp(18.0, 38.0);
            final boardW = cell * _cols;
            final boardH = cell * _rows;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _hud(),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: boardW,
                    height: boardH,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(boardW, boardH),
                          painter: _BomberPainter(
                            grid: _grid,
                            player: _player,
                            enemies: _enemies,
                            bombs: _bombs,
                            flame: _flame,
                            powers: _powers,
                            cell: cell,
                            repaint: _repaint,
                          ),
                        ),
                        if (!_started || _over || _paused || _cleared)
                          _overlay(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _controls(ctrl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _hud() {
    final alive = _enemies.where((e) => e.alive).length;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          _chip('关卡', '$_level', const Color(0xFFFF8A4C)),
          _chip('得分', '$_score', const Color(0xFFFFD54A)),
          _chip('敌', '$alive', const Color(0xFFEF5350)),
          _chip('💣', '${_player.maxBombs}', const Color(0xFFB0BEC5)),
          _chip('🔥', '${_player.flameRange}', const Color(0xFFFF7043)),
          _chip('❤', '${_player.lives}', const Color(0xFFE57373)),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ',
              style: const TextStyle(color: Color(0xFF999999), fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _overlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC000000),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_cleared) ...[
              Text('🎉 第 $_level 关 通过!',
                  style: const TextStyle(
                      color: Color(0xFFFFD54A),
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('+500 分 · 当前 $_score',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              _ovBtn('进入下一关', const Color(0xFFFF8A4C), _nextLevel),
            ] else if (_over) ...[
              const Text('游戏结束',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('到达第 $_level 关 · 得分 $_score · 最高 $_best',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              _ovBtn('再来一局', const Color(0xFFFFD54A), _start),
            ] else if (_paused) ...[
              const Text('暂停',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              _ovBtn('继续游戏', const Color(0xFFFF8A4C), _togglePause),
            ] else ...[
              const Text('泡泡堂',
                  style: TextStyle(
                      color: Color(0xFFFF8A4C),
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('方向键移动 · 炸弹键放雷\n炸掉所有敌人即可过关',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              _ovBtn('开始游戏', const Color(0xFFFF8A4C), _start),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ovBtn(String text, Color color, VoidCallback onTap) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
      ),
      onPressed: onTap,
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF222222), fontWeight: FontWeight.bold)),
    );
  }

  Widget _controls(double btn) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 方向键(十字)
          SizedBox(
            width: btn * 3,
            height: btn * 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                    top: 0,
                    child: _dirBtn(SwipeDir.up, Icons.arrow_drop_up, btn)),
                Positioned(
                    bottom: 0,
                    child: _dirBtn(SwipeDir.down, Icons.arrow_drop_down, btn)),
                Positioned(
                    left: 0,
                    child: _dirBtn(SwipeDir.left, Icons.arrow_left, btn)),
                Positioned(
                    right: 0,
                    child: _dirBtn(SwipeDir.right, Icons.arrow_right, btn)),
                Container(
                  width: btn,
                  height: btn,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF444444)),
                  ),
                ),
              ],
            ),
          ),
          // 炸弹键
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _placeBomb,
            child: Container(
              width: btn * 1.5,
              height: btn * 1.5,
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                shape: BoxShape.circle,
                border:
                    Border.all(color: const Color(0xFFFF7043), width: 2.5),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x55FF7043), blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💣', style: TextStyle(fontSize: 30)),
                  const Text('放雷',
                      style: TextStyle(
                          color: Color(0xFFFF7043),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dirBtn(SwipeDir d, IconData icon, double s) {
    const color = Color(0xFFFF8A4C);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pressDir(d),
      onTapUp: (_) => _releaseDir(d),
      onTapCancel: () => _releaseDir(d),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: s * 0.85),
      ),
    );
  }
}

/// 泡泡堂绘制:地面/钢墙/砖块/道具/炸弹/火焰/敌人/玩家。
class _BomberPainter extends CustomPainter {
  final List<List<int>> grid;
  final _Player player;
  final List<_Enemy> enemies;
  final Map<int, _Bomb> bombs;
  final Map<int, double> flame;
  final List<_PowerUp> powers;
  final double cell;
  _BomberPainter({
    required this.grid,
    required this.player,
    required this.enemies,
    required this.bombs,
    required this.flame,
    required this.powers,
    required this.cell,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 地面
    final floorA = Paint()..color = const Color(0xFF2E7D32);
    final floorB = Paint()..color = const Color(0xFF266A2A);
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cell, r * cell, cell, cell),
          (r + c) % 2 == 0 ? floorA : floorB,
        );
      }
    }
    // 钢墙/砖块
    final steel = Paint()..color = const Color(0xFF8E9AAB);
    final steelDark = Paint()..color = const Color(0xFF5C6776);
    final crate = Paint()..color = const Color(0xFFC98A45);
    final crateDark = Paint()..color = const Color(0xFF7A4E20);
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        final v = grid[r][c];
        if (v == 2) {
          _roundRect(canvas, c * cell, r * cell, cell, cell, cell * 0.12,
              steel);
          canvas.drawRect(
            Rect.fromLTWH(
                c * cell + cell * 0.18, r * cell + cell * 0.18, cell * 0.64, cell * 0.64),
            steelDark,
          );
        } else if (v == 1) {
          _roundRect(canvas, c * cell + 1, r * cell + 1, cell - 2, cell - 2,
              cell * 0.14, crate);
          // 砖纹
          canvas.drawLine(
              Offset(c * cell + 1, r * cell + cell * 0.5),
              Offset(c * cell + cell - 1, r * cell + cell * 0.5),
              crateDark..strokeWidth = 1);
        }
      }
    }
    // 道具
    for (final p in powers) {
      _drawPower(canvas, p);
    }
    // 炸弹
    for (final b in bombs.values) {
      _drawBomb(canvas, b);
    }
    // 火焰
    flame.forEach((k, v) {
      final r = k ~/ _cols, c = k % _cols;
      _drawFlame(canvas, c * cell, r * cell, cell, v);
    });
    // 敌人
    for (final e in enemies) {
      if (!e.alive) continue;
      _drawBlob(canvas, e.posOf(cell), cell, e.color, false, e.dir);
    }
    // 玩家
    if (player.alive) {
      final blink = player.invuln > 0 &&
          (player.invuln * 10).floor() % 2 == 0;
      if (!blink) {
        _drawBlob(canvas, player.posOf(cell), cell,
            const Color(0xFF42A5F5), true, player.dir);
      }
    }
  }

  void _roundRect(Canvas canvas, double x, double y, double w, double h,
      double r, Paint p) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        p);
  }

  void _drawPower(Canvas canvas, _PowerUp p) {
    final cx = p.col * cell + cell / 2, cy = p.row * cell + cell / 2;
    final r = cell * 0.3;
    final color = switch (p.kind) {
      _Power.bomb => const Color(0xFFFFCA28),
      _Power.flame => const Color(0xFFFF7043),
      _Power.speed => const Color(0xFF42A5F5),
    };
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
    final letter = switch (p.kind) {
      _Power.bomb => 'B',
      _Power.flame => 'F',
      _Power.speed => 'S',
    };
    final tp = TextPainter(
      text: TextSpan(
          text: letter,
          style: const TextStyle(
              color: Color(0xFF222222),
              fontSize: 13,
              fontWeight: FontWeight.bold)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _drawBomb(Canvas canvas, _Bomb b) {
    final cx = b.col * cell + cell / 2, cy = b.row * cell + cell / 2;
    // 引信越短越大并闪烁
    final pulse = 1 + (1 - (b.fuse / _kFuse).clamp(0.0, 1.0)) * 0.18;
    final blink = b.fuse < 0.6 && (b.fuse * 12).floor() % 2 == 0;
    final r = cell * 0.32 * pulse;
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = blink ? const Color(0xFFFF5252) : const Color(0xFF202020));
    canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.3),
        r * 0.28,
        Paint()..color = const Color(0xFF666666));
    // 引信火星
    canvas.drawCircle(Offset(cx + r * 0.5, cy - r * 0.7), cell * 0.06,
        Paint()..color = const Color(0xFFFFD54A));
  }

  void _drawFlame(Canvas canvas, double x, double y, double cellSize, double v) {
    final a = (v / _kFlameTime).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2, y + 2, cellSize - 4, cellSize - 4),
        Radius.circular(cellSize * 0.2),
      ),
      Paint()..color = const Color(0xFFFFCA28).withValues(alpha: 0.55 + 0.35 * a),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + cellSize * 0.22, y + cellSize * 0.22,
            cellSize * 0.56, cellSize * 0.56),
        Radius.circular(cellSize * 0.18),
      ),
      Paint()..color = const Color(0xFFFF5252).withValues(alpha: 0.5 + 0.4 * a),
    );
  }

  void _drawBlob(Canvas canvas, Offset center, double cellSize, Color color,
      bool isPlayer, SwipeDir? dir) {
    final r = cellSize * 0.36;
    // 身体
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(center, r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // 眼睛朝向
    double ex = 0, ey = -r * 0.1;
    double lookx = 0, looky = 0;
    switch (dir) {
      case SwipeDir.up:
        ey = -r * 0.25;
        looky = -1;
        break;
      case SwipeDir.down:
        ey = r * 0.05;
        looky = 1;
        break;
      case SwipeDir.left:
        ex = -r * 0.1;
        lookx = -1;
        break;
      case SwipeDir.right:
        ex = r * 0.1;
        lookx = 1;
        break;
      case null:
        break;
    }
    final sep = r * 0.32;
    // 沿垂直方向分布两眼
    final (px, py) = dir == SwipeDir.left || dir == SwipeDir.right
        ? (0.0, 1.0)
        : (1.0, 0.0);
    for (final s in const [-1.0, 1.0]) {
      final eyeX = center.dx + ex + px * sep * s;
      final eyeY = center.dy + ey + py * sep * s;
      canvas.drawCircle(Offset(eyeX, eyeY), r * 0.2,
          Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset(eyeX + lookx * r * 0.08, eyeY + looky * r * 0.08),
          r * 0.1,
          Paint()..color = const Color(0xFF111111));
    }
    if (isPlayer) {
      // 头顶天线小点
      canvas.drawCircle(Offset(center.dx, center.dy - r * 1.05), cellSize * 0.05,
          Paint()..color = const Color(0xFFFFD54A));
    }
  }

  @override
  bool shouldRepaint(covariant _BomberPainter old) => true;
}
