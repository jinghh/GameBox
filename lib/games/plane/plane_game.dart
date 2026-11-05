// 飞机大战 —— 竖版弹幕射击：拖拽移动、自动开火、火力/护盾/炸弹道具、波次与 Boss。
// 纯单机离线；最高分本地持久化；画面全部 CustomPaint 手绘，零图片素材。
//
// 帧循环用 Ticker（对齐 vsync，后台不空转）：每帧只改纯 Dart 实体数据，
// 由 ValueNotifier 驱动画布重绘；HUD/覆盖层用 record 快照做值相等判断，
// 仅在数值变化时重建，避免逐帧 setState 造成整页重复渲染。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../debug/game_debug_registry.dart';
import '../../shared/best_score_store.dart';
import '../../shared/game_shell.dart';
import '../../shared/orientation.dart';
import '../../shared/sound_store.dart';
import 'plane_constants.dart';
import 'plane_entities.dart';
import 'plane_painter.dart';
import 'plane_sound.dart';
import 'plane_sprites.dart';

class PlanePage extends StatefulWidget {
  const PlanePage({super.key});

  @override
  State<PlanePage> createState() => _PlanePageState();
}

class _PlanePageState extends State<PlanePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver,
        GameDebugMixin<PlanePage> {
  static const String _bestKey = 'best_plane';

  final PlaneScene _scene = PlaneScene();
  late final PlanePainter _painter;
  late final PlaneSound _sound;
  PlaneSprites? _sprites;

  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<PlaneHud> _hud = ValueNotifier<PlaneHud>(
    (score: 0, best: 0, lives: 3, wave: 1, power: 1, bombs: 2),
  );
  final ValueNotifier<PlanePhase> _phase =
      ValueNotifier<PlanePhase>(PlanePhase.ready);

  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = <LogicalKeyboardKey>{};
  final math.Random _rng = math.Random();

  Ticker? _ticker;
  Duration? _lastElapsed;

  int _score = 0;
  int _best = 0;
  int _lives = 3;
  int _wave = 1;
  int _spawned = 0;
  int _quota = planeWaveQuota(1);
  double _spawnCd = 0.7;
  double _bombCd = 0; // 防止长按空格/连点瞬间耗尽全部炸弹
  bool _bossActive = false;
  Offset? _pointerTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_onFocusChanged);
    _painter = PlanePainter(_scene, repaint: _frame);
    _sound = PlaneSound();
    _best = BestScoreStore.get(_bestKey);
    _syncHud();
    _sound.init();
    unawaited(_loadSprites());
    // 强制竖屏（沿用项目 MethodChannel 方案，避开部分 ROM 忽略 SystemChrome）
    OrientationChannel.set(AppOrientation.portrait);
    unawaited(_setWakelock(true));
    _ticker = createTicker(_onTick);
    _ticker!.start();
  }

  @override
  void dispose() {
    // 先停帧循环，再释放 notifier，避免回调访问已销毁对象。
    _ticker?.dispose();
    _ticker = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setWakelock(false));
    OrientationChannel.set(AppOrientation.portrait);
    _sprites?.dispose();
    _sprites = null;
    _sound.dispose();
    _painter.disposeIcons();
    _frame.dispose();
    _hud.dispose();
    _phase.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  /// 焦点被按钮/系统抢走时清掉按下状态，避免「卡键」让飞机一直朝一个方向飞。
  void _onFocusChanged() {
    if (!_focus.hasFocus) _keys.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive 多由输入法/系统浮层触发（dev 调试面板输入时会短暂进入），不算切后台。
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      return;
    }
    _keys.clear();
    // 切后台/来电时自动暂停：停帧期间累计的弹幕不会在回来瞬间「秒杀」玩家。
    if (_phase.value == PlanePhase.playing) _togglePause();
  }

  static Future<void> _setWakelock(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on Object {
      // 平台不支持时忽略，不影响游戏
    }
  }

  /// 精灵图异步解码；完成前 painter 用几何绘制兜底。
  /// 页面在加载途中被销毁时直接释放已解码的图片，避免纹理泄漏。
  Future<void> _loadSprites() async {
    final sprites = await PlaneSprites.load();
    if (!mounted) {
      sprites.dispose();
      return;
    }
    _sprites = sprites;
    _painter.sprites = sprites;
    _frame.value++; // 立即重绘为精灵版本
  }

  // ---- dev 调试面板：仅开发包注册，可直接跳波次验证重装机 / Boss ----
  @override
  String get id => 'plane';

  @override
  Map<String, String> info() => {
        '波次': '$_wave',
        '分数': '$_score',
        '敌机': '${_scene.enemies.length}',
        '火力': 'Lv.${_scene.player.power}',
        'Boss': _bossActive ? '在场' : '无',
      };

  @override
  int? get currentLevel => _wave;

  @override
  int? get maxLevel => null; // 无尽模式

  @override
  void jumpToLevel(int n) {
    final wave = n.clamp(1, 99).toInt();
    _scene.enemies.clear();
    _scene.enemyBullets.clear();
    _scene.bullets.clear();
    _wave = wave;
    _spawned = 0;
    _quota = planeWaveQuota(wave);
    _spawnCd = 0.6;
    _bossActive = false;
    if (wave % kBossEveryWaves == 0) _spawnBoss();
    if (_phase.value == PlanePhase.ready ||
        _phase.value == PlanePhase.gameOver) {
      _phase.value = PlanePhase.playing;
    }
    _syncHud();
  }

  // ---- 帧循环 ----
  void _onTick(Duration elapsed) {
    final last = _lastElapsed;
    _lastElapsed = elapsed;
    var dt = last == null ? 0.0 : (elapsed - last).inMicroseconds / 1e6;
    if (dt < 0) dt = 0;
    if (dt > 1 / 30) dt = 1 / 30; // 卡顿/切后台回来时限位，防穿模与瞬时刷怪

    switch (_phase.value) {
      case PlanePhase.playing:
        _scene.time += dt;
        _scene.scrollStars(dt, 1);
        _update(dt);
        _frame.value++;
        break;
      case PlanePhase.ready:
        // 待机时星空缓慢滚动，画面不静止
        _scene.time += dt * 0.4;
        _scene.scrollStars(dt, 0.4);
        _frame.value++;
        break;
      case PlanePhase.paused:
      case PlanePhase.gameOver:
        // 冻结画面且不触发重绘，避免无意义耗电
        break;
    }
  }

  void _update(double dt) {
    final p = _scene.player;
    if (_bombCd > 0) _bombCd = math.max(0.0, _bombCd - dt);
    if (p.invuln > 0) p.invuln = math.max(0.0, p.invuln - dt);
    if (p.shield > 0) p.shield = math.max(0.0, p.shield - dt);
    if (_scene.flash > 0) {
      _scene.flash = math.max(0.0, _scene.flash - dt * 2.2);
    }

    _updatePlayer(dt);
    _updateSpawns(dt);
    _updateEnemies(dt);
    _stepBullets(_scene.bullets, dt);
    _stepBullets(_scene.enemyBullets, dt);
    _updatePowerUps(dt);
    _updateParticles(dt);
    _collide();
    _syncHud();
  }

  // ---- 玩家 ----
  void _updatePlayer(double dt) {
    final p = _scene.player;
    var dx = 0.0;
    var dy = 0.0;
    if (_pressed(LogicalKeyboardKey.arrowLeft) ||
        _pressed(LogicalKeyboardKey.keyA)) {
      dx -= 1;
    }
    if (_pressed(LogicalKeyboardKey.arrowRight) ||
        _pressed(LogicalKeyboardKey.keyD)) {
      dx += 1;
    }
    if (_pressed(LogicalKeyboardKey.arrowUp) ||
        _pressed(LogicalKeyboardKey.keyW)) {
      dy -= 1;
    }
    if (_pressed(LogicalKeyboardKey.arrowDown) ||
        _pressed(LogicalKeyboardKey.keyS)) {
      dy += 1;
    }

    if (dx != 0 || dy != 0) {
      final len = math.sqrt(dx * dx + dy * dy);
      p.x += dx / len * kPlayerSpeed * dt;
      p.y += dy / len * kPlayerSpeed * dt;
      _pointerTarget = null; // 键盘接管，避免手指残留位置把飞机拉回
    } else {
      final t = _pointerTarget;
      if (t != null) {
        final k = math.min(1.0, dt * 16); // 帧率无关的平滑跟随
        p.x += (t.dx - p.x) * k;
        p.y += (t.dy - p.y) * k;
      }
    }
    p.x = p.x.clamp(18.0, kPlaneW - 18.0).toDouble();
    p.y = p.y.clamp(60.0, kPlaneH - 24.0).toDouble();

    p.fireCd -= dt;
    if (p.fireCd <= 0) {
      _fire();
      p.fireCd = math.max(0.085, 0.17 - p.power * 0.018);
    }
  }

  bool _pressed(LogicalKeyboardKey k) => _keys.contains(k);

  void _fire() {
    if (_scene.bullets.length > 160) return; // 数量兜底，防极端情况无限增长
    final p = _scene.player;
    const vy = -540.0;
    switch (p.power) {
      case 1:
        _scene.bullets.add(Bullet(p.x, p.y - 20, 0, vy));
        break;
      case 2:
        _scene.bullets.add(Bullet(p.x - 8, p.y - 8, 0, vy));
        _scene.bullets.add(Bullet(p.x + 8, p.y - 8, 0, vy));
        break;
      case 3:
        _scene.bullets.add(Bullet(p.x, p.y - 20, 0, vy));
        _scene.bullets.add(Bullet(p.x - 10, p.y - 8, -90, vy));
        _scene.bullets.add(Bullet(p.x + 10, p.y - 8, 90, vy));
        break;
      default:
        _scene.bullets.add(Bullet(p.x - 5, p.y - 20, 0, vy));
        _scene.bullets.add(Bullet(p.x + 5, p.y - 20, 0, vy));
        _scene.bullets.add(Bullet(p.x - 12, p.y - 8, -150, vy));
        _scene.bullets.add(Bullet(p.x + 12, p.y - 8, 150, vy));
    }
    _sound.shoot();
  }

  // ---- 刷怪 / 波次 ----
  void _updateSpawns(double dt) {
    if (_spawned < _quota) {
      _spawnCd -= dt;
      if (_spawnCd <= 0) {
        _spawnEnemy();
        _spawned++;
        final jitter = 0.75 + _rng.nextDouble() * 0.5;
        _spawnCd = planeSpawnInterval(_wave) *
            jitter *
            (_bossActive ? 1.8 : 1.0); // Boss 战减少杂兵密度
      }
    } else if (_scene.enemies.isEmpty && !_bossActive) {
      _nextWave();
    }
  }

  void _spawnEnemy() {
    final r = _rng.nextDouble();
    final kind = _wave >= 3 && r < 0.18
        ? EnemyKind.heavy
        : (r < 0.45 ? EnemyKind.zigzag : EnemyKind.scout);
    final speed = planeSpeedScale(_wave);
    final x = 30 + _rng.nextDouble() * (kPlaneW - 60);
    switch (kind) {
      case EnemyKind.scout:
        _scene.enemies.add(Enemy(
          kind: kind,
          x: x,
          y: -20,
          vx: 0,
          vy: 118 * speed,
          w: 19,
          h: 20,
          hp: 1 + _wave ~/ 6,
          score: 10,
          fireCd: 0,
        ));
        break;
      case EnemyKind.zigzag:
        _scene.enemies.add(Enemy(
          kind: kind,
          x: x,
          y: -24,
          vx: 0,
          vy: 88 * speed,
          w: 23,
          h: 21,
          hp: 2 + _wave ~/ 5,
          score: 20,
          fireCd: 0,
          phase: _rng.nextDouble() * math.pi * 2,
        ));
        break;
      case EnemyKind.heavy:
        _scene.enemies.add(Enemy(
          kind: kind,
          x: x,
          y: -30,
          vx: 0,
          vy: 58 * speed,
          w: 34,
          h: 32,
          hp: 6 + _wave ~/ 2,
          score: 50,
          fireCd: 1.4,
        ));
        break;
      case EnemyKind.boss:
        break; // Boss 由 _spawnBoss 单独生成
    }
  }

  void _spawnBoss() {
    _bossActive = true;
    _scene.enemies.add(Enemy(
      kind: EnemyKind.boss,
      x: kPlaneW / 2,
      y: -70,
      vx: 72,
      vy: 0,
      w: 112,
      h: 62,
      hp: planeBossHp(_wave),
      score: 500,
      fireCd: 1.8,
    ));
  }

  void _nextWave() {
    _wave++;
    _spawned = 0;
    _quota = planeWaveQuota(_wave);
    _spawnCd = 0.8;
    if (_wave % kBossEveryWaves == 0) _spawnBoss();
  }

  // ---- 实体推进 ----
  void _updateEnemies(double dt) {
    final p = _scene.player;
    for (final e in _scene.enemies) {
      e.t += dt;
      if (e.hitFlash > 0) {
        e.hitFlash = math.max(0.0, e.hitFlash - dt);
      }
      if (e.flashCooldown > 0) {
        e.flashCooldown = math.max(0.0, e.flashCooldown - dt);
      }
      if (e.kind == EnemyKind.boss) {
        if (e.y < 105) e.y += 62 * dt; // 入场后停在上半屏
        e.x += e.vx * dt;
        if (e.x < kBossMoveMargin) {
          e.x = kBossMoveMargin;
          e.vx = e.vx.abs();
        } else if (e.x > kPlaneW - kBossMoveMargin) {
          e.x = kPlaneW - kBossMoveMargin;
          e.vx = -e.vx.abs();
        }
      } else if (e.kind == EnemyKind.zigzag) {
        e.y += e.vy * dt;
        e.x = (e.baseX + math.sin(e.t * 2.4 + e.phase) * 62)
            .clamp(20.0, kPlaneW - 20.0)
            .toDouble();
      } else {
        e.x += e.vx * dt;
        e.y += e.vy * dt;
      }
      if (e.y > kPlaneH + e.h) {
        e.dead = true; // 漏掉的敌机直接移除（不扣命）
        continue;
      }
      if (e.kind == EnemyKind.scout || e.kind == EnemyKind.zigzag) continue;

      e.fireCd -= dt;
      if (e.fireCd > 0) continue;
      if (e.kind == EnemyKind.heavy) {
        if (e.y < 20 || e.y > kPlaneH - 170) continue;
        e.fireCd = 1.8;
        final vx = p.x - e.x;
        final vy = p.y - e.y;
        final len = math.max(1.0, math.sqrt(vx * vx + vy * vy));
        _addEnemyBullet(
            Bullet(e.x, e.y + 16, vx / len * 170, vy / len * 170, r: 4));
        _sound.enemyShoot();
      } else {
        if (e.y < 60) continue;
        e.fireCd = math.max(0.75, 1.35 - _wave * 0.03);
        final aim = math.atan2(p.y - e.y, p.x - e.x);
        for (var i = -2; i <= 2; i++) {
          final a = aim + i * 0.22;
          _addEnemyBullet(Bullet(
            e.x,
            e.y + 26,
            math.cos(a) * 165,
            math.sin(a) * 165,
            r: 4.5,
          ));
        }
        _sound.enemyShoot();
      }
    }
    _scene.enemies.removeWhere((e) => e.dead);
    _refreshBossFlag();
  }

  void _refreshBossFlag() {
    if (_bossActive &&
        !_scene.enemies.any((e) => e.kind == EnemyKind.boss)) {
      _bossActive = false;
    }
  }

  void _addEnemyBullet(Bullet b) {
    if (_scene.enemyBullets.length < 200) _scene.enemyBullets.add(b);
  }

  void _stepBullets(List<Bullet> list, double dt) {
    for (final b in list) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      if (b.y < -30 ||
          b.y > kPlaneH + 30 ||
          b.x < -30 ||
          b.x > kPlaneW + 30) {
        b.dead = true;
      }
    }
    list.removeWhere((b) => b.dead);
  }

  void _updatePowerUps(double dt) {
    for (final pu in _scene.powerUps) {
      pu.y += kPowerFallSpeed * dt;
      pu.t += dt;
      if (pu.t > 12 || pu.y > kPlaneH + 20) pu.dead = true;
    }
    _scene.powerUps.removeWhere((pu) => pu.dead);
  }

  void _updateParticles(double dt) {
    for (final p in _scene.particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 90 * dt;
      p.life -= dt;
    }
    _scene.particles.removeWhere((p) => p.life <= 0);
  }

  // ---- 碰撞 ----
  void _collide() {
    final p = _scene.player;

    // 1) 玩家子弹 → 敌机
    for (final b in _scene.bullets) {
      for (final e in _scene.enemies) {
        if (e.dead || !b.rect.overlaps(e.rect)) continue;
        b.dead = true;
        e.hp -= b.damage;
        if (e.flashCooldown <= 0) {
          e.hitFlash = kHitFlashDuration;
          e.flashCooldown = kHitFlashCooldown;
        }
        _spark(b.x, b.y);
        _sound.hit();
        if (e.hp <= 0) _killEnemy(e);
        break;
      }
    }
    _scene.bullets.removeWhere((b) => b.dead);
    _scene.enemies.removeWhere((e) => e.dead);
    _refreshBossFlag();

    // 2) 拾取道具（无敌期也能拾取）
    final pickup = p.rect.inflate(8);
    for (final pu in _scene.powerUps) {
      if (pu.dead || !pu.rect.overlaps(pickup)) continue;
      pu.dead = true;
      _applyPower(pu.kind);
    }
    _scene.powerUps.removeWhere((pu) => pu.dead);

    if (p.invuln > 0) return;

    // 3) 敌弹 → 玩家
    for (final b in _scene.enemyBullets) {
      if (!b.rect.overlaps(p.rect)) continue;
      b.dead = true;
      _damagePlayer();
      break;
    }
    _scene.enemyBullets.removeWhere((b) => b.dead);
    if (p.invuln > 0 || _phase.value != PlanePhase.playing) {
      _syncHud();
      return;
    }

    // 4) 撞机（Boss 不因碰撞消失，否则贴脸撞击等于白打一架 Boss）
    for (final e in _scene.enemies) {
      if (!e.rect.overlaps(p.rect)) continue;
      if (e.kind != EnemyKind.boss) {
        e.dead = true;
        _explode(e.x, e.y, big: e.kind == EnemyKind.heavy);
      }
      _damagePlayer();
      break;
    }
    _scene.enemies.removeWhere((e) => e.dead);
    _refreshBossFlag();
    _syncHud();
  }

  void _killEnemy(Enemy e) {
    e.dead = true;
    _score += e.score;
    final big = e.kind == EnemyKind.heavy || e.kind == EnemyKind.boss;
    _explode(e.x, e.y, big: big);
    if (big) {
      _sound.bigExplode();
    } else {
      _sound.explode();
    }
    if (e.kind == EnemyKind.boss) {
      _bossActive = false;
      _scene.flash = 0.6;
      _scene.enemyBullets.clear(); // 击败 Boss 清弹，给玩家喘息
      _scene.powerUps.add(PowerUp(PowerKind.power, e.x, e.y));
      _scene.powerUps.add(PowerUp(PowerKind.bomb, e.x + 24, e.y));
    } else if (_rng.nextDouble() < 0.13) {
      _dropPower(e.x, e.y);
    }
  }

  void _dropPower(double x, double y) {
    final r = _rng.nextDouble();
    final kind = r < 0.5
        ? PowerKind.power
        : (r < 0.72
            ? PowerKind.shield
            : (r < 0.9 ? PowerKind.bomb : PowerKind.life));
    _scene.powerUps.add(PowerUp(kind, x, y));
  }

  void _applyPower(PowerKind kind) {
    final p = _scene.player;
    switch (kind) {
      case PowerKind.power:
        if (p.power < 4) {
          p.power++;
        } else {
          _score += 50; // 满级转化为分数
        }
        break;
      case PowerKind.shield:
        p.shield = 8;
        break;
      case PowerKind.bomb:
        p.bombs = math.min(p.bombs + 1, 5);
        break;
      case PowerKind.life:
        _lives = math.min(_lives + 1, 6);
        break;
    }
    _sound.power();
    _syncHud();
  }

  void _damagePlayer() {
    final p = _scene.player;
    _explode(p.x, p.y, big: p.shield <= 0);
    if (p.shield > 0) {
      p.shield = 0;
      p.invuln = 0.9; // 破盾后短暂无敌，避免同一波弹幕连扣两条命
      _sound.hit();
      return;
    }
    _lives--;
    _sound.bigExplode();
    if (_lives <= 0) {
      _gameOver();
      return;
    }
    p.respawn();
    _pointerTarget = null;
    _keys.clear();
  }

  // ---- 特效 ----
  void _explode(double x, double y, {required bool big}) {
    final count = big ? 22 : 10;
    if (_scene.particles.length + count > kMaxParticles) return;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = 40 + _rng.nextDouble() * (big ? 170 : 105);
      _scene.particles.add(Particle(
        x: x,
        y: y,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp,
        life: 0.3 + _rng.nextDouble() * 0.4,
        r: 1.5 + _rng.nextDouble() * (big ? 3.5 : 2.0),
        color: _rng.nextBool()
            ? const Color(0xFFFFCA28)
            : const Color(0xFFFF7043),
      ));
    }
  }

  void _spark(double x, double y) {
    if (_scene.particles.length + 3 > kMaxParticles) return;
    for (var i = 0; i < 3; i++) {
      _scene.particles.add(Particle(
        x: x,
        y: y,
        vx: (_rng.nextDouble() - 0.5) * 90,
        vy: -30 - _rng.nextDouble() * 60,
        life: 0.16 + _rng.nextDouble() * 0.12,
        r: 1.2,
        color: const Color(0xFFB3E5FC),
      ));
    }
  }

  // ---- 局面控制 ----
  void _syncHud() {
    if (_score > _best) _best = _score;
    _hud.value = (
      score: _score,
      best: _best,
      lives: _lives,
      wave: _wave,
      power: _scene.player.power,
      bombs: _scene.player.bombs,
    );
  }

  void _start() {
    _scene.restart();
    _score = 0;
    _lives = 3;
    _wave = 1;
    _spawned = 0;
    _quota = planeWaveQuota(1);
    _spawnCd = 0.7;
    _bombCd = 0;
    _bossActive = false;
    _pointerTarget = null;
    _keys.clear();
    _phase.value = PlanePhase.playing;
    _sound.start();
    _syncHud();
  }

  void _gameOver() {
    _lives = 0;
    _keys.clear();
    _phase.value = PlanePhase.gameOver;
    _sound.over();
    // 只在此处落盘，避免得分变化时频繁写 SharedPreferences
    unawaited(BestScoreStore.setIfGreater(_bestKey, _score));
  }

  void _togglePause() {
    switch (_phase.value) {
      case PlanePhase.playing:
        _keys.clear(); // 防止暂停时按键一直卡在按下状态
        _phase.value = PlanePhase.paused;
        break;
      case PlanePhase.paused:
        _phase.value = PlanePhase.playing;
        break;
      case PlanePhase.ready:
      case PlanePhase.gameOver:
        break;
    }
  }

  void _useBomb() {
    if (_phase.value != PlanePhase.playing) return;
    final p = _scene.player;
    if (p.bombs <= 0 || _bombCd > 0) return;
    p.bombs--;
    _bombCd = 0.35; // 长按自动重复按键不会一次清空所有炸弹
    _sound.bomb();
    _scene.flash = 1;
    _scene.enemyBullets.clear();
    for (final e in _scene.enemies) {
      if (e.kind == EnemyKind.boss) {
        e.hp -= (e.maxHp * 0.25).round();
      } else {
        e.hp = 0;
      }
      if (e.hp <= 0) {
        _killEnemy(e);
      } else {
        e.hitFlash = kHitFlashDuration;
        _explode(e.x, e.y, big: false);
      }
    }
    _scene.enemies.removeWhere((e) => e.dead);
    _refreshBossFlag();
    _syncHud();
  }

  // ---- 输入 ----
  void _onPointer(Offset local, Size size) {
    if (_phase.value != PlanePhase.playing) return;
    // 触摸是最新输入，立刻接管并清掉可能卡住的键盘方向。
    _keys.clear();
    final tr = planeTransform(size);
    if (tr.scale <= 0) return;
    final x = (local.dx - tr.origin.dx) / tr.scale;
    final y = (local.dy - tr.origin.dy) / tr.scale;
    // 飞机停在手指上方，避免手指遮挡机身
    _pointerTarget = Offset(
      x.clamp(18.0, kPlaneW - 18.0).toDouble(),
      (y - 42).clamp(60.0, kPlaneH - 24.0).toDouble(),
    );
  }

  void _onKeyEvent(KeyEvent event) {
    final k = event.logicalKey;
    if (event is KeyDownEvent) {
      if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) {
        _togglePause();
        return;
      }
      if (k == LogicalKeyboardKey.keyM) {
        unawaited(SoundStore.toggle());
        return;
      }
      if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyB) {
        _useBomb();
        return;
      }
      if (k == LogicalKeyboardKey.enter) {
        switch (_phase.value) {
          case PlanePhase.ready:
          case PlanePhase.gameOver:
            _start();
            break;
          case PlanePhase.paused:
            _togglePause();
            break;
          case PlanePhase.playing:
            break;
        }
        return;
      }
      if (_isMoveKey(k)) _keys.add(k);
    } else if (event is KeyUpEvent) {
      _keys.remove(k);
    }
  }

  static bool _isMoveKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.keyW ||
      k == LogicalKeyboardKey.keyA ||
      k == LogicalKeyboardKey.keyS ||
      k == LogicalKeyboardKey.keyD;

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return GameShell(
      title: '飞机大战 ✈️',
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: kMuted,
          builder: (_, muted, _) => IconButton(
            tooltip: muted ? '开启声音' : '静音',
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () => unawaited(SoundStore.toggle()),
          ),
        ),
        ValueListenableBuilder<PlanePhase>(
          valueListenable: _phase,
          builder: (_, ph, _) => IconButton(
            tooltip: ph == PlanePhase.paused ? '继续' : '暂停',
            icon: Icon(ph == PlanePhase.paused
                ? Icons.play_arrow
                : Icons.pause),
            onPressed: ph == PlanePhase.playing || ph == PlanePhase.paused
                ? _togglePause
                : null,
          ),
        ),
      ],
      body: SafeArea(
        child: KeyboardListener(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: _onKeyEvent,
          child: Column(
            children: [
              _buildHud(),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, cons) {
                    final size = Size(cons.maxWidth, cons.maxHeight);
                    return Stack(
                      children: [
                        RepaintBoundary(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanDown: (d) {
                              // 顶部/底部按钮可能抢走键盘焦点，点回画布时取回
                              if (!_focus.hasFocus) _focus.requestFocus();
                              _onPointer(d.localPosition, size);
                            },
                            onPanUpdate: (d) =>
                                _onPointer(d.localPosition, size),
                            child: CustomPaint(
                              painter: _painter,
                              size: size,
                            ),
                          ),
                        ),
                        _buildOverlay(),
                      ],
                    );
                  },
                ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHud() => ValueListenableBuilder<PlaneHud>(
        valueListenable: _hud,
        builder: (_, h, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat('分数', '${h.score}'),
              _stat('最高', '${h.best}'),
              _stat('波次', '${h.wave}'),
            ],
          ),
        ),
      );

  Widget _stat(String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(value,
              style: const TextStyle(
                color: Color(0xFFFFD54A),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
        ],
      );

  Widget _buildControls() => ValueListenableBuilder<PlaneHud>(
        valueListenable: _hud,
        builder: (_, h, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              ...List.generate(
                h.lives,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.favorite,
                      color: Color(0xFFEF5350), size: 16),
                ),
              ),
              const SizedBox(width: 10),
              Text('火力 Lv.${h.power}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: h.bombs > 0 ? _useBomb : null,
                icon: const Icon(Icons.flash_on, size: 16),
                label: Text('炸弹 ${h.bombs}'),
              ),
            ],
          ),
        ),
      );

  Widget _buildOverlay() => ValueListenableBuilder<PlanePhase>(
        valueListenable: _phase,
        builder: (_, ph, _) {
          if (ph == PlanePhase.playing) return const SizedBox.shrink();
          var title = '';
          var sub = '';
          var buttonText = '';
          switch (ph) {
            case PlanePhase.ready:
              title = '飞机大战';
              sub = '拖动屏幕移动 · 自动射击\n'
                  'WASD/方向键移动 · 空格放炸弹 · P 暂停';
              buttonText = '开始游戏';
              break;
            case PlanePhase.paused:
              title = '已暂停';
              sub = '喘息一下，随时继续';
              buttonText = '继续游戏';
              break;
            case PlanePhase.gameOver:
              title = 'GAME OVER';
              sub = '得分 ${_hud.value.score}　最高 ${_hud.value.best}';
              buttonText = '再来一局';
              break;
            case PlanePhase.playing:
              break;
          }
          return Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.62),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFFFD54A),
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      sub,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      onPressed: () => _onOverlayAction(ph),
                      child: Text(buttonText),
                    ),
                    if (ph == PlanePhase.paused)
                      TextButton(
                        onPressed: _start,
                        child: const Text('重新开始'),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  void _onOverlayAction(PlanePhase ph) {
    switch (ph) {
      case PlanePhase.ready:
      case PlanePhase.gameOver:
        _start();
        break;
      case PlanePhase.paused:
        _togglePause();
        break;
      case PlanePhase.playing:
        break;
    }
  }
}
