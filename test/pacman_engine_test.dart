import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:tank_app/games/pacman/pacman_map.dart';
import 'package:tank_app/games/pacman/pacman_entities.dart';

/// 经典幽灵模式时间表（与 pacman_game.dart 保持一致）。
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

// 移动逻辑直接复用生产代码的 stepMover，避免测试复制实现与线上逻辑漂移。
void step(Mover m, PacManMap map, double dt, bool isGhost,
    Dir? Function(int, int, Dir) choose, void Function(int, int) onCenter) {
  stepMover(m, map, dt, isGhost, choose, onCenter);
}

class Sim {
  late PacManMap map;
  late PacMan pac;
  late List<Ghost> ghosts;
  double elapsed = 0;
  int level = 1;
  int phaseIndex = 0;
  GhostMode phaseMode = GhostMode.scatter;
  double phaseTimer = 7;
  double frightenedTimer = 0;
  int ghostEatChain = 200;
  final Random rand = Random(42);

  Sim() {
    reset();
  }

  void reset() {
    map = PacManMap();
    pac = PacMan(
      x: PacManMap.pacStartX,
      y: PacManMap.pacStartY,
      dir: Dir.left,
      pending: Dir.none,
    );
    ghosts = [
      Ghost(
        name: GhostName.blinky,
        x: 13,
        y: 11,
        dir: Dir.left,
        mode: phaseMode,
        speed: 7,
        releaseAt: 0,
      ),
      Ghost(
        name: GhostName.pinky,
        x: 13,
        y: 14,
        dir: Dir.up,
        mode: GhostMode.house,
        speed: 7,
        releaseAt: 2,
      ),
      Ghost(
        name: GhostName.inky,
        x: 11,
        y: 14,
        dir: Dir.up,
        mode: GhostMode.house,
        speed: 7,
        releaseAt: 5,
      ),
      Ghost(
        name: GhostName.clyde,
        x: 16,
        y: 14,
        dir: Dir.up,
        mode: GhostMode.house,
        speed: 7,
        releaseAt: 8,
      ),
    ];
  }

  Dir? choosePac(int tx, int ty, Dir cur) {
    if (pac.pending != Dir.none &&
        map.isWalkable(tx + pac.pending.dx, ty + pac.pending.dy, false)) {
      final d = pac.pending;
      pac.pending = Dir.none;
      return d;
    }
    if (map.isWalkable(tx + cur.dx, ty + cur.dy, false)) return cur;
    return null;
  }

  ({double x, double y}) ghostTarget(Ghost g) {
    switch (g.mode) {
      case GhostMode.house:
      case GhostMode.leaving:
        return (
          x: PacManMap.doorExitX.toDouble(),
          y: PacManMap.doorExitY.toDouble()
        );
      case GhostMode.eyes:
        return (
          x: PacManMap.houseX.toDouble(),
          y: PacManMap.houseY.toDouble()
        );
      case GhostMode.frightened:
        return (
          x: PacManMap.doorExitX.toDouble(),
          y: PacManMap.doorExitY.toDouble()
        );
      case GhostMode.scatter:
        return scatterCorner(g.name);
      case GhostMode.chase:
        return chaseTarget(g);
    }
  }

  ({double x, double y}) scatterCorner(GhostName n) => switch (n) {
        GhostName.blinky => (x: PacManMap.cols - 2.0, y: 0),
        GhostName.pinky => (x: 1.0, y: 0),
        GhostName.inky => (x: PacManMap.cols - 1.0, y: PacManMap.rows - 1.0),
        GhostName.clyde => (x: 0.0, y: PacManMap.rows - 1.0),
      };

  ({double x, double y}) chaseTarget(Ghost g) {
    final px = pac.x;
    final py = pac.y;
    final pdx = pac.dir.dx;
    final pdy = pac.dir.dy;
    return switch (g.name) {
      GhostName.blinky => (x: px, y: py),
      GhostName.pinky => (x: px + 4 * pdx, y: py + 4 * pdy),
      GhostName.inky => (() {
          final blinky = ghosts.firstWhere((e) => e.name == GhostName.blinky);
          final pivotX = px + 2 * pdx;
          final pivotY = py + 2 * pdy;
          return (x: 2 * pivotX - blinky.x, y: 2 * pivotY - blinky.y);
        })(),
      GhostName.clyde => () {
          final d = sqrt(sqDist(g.x, g.y, px, py));
          if (d > 8) return (x: px, y: py);
          return scatterCorner(GhostName.clyde);
        }(),
    };
  }

  Dir chooseGhost(Ghost g, int tx, int ty, Dir cur) {
    final door = g.mode == GhostMode.leaving || g.mode == GhostMode.eyes;
    if (g.mode == GhostMode.frightened) {
      final opts = [Dir.up, Dir.left, Dir.down, Dir.right]..remove(cur.opposite);
      final valid = opts
          .where((d) => map.isWalkable(tx + d.dx, ty + d.dy, door))
          .toList();
      if (valid.isEmpty) return cur.opposite;
      return valid[rand.nextInt(valid.length)];
    }
    final t = ghostTarget(g);
    final opts = [Dir.up, Dir.left, Dir.down, Dir.right]..remove(cur.opposite);
    final valid = opts
        .where((d) => map.isWalkable(tx + d.dx, ty + d.dy, door))
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

  void stepHouse(Ghost g, double dt) {
    step(g, map, dt, true, (tx, ty, cur) {
      if (cur == Dir.up && ty <= 14) return Dir.down;
      if (cur == Dir.down && ty >= 16) return Dir.up;
      if (map.isWalkable(tx + cur.dx, ty + cur.dy, true)) return cur;
      return cur == Dir.up ? Dir.down : Dir.up;
    }, (_, _) {});
  }

  void updateGhost(Ghost g, double dt) {
    if (g.mode == GhostMode.house) {
      if (elapsed >= g.releaseAt) {
        g.mode = GhostMode.leaving;
      } else {
        stepHouse(g, dt);
        return;
      }
    }
    if (g.mode == GhostMode.leaving) {
      if (g.y.round() <= PacManMap.doorExitY) g.mode = phaseMode;
    }
    if (g.mode == GhostMode.eyes) {
      final tx = g.x.round();
      final ty = g.y.round();
      if (ty >= 13 && tx >= 10 && tx <= 17 && map.tileAt(tx, ty) == Tile.empty) {
        g.mode = GhostMode.leaving;
      }
    }
    final mul = 1 + 0.03 * (level - 1);
    final base = g.baseSpeed * mul;
    g.speed = g.mode == GhostMode.frightened
        ? base * 0.6
        : (g.mode == GhostMode.eyes ? 14.0 : base);
    final canUseDoor =
        g.mode == GhostMode.leaving || g.mode == GhostMode.eyes;
    step(g, map, dt, canUseDoor, (tx, ty, cur) => chooseGhost(g, tx, ty, cur),
        (_, _) {});
  }

  void updatePlay(double dt) {
    elapsed += dt;
    if (frightenedTimer > 0) {
      frightenedTimer -= dt;
    } else {
      phaseTimer -= dt;
      if (phaseTimer <= 0 && phaseIndex < _phases.length - 1) {
        phaseIndex++;
        phaseMode = _phases[phaseIndex].$1;
        phaseTimer = _phases[phaseIndex].$2;
      }
    }
    step(pac, map, dt, false, choosePac, (_, _) {});
    for (final g in ghosts) {
      updateGhost(g, dt);
    }
  }
}

void boundsTest() {
  final sim = Sim();
  final dt = 1 / 60;
  bool ok = true;
  String fail = '';
  int failFrame = -1;
  for (int i = 0; i < 60 * 30 && ok; i++) {
    sim.updatePlay(dt);
    for (final g in sim.ghosts) {
      if (g.x < 0 || g.x >= PacManMap.cols || g.y < 0 || g.y >= PacManMap.rows) {
        ok = false;
        fail = 'ghost ${g.name} OOB @frame$i pos=(${g.x},${g.y})';
        failFrame = i;
        break;
      }
      final t = sim.map.tileAt(g.x.round(), g.y.round());
      if (t == Tile.wall) {
        ok = false;
        fail = 'ghost ${g.name} IN WALL @frame$i pos=(${g.x.toStringAsFixed(2)},${g.y.toStringAsFixed(2)})';
        failFrame = i;
        break;
      }
    }
    if (!ok) break;
    if (sim.pac.x < 0 ||
        sim.pac.x >= PacManMap.cols ||
        sim.pac.y < 0 ||
        sim.pac.y >= PacManMap.rows) {
      ok = false;
      fail = 'pac OOB @frame$i pos=(${sim.pac.x},${sim.pac.y})';
      failFrame = i;
      break;
    }
  }
  expect(ok, isTrue, reason: '第 $failFrame 帧越界/穿墙: $fail');
  // 鬼屋内部：row 12..16, col 11..16（含门 row12）。30s 后不应有鬼滞留其中。
  final trapped = sim.ghosts
      .where((g) =>
          g.y > 11.5 && g.y < 16.5 && g.x > 10.5 && g.x < 16.5)
      .map((g) => '${g.name}(${g.x.toStringAsFixed(1)},${g.y.toStringAsFixed(1)}:${g.mode})')
      .toList();
  expect(trapped, isEmpty, reason: '鬼屋滞留: ${trapped.join(', ')}');
}

void inputTest() {
  final sim = Sim();
  final dt = 1 / 60;
  for (int i = 0; i < 5; i++) {
    sim.updatePlay(dt);
  }
  sim.pac.pending = Dir.right;
  bool turned = false;
  for (int i = 0; i < 300; i++) {
    sim.updatePlay(dt);
    if (sim.pac.dir == Dir.right) turned = true;
  }
  expect(turned, isTrue,
      reason: '吃豆人未响应 right 输入, dir=${sim.pac.dir}');
}

void main() {
  test('30s 模拟内实体不越界/不穿墙，且无鬼滞留鬼屋', boundsTest);
  test('吃豆人响应 right 输入并转向', inputTest);
}
