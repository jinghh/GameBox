/// 经典《吃豆人》(Pac-Man) 迷宫与通用常量。
///
/// 坐标系：实体的 (x, y) 以「格子中心」为单位（tile 坐标），即第 (col,row)
/// 格的中心坐标为 (col, row) 的 double 形式。整数即对齐格子中心，
/// 移动时在格子中心处决定转向，避免穿墙。

library;

enum Dir { up, down, left, right, none }

extension DirX on Dir {
  int get dx => this == Dir.left ? -1 : this == Dir.right ? 1 : 0;
  int get dy => this == Dir.up ? -1 : this == Dir.down ? 1 : 0;
  Dir get opposite => switch (this) {
        Dir.up => Dir.down,
        Dir.down => Dir.up,
        Dir.left => Dir.right,
        Dir.right => Dir.left,
        Dir.none => Dir.none,
      };
  /// 经典幽灵 AI 的平局优先级：上 > 左 > 下 > 右。
  int get priority => switch (this) {
        Dir.up => 0,
        Dir.left => 1,
        Dir.down => 2,
        Dir.right => 3,
        Dir.none => 9,
      };
}

/// 格子类型。
class Tile {
  static const int wall = 0;
  static const int pellet = 1;
  static const int energizer = 2;
  static const int empty = 3; // 可走、无豆（含隧道两端与房子内部）
  static const int door = 4; // 鬼门，仅幽灵可走
}

class PacManMap {
  static const int cols = 28;
  static const int rows = 31;

  /// 经典街机布局（28×31）。'#' 墙，'.' 豆，'o' 大力丸，'-' 鬼门，' ' 空路/房子内部。
  /// 第 14 行为左右隧道（两端开口，横向回卷）。
  static const List<String> _rows = [
    '############################',
    '#............##............#',
    '#.####.#####.##.#####.####.#',
    '#o####.#####.##.#####.####o#',
    '#.####.#####.##.#####.####.#',
    '#..........................#',
    '#.####.##.########.##.####.#',
    '#.####.##.########.##.####.#',
    '#......##....##....##......#',
    '######.#####.##.#####.######',
    '######.#####.##.#####.######',
    '######.##..........##.######',
    '######.##.###--###.##.######',
    '######.##.#      #.##.######',
    '      .##.#      #.##.      ',
    '######.##.#      #.##.######',
    '######.##.###--###.##.######',
    '######.##..........##.######',
    '######.#####.##.#####.######',
    '######.#####.##.#####.######',
    '#............##............#',
    '#.####.#####.##.#####.####.#',
    '#.####.#####.##.#####.####.#',
    '#o..##.......  .......##..o#',
    '###.##.##.########.##.##.###',
    '###.##.##.########.##.##.###',
    '#......##....##....##......#',
    '#.##########.##.##########.#',
    '#.##########.##.##########.#',
    '#..........................#',
    '############################',
  ];

  late final List<List<int>> grid;
  late final int totalPellets;

  /// 吃豆人起点（底部中央空路）。
  static const double pacStartX = 13.0;
  static const double pacStartY = 23.0;

  /// 鬼门上方出口格（row11 横向走廊），幽灵离巢/眼睛回巢的目标。
  static const int doorExitX = 14;
  static const int doorExitY = 11;
  /// 房子内部复活点。
  static const int houseX = 13;
  static const int houseY = 14;

  PacManMap() {
    grid = List.generate(rows, (_) => List.filled(cols, Tile.wall));
    int pellets = 0;
    for (int r = 0; r < rows; r++) {
      final row = _rows[r];
      for (int c = 0; c < cols; c++) {
        switch (row[c]) {
          case '#':
            grid[r][c] = Tile.wall;
            break;
          case '.':
            grid[r][c] = Tile.pellet;
            pellets++;
            break;
          case 'o':
            grid[r][c] = Tile.energizer;
            pellets++;
            break;
          case '-':
            grid[r][c] = Tile.door;
            break;
          default:
            grid[r][c] = Tile.empty;
        }
      }
    }
    totalPellets = pellets;
  }

  /// 取格子类型，x 做横向回卷；y 越界视为墙。
  int tileAt(int col, int row) {
    if (row < 0 || row >= rows) return Tile.wall;
    final c = ((col % cols) + cols) % cols;
    return grid[row][c];
  }

  /// [canUseDoor]：仅「在巢/离巢/眼睛回巢」状态的幽灵可穿鬼门；
  /// 追逐/散布/惊惧状态的幽灵与吃豆人都不能穿门（经典规则），
  /// 否则幽灵会反复钻进钻出鬼屋，在门口垂直往返。
  bool isWalkable(int col, int row, bool canUseDoor) {
    final t = tileAt(col, row);
    if (t == Tile.wall) return false;
    if (t == Tile.door) return canUseDoor;
    return true;
  }

  /// 调试用：返回所有无法从吃豆人起点到达的豆子数量（应为 0）。
  int unreachablePellets() {
    final seen = List.generate(rows, (_) => List.filled(cols, false));
    final q = <(int, int)>[];
    final sx = pacStartX.round();
    final sy = pacStartY.round();
    seen[sy][sx] = true;
    q.add((sx, sy));
    final dirs = [
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1),
    ];
    while (q.isNotEmpty) {
      final (x, y) = q.removeLast();
      for (final (dx, dy) in dirs) {
        final nx = ((x + dx) % cols + cols) % cols;
        final ny = y + dy;
        if (ny < 0 || ny >= rows) continue;
        if (seen[ny][nx]) continue;
        if (!isWalkable(nx, ny, false)) continue;
        seen[ny][nx] = true;
        q.add((nx, ny));
      }
    }
    int bad = 0;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if ((grid[r][c] == Tile.pellet || grid[r][c] == Tile.energizer) &&
            !seen[r][c]) {
          bad++;
        }
      }
    }
    return bad;
  }
}
