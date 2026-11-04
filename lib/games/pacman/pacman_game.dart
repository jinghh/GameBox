import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/best_score_store.dart';
import '../../shared/orientation.dart';
import '../../shared/sound_store.dart';
import 'pacman_entities.dart';
import 'pacman_map.dart';
import 'pacman_painter.dart';
import 'pacman_sound.dart';

enum GameState { ready, playing, dying, levelClear, gameOver }

/// 经典幽灵模式时间表：散布/追逐 交替。
const List<(GhostMode, double)> _phases = [
  (GhostMode.scatter, 7),
  (GhostMode.chase, 20),
  (GhostMode.scatter, 7),
  (GhostMode.chase, 20),
  (GhostMode.scatter, 5),
  (GhostMode.chase, 20),
  (GhostMode.scatter, 5),
  (GhostMode.chase, 9999),
];

class PacManPage extends StatefulWidget {
  const PacManPage({super.key});

  @override
  State<PacManPage> createState() => _PacManPageState();
}

class _PacManPageState extends State<PacManPage> {
  late PacManMap _map;
  late PacMan _pac;
  late List<Ghost> _ghosts;
  late PacmanSound _sound;

  int _score = 0;
  int _high = 0;
  int _lives = 3;
  int _level = 1;
  int _pelletsRemaining = 0;

  GameState _state = GameState.ready;
  double _readyTimer = 0;
  double _deathTimer = 0;
  double _clearTimer = 0;

  double _mouthPhase = 0;
  double _energizerPulse = 0;
  double _elapsed = 0;

  double _frightenedTimer = 0;
  int _ghostEatChain = 200;
  int _phaseIndex = 0;
  GhostMode _phaseMode = GhostMode.scatter;
  double _phaseTimer = 7;

  // 水果（经典樱桃）
  ({double x, double y, int value})? _fruit;
  double _fruitTimer = 0;
  final Set<int> _fruitSpawned = {};

  final Random _rand = Random();
  final FocusNode _focus = FocusNode();
  Timer? _timer;
  final Stopwatch _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    _sound = PacmanSound();
    _initGame();
    _sound.init();
    BestScoreStore.ensureLoaded().then((_) {
      if (mounted) setState(() => _high = BestScoreStore.get('pacman_best'));
    });
    // 竖屏：通过原生 MethodChannel 强制，绕过 MIUI 对 SystemChrome 的忽略
    OrientationChannel.set(AppOrientation.portrait);
    _sw.start();
    // 主页改全局静音时，本页图标需跟着变
    kMuted.addListener(_onMuteChanged);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _onTick());
  }

  @override
  void dispose() {
    kMuted.removeListener(_onMuteChanged);
    _timer?.cancel();
    _sound.dispose();
    _focus.dispose();
    // 退出时恢复 App 默认竖屏（勿用 sensor：横拿手机时会导致主页/其他页横屏）
    OrientationChannel.set(AppOrientation.portrait);
    super.dispose();
  }

  void _initGame() {
    _map = PacManMap();
    _score = 0;
    _lives = 3;
    _level = 1;
    _pelletsRemaining = _map.totalPellets;
    _frightenedTimer = 0;
    _phaseIndex = 0;
    _phaseMode = GhostMode.scatter;
    _phaseTimer = _phases[0].$2;
    _ghostEatChain = 200;
    _elapsed = 0;
    _fruitSpawned.clear();
    _fruit = null;
    _resetPositions();
    _state = GameState.ready;
    _readyTimer = 0;
    if (_score > _high) _high = _score;
  }

  void _resetPositions() {
    _pac = PacMan(
      x: PacManMap.pacStartX,
      y: PacManMap.pacStartY,
      dir: Dir.left,
      pending: Dir.none,
    );
    _ghosts = [
      Ghost(
        name: GhostName.blinky,
        x: 13,
        y: 11,
        dir: Dir.left,
        mode: _phaseMode,
        speed: 7.0,
        releaseAt: 0,
      ),
      Ghost(
        name: GhostName.pinky,
        x: 13,
        y: 14,
        dir: Dir.up,
        mode: GhostMode.house,
        speed: 7.0,
        releaseAt: 2,
      ),
      Ghost(
        name: GhostName.inky,
        x: 11,
        y: 14,
        dir: Dir.up,
        mode: GhostMode.house,
        speed: 7.0,
        releaseAt: 5,
      ),
      Ghost(
        name: GhostName.clyde,
        x: 16,
        y: 14,
        dir: Dir.up,
        mode: GhostMode.house,
        speed: 7.0,
        releaseAt: 8,
      ),
    ];
  }

  // ---- 主循环 ----
  void _onTick() {
    final dt = min(_sw.elapsedMilliseconds / 1000, 0.05);
    _sw.reset();
    _elapsed += dt;
    _mouthPhase += dt * 12;
    _energizerPulse += dt * 1.5;
    // 注意：Dart 的 switch 在 case 末尾没有 break 时会贯穿(fall-through)，
    // 这里每个 case 必须以 break 结尾，否则 playing 会额外执行 dying/levelClear 逻辑，导致秒死/秒过关。
    switch (_state) {
      case GameState.ready:
        _readyTimer += dt;
        if (_readyTimer > 1.6) _state = GameState.playing;
        break;
      case GameState.playing:
        _updatePlay(dt);
        break;
      case GameState.dying:
        _deathTimer += dt;
        if (_deathTimer > 1.3) _afterDeath();
        break;
      case GameState.levelClear:
        _clearTimer += dt;
        if (_clearTimer > 1.6) _nextLevel();
        break;
      case GameState.gameOver:
        break;
    }
    if (_score > _high) _high = _score;
    setState(() {});
  }

  void _updatePlay(double dt) {
    // 惊吓计时
    if (_frightenedTimer > 0) {
      _frightenedTimer -= dt;
      if (_frightenedTimer <= 0) {
        for (final g in _ghosts) {
          if (g.mode == GhostMode.frightened) g.mode = _phaseMode;
        }
      }
    } else {
      _phaseTimer -= dt;
      if (_phaseTimer <= 0 && _phaseIndex < _phases.length - 1) {
        _phaseIndex++;
        _phaseMode = _phases[_phaseIndex].$1;
        _phaseTimer = _phases[_phaseIndex].$2;
      }
    }

    _step(_pac, dt, false, _choosePac, _onCenterPac);
    for (final g in _ghosts) {
      _updateGhost(g, dt);
    }
    _updateFruit(dt);
    _checkCollisions();

    if (_pelletsRemaining <= 0) {
      _state = GameState.levelClear;
      _clearTimer = 0;
    }
  }

  void _updateGhost(Ghost g, double dt) {
    if (g.mode == GhostMode.house) {
      if (_elapsed >= g.releaseAt) {
        g.mode = GhostMode.leaving;
      } else {
        _stepHouse(g, dt);
        return;
      }
    }
    if (g.mode == GhostMode.leaving) {
      if (g.y.round() <= PacManMap.doorExitY) g.mode = _phaseMode;
    }
    if (g.mode == GhostMode.eyes) {
      final tx = g.x.round();
      final ty = g.y.round();
      if (ty >= 13 && tx >= 10 && tx <= 17 && _map.tileAt(tx, ty) == Tile.empty) {
        // 回巢完成后必须先转 leaving（可穿门）再出巢，
        // 若直接转 chase/scatter 会因无法穿门被困在鬼屋里。
        g.mode = GhostMode.leaving;
      }
    }
    final mul = 1 + 0.03 * (_level - 1);
    final base = g.baseSpeed * mul;
    g.speed = g.mode == GhostMode.frightened
        ? base * 0.6
        : (g.mode == GhostMode.eyes ? 14.0 : base);
    // 关键修复：只有「离巢/眼睛回巢」可穿鬼门。追逐/散布/惊惧的鬼若可穿门，
    // 会反复钻进钻出鬼屋，表现为在中央区域"直上直下飞来飞去"。
    final canUseDoor =
        g.mode == GhostMode.leaving || g.mode == GhostMode.eyes;
    _step(g, dt, canUseDoor, (tx, ty, cur) => _chooseGhost(g, tx, ty, cur),
        (_, _) {});
  }

  // ---- 移动（格子锁定） ----
  // 具体实现见 pacman_entities.dart 的 stepMover：页面与引擎单测共用同一份逻辑，
  // 避免复制实现随时间漂移；这里只补上页面持有的 _map。
  void _step(
    Mover m,
    double dt,
    bool canUseDoor,
    Dir? Function(int, int, Dir) choose,
    void Function(int, int) onCenter,
  ) {
    stepMover(m, _map, dt, canUseDoor, choose, onCenter);
  }

  void _stepHouse(Ghost g, double dt) {
    _step(g, dt, true, (tx, ty, cur) {
      if (cur == Dir.up && ty <= 14) {
        return Dir.down;
      }
      if (cur == Dir.down && ty >= 16) {
        return Dir.up;
      }
      if (_map.isWalkable(tx + cur.dx, ty + cur.dy, true)) {
        return cur;
      }
      return cur == Dir.up ? Dir.down : Dir.up;
    }, (_, _) {});
  }

  Dir? _choosePac(int tx, int ty, Dir cur) {
    if (_pac.pending != Dir.none &&
        _map.isWalkable(
            tx + _pac.pending.dx, ty + _pac.pending.dy, false)) {
      final d = _pac.pending;
      _pac.pending = Dir.none;
      return d;
    }
    if (_map.isWalkable(tx + cur.dx, ty + cur.dy, false)) return cur;
    return null;
  }

  ({double x, double y}) _ghostTarget(Ghost g) {
    switch (g.mode) {
      case GhostMode.house:
      case GhostMode.leaving:
        return (x: PacManMap.doorExitX.toDouble(), y: PacManMap.doorExitY.toDouble());
      case GhostMode.eyes:
        return (x: PacManMap.houseX.toDouble(), y: PacManMap.houseY.toDouble());
      case GhostMode.frightened:
        return (x: PacManMap.doorExitX.toDouble(), y: PacManMap.doorExitY.toDouble());
      case GhostMode.scatter:
        return _scatterCorner(g.name);
      case GhostMode.chase:
        return _chaseTarget(g);
    }
  }

  ({double x, double y}) _scatterCorner(GhostName n) => switch (n) {
        GhostName.blinky => (x: PacManMap.cols - 2.0, y: 0),
        GhostName.pinky => (x: 1.0, y: 0),
        GhostName.inky => (x: PacManMap.cols - 1.0, y: PacManMap.rows - 1.0),
        GhostName.clyde => (x: 0.0, y: PacManMap.rows - 1.0),
      };

  ({double x, double y}) _chaseTarget(Ghost g) {
    final px = _pac.x;
    final py = _pac.y;
    final pdx = _pac.dir.dx;
    final pdy = _pac.dir.dy;
    return switch (g.name) {
      GhostName.blinky => (x: px, y: py),
      GhostName.pinky => (x: px + 4 * pdx, y: py + 4 * pdy),
      GhostName.inky => (() {
          final blinky = _ghosts.firstWhere((e) => e.name == GhostName.blinky);
          final pivotX = px + 2 * pdx;
          final pivotY = py + 2 * pdy;
          return (
            x: 2 * pivotX - blinky.x,
            y: 2 * pivotY - blinky.y,
          );
        })(),
      GhostName.clyde => () {
          final d = sqrt(sqDist(g.x, g.y, px, py));
          if (d > 8) {
            return (x: px, y: py);
          }
          return _scatterCorner(GhostName.clyde);
        }(),
    };
  }

  Dir _chooseGhost(Ghost g, int tx, int ty, Dir cur) {
    // 与 _step 中一致：仅离巢/眼睛可把鬼门视为可走
    final door = g.mode == GhostMode.leaving || g.mode == GhostMode.eyes;
    if (g.mode == GhostMode.frightened) {
      final opts = [Dir.up, Dir.left, Dir.down, Dir.right]..remove(cur.opposite);
      final valid = opts
          .where((d) => _map.isWalkable(tx + d.dx, ty + d.dy, door))
          .toList();
      if (valid.isEmpty) return cur.opposite;
      return valid[_rand.nextInt(valid.length)];
    }
    final t = _ghostTarget(g);
    final opts = [Dir.up, Dir.left, Dir.down, Dir.right]..remove(cur.opposite);
    final valid = opts
        .where((d) => _map.isWalkable(tx + d.dx, ty + d.dy, door))
        .toList();
    if (valid.isEmpty) return cur.opposite;
    valid.sort((a, b) {
      final da = sqDist(tx + a.dx * 1.0, ty + a.dy * 1.0, t.x, t.y);
      final db = sqDist(tx + b.dx * 1.0, ty + b.dy * 1.0, t.x, t.y);
      if ((da - db).abs() > 0.01) return da < db ? -1 : 1;
      return a.priority.compareTo(b.priority);
    });
    return valid.first;
  }

  void _onCenterPac(int tx, int ty) {
    final t = _map.grid[ty][tx];
    if (t == Tile.pellet) {
      _map.grid[ty][tx] = Tile.empty;
      _score += 10;
      _pelletsRemaining--;
      _sound.eat();
    } else if (t == Tile.energizer) {
      _map.grid[ty][tx] = Tile.empty;
      _score += 50;
      _pelletsRemaining--;
      _sound.eat();
      _triggerFright();
    }
  }

  void _triggerFright() {
    _frightenedTimer = max(2.0, 7.0 - (_level - 1) * 0.7);
    _ghostEatChain = 200;
    for (final g in _ghosts) {
      if (g.mode == GhostMode.scatter ||
          g.mode == GhostMode.chase ||
          g.mode == GhostMode.leaving) {
        g.mode = GhostMode.frightened;
        g.dir = g.dir.opposite;
        g.pending = Dir.none;
      }
    }
    _sound.energizer();
  }

  void _updateFruit(double dt) {
    final eaten = _map.totalPellets - _pelletsRemaining;
    if (_fruit == null) {
      if (!_fruitSpawned.contains(70) && eaten >= 70) {
        _fruitSpawned.add(70);
        _fruit = (x: 13, y: 17, value: 100);
        _fruitTimer = 9;
      } else if (!_fruitSpawned.contains(170) && eaten >= 170) {
        _fruitSpawned.add(170);
        _fruit = (x: 13, y: 17, value: 300);
        _fruitTimer = 9;
      }
    } else {
      _fruitTimer -= dt;
      if (sqDist(_pac.x, _pac.y, _fruit!.x, _fruit!.y) < 0.5 * 0.5) {
        _score += _fruit!.value;
        _fruit = null;
      } else if (_fruitTimer <= 0) {
        _fruit = null;
      }
    }
  }

  void _checkCollisions() {
    for (final g in _ghosts) {
      if (sqDist(_pac.x, _pac.y, g.x, g.y) < 0.5 * 0.5) {
        if (g.mode == GhostMode.frightened) {
          _score += _ghostEatChain;
          _ghostEatChain = min(_ghostEatChain * 2, 1600);
          g.mode = GhostMode.eyes;
          _sound.eatGhost();
        } else if (g.mode == GhostMode.eyes) {
          // 穿身而过
        } else {
          _die();
          return;
        }
      }
    }
  }

  void _die() {
    _state = GameState.dying;
    _deathTimer = 0;
    _frightenedTimer = 0;
    _sound.death();
  }

  void _afterDeath() {
    _lives--;
    if (_lives <= 0) {
      _state = GameState.gameOver;
      BestScoreStore.setIfGreater('pacman_best', _score);
    } else {
      _resetPositions();
      _state = GameState.ready;
      _readyTimer = 0;
    }
  }

  void _nextLevel() {
    _level++;
    _map = PacManMap();
    _pelletsRemaining = _map.totalPellets;
    _frightenedTimer = 0;
    _phaseIndex = 0;
    _phaseMode = GhostMode.scatter;
    _phaseTimer = _phases[0].$2;
    _ghostEatChain = 200;
    _fruitSpawned.clear();
    _fruit = null;
    _resetPositions();
    _state = GameState.ready;
    _readyTimer = 0;
  }

  // ---- 输入 ----
  // 虚拟摇杆：拖动即输出 4 向。松开(d=null)时保持当前方向不清除，使吃豆人持续移动。
  void _onJoystick(Dir? d) {
    if (_state != GameState.playing || d == null) return;
    _pac.pending = d;
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || _state != GameState.playing) return;
    Dir? d;
    if (e.logicalKey == LogicalKeyboardKey.arrowUp ||
        e.logicalKey == LogicalKeyboardKey.keyW) {
      d = Dir.up;
    } else if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
        e.logicalKey == LogicalKeyboardKey.keyS) {
      d = Dir.down;
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft ||
        e.logicalKey == LogicalKeyboardKey.keyA) {
      d = Dir.left;
    } else if (e.logicalKey == LogicalKeyboardKey.arrowRight ||
        e.logicalKey == LogicalKeyboardKey.keyD) {
      d = Dir.right;
    }
    if (d != null) _pac.pending = d;
  }

  /// 全局静音被改（本页按钮或主页）时刷新图标。
  void _onMuteChanged() {
    if (!mounted) return;
    setState(() {});
  }

  PacManView get _view => PacManView(
        grid: _map.grid,
        pac: _pac,
        ghosts: _ghosts,
        mouthPhase: _mouthPhase,
        dying: _state == GameState.dying
            ? (_deathTimer / 1.0).clamp(0.0, 1.0)
            : 0,
        energizerPulse: _energizerPulse,
        frightenedFlash: _frightenedTimer > 0 &&
            _frightenedTimer < 2 &&
            (_elapsed * 5).floor().isOdd,
      );

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, cons) {
                      final cell = min(
                        cons.maxWidth / PacManMap.cols,
                        cons.maxHeight / PacManMap.rows,
                      );
                      final w = cell * PacManMap.cols;
                      final h = cell * PacManMap.rows;
                      return Center(
                        child: Stack(
                          children: [
                            SizedBox(
                              width: w,
                              height: h,
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: PacManPainter(view),
                                    size: Size(w, h),
                                  ),
                                  _Joystick(onDir: _onJoystick),
                                ],
                              ),
                            ),
                            if (_fruit != null)
                              Positioned(
                                left: _fruit!.x * cell + cell / 2 - cell * 0.22,
                                top: _fruit!.y * cell + cell / 2 - cell * 0.22,
                                child: _FruitIcon(size: cell * 0.44),
                              ),
                            _overlay(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _bottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            _scoreText('分数', _score),
            const Spacer(),
            _scoreText('最高', _high),
            const Spacer(),
            IconButton(
              icon: Icon(
                kMuted.value ? Icons.volume_off : Icons.volume_up,
                color: Colors.white70,
              ),
              onPressed: () => setState(() => kMuted.value = !kMuted.value),
            ),
          ],
        ),
      );

  Widget _scoreText(String label, int v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.yellow, fontSize: 12)),
          Text('$v',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
        ],
      );

  Widget _bottomBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: List.generate(
                    _lives,
                    (i) => const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child:
                          Icon(Icons.circle, color: Color(0xFFFFE100), size: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('第 $_level 关',
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ),
            const Spacer(),
          ],
        ),
      );

  Widget _overlay() {
    if (_state == GameState.playing) return const SizedBox.shrink();
    String title;
    String sub;
    bool showReplay = false;
    switch (_state) {
      case GameState.ready:
        title = 'READY!';
        sub = '方向键 / 滑动控制';
        break;
      case GameState.levelClear:
        title = '过关！';
        sub = '第 $_level 关达成';
        break;
      case GameState.gameOver:
        title = 'GAME OVER';
        sub = '得分 $_score';
        showReplay = true;
        break;
      case GameState.dying:
        return const SizedBox.shrink();
      case GameState.playing:
        return const SizedBox.shrink();
    }
    return IgnorePointer(
      // 无按钮时（READY/过关）不拦截手势，确保下方地图仍可接收滑动/方向键
      ignoring: !showReplay,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 40,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(sub, style: const TextStyle(color: Colors.white70)),
              if (showReplay)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ElevatedButton(
                    onPressed: () {
                      _initGame();
                      setState(() {});
                    },
                    child: const Text('点击重玩'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 动态虚拟摇杆：在游戏区域内按下即出现，拖动控制 4 向，松开消失。
/// 适配吃豆人：游戏中生效；松开（onDir=null）保持当前移动方向不清除。
class _Joystick extends StatefulWidget {
  final ValueChanged<Dir?> onDir;
  const _Joystick({required this.onDir});
  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  static const double _base = 66;
  static const double _dead = 14;
  Offset? _origin;
  Offset? _knob;

  void _update(Offset o, {required bool isNew}) {
    final origin = isNew ? o : (_origin ?? o);
    final dx = o.dx - origin.dx;
    final dy = o.dy - origin.dy;
    final len2 = dx * dx + dy * dy;
    Dir? dir;
    Offset knob = origin;
    if (len2 >= _dead * _dead) {
      final len = sqrt(len2);
      final cl = len > _base ? _base / len : 1.0;
      knob = Offset(origin.dx + dx * cl, origin.dy + dy * cl);
      if (dx.abs() > dy.abs()) {
        dir = dx > 0 ? Dir.right : Dir.left;
      } else {
        dir = dy > 0 ? Dir.down : Dir.up;
      }
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
  Widget build(BuildContext context) => GestureDetector(
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

class _JoystickPainter extends CustomPainter {
  final Offset? origin;
  final Offset? knob;
  _JoystickPainter(this.origin, this.knob);
  @override
  void paint(Canvas canvas, Size size) {
    if (origin == null) return;
    canvas.drawCircle(origin!, 66, Paint()..color = const Color(0x22FFFFFF));
    canvas.drawCircle(
      origin!,
      66,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(knob ?? origin!, 26, Paint()..color = const Color(0xCCFFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _FruitIcon extends StatelessWidget {
  final double size;
  const _FruitIcon({required this.size});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(size * 0.4),
        ),
        child: Center(
          child: Container(
            width: size * 0.4,
            height: size * 0.4,
            decoration: const BoxDecoration(
              color: Colors.lightGreen,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}
