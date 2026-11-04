import 'pacman_map.dart';

/// 移动体的最小接口，供通用步进函数复用。
abstract class Mover {
  double get x;
  set x(double v);
  double get y;
  set y(double v);
  Dir get dir;
  set dir(Dir v);
  double get speed;
}

enum GhostName { blinky, pinky, inky, clyde }

enum GhostMode { house, leaving, scatter, chase, frightened, eyes }

class PacMan implements Mover {
  @override
  double x;
  @override
  double y;
  @override
  Dir dir;
  Dir pending;
  @override
  final double speed;

  PacMan({
    required this.x,
    required this.y,
    this.dir = Dir.left,
    this.pending = Dir.none,
    this.speed = 8.0,
  });
}

class Ghost implements Mover {
  final GhostName name;
  @override
  double x;
  @override
  double y;
  @override
  Dir dir;
  Dir pending;
  @override
  double speed;
  final double baseSpeed; // 固定基础速度，避免每帧以 speed 为基准导致衰减
  GhostMode mode;
  final int releaseAt; // 出场延迟（秒）

  Ghost({
    required this.name,
    required this.x,
    required this.y,
    this.dir = Dir.up,
    this.pending = Dir.none,
    this.speed = 7.0,
    this.baseSpeed = 7.0,
    this.mode = GhostMode.house,
    this.releaseAt = 0,
  });
}

/// 渲染所需的瞬时视图数据（painter 只读）。
class PacManView {
  final List<List<int>> grid;
  final PacMan pac;
  final List<Ghost> ghosts;
  final double mouthPhase;
  final double dying; // 0..1，>0 表示死亡收缩动画
  final double energizerPulse; // 0..1 大力丸呼吸
  final bool frightenedFlash;

  PacManView({
    required this.grid,
    required this.pac,
    required this.ghosts,
    required this.mouthPhase,
    this.dying = 0,
    required this.energizerPulse,
    this.frightenedFlash = false,
  });
}

/// 计算两点（格坐标）平方距离，用于幽灵目标选取。
double sqDist(double ax, double ay, double bx, double by) {
  final dx = ax - bx;
  final dy = ay - by;
  return dx * dx + dy * dy;
}

/// 格子锁定步进：生产游戏与引擎单测共用的唯一实现，避免两份逻辑漂移。
///
/// 关键修复：实体必须 snap 到格中心才能做方向决策与墙体检测。
/// 旧实现用 round() 判中心，因步长与格距不成整数倍，浮点累加永远跳过分格
/// 整数点，导致既不检测墙体、也不处理转向输入。
/// 现实现用 floor() 取当前格、以「移动方向上的下一个格中心」为目标，到达即 snap。
void stepMover(
  Mover m,
  PacManMap map,
  double dt,
  bool canUseDoor,
  Dir? Function(int, int, Dir) choose,
  void Function(int, int) onCenter,
) {
  double dist = m.speed * dt;
  int guard = 0;
  while (dist > 1e-6 && guard++ < 256) {
    final cx = m.x.floor();
    final cy = m.y.floor();
    final cxCenter = cx.toDouble();
    final cyCenter = cy.toDouble();
    final atCenter =
        (m.x - cxCenter).abs() < 1e-6 && (m.y - cyCenter).abs() < 1e-6;
    if (atCenter) {
      m.x = cxCenter;
      m.y = cyCenter;
      final chosen = choose(cx, cy, m.dir);
      if (chosen != null) m.dir = chosen;
      if (m.dir == Dir.none) break;
      if (!map.isWalkable(cx + m.dir.dx, cy + m.dir.dy, canUseDoor)) {
        m.dir = Dir.none;
        break;
      }
    }
    double targetX = m.x;
    double targetY = m.y;
    if (m.dir == Dir.left) {
      targetX = m.x.ceilToDouble() - 1;
    } else if (m.dir == Dir.right) {
      targetX = m.x.floorToDouble() + 1;
    } else if (m.dir == Dir.up) {
      targetY = m.y.ceilToDouble() - 1;
    } else {
      targetY = m.y.floorToDouble() + 1;
    }
    final moveDist = (m.dir == Dir.left || m.dir == Dir.right)
        ? (targetX - m.x).abs()
        : (targetY - m.y).abs();
    if (moveDist <= dist) {
      m.x = targetX;
      m.y = targetY;
      dist -= moveDist;
      if (m.x < 0) {
        m.x += PacManMap.cols;
      } else if (m.x >= PacManMap.cols) {
        m.x -= PacManMap.cols;
      }
      onCenter(m.x.round(), m.y.round());
    } else {
      if (m.dir == Dir.left) {
        m.x -= dist;
      } else if (m.dir == Dir.right) {
        m.x += dist;
      } else if (m.dir == Dir.up) {
        m.y -= dist;
      } else {
        m.y += dist;
      }
      dist = 0;
    }
  }
}
