// 泡泡堂 · 双人蓝牙联机网络编码(host 权威快照 + 客机输入帧)。
//
// 与坦克联机共用底层 BtSppLink / TankBluetooth(经典蓝牙 SPP),
// 这里只定义泡泡堂专属的消息结构(host→客 快照, 客→主 输入帧)。
//
// 方向编码:_dirToIdx / _idxToDir 由页面侧提供(本文件只存 0..3 / 255)。

import 'dart:typed_data';

const int kBomberMsgSnapshot = 1;
const int kBomberMsgInput = 2;

class _ByteWriter {
  final List<int> b = [];
  void u8(int v) => b.add(v & 0xFF);
  void u16(int v) {
    u8(v);
    u8(v >> 8);
  }
}

class _ByteReader {
  final Uint8List d;
  int i = 0;
  _ByteReader(this.d);
  int u8() => d[i++];
  int u16() => u8() | (u8() << 8);
}

/// 单个玩家的快照字段(全用基础类型,页面侧负责与 [_Player] 互转)。
class BomberPlayerSnap {
  final int col, row;
  final double t;
  final int dirIdx; // 255 = 无
  final bool alive;
  final double invuln;
  final int lives, maxBombs, flameRange;
  final double speed;
  final int activeBombs, score;
  const BomberPlayerSnap({
    required this.col,
    required this.row,
    required this.t,
    required this.dirIdx,
    required this.alive,
    required this.invuln,
    required this.lives,
    required this.maxBombs,
    required this.flameRange,
    required this.speed,
    required this.activeBombs,
    required this.score,
  });
}

class BomberBombSnap {
  final int col, row, range, owner;
  final double fuse;
  const BomberBombSnap(
      {required this.col,
      required this.row,
      required this.range,
      required this.fuse,
      required this.owner});
}

class BomberFlameSnap {
  final int col, row;
  final double rem;
  const BomberFlameSnap(
      {required this.col, required this.row, required this.rem});
}

class BomberPowerSnap {
  final int col, row, kind;
  const BomberPowerSnap(
      {required this.col, required this.row, required this.kind});
}

/// 主机 → 客机:整局状态快照。
class BomberSnapshot {
  final int level;
  final bool over;
  final int winner; // 0 无 / 1 P1 / 2 P2
  final int gridSeq;
  final List<List<int>> grid; // rows×cols (0 空 / 1 砖 / 2 钢)
  final List<BomberPlayerSnap> players; // 长度 2
  final List<BomberBombSnap> bombs;
  final List<BomberFlameSnap> flames;
  final List<BomberPowerSnap> powers;
  const BomberSnapshot({
    required this.level,
    required this.over,
    required this.winner,
    required this.gridSeq,
    required this.grid,
    required this.players,
    required this.bombs,
    required this.flames,
    required this.powers,
  });

  Uint8List encode() {
    final w = _ByteWriter();
    w.u8(kBomberMsgSnapshot);
    w.u8(level & 0xFF);
    w.u8(over ? 1 : 0);
    w.u8(winner & 0x03);
    w.u8(gridSeq & 0xFF);
    for (final row in grid) {
      for (final v in row) {
        w.u8(v);
      }
    }
    w.u8(players.length.clamp(0, 255));
    for (final p in players) {
      w.u8(p.col & 0xFF);
      w.u8(p.row & 0xFF);
      w.u8((p.t.clamp(0, 1) * 255).round() & 0xFF);
      w.u8(p.dirIdx & 0xFF);
      w.u8((p.alive ? 1 : 0) | (p.invuln > 0 ? 2 : 0));
      w.u8(p.lives.clamp(0, 255));
      w.u8(p.maxBombs.clamp(0, 255));
      w.u8(p.flameRange.clamp(0, 255));
      w.u8(p.speed.clamp(0, 255).round());
      w.u8(p.activeBombs.clamp(0, 255));
      w.u16(p.score.clamp(0, 65535));
    }
    w.u8(bombs.length.clamp(0, 255));
    for (final b in bombs) {
      w.u8(b.col & 0xFF);
      w.u8(b.row & 0xFF);
      w.u8(b.range & 0xFF);
      w.u8((b.fuse.clamp(0, 4) * 63).round() & 0xFF);
      w.u8(b.owner & 0xFF);
    }
    w.u8(flames.length.clamp(0, 255));
    for (final f in flames) {
      w.u8(f.col & 0xFF);
      w.u8(f.row & 0xFF);
      w.u8((f.rem.clamp(0, 1) * 255).round() & 0xFF);
    }
    w.u8(powers.length.clamp(0, 255));
    for (final p in powers) {
      w.u8(p.col & 0xFF);
      w.u8(p.row & 0xFF);
      w.u8(p.kind & 0xFF);
    }
    return Uint8List.fromList(w.b);
  }

  static BomberSnapshot? decode(Uint8List d) {
    if (d.length < 2 || d[0] != kBomberMsgSnapshot) return null;
    final r = _ByteReader(d);
    r.u8(); // 跳过类型字节
    final level = r.u8();
    final over = r.u8() == 1;
    final winner = r.u8();
    final gridSeq = r.u8();
    const n = 13;
    final grid = List.generate(n, (_) {
      return List.generate(n, (_) => r.u8());
    });
    final pc = r.u8();
    final players = <BomberPlayerSnap>[];
    for (int i = 0; i < pc; i++) {
      final col = r.u8();
      final row = r.u8();
      final t = r.u8() / 255;
      final dirIdx = r.u8();
      final flags = r.u8();
      final lives = r.u8();
      final maxBombs = r.u8();
      final flameRange = r.u8();
      final speed = r.u8().toDouble();
      final activeBombs = r.u8();
      final score = r.u16();
      players.add(BomberPlayerSnap(
        col: col,
        row: row,
        t: t,
        dirIdx: dirIdx,
        alive: (flags & 1) != 0,
        invuln: (flags & 2) != 0 ? 1.0 : 0.0,
        lives: lives,
        maxBombs: maxBombs,
        flameRange: flameRange,
        speed: speed,
        activeBombs: activeBombs,
        score: score,
      ));
    }
    final bc = r.u8();
    final bombs = <BomberBombSnap>[];
    for (int i = 0; i < bc; i++) {
      final col = r.u8();
      final row = r.u8();
      final range = r.u8();
      final fuse = r.u8() / 63;
      final owner = r.u8();
      bombs.add(BomberBombSnap(
          col: col, row: row, range: range, fuse: fuse, owner: owner));
    }
    final fc = r.u8();
    final flames = <BomberFlameSnap>[];
    for (int i = 0; i < fc; i++) {
      final col = r.u8();
      final row = r.u8();
      final rem = r.u8() / 255;
      flames.add(BomberFlameSnap(col: col, row: row, rem: rem));
    }
    final pc2 = r.u8();
    final powers = <BomberPowerSnap>[];
    for (int i = 0; i < pc2; i++) {
      final col = r.u8();
      final row = r.u8();
      final kind = r.u8();
      powers.add(BomberPowerSnap(col: col, row: row, kind: kind));
    }
    return BomberSnapshot(
      level: level,
      over: over,
      winner: winner,
      gridSeq: gridSeq,
      grid: grid,
      players: players,
      bombs: bombs,
      flames: flames,
      powers: powers,
    );
  }
}

/// 客机 → 主机:本地方向 + 放雷边沿。
class BomberInput {
  final int dirIdx; // 255 = 无
  final bool bomb;
  const BomberInput({required this.dirIdx, required this.bomb});

  Uint8List encode() {
    final w = _ByteWriter();
    w.u8(kBomberMsgInput);
    w.u8(dirIdx & 0xFF);
    w.u8(bomb ? 1 : 0);
    return Uint8List.fromList(w.b);
  }

  static BomberInput? decode(Uint8List d) {
    if (d.length < 2 || d[0] != kBomberMsgInput) return null;
    final r = _ByteReader(d);
    r.u8(); // 跳过类型字节
    final dirIdx = r.u8();
    final bomb = r.u8() == 1;
    return BomberInput(dirIdx: dirIdx, bomb: bomb);
  }
}
