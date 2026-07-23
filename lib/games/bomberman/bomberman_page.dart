// 泡泡堂 —— 经典炸弹人。网格步进移动,放炸弹十字爆炸,炸砖块/敌人,掉道具。
// 人 vs AI(多敌人,游走+追击+避炸弹),生命制,过关递增。纯单机;最高分本地保存。
// 实时引擎用 Ticker + CustomPainter(与坦克同款高效画法),复用坦克的 SoundService。

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../debug/game_debug_registry.dart';
import '../../shared/best_score_store.dart';
import '../../shared/bgm_synth.dart';
import '../../shared/game_shell.dart';
import '../../shared/net/p2p_link.dart';
import '../../shared/swipe_detector.dart';
import '../tank/net/wire.dart'; // NetRole(与坦克联机共用)
import '../tank/sound.dart';
import 'net/bomber_wire.dart';

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
  int id = 0; // 0 = P1 / 1 = P2
  int homeCol = 1, homeRow = 1; // 复活点
  int score = 0; // 联机计分(炸砖块)
  _Player({int col = 1, int row = 1, this.invuln = 0})
      : lives = 3,
        maxBombs = 1,
        flameRange = 2,
        activeBombs = 0,
        speed = _kPlayerSpeed,
        super(col, row);
}

enum _EnemyType { wanderer, chaser }

class _Enemy extends _Mover {
  final double speed;
  final Color color;
  final _EnemyType type;
  bool alive = true;
  _Enemy(super.col, super.row, this.color, this.speed,
      [this.type = _EnemyType.wanderer]);
}

class _Bomb {
  final int col, row, range, owner;
  double fuse;
  _Bomb(this.col, this.row, this.range, this.fuse, {this.owner = 0});
}

class _PowerUp {
  final int col, row;
  final _Power kind;
  _PowerUp(this.col, this.row, this.kind);
}

// 视觉特效(死亡弹开/得分飘字)
class _Vfx {
  double cx, cy; // 连续格坐标
  double timer; // 剩余秒
  final int? score; // 飘字用(非空=文字,+N)
  _Vfx(this.cx, this.cy, this.timer, {this.score});
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
  final NetRole role;
  final P2pLink? link;
  final bool autoStart;
  final bool coop; // 双人闯关(同屏):P1 下方 / P2 上方,均本地控制
  const BomberPage(
      {super.key,
      this.role = NetRole.offline,
      this.link,
      this.autoStart = true,
      this.coop = false});
  @override
  State<BomberPage> createState() => _BomberPageState();
}

class _BomberPageState extends State<BomberPage>
    with SingleTickerProviderStateMixin, GameDebugMixin<BomberPage> {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _lastElapsed = Duration.zero;

  late List<List<int>> _grid; // 0 空 / 1 砖 / 2 钢(含边界与柱)
  final _Player _player = _Player();
  final List<_Enemy> _enemies = [];
  final Map<int, _Bomb> _bombs = {}; // key = row*cols+col
  final Map<int, double> _flame = {}; // key -> 剩余秒
  final List<_PowerUp> _powers = [];
  final List<_Vfx> _vfx = [];
  double _shakeTimer = 0; // 震屏剩余秒(爆炸近距离时触发)

  int _level = 1;
  int _score = 0, _best = 0;
  bool _started = false, _paused = false, _over = false, _cleared = false;

  // ---- 联机(双人蓝牙) ----
  _Player? _player2; // 对手(主机:本地模拟;客机:快照渲染)
  final List<SwipeDir> _held2 = []; // 主机控制 _player2 的方向栈
  int _gridSeq = 0;
  int _lastGridSeq = -1;
  int _netWinner = 0; // 0 无 / 1 P1 / 2 P2
  bool _netEnded = false;
  bool _disconnected = false;
  BomberSnapshot? _pending; // 客机待应用快照
  SwipeDir? _remoteDir; // 客机本地方向(上行)
  bool _remoteBombQueued = false; // 客机待上行放雷边沿
  double _netSendAcc = 0;
  StreamSubscription<Uint8List>? _linkSub;
  bool get _isNet => widget.link != null;
  bool get _isCoop => widget.coop;
  bool get _isHost => widget.role == NetRole.host;
  bool get _isGuest => widget.role == NetRole.guest;
  int get _localId => _isHost ? 0 : 1;

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
      _started &&
      !_paused &&
      !_over &&
      !_cleared &&
      (_isCoop
          ? (_player.alive || (_player2?.alive ?? false))
          : _player.alive);

  @override
  void initState() {
    super.initState();
    _best = BestScoreStore.get(_bestKey);
    _ticker = Ticker(_onTick);
    _buildArena(_level);
    _snd.init(); // 异步预加载,失败忽略
    _bgm = ChiptuneBgm(theme: BgmTheme.bounce);
    _bgm.init();
    if (_isCoop) {
      // 双人闯关锁定竖屏
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (_isNet) _setupNet();
    if (widget.autoStart) _start();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    _focus.dispose();
    _snd.dispose();
    _bgm.dispose();
    widget.link?.close();
    if (_isCoop) SystemChrome.setPreferredOrientations([]);
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
    final dt =
        ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;
    // 联机收发:即使非 playing 也要跑(驱动客机结算 / 断线检测)
    if (_isNet) {
      if (_isHost) {
        if (!_disconnected) {
          _netSendAcc += dt;
          if (_netSendAcc >= 1 / 30) {
            _netSendAcc = 0;
            _sendSnapshot();
          }
        }
      } else {
        _drainSnapshot();
        if (_playing) _sendInput();
      }
    }
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
    if (_isNet) {
      // 联机:双方出生点周围留安全区(主机=左上,客机=右下;按本地视角对齐)
      final myC = _isHost ? 1 : _cols - 2;
      final myR = _isHost ? 1 : _rows - 2;
      final foeC = _isHost ? _cols - 2 : 1;
      final foeR = _isHost ? _rows - 2 : 1;
      for (int r = 1; r < _rows - 1; r++) {
        for (int c = 1; c < _cols - 1; c++) {
          if (_grid[r][c] != 0) continue;
          if ((c - myC).abs() + (r - myR).abs() <= 2) continue;
          if ((c - foeC).abs() + (r - foeR).abs() <= 2) continue;
          if (_rng.nextDouble() < 0.74) _grid[r][c] = 1;
        }
      }
      _player
        ..col = myC
        ..row = myR
        ..dir = null
        ..t = 0
        ..id = _localId
        ..invuln = _kInvuln
        ..activeBombs = 0
        ..alive = true
        ..lives = 3
        ..maxBombs = 1
        ..flameRange = 2
        ..speed = _kPlayerSpeed
        ..score = 0
        ..homeCol = myC
        ..homeRow = myR;
      _player2 = _Player(col: foeC, row: foeR, invuln: _kInvuln)
        ..alive = true
        ..id = 1 - _localId
        ..lives = 3
        ..maxBombs = 1
        ..flameRange = 2
        ..speed = _kPlayerSpeed
        ..score = 0
        ..homeCol = foeC
        ..homeRow = foeR;
      _enemies.clear();
      _gridSeq++;
      _lastGridSeq = -1;
      _netWinner = 0;
      _netEnded = false;
      _bombs.clear();
      _flame.clear();
      _powers.clear();
      _vfx.clear();
      _shakeTimer = 0;
      _held.clear();
      _held2.clear();
      return;
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
      ..id = 0
      ..invuln = _kInvuln
      ..activeBombs = 0
      ..alive = true
      ..homeCol = 1
      ..homeRow = 1
      ..score = 0;
    if (_isCoop) {
      // 双人闯关:第二个玩家出生在右上角(1,11),与 P1 分隔
      _player2 = _Player(col: _cols - 2, row: 1, invuln: _kInvuln)
        ..alive = true
        ..id = 1
        ..lives = 3
        ..maxBombs = 1
        ..flameRange = 2
        ..speed = _kPlayerSpeed
        ..score = 0
        ..homeCol = _cols - 2
        ..homeRow = 1;
      _held2.clear();
    } else {
      _player2 = null;
    }
    // 敌人:远角生成,数量随关卡
    _enemies.clear();
    _bombs.clear();
    _flame.clear();
    _powers.clear();
    _vfx.clear();
    _shakeTimer = 0;
    final corners = <(int, int)>[
      (_cols - 2, _rows - 2),
      (_cols - 2, 1),
      (1, _rows - 2),
    ];
    final count = min(2 + level, 6);
    for (int i = 0; i < count; i++) {
      final (cc, rr) = corners[i % corners.length];
      _grid[rr][cc] = 0;
      _spawnClearNeighbor(cc, rr);
      final speed = min(3.3, 2.35 + level * 0.12);
      // 第3关开始出现追击型,关卡越高追击比例越大
      final type = (level >= 3 && i < level - 1)
          ? _EnemyType.chaser
          : _EnemyType.wanderer;
      final color = type == _EnemyType.chaser
          ? const Color(0xFFFF1744) // 鲜红色=追击
          : _enemyColors[i % _enemyColors.length];
      final e = _Enemy(cc, rr, color, speed, type);
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
    _netEnded = false;
    _netWinner = 0;
    _disconnected = false;
    _pending = null;
    _player.invuln = _kInvuln;
    _lastElapsed = Duration.zero;
    _snd.play('start');
    _syncTicker();
    if (widget.autoStart && !_isGuest) _bgm.start();
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
    if (_isNet) {
      _start(); // 联机:直接重开本局
      return;
    }
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

  // ---- 调试面板(GameDebug) ----
  @override
  String get id => 'bomber';

  @override
  int? get currentLevel => _level;

  @override
  int? get maxLevel => null; // 无尽

  @override
  Map<String, String> info() => {
        '关卡': '$_level',
        '得分': '$_score',
        '最高': '$_best',
        '炸弹': '${_player.maxBombs}',
        '火力': '${_player.flameRange}',
        '生命': '${_player.lives}',
        '状态': _over
            ? '结束'
            : _cleared
                ? '过关'
                : _paused
                    ? '暂停'
                    : _started
                        ? '进行中'
                        : '未开始',
      };

  @override
  void jumpToLevel(int n) {
    _level = n < 1 ? 1 : n;
    _score = 0;
    _player
      ..lives = 3
      ..maxBombs = 1
      ..flameRange = 2
      ..speed = _kPlayerSpeed
      ..alive = true;
    _started = true;
    _paused = false;
    _over = false;
    _cleared = false;
    _buildArena(_level);
    _player.invuln = _kInvuln;
    _lastElapsed = Duration.zero;
    _syncTicker();
    _bgm.start();
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
    if (_isGuest) {
      // 客机:本地输入只上行,不直接模拟
      _remoteDir = d;
      return;
    }
    if (!_started && !_over) _start();
    if (_over || _cleared) return;
    _held.remove(d);
    _held.add(d);
    _applyInput(d);
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
      return;
    }
    // 垂直转向:沿当前方向行进途中允许即刻拐弯,自动对准新方向的车道
    if (_opp(d) != _player.dir && d != _player.dir) {
      final (cx, cy) = _cellPos(_player);
      final (ndx, ndy) = _delta(d);
      int nc, nr;
      double nt;
      if (ndx != 0) {
        // 水平方向:横向对齐车道,纵向取四舍五入
        nr = cy.round();
        if (ndx > 0) {
          nc = cx.floor();
          nt = cx - nc;
        } else {
          nc = cx.ceil();
          nt = nc - cx;
        }
      } else {
        // 垂直方向:纵向对齐车道,横向取四舍五入
        nc = cx.round();
        if (ndy > 0) {
          nr = cy.floor();
          nt = cy - nr;
        } else {
          nr = cy.ceil();
          nt = nr - cy;
        }
      }
      if (nc < 0 || nc >= _cols || nr < 0 || nr >= _rows) return;
      if (_cellSolid(nc, nr)) return;
      _player.col = nc;
      _player.row = nr;
      _player.dir = d;
      _player.t = nt.clamp(0.0, 1.0);
    }
    // 同向忽略,onArrive 时取 _held.last 决定继续或停
  }

  bool _cellSolidNeighbor(int c, int r, SwipeDir d) {
    final (dx, dy) = _delta(d);
    return _cellSolid(c + dx, r + dy);
  }

  void _placeBomb() {
    if (_isGuest) {
      _remoteBombQueued = true;
      return;
    }
    if (!_playing) {
      if (!_started && !_over) _start();
      return;
    }
    _placeBombFor(_player);
  }

  void _placeBombFor(_Player p) {
    if (!p.alive) return;
    if (p.activeBombs >= p.maxBombs) return;
    final k = _key(p.col, p.row);
    if (_bombs.containsKey(k)) return;
    if (_grid[p.row][p.col] != 0) return;
    _bombs[k] = _Bomb(p.col, p.row, p.flameRange, _kFuse, owner: p.id);
    p.activeBombs++;
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
    if (_shakeTimer > 0) _shakeTimer = max(0, _shakeTimer - dt);
    // VFX 计时
    if (_vfx.isNotEmpty) {
      for (int i = _vfx.length - 1; i >= 0; i--) {
        _vfx[i].timer -= dt;
        if (_vfx[i].timer <= 0) _vfx.removeAt(i);
      }
    }

    // 移动
    if (_player.alive) _advance(_player, dt, _player.speed, _playerArrive);
    if (_player2 != null && (_isHost || _isCoop) && _player2!.alive) {
      _advance(_player2!, dt, _player2!.speed, _player2Arrive);
    }
    if (!_isNet) {
      for (final e in _enemies) {
        if (e.alive) _advance(e, dt, e.speed, () => _enemyArrive(e));
      }
      // 撞怪判负(无敌期除外):用连续格坐标算距离,同格或迎面穿过都算撞上
      _resolveEnemyContact();
    }

    // 火焰伤害(当前格或半程后的目标格)
    if (_flame.isNotEmpty) _resolveFlameHits();

    // 清死亡敌人(单机)
    if (_enemies.isNotEmpty && _enemies.any((e) => !e.alive)) {
      _enemies.removeWhere((e) => !e.alive);
      setState(() {});
    }

    // 道具拾取(双方)
    if (_player.alive) _pickupFor(_player);
    if (_player2 != null && _player2!.alive) _pickupFor(_player2!);

    // 胜负判定
    if (_isNet) {
      if (_player2 != null) {
        if (!_player.alive && !_player2!.alive) {
          _endNet(0); // 同归于尽
        } else if (!_player.alive) {
          _endNet(2); // P1(主机)亡 → P2 胜
        } else if (!_player2!.alive) {
          _endNet(1); // P2 亡 → P1 胜
        }
      }
    } else if (_enemies.isEmpty && !_over && !_cleared) {
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

  // 主机控制 _player2(远程对手)的输入处理
  void _applyInput2(SwipeDir d) {
    final p = _player2!;
    if (!_playing) return;
    if (p.dir != null && _opp(d) == p.dir) {
      final (dx, dy) = _delta(p.dir!);
      final nc = p.col + dx, nr = p.row + dy;
      if (!_cellSolid(nc, nr)) {
        p.col = nc;
        p.row = nr;
        p.dir = _opp(p.dir!);
        p.t = 1 - p.t;
        final nd = _player2Arrive();
        p.dir = nd;
        if (nd == null) p.t = 0;
      } else {
        p.dir = d;
      }
    } else {
      p.dir = d;
    }
  }

  SwipeDir? _player2Arrive() {
    if (_held2.isNotEmpty) {
      final d = _held2.last;
      if (!_cellSolidNeighbor(_player2!.col, _player2!.row, d)) return d;
    }
    return null;
  }

  // ---- 联机收发 ----
  void _setupNet() {
    final link = widget.link!;
    _linkSub = link.incoming.listen(
      _onNetReceive,
      onDone: () {
        if (!mounted) return;
        _bgm.stop();
        if (mounted) setState(() => _disconnected = true);
      },
    );
  }

  int _dirToIdx(SwipeDir? d) => d == null
      ? 255
      : const [SwipeDir.up, SwipeDir.down, SwipeDir.left, SwipeDir.right]
          .indexOf(d);
  SwipeDir? _idxToDir(int i) => i == 255
      ? null
      : const [SwipeDir.up, SwipeDir.down, SwipeDir.left, SwipeDir.right][i];

  _Player? _playerById(int id) =>
      _player.id == id ? _player : (_player2?.id == id ? _player2 : null);

  void _onNetReceive(Uint8List bytes) {
    if (bytes.isEmpty) return;
    if (bytes[0] == kBomberMsgSnapshot) {
      final s = BomberSnapshot.decode(bytes);
      if (s != null) _pending = s;
    } else if (bytes[0] == kBomberMsgInput) {
      final f = BomberInput.decode(bytes);
      if (f != null) _onInput(f);
    }
  }

  // 主机:应用客机方向帧
  void _onInput(BomberInput f) {
    if (_player2 == null || !_player2!.alive) return;
    if (f.dirIdx != 255) {
      final d = _idxToDir(f.dirIdx);
      if (d != null) {
        _held2.remove(d);
        _held2.add(d);
        _applyInput2(d);
      }
    } else {
      _held2.clear();
    }
    if (f.bomb) _placeBombFor(_player2!);
  }

  // 客机:上行本地输入
  void _sendInput() {
    if (_disconnected) return;
    final f = BomberInput(
      dirIdx: _remoteDir == null ? 255 : _dirToIdx(_remoteDir!),
      bomb: _remoteBombQueued,
    );
    _remoteBombQueued = false;
    widget.link!.send(f.encode());
  }

  void _drainSnapshot() {
    final s = _pending;
    if (s == null) return;
    _pending = null;
    _applySnapshot(s);
  }

  BomberPlayerSnap _toSnap(_Player p) => BomberPlayerSnap(
        col: p.col,
        row: p.row,
        t: p.t,
        dirIdx: _dirToIdx(p.dir),
        alive: p.alive,
        invuln: p.invuln,
        lives: p.lives,
        maxBombs: p.maxBombs,
        flameRange: p.flameRange,
        speed: p.speed,
        activeBombs: p.activeBombs,
        score: p.score,
      );

  void _sendSnapshot() {
    final players = [_toSnap(_player), _toSnap(_player2!)]; // [P1, P2]
    final bombs = _bombs.values
        .map((b) => BomberBombSnap(
            col: b.col, row: b.row, range: b.range, fuse: b.fuse, owner: b.owner))
        .toList();
    final flames = _flame.entries
        .map((e) => BomberFlameSnap(
            col: e.key % _cols, row: e.key ~/ _cols, rem: e.value))
        .toList();
    final powers = _powers
        .map((p) => BomberPowerSnap(col: p.col, row: p.row, kind: p.kind.index))
        .toList();
    final snap = BomberSnapshot(
      level: _level,
      over: _netEnded,
      winner: _netWinner,
      gridSeq: _gridSeq,
      grid: _grid,
      players: players,
      bombs: bombs,
      flames: flames,
      powers: powers,
    );
    widget.link!.send(snap.encode());
  }

  void _applySnapshot(BomberSnapshot s) {
    if (s.gridSeq != _lastGridSeq) {
      _grid.clear();
      for (final row in s.grid) {
        _grid.add(List<int>.from(row));
      }
      _lastGridSeq = s.gridSeq;
    }
    // 角色映射:players[0]=P1(远程), players[1]=P2(本地)
    _applyPlayerSnap(_player2!, s.players[0]);
    _applyPlayerSnap(_player, s.players[1]);
    _bombs.clear();
    for (final b in s.bombs) {
      _bombs[_key(b.col, b.row)] =
          _Bomb(b.col, b.row, b.range, b.fuse, owner: b.owner);
    }
    _flame.clear();
    for (final f in s.flames) {
      _flame[_key(f.col, f.row)] = f.rem;
    }
    _powers.clear();
    for (final p in s.powers) {
      _powers.add(_PowerUp(p.col, p.row, _Power.values[p.kind]));
    }
    _level = s.level;
    if (s.over) {
      _netEnded = true;
      _netWinner = s.winner;
      _over = true;
      _bgm.stop();
    }
    _repaint.value = (_repaint.value + 1) & 0x3fffffff;
  }

  void _applyPlayerSnap(_Player p, BomberPlayerSnap s) {
    p.col = s.col;
    p.row = s.row;
    p.t = s.t;
    p.dir = _idxToDir(s.dirIdx);
    p.alive = s.alive;
    p.invuln = s.invuln;
    p.lives = s.lives;
    p.maxBombs = s.maxBombs;
    p.flameRange = s.flameRange;
    p.speed = s.speed;
    p.activeBombs = s.activeBombs;
    p.score = s.score;
  }

  void _endNet(int winner) {
    _netWinner = winner;
    _netEnded = true;
    _over = true;
    _snd.play('gameover');
    _bgm.stop();
    setState(() {});
  }

  /// 敌人追击的目标玩家(双人闯关时选择最近的一个)。
  _Player? _chaseTarget(_Enemy e) {
    final p1 = _player.alive ? _player : null;
    final p2 = (_isCoop && _player2 != null && _player2!.alive) ? _player2! : null;
    if (p1 != null && p2 != null) {
      final d1 = (_player.col - e.col).abs() + (_player.row - e.row).abs();
      final d2 =
          (_player2!.col - e.col).abs() + (_player2!.row - e.row).abs();
      return d1 <= d2 ? _player : _player2!;
    }
    return p1 ?? p2;
  }

  int _manhTo(_Enemy e, SwipeDir d, _Player t) {
    final (dx, dy) = _delta(d);
    return (t.col - (e.col + dx)).abs() + (t.row - (e.row + dy)).abs();
  }

  SwipeDir? _enemyArrive(_Enemy e) {
    final valid = <SwipeDir>[];
    for (final d in _allDirs) {
      if (!_cellSolidNeighbor(e.col, e.row, d)) valid.add(d);
    }
    if (valid.isEmpty) return null;
    final target = _chaseTarget(e);
    // 追击型:始终选离目标玩家最近的有效方向
    if (e.type == _EnemyType.chaser && target != null) {
      valid.sort((a, b) =>
          _manhTo(e, a, target).compareTo(_manhTo(e, b, target)));
      return valid.first;
    }
    // 游走型:概率追击目标玩家,概率保持,否则随机
    if (target != null && _rng.nextDouble() < 0.42) {
      valid.sort((a, b) =>
          _manhTo(e, a, target).compareTo(_manhTo(e, b, target)));
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

  // ---- 爆炸(含连锁引爆) ----
  // 已处理过的炸弹 key,防止 A←B 互炸形成死循环。
  final Set<int> _chainDone = {};

  void _explode(_Bomb b) {
    _chainDone.clear();
    _explodeChain(b);
    _chainDone.clear();
    // 近距离爆炸震屏
    final dist = (_player.col - b.col).abs() + (_player.row - b.row).abs();
    if (dist <= 3) _shakeTimer = 0.18;
  }

  void _explodeChain(_Bomb b) {
    final bk = _key(b.col, b.row);
    if (_chainDone.contains(bk)) return;
    _chainDone.add(bk);
    final owner = _playerById(b.owner);
    if (owner != null) owner.activeBombs = max(0, owner.activeBombs - 1);
    _snd.play('explosion');
    if (_vfx.length < 24) {
      _vfx.add(_Vfx(b.col.toDouble() + 0.5, b.row.toDouble() + 0.5, 0.35));
    }
    final cells = <int>[];
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
          _gridSeq++;
          if (_isNet) {
            if (owner != null) owner.score += 5;
          } else {
            _score += 5;
          }
          if (_vfx.length < 24) {
            _vfx.add(_Vfx(c.toDouble() + 0.5, r.toDouble() + 0.5, 0.28));
          }
          if (_rng.nextDouble() < _kCrateDropChance) {
            _powers.add(_PowerUp(c, r, _Power.values[_rng.nextInt(3)]));
          }
          break;
        }
        // 链式:火焰碰到其他炸弹 → 立刻引爆(沿火焰方向继续,但新炸弹按自身范围扩)
        if (_bombs.containsKey(k) && !_chainDone.contains(k)) {
          final nb = _bombs.remove(k);
          if (nb != null) _explodeChain(nb);
        }
      }
    }
    for (final k in cells) {
      _flame[k] = _kFlameTime;
    }
    _updateBest();
    setState(() {});
  }

  /// 玩家与敌人的连续格坐标(含行进插值),用于碰撞判定。
  (double, double) _cellPos(_Mover m) {
    if (m.dir == null) return (m.col.toDouble(), m.row.toDouble());
    final (dx, dy) = _delta(m.dir!);
    return (m.col + dx * m.t, m.row + dy * m.t);
  }

  /// 玩家撞到敌人 → 受伤(无敌期除外)。同格或迎面穿过都会触发。
  void _resolveEnemyContact() {
    _checkContact(_player);
    if (_isCoop && _player2 != null) _checkContact(_player2!);
  }

  void _checkContact(_Player p) {
    if (!p.alive || p.invuln > 0) return;
    final (px, py) = _cellPos(p);
    for (final e in _enemies) {
      if (!e.alive) continue;
      final (ex, ey) = _cellPos(e);
      final d2 = (px - ex) * (px - ex) + (py - ey) * (py - ey);
      if (d2 < 0.6 * 0.6) {
        _hurtPlayer(p);
        return;
      }
    }
  }

  bool _flameHit(_Mover m) {
    if (_flame.containsKey(_key(m.col, m.row))) return true;
    if (m.dir != null && m.t > 0.5) {
      final (dx, dy) = _delta(m.dir!);
      if (_flame.containsKey(_key(m.col + dx, m.row + dy))) return true;
    }
    return false;
  }

  void _resolveFlameHits() {
    final hitLocal = _player.alive && _player.invuln <= 0 && _flameHit(_player);
    final hitRemote =
        _player2 != null && _player2!.alive && _player2!.invuln <= 0 && _flameHit(_player2!);
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
        // 死亡动效 + 得分飘字
        if (_vfx.length < 20) {
          _vfx.add(_Vfx(
              e.col.toDouble() + 0.5, e.row.toDouble() + 0.5, 0.40,
              score: 100));
        }
      }
    }
    if (hitLocal) _hurtPlayer(_player);
    if (hitRemote) _hurtPlayer(_player2!);
    if (hitLocal || hitRemote || _score >= 0) _updateBest();
  }

  void _hurtPlayer(_Player p) {
    p.lives--;
    _snd.play('hit');
    HapticFeedback.heavyImpact();
    if (p.lives <= 0) {
      p.alive = false;
      p.dir = null;
      p.t = 0;
      if (_isCoop) {
        // 双人闯关:双方都阵亡才算失败
        if (!_player.alive && !_player2!.alive) {
          _over = true;
          _snd.play('gameover');
          _ticker.stop();
          _bgm.stop();
        }
      } else if (!_isNet) {
        _over = true;
        _snd.play('gameover');
        _ticker.stop();
        _bgm.stop();
      }
      setState(() {});
      return;
    }
    // 复活到出生格(若被占则就近)
    int rc = p.homeCol, rr = p.homeRow;
    if (_cellSolid(rc, rr) || _flame.containsKey(_key(rc, rr))) {
      outer:
      for (int rad = 1; rad < 4; rad++) {
        for (int r = 1; r <= rad; r++) {
          for (int c = 1; c <= rad; c++) {
            if (c == rc && r == rr) continue;
            if (!_cellSolid(c, r) && !_flame.containsKey(_key(c, r))) {
              rc = c;
              rr = r;
              break outer;
            }
          }
        }
      }
    }
    p
      ..col = rc
      ..row = rr
      ..dir = null
      ..t = 0
      ..invuln = _kInvuln
      // 死亡复活:加成恢复初始,避免越死越强、跨命累加
      ..maxBombs = 1
      ..flameRange = 2
      ..speed = _kPlayerSpeed
      ..activeBombs = 0;
    if (p == _player) {
      _held.clear();
    } else {
      _held2.clear();
    }
    setState(() {});
  }

  void _pickupFor(_Player p) {
    if (!p.alive) return;
    final ps = _powers;
    for (int i = ps.length - 1; i >= 0; i--) {
      if (ps[i].col == p.col && ps[i].row == p.row) {
        _collect(p, ps[i]);
        ps.removeAt(i);
      }
    }
  }

  void _collect(_Player p, _PowerUp pw) {
    _snd.play('powerup');
    HapticFeedback.mediumImpact();
    setState(() {
      switch (pw.kind) {
        case _Power.bomb:
          p.maxBombs = min(6, p.maxBombs + 1);
          break;
        case _Power.flame:
          p.flameRange = min(8, p.flameRange + 1);
          break;
        case _Power.speed:
          p.speed = min(5.6, p.speed + 0.5);
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
    if (_isNet) return;
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
      title: _isCoop ? '泡泡堂 · 双人闯关' : '泡泡堂',
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
            final reserveTop = _isCoop ? (ctrl * 3 + 16) : 46.0; // 双人:上方 P2 操作区
            final reserveBottom = ctrl * 3 + 26; // 方向键 + 间距
            final cell =
                min(maxW / _cols, (maxH - reserveTop - reserveBottom) / _rows)
                    .clamp(18.0, 38.0);
            final boardW = cell * _cols;
            final boardH = cell * _rows;
            final board = _buildBoard(boardW, boardH, cell);
            if (_isCoop) {
              // 双人闯关(竖屏):P2 操作区在上方,P1 在下方,游戏区居中
              return Column(
                children: [
                  _controls(ctrl,
                      onDir: _onJoystickDir2, onBomb: _placeBomb2, p2: true),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _hud(),
                          const SizedBox(height: 6),
                          board,
                        ],
                      ),
                    ),
                  ),
                  _controls(ctrl),
                ],
              );
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _hud(),
                  const SizedBox(height: 6),
                  board,
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

  Widget _buildBoard(double boardW, double boardH, double cell) {
    return Transform.translate(
      offset: _shakeTimer > 0
          ? Offset((_rng.nextDouble() - 0.5) * cell * 0.28,
              (_rng.nextDouble() - 0.5) * cell * 0.28)
          : Offset.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          width: boardW,
          height: boardH,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(boardW, boardH),
                painter: _BomberPainter(
                  grid: _grid,
                  player: _player,
                  player2: _player2,
                  enemies: _enemies,
                  bombs: _bombs,
                  flame: _flame,
                  powers: _powers,
                  vfx: _vfx,
                  cell: cell,
                  repaint: _repaint,
                ),
              ),
              if (!_started || _over || _paused || _cleared) _overlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hud() {
    if (_isCoop) {
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
            _chip('P1❤', '${_player.lives}', const Color(0xFF42A5F5)),
            if (_player2 != null)
              _chip('P2❤', '${_player2!.lives}', const Color(0xFFFF5252)),
            _chip('💣', '${_player.maxBombs}', const Color(0xFFB0BEC5)),
            _chip('🔥', '${_player.flameRange}', const Color(0xFFFF7043)),
          ],
        ),
      );
    }
    if (_isNet) {
      final you = _player; // 本地
      final foe = _player2 ?? _player;
      final youName = _isHost ? 'P1' : 'P2';
      final foeName = _isHost ? 'P2' : 'P1';
      return SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            _chip('蓝牙',
                _disconnected ? '断开' : '已连',
                _disconnected
                    ? const Color(0xFFEF5350)
                    : const Color(0xFF66BB6A)),
            _chip('你($youName)',
                '${you.lives}❤ ${you.maxBombs}💣 ${you.flameRange}🔥',
                const Color(0xFF42A5F5)),
            _chip('对手($foeName)', '${foe.lives}❤',
                const Color(0xFFFF5252)),
          ],
        ),
      );
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ',
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: color.withValues(alpha: 0.6), blurRadius: 4)
                  ])),
        ],
      ),
    );
  }

  Widget _overlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xE6000000), Color(0xF2000000)],
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_disconnected) ...[
              const Text('对手已断开',
                  style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Color(0xFFFF5252), blurRadius: 18)])),
              const SizedBox(height: 8),
              const Text('蓝牙连接已丢失',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              _ovBtn('返回', const Color(0xFFFF8A4C),
                  () => Navigator.of(context).maybePop()),
            ] else if (_netEnded) ...[
              Text(_netWinText(),
                  style: TextStyle(
                      color: _netWinner == _localId + 1
                          ? const Color(0xFFFFD54A)
                          : const Color(0xFFFF5252),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                            color: _netWinner == _localId + 1
                                ? const Color(0xFFFFD54A)
                                : const Color(0xFFFF5252),
                            blurRadius: 18)
                      ])),
              const SizedBox(height: 8),
              Text(_netWinSub(),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              _ovBtn('再来一局', const Color(0xFFFFD54A), _start),
            ] else if (_cleared) ...[
              Text('🎉 第 $_level 关 通过!',
                  style: const TextStyle(
                      color: Color(0xFFFFD54A),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Color(0xFFFFD54A), blurRadius: 18)
                      ])),
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
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Color(0xFFFF5252), blurRadius: 18)
                      ])),
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
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Color(0xFFFF8A4C), blurRadius: 18)
                      ])),
              const SizedBox(height: 14),
              _ovBtn('继续游戏', const Color(0xFFFF8A4C), _togglePause),
            ] else if (_isCoop) ...[
              const Text('泡泡堂 · 双人闯关',
                  style: TextStyle(
                      color: Color(0xFFFF8A4C),
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Color(0xFFFF8A4C), blurRadius: 20)
                      ])),
              const SizedBox(height: 10),
              const Text(
                  'P1 操作区在下方 · P2 操作区在上方\n方向键移动 · 炸弹键放雷\n一起炸掉所有敌人即可过关',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              _ovBtn('开始游戏', const Color(0xFFFF8A4C), _start),
            ] else ...[
              const Text('泡泡堂',
                  style: TextStyle(
                      color: Color(0xFFFF8A4C),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Color(0xFFFF8A4C), blurRadius: 20)
                      ])),
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

  String _netWinText() {
    if (_netWinner == _localId + 1) return '🏆 你赢了!';
    if (_netWinner == 0) return '平局';
    return '你输了';
  }

  String _netWinSub() {
    if (_netWinner == 0) return '同归于尽';
    final you = _localId + 1; // 1=P1, 2=P2
    final foe = 3 - you;
    return '你(P$you) 击败 对手(P$foe)';
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

  Widget _controls(double btn,
      {ValueChanged<SwipeDir?>? onDir,
      VoidCallback? onBomb,
      bool p2 = false}) {
    final d = onDir ?? _onJoystickDir;
    final b = onBomb ?? _placeBomb;
    final accent = p2 ? const Color(0xFFFF5252) : const Color(0xFFFF7043);
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 虚拟摇杆(仿坦克,拖动控制四向)
          SizedBox(
            width: btn * 3,
            height: btn * 3,
            child: _Joystick(onDir: d),
          ),
          // 炸弹键
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: b,
            child: Container(
              width: btn * 1.5,
              height: btn * 1.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  radius: 0.9,
                  colors: [Color(0xFF3A2A26), Color(0xFF171717)],
                ),
                border: Border.all(color: accent, width: 2.5),
                boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 3)),
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💣', style: TextStyle(fontSize: 30)),
                  Text(p2 ? 'P2' : '放雷',
                      style: TextStyle(
                          color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onJoystickDir(SwipeDir? d) {
    if (_isGuest) {
      _remoteDir = d;
      return;
    }
    if (d != null) {
      _held.clear();
      _held.add(d);
      _applyInput(d);
    } else {
      _held.clear();
    }
  }

  void _onJoystickDir2(SwipeDir? d) {
    if (d != null) {
      if (!_started && !_over) _start();
      if (_over || _cleared) return;
      _held2.clear();
      _held2.add(d);
      _applyInput2(d);
    } else {
      _held2.clear();
    }
  }

  void _placeBomb2() {
    if (!_started && !_over) _start();
    if (!_playing || _over || _cleared) return;
    if (_player2 != null) _placeBombFor(_player2!);
  }
}

/// 泡泡堂绘制:地面/钢墙/砖块/道具/炸弹/火焰/敌人/玩家。霓虹抛光风。
class _BomberPainter extends CustomPainter {
  final List<List<int>> grid;
  final _Player player;
  final _Player? player2; // 联机对手(本地视角已在 _player)
  final List<_Enemy> enemies;
  final Map<int, _Bomb> bombs;
  final Map<int, double> flame;
  final List<_PowerUp> powers;
  final List<_Vfx> vfx;
  final double cell;
  final ValueNotifier<int> _tick; // 帧计数,驱动道具脉冲等动画

  _BomberPainter({
    required this.grid,
    required this.player,
    this.player2,
    required this.enemies,
    required this.bombs,
    required this.flame,
    required this.powers,
    required this.cell,
    this.vfx = const [],
    required ValueNotifier<int> repaint,
  })  : _tick = repaint,
        super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 地面双色棋盘
    final floorA = Paint()..color = const Color(0xFF2E7D32);
    final floorB = Paint()..color = const Color(0xFF256B29);
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cell, r * cell, cell, cell),
          (r + c) % 2 == 0 ? floorA : floorB,
        );
      }
    }
    // 地面格线
    final gridLine = Paint()
      ..color = const Color(0x15000000)
      ..strokeWidth = 1;
    for (int r = 0; r <= _rows; r++) {
      canvas.drawLine(Offset(0, r * cell), Offset(w, r * cell), gridLine);
    }
    for (int c = 0; c <= _cols; c++) {
      canvas.drawLine(Offset(c * cell, 0), Offset(c * cell, h), gridLine);
    }
    // 钢墙 / 砖块
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        final v = grid[r][c];
        if (v == 2) {
          _drawSteel(canvas, c * cell, r * cell, cell);
        } else if (v == 1) {
          _drawCrate(canvas, c * cell, r * cell, cell);
        }
      }
    }
    // 道具(脉冲发光)
    final phase = (_tick.value % 60) / 60.0;
    for (final p in powers) {
      _drawPower(canvas, p, phase);
    }
    // 敌人
    for (final e in enemies) {
      if (!e.alive) continue;
      _drawBlob(canvas, e.posOf(cell), cell, e.color, false, e.dir,
          shadow: true, angry: e.type == _EnemyType.chaser);
    }
    // 对手(联机):先画在底层
    if (player2 != null && player2!.alive) {
      final blink =
          player2!.invuln > 0 && (player2!.invuln * 10).floor() % 2 == 0;
      if (!blink) {
        _drawBlob(canvas, player2!.posOf(cell), cell, const Color(0xFFFF5252),
            true, player2!.dir,
            shadow: true);
      }
    }
    // 玩家
    if (player.alive) {
      final blink = player.invuln > 0 && (player.invuln * 10).floor() % 2 == 0;
      if (!blink) {
        _drawBlob(canvas, player.posOf(cell), cell, const Color(0xFF42A5F5),
            true, player.dir,
            shadow: true);
      }
    }
    // 炸弹(画在玩家上面,确保脚下的雷清晰可见)
    for (final b in bombs.values) {
      _drawBomb(canvas, b);
    }
    // 火焰
    flame.forEach((k, v) {
      final r = k ~/ _cols, c = k % _cols;
      _drawFlame(canvas, c * cell, r * cell, cell, v);
    });
    // VFX:死亡弹开 / 得分飘字
    for (final v in vfx) {
      final a = (v.timer / 0.40).clamp(0.0, 1.0);
      if (v.score != null) {
        final tp = TextPainter(
          text: TextSpan(
              text: '+${v.score}',
              style: TextStyle(
                  color: const Color(0xFFFFD54A).withValues(alpha: a),
                  fontSize: cell * 0.55,
                  fontWeight: FontWeight.bold)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout();
        final rise = (1 - a) * cell * 0.5;
        tp.paint(canvas,
            Offset(v.cx * cell - tp.width / 2, v.cy * cell - rise - tp.height));
      } else {
        final r = cell * 0.10 + (1 - a) * cell * 0.30;
        canvas.drawCircle(Offset(v.cx * cell, v.cy * cell), r,
            Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: a * 0.7));
      }
    }
    // 暗角(增加纵深感)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x55000000),
          ],
          stops: const [0.0, 0.65, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  // ---- 钢墙:金属斜面 + 铆钉 ----
  void _drawSteel(Canvas canvas, double x, double y, double s) {
    final outer = Rect.fromLTWH(x + 1, y + 1, s - 2, s - 2);
    const rad = Radius.circular(2);
    canvas.drawRRect(RRect.fromRectAndRadius(outer, rad),
        Paint()..color = const Color(0xFF5B6770));
    final inner = outer.deflate(s * 0.10);
    canvas.drawRRect(RRect.fromRectAndRadius(inner, rad),
        Paint()..color = const Color(0xFF9AA7B6));
    // 左上高光弧
    canvas.drawArc(
        inner,
        pi * 1.12,
        pi * 0.6,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.32)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.07);
    // 右下暗边
    canvas.drawArc(
        inner,
        pi * 0.12,
        pi * 0.5,
        false,
        Paint()
          ..color = const Color(0xFF3A434C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.07);
    // 四角铆钉
    final rp = s * 0.05;
    final pad = s * 0.20;
    final rivet = Paint()..color = const Color(0xFF3C4450);
    for (final (rx, ry) in [
      (inner.left + pad, inner.top + pad),
      (inner.right - pad, inner.top + pad),
      (inner.left + pad, inner.bottom - pad),
      (inner.right - pad, inner.bottom - pad),
    ]) {
      canvas.drawCircle(Offset(rx, ry), rp, rivet);
    }
  }

  // ---- 砖块:木箱纹 + 斜面 ----
  void _drawCrate(Canvas canvas, double x, double y, double s) {
    final outer = Rect.fromLTWH(x + 1, y + 1, s - 2, s - 2);
    final rad = Radius.circular(s * 0.14);
    canvas.drawRRect(RRect.fromRectAndRadius(outer, rad),
        Paint()..color = const Color(0xFF5E3A1A));
    final inner = outer.deflate(s * 0.09);
    canvas.drawRRect(RRect.fromRectAndRadius(inner, rad),
        Paint()..color = const Color(0xFFCC8B45));
    // 木板中缝
    final mid = inner.top + inner.height / 2;
    canvas.drawLine(
        Offset(inner.left, mid),
        Offset(inner.right, mid),
        Paint()
          ..color = const Color(0xFF7A4E20)
          ..strokeWidth = 1.2);
    // 左上高光
    canvas.drawArc(
        inner,
        pi * 1.12,
        pi * 0.6,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.06);
  }

  void _drawPower(Canvas canvas, _PowerUp p, double phase) {
    final cx = p.col * cell + cell / 2, cy = p.row * cell + cell / 2;
    final pulse = 0.5 + 0.5 * sin(phase * 2 * pi);
    final color = switch (p.kind) {
      _Power.bomb => const Color(0xFFFFCA28),
      _Power.flame => const Color(0xFFFF7043),
      _Power.speed => const Color(0xFF42A5F5),
    };
    // 发光晕
    canvas.drawCircle(
      Offset(cx, cy),
      cell * (0.34 + 0.07 * pulse),
      Paint()..color = color.withValues(alpha: 0.16 + 0.16 * pulse),
    );
    // 主体
    final r = cell * 0.30;
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // 字母
    final letter = switch (p.kind) {
      _Power.bomb => 'B',
      _Power.flame => 'F',
      _Power.speed => 'S',
    };
    final tp = TextPainter(
      text: TextSpan(
          text: letter,
          style: TextStyle(
              color: const Color(0xFF222222),
              fontSize: cell * 0.42,
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
    // 地面阴影
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + r * 0.75), width: r * 1.8, height: r * 0.7),
      Paint()..color = const Color(0x55000000),
    );
    // 球体
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = blink ? const Color(0xFFFF5252) : const Color(0xFF1F1F1F),
    );
    // 球面高光
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.5, -0.5),
          radius: 0.7,
          colors: [
            Colors.white.withValues(alpha: 0.5),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    // 引信 + 火星
    final fuseEnd = Offset(cx + r * 0.55, cy - r * 0.85);
    canvas.drawLine(
      Offset(cx + r * 0.25, cy - r * 0.55),
      fuseEnd,
      Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = cell * 0.06
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(fuseEnd, cell * 0.075,
        Paint()..color = const Color(0xFFFFD54A));
    canvas.drawCircle(fuseEnd, cell * 0.13,
        Paint()..color = const Color(0x66FF7043));
  }

  void _drawFlame(Canvas canvas, double x, double y, double s, double v) {
    final a = (v / _kFlameTime).clamp(0.0, 1.0);
    // 外焰
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y + 1, s - 2, s - 2),
        Radius.circular(s * 0.22),
      ),
      Paint()..color = const Color(0xFFFF6A00).withValues(alpha: 0.45 + 0.35 * a),
    );
    // 中焰
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + s * 0.16, y + s * 0.16, s * 0.68, s * 0.68),
        Radius.circular(s * 0.2),
      ),
      Paint()..color = const Color(0xFFFFC107).withValues(alpha: 0.6 + 0.35 * a),
    );
    // 内核
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + s * 0.32, y + s * 0.32, s * 0.36, s * 0.36),
        Radius.circular(s * 0.14),
      ),
      Paint()..color = const Color(0xFFFFF59D).withValues(alpha: 0.75 + 0.25 * a),
    );
  }

  void _drawBlob(Canvas canvas, Offset center, double s, Color color,
      bool isPlayer, SwipeDir? dir,
      {bool shadow = false, bool angry = false}) {
    final r = s * 0.36;
    if (shadow) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(center.dx, center.dy + r * 0.85),
            width: r * 1.7,
            height: r * 0.6),
        Paint()..color = const Color(0x44000000),
      );
    }
    // 身体径向(顶亮底暗,有体积感)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.95,
          colors: [
            _lighten(color, 0.4),
            color,
            _darken(color, 0.28),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // 外发光描边
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
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
    for (final sgn in const [-1.0, 1.0]) {
      final eyeX = center.dx + ex + px * sep * sgn;
      final eyeY = center.dy + ey + py * sep * sgn;
      canvas.drawCircle(Offset(eyeX, eyeY), r * 0.2,
          Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset(eyeX + lookx * r * 0.08, eyeY + looky * r * 0.08),
          r * 0.1,
          Paint()..color = const Color(0xFF111111));
    }
    // 追击型敌人:怒眉
    if (angry) {
      final brow = Paint()
        ..color = const Color(0xFF2A0000)
        ..strokeWidth = r * 0.12
        ..strokeCap = StrokeCap.round;
      for (final sgn in const [-1.0, 1.0]) {
        final eyeX = center.dx + ex + px * sep * sgn;
        final eyeY = center.dy + ey + py * sep * sgn;
        canvas.drawLine(
            Offset(eyeX - r * 0.2, eyeY - r * 0.24),
            Offset(eyeX + r * 0.16, eyeY - r * 0.06),
            brow);
      }
    }
    if (isPlayer) {
      // 头顶天线 + 发光端
      canvas.drawCircle(Offset(center.dx, center.dy - r * 1.05), s * 0.11,
          Paint()..color = const Color(0x55FFD54A));
      canvas.drawCircle(Offset(center.dx, center.dy - r * 1.05), s * 0.06,
          Paint()..color = const Color(0xFFFFD54A));
    }
  }

  @override
  bool shouldRepaint(covariant _BomberPainter old) => true;
}

Color _lighten(Color c, double amt) {
  return Color.fromARGB(
    (c.a * 255).round().clamp(0, 255),
    ((c.r + (1 - c.r) * amt) * 255).round().clamp(0, 255),
    ((c.g + (1 - c.g) * amt) * 255).round().clamp(0, 255),
    ((c.b + (1 - c.b) * amt) * 255).round().clamp(0, 255),
  );
}

Color _darken(Color c, double amt) {
  return Color.fromARGB(
    (c.a * 255).round().clamp(0, 255),
    (c.r * (1 - amt) * 255).round().clamp(0, 255),
    (c.g * (1 - amt) * 255).round().clamp(0, 255),
    (c.b * (1 - amt) * 255).round().clamp(0, 255),
  );
}

// ---- 虚拟摇杆(仿坦克,拖动控制四向) ----
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
    setState(() { _origin = origin; _knob = knob; });
    widget.onDir(dir);
  }

  void _reset() {
    setState(() { _origin = null; _knob = null; });
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
    canvas.drawCircle(origin!, 56, Paint()..color = const Color(0x18FFFFFF));
    canvas.drawCircle(
      origin!, 56,
      Paint()
        ..color = const Color(0x44FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(knob ?? origin!, 24, Paint()..color = const Color(0x88FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
