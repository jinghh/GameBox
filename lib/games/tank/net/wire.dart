// 坦克大战联机:网络角色 + 紧凑二进制序列化。
//
// 架构:host(权威主机)每帧把完整可渲染状态打包成 Snapshot 下发给 guest;
//       guest 把本地输入打包成 InputFrame 上行给 host。
//
// 字节格式:字节对齐 + 小端,定点坐标(world × 16 存 int16)。
// 阶段1 优先正确性与可调试性(回环无带宽压力);阶段2 接真蓝牙时可改为位打包/grid 差量。

import 'dart:typed_data';
import 'dart:ui';

import '../constants.dart';
import '../models.dart';

/// 网络角色。offline = 现有单机/双人合作(完全不走联机分支)。
/// host = 玩家0(本地 P1),跑完整游戏逻辑并广播快照。
/// guest = 玩家1(远端 P2),只发输入、收快照渲染。
enum NetRole { offline, host, guest }

/// 消息类型(每条消息首字节)。
const int kMsgSnapshot = 1;
const int kMsgInput = 2;

// ============================ 字节读写器 ============================

class _ByteWriter {
  final BytesBuilder _b = BytesBuilder();
  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) {
    _b.addByte(v & 0xFF);
    _b.addByte((v >>> 8) & 0xFF);
  }

  /// 有符号 16 位:负数经 toUnsigned 转 2 补码。
  void i16(int v) => u16(v.toUnsigned(16));
  void u32(int v) {
    _b.addByte(v & 0xFF);
    _b.addByte((v >>> 8) & 0xFF);
    _b.addByte((v >>> 16) & 0xFF);
    _b.addByte((v >>> 24) & 0xFF);
  }

  void i32(int v) => u32(v.toUnsigned(32));

  void f32(double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    _b.add(bd.buffer.asUint8List());
  }

  Uint8List take() => _b.takeBytes();
}

class _ByteReader {
  final Uint8List _b;
  int _i = 0;
  _ByteReader(this._b);

  int u8() {
    if (_i >= _b.length) return 0; // 越界保护:防畸形包崩溃
    return _b[_i++];
  }

  int u16() {
    final lo = u8();
    final hi = u8();
    return lo | (hi << 8);
  }

  int i16() {
    final v = u16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int u32() {
    final b0 = u8(), b1 = u8(), b2 = u8(), b3 = u8();
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }

  int i32() {
    final v = u32();
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  double f32() {
    if (_i + 4 > _b.length) return 0;
    final bd = ByteData.sublistView(_b, _i, _i + 4);
    _i += 4;
    return bd.getFloat32(0, Endian.little);
  }
}

// ============================ 实体序列化 ============================
// Tank:不同步本地态(fireCooldown/aiTimer/aiDir/bombTimer/summonTimer/
//       spawnAnim/hitFlashTime)与 speed(guest 不跑逻辑,无需)。13 字节。

void _writeTank(_ByteWriter w, Tank t) {
  w.i16((t.pos.dx * 16).round());
  w.i16((t.pos.dy * 16).round());
  w.u8(t.dir.index);
  int flags = 0;
  if (t.isPlayer) flags |= 1 << 0;
  if (t.isBoss) flags |= 1 << 1;
  if (t.isMiniBoss) flags |= 1 << 2;
  if (t.alive) flags |= 1 << 3;
  if (t.bonus) flags |= 1 << 4;
  if (t.spawning) flags |= 1 << 5;
  if (t.size >= kBossSize) flags |= 1 << 6; // 普通kTank / Boss kBossSize
  w.u8(flags);
  w.u8(t.kind?.index ?? 0);
  w.u8(t.player);
  w.u8(t.bulletLevel);
  w.u8(t.hp);
  w.u8(t.armorHp);
  w.u16((t.shieldTime * 10).round().clamp(0, 65535)); // ×10 定点
}

Tank _readTank(_ByteReader r) {
  final dx = r.i16() / 16.0;
  final dy = r.i16() / 16.0;
  final dirIdx = r.u8();
  final flags = r.u8();
  final kindIdx = r.u8();
  final player = r.u8();
  final bulletLevel = r.u8();
  final hp = r.u8();
  final armorHp = r.u8();
  final shieldQ = r.u16();
  final isPlayer = (flags & (1 << 0)) != 0;
  final t = Tank(
    pos: Offset(dx, dy),
    dir: Dir.values[dirIdx.clamp(0, Dir.values.length - 1)],
    isPlayer: isPlayer,
    kind: isPlayer
        ? null
        : EnemyKind.values[kindIdx.clamp(0, EnemyKind.values.length - 1)],
    speed: 0, // guest 不跑逻辑
    bonus: (flags & (1 << 4)) != 0,
    player: player,
    size: (flags & (1 << 6)) != 0 ? kBossSize : kTank,
  )
    ..alive = (flags & (1 << 3)) != 0
    ..isBoss = (flags & (1 << 1)) != 0
    ..isMiniBoss = (flags & (1 << 2)) != 0
    ..bulletLevel = bulletLevel
    ..hp = hp
    ..armorHp = armorHp
    ..shieldTime = shieldQ / 10.0
    ..spawning = (flags & (1 << 5)) != 0;
  return t;
}

// Bullet:8 字节(speed 不传)。
void _writeBullet(_ByteWriter w, Bullet b) {
  w.i16((b.pos.dx * 16).round());
  w.i16((b.pos.dy * 16).round());
  w.u8(b.dir.index);
  int flags = 0;
  if (b.fromPlayer) flags |= 1 << 0;
  if (b.isBomb) flags |= 1 << 1;
  if (b.owner != null) flags |= 1 << 2;
  w.u8(flags);
  w.u8(b.owner ?? 0);
  w.u8(b.power);
}

Bullet _readBullet(_ByteReader r) {
  final dx = r.i16() / 16.0;
  final dy = r.i16() / 16.0;
  final dirIdx = r.u8();
  final flags = r.u8();
  final owner = r.u8();
  final power = r.u8();
  return Bullet(
    pos: Offset(dx, dy),
    dir: Dir.values[dirIdx.clamp(0, Dir.values.length - 1)],
    fromPlayer: (flags & 1) != 0,
    speed: 0, // guest 不跑逻辑
    power: power,
    owner: (flags & (1 << 2)) != 0 ? owner : null,
    isBomb: (flags & (1 << 1)) != 0,
  );
}

// PowerUp:5 字节。
void _writePowerUp(_ByteWriter w, PowerUp p) {
  w.i16((p.pos.dx * 16).round());
  w.i16((p.pos.dy * 16).round());
  w.u8(p.kind.index);
}

PowerUp _readPowerUp(_ByteReader r) {
  final dx = r.i16() / 16.0;
  final dy = r.i16() / 16.0;
  final kindIdx = r.u8();
  return PowerUp(
    PowerKind.values[kindIdx.clamp(0, PowerKind.values.length - 1)],
    Offset(dx, dy),
  );
}

// Explosion:17 字节(纯视觉,阶段1 全量同步保证画面一致)。
void _writeExplosion(_ByteWriter w, Explosion e) {
  w.i16((e.pos.dx * 16).round());
  w.i16((e.pos.dy * 16).round());
  w.f32(e.t);
  w.f32(e.life);
  w.f32(e.size);
  w.u8(e.big ? 1 : 0);
}

Explosion _readExplosion(_ByteReader r) {
  final dx = r.i16() / 16.0;
  final dy = r.i16() / 16.0;
  final t = r.f32();
  final life = r.f32();
  final size = r.f32();
  final big = r.u8() != 0;
  return Explosion(Offset(dx, dy), life: life, size: size, big: big)..t = t;
}

// grid:26×26,u8/格(terrain.index)。676 字节(阶段1 全量;阶段2 改差量)。
void _writeGrid(_ByteWriter w, List<List<Terrain>> grid) {
  for (int y = 0; y < kCells; y++) {
    final row = grid[y];
    for (int x = 0; x < kCells; x++) {
      w.u8(row[x].index);
    }
  }
}

List<List<Terrain>> _readGrid(_ByteReader r) {
  final grid = <List<Terrain>>[];
  for (int y = 0; y < kCells; y++) {
    final row = <Terrain>[];
    for (int x = 0; x < kCells; x++) {
      row.add(Terrain.values[r.u8().clamp(0, Terrain.values.length - 1)]);
    }
    grid.add(row);
  }
  return grid;
}

// ============================ 消息体 ============================

/// host→guest:一帧完整可渲染 + HUD 状态。
class Snapshot {
  final Phase phase;
  final int score;
  final int lives;
  final int level;
  final bool isBossLevel;
  final bool baseAlive;
  final bool freezeActive;
  final int bossHpShown;
  final int bossMaxHp; // Boss 总血量(guest 计算血条比例用)
  final int enemyRemaining;
  final int gridSeq; // 地形版本:host 仅在 _bumpTerrain 时 +1;guest 据此判断是否需要重绘地形
  final double time;
  final List<List<Terrain>>? grid; // 可空:null = 引用上一帧地形(差量同步)
  bool get hasGrid => grid != null;
  final List<Tank> players;
  final List<Tank> enemies;
  final List<Bullet> bullets;
  final List<PowerUp> powerups;
  final List<Explosion> explosions;

  Snapshot({
    required this.phase,
    required this.score,
    required this.lives,
    required this.level,
    required this.isBossLevel,
    required this.baseAlive,
    required this.freezeActive,
    required this.bossHpShown,
    required this.bossMaxHp,
    required this.enemyRemaining,
    required this.gridSeq,
    required this.time,
    required this.grid,
    required this.players,
    required this.enemies,
    required this.bullets,
    required this.powerups,
    required this.explosions,
  });

  Uint8List toBytes() {
    final w = _ByteWriter();
    w.u8(kMsgSnapshot);
    w.u8(phase.index);
    w.i32(score);
    w.u8(lives);
    w.u8(level);
    int flags = 0;
    if (isBossLevel) flags |= 1 << 0;
    if (baseAlive) flags |= 1 << 1;
    if (freezeActive) flags |= 1 << 2;
    w.u8(flags);
    w.u8(bossHpShown);
    w.u8(bossMaxHp);
    w.u8(enemyRemaining);
    w.u8(gridSeq);
    w.f32(time);
    w.u8(grid != null ? 1 : 0); // 含地形? 1=随包带 grid,0=引用上一帧(差量)
    if (grid != null) _writeGrid(w, grid!);
    w.u8(players.length);
    for (final t in players) {
      _writeTank(w, t);
    }
    w.u8(enemies.length);
    for (final t in enemies) {
      _writeTank(w, t);
    }
    w.u8(bullets.length);
    for (final b in bullets) {
      _writeBullet(w, b);
    }
    w.u8(powerups.length);
    for (final p in powerups) {
      _writePowerUp(w, p);
    }
    w.u8(explosions.length);
    for (final e in explosions) {
      _writeExplosion(w, e);
    }
    return w.take();
  }

  /// 解析;首字节不符返回 null。
  static Snapshot? fromBytes(Uint8List bytes) {
    final r = _ByteReader(bytes);
    if (r.u8() != kMsgSnapshot) return null;
    final phase = Phase.values[r.u8().clamp(0, Phase.values.length - 1)];
    final score = r.i32();
    final lives = r.u8();
    final level = r.u8();
    final flags = r.u8();
    final bossHpShown = r.u8();
    final bossMaxHp = r.u8();
    final enemyRemaining = r.u8();
    final gridSeq = r.u8();
    final time = r.f32();
    final includeGrid = r.u8() != 0;
    final grid = includeGrid ? _readGrid(r) : null;
    final players = <Tank>[];
    for (int i = 0, n = r.u8(); i < n; i++) {
      players.add(_readTank(r));
    }
    final enemies = <Tank>[];
    for (int i = 0, n = r.u8(); i < n; i++) {
      enemies.add(_readTank(r));
    }
    final bullets = <Bullet>[];
    for (int i = 0, n = r.u8(); i < n; i++) {
      bullets.add(_readBullet(r));
    }
    final powerups = <PowerUp>[];
    for (int i = 0, n = r.u8(); i < n; i++) {
      powerups.add(_readPowerUp(r));
    }
    final explosions = <Explosion>[];
    for (int i = 0, n = r.u8(); i < n; i++) {
      explosions.add(_readExplosion(r));
    }
    return Snapshot(
      phase: phase,
      score: score,
      lives: lives,
      level: level,
      isBossLevel: (flags & (1 << 0)) != 0,
      baseAlive: (flags & (1 << 1)) != 0,
      freezeActive: (flags & (1 << 2)) != 0,
      bossHpShown: bossHpShown,
      bossMaxHp: bossMaxHp,
      enemyRemaining: enemyRemaining,
      gridSeq: gridSeq,
      time: time,
      grid: grid,
      players: players,
      enemies: enemies,
      bullets: bullets,
      powerups: powerups,
      explosions: explosions,
    );
  }
}

/// guest→host:本地输入(语义=玩家1)。
class InputFrame {
  final Dir? dir;
  final bool fire;

  InputFrame({this.dir, required this.fire});

  Uint8List toBytes() {
    final w = _ByteWriter();
    w.u8(kMsgInput);
    w.u8(dir?.index ?? 255); // 255 = 无方向
    w.u8(fire ? 1 : 0);
    return w.take();
  }

  static InputFrame? fromBytes(Uint8List bytes) {
    final r = _ByteReader(bytes);
    if (r.u8() != kMsgInput) return null;
    final dirIdx = r.u8();
    final fire = r.u8() != 0;
    return InputFrame(
      dir: dirIdx == 255
          ? null
          : Dir.values[dirIdx.clamp(0, Dir.values.length - 1)],
      fire: fire,
    );
  }
}
