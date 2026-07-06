// 生成应用图标：深色底 + 2×2 彩色方块矩阵（像素风，呼应「经典小游戏」合集）。
// 运行：dart run tool/gen_icon.dart
// 输出：assets/icon.png（带深色背景）、assets/icon_fg.png（透明前景，用于自适应图标）
import 'dart:io';
import 'package:image/image.dart';

const int S = 1024;
const int bw = 300; // 方块边长
const int gap = 44; // 方块间隙
const int start = (S - (bw * 2 + gap)) ~/ 2; // 居中起点 = 190

// 四色取自各游戏 accent：琥珀(坦克) / 绿(蛇) / 蓝(扫雷) / 橙(方块)
const List<List<int>> colors = [
  [255, 213, 74],
  [110, 224, 96],
  [79, 195, 247],
  [255, 162, 38],
];

void drawBlocks(Image img) {
  for (int i = 0; i < 4; i++) {
    final r = i ~/ 2, c = i % 2;
    final x = start + c * (bw + gap);
    final y = start + r * (bw + gap);
    final col = colors[i];
    fillRect(img,
        x1: x,
        y1: y,
        x2: x + bw,
        y2: y + bw,
        color: ColorUint8.rgb(col[0], col[1], col[2]));
    // 顶部高光（半透明白叠加，像素风质感）
    fillRect(img,
        x1: x,
        y1: y,
        x2: x + bw,
        y2: y + (bw * 0.16).toInt(),
        color: ColorUint8.rgba(255, 255, 255, 46));
  }
}

void main() {
  // 1) 完整图标：深色背景 + 方块矩阵
  final full = Image(width: S, height: S);
  fill(full, color: ColorUint8.rgb(22, 22, 28));
  drawBlocks(full);
  File('assets/icon.png').writeAsBytesSync(encodePng(full));

  // 2) 自适应图标前景：透明背景 + 方块矩阵（居中，留出安全区）
  final fg = Image(width: S, height: S);
  fill(fg, color: ColorUint8.rgba(0, 0, 0, 0));
  drawBlocks(fg);
  File('assets/icon_fg.png').writeAsBytesSync(encodePng(fg));

  print('Generated assets/icon.png and assets/icon_fg.png');
}
