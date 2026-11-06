// 飞机大战精灵图流水线：从三张设计稿裁出各机型的火焰动画帧。
//
// 处理步骤（跑一次即可，产物提交进仓库，游戏运行时零处理）：
//   1. 按像素框裁切（设计稿 2752x1536，标注文字不进框）
//   2. 从四边 flood fill 去掉棋盘格背景（灰度 + 通道差判定），保留机身内部浅色
//   3. 只保留主要连通区域，自动丢弃 "Frame 1" 之类的标注文字与杂点
//   4. 裁掉透明留白，再按组统一画布居中，保证同一机型多帧对齐
//   5. 旋转到游戏朝向（敌机朝下、Boss 朝下、玩家朝上），等比缩放到目标分辨率
//
// 用法：
//   dart run tool/gen_plane_sprites.dart            # 生成 assets/image/plane/*.png
//   dart run tool/gen_plane_sprites.dart --preview  # 额外输出 TEMP 下的拼图预览
//
// 注意：tool/ 已在 analysis_options.yaml 排除，不参与 flutter analyze。

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const String _srcDir = 'assets/image';
const String _outDir = 'assets/image/plane';

class FrameSpec {
  const FrameSpec({
    required this.file,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotate = 0,
  });

  final String file;
  final int x, y, w, h;

  /// 顺时针旋转角度：90 = 机头朝右转成朝下；180 = 机头朝上转成朝下。
  /// image 包的 copyRotate 正角度为顺时针。
  final int rotate;
}

class GroupSpec {
  const GroupSpec({
    required this.id,
    required this.maxSide,
    required this.frames,
  });

  final String id;
  final int maxSide;
  final List<FrameSpec> frames;
}

// 裁切框来自 `--boxes` 的前景投影检测结果 + 少量安全边，
// 保证机翼、尾焰不被切掉；标注文字由连通域过滤自动剔除。
const List<GroupSpec> _groups = [
  // 图 1 第一行：侦察机（机头朝右 → 顺时针转 90° 朝下）
  GroupSpec(id: 'enemy_scout', maxSide: 160, frames: [
    FrameSpec(file: 'plane-1.jpg', x: 834, y: 39, w: 419, h: 370, rotate: 90),
    FrameSpec(file: 'plane-1.jpg', x: 1504, y: 39, w: 407, h: 370, rotate: 90),
  ]),
  // 图 1 第二行：摆动型（三帧火焰）
  GroupSpec(id: 'enemy_zigzag', maxSide: 144, frames: [
    FrameSpec(file: 'plane-1.jpg', x: 822, y: 560, w: 447, h: 406, rotate: 90),
    FrameSpec(file: 'plane-1.jpg', x: 1460, y: 558, w: 443, h: 408, rotate: 90),
    FrameSpec(file: 'plane-1.jpg', x: 2068, y: 573, w: 385, h: 393, rotate: 90),
  ]),
  // 图 1 第三行：重装型（机头朝上 → 转 180° 朝下）
  GroupSpec(id: 'enemy_heavy', maxSide: 192, frames: [
    FrameSpec(file: 'plane-1.jpg', x: 894, y: 1039, w: 448, h: 477, rotate: 180),
    FrameSpec(file: 'plane-1.jpg', x: 1508, y: 1039, w: 448, h: 477, rotate: 180),
    FrameSpec(file: 'plane-1.jpg', x: 2063, y: 1014, w: 448, h: 502, rotate: 180),
  ]),
  // 图 2 STYLE A：重装机械 Boss（两帧并排）。
  // 两架机翼几乎占满整幅，按画布中线一分为二才不会切掉翼尖；
  // 中线正好落在两架之间的空隙里。y 只取上半幅，避开 STYLE B。
  GroupSpec(id: 'boss', maxSide: 512, frames: [
    FrameSpec(file: 'plane-2.jpg', x: 0, y: 55, w: 1376, h: 830, rotate: 180),
    FrameSpec(file: 'plane-2.jpg', x: 1376, y: 55, w: 1376, h: 830, rotate: 180),
  ]),
  // 图 2 下半幅 STYLE B：异星生物科技 Boss（两帧）。
  // 同样按中线一分为二；下边界收在底部标注文字之前，尾焰刚好保留。
  GroupSpec(id: 'boss_b', maxSide: 512, frames: [
    FrameSpec(file: 'plane-2.jpg', x: 0, y: 885, w: 1376, h: 645, rotate: 180),
    FrameSpec(file: 'plane-2.jpg', x: 1376, y: 885, w: 1376, h: 645, rotate: 180),
  ]),
  // 图 3 STYLE A：高科技流线型玩家机（机头已朝上，两帧）
  GroupSpec(id: 'player', maxSide: 288, frames: [
    FrameSpec(file: 'plane-3.jpg', x: 72, y: 158, w: 594, h: 1080),
    FrameSpec(file: 'plane-3.jpg', x: 704, y: 158, w: 594, h: 1138),
  ]),
];

void main(List<String> args) {
  final preview = args.contains('--preview');
  if (args.contains('--boxes')) {
    for (final file in ['plane-1.jpg', 'plane-2.jpg', 'plane-3.jpg']) {
      final im = img
          .decodeJpg(File('$_srcDir/$file').readAsBytesSync())!
          .convert(numChannels: 4);
      _removeBackground(im);
      // 图 2 上下两行 Boss 之间几乎相连，限定上半部分才能分出 STYLE A 的两帧
      final bands = _detectBands(
        im,
        horizontal: true,
        gap: 25,
        minSize: 60,
        to: file == 'plane-2.jpg' ? 860 : null,
      );
      stdout.writeln('== $file');
      for (var r = 0; r < bands.length; r++) {
        final band = bands[r];
        final cols = _detectBands(
          im,
          horizontal: false,
          gap: 25,
          minSize: 40,
          from: band.start,
          to: band.end,
        );
        for (var c = 0; c < cols.length; c++) {
          final box = _foregroundBox(im, band.start, band.end, cols[c].start,
              cols[c].end);
          if (box == null) continue;
          stdout.writeln('row=$r col=$c '
              'x=${box.$1} y=${box.$2} w=${box.$3} h=${box.$4}');
        }
      }
    }
    return;
  }
  Directory(_outDir).createSync(recursive: true);
  final sources = <String, img.Image>{};
  for (final g in _groups) {
    for (final f in g.frames) {
      sources.putIfAbsent(
        f.file,
        () => img.decodeJpg(File('$_srcDir/${f.file}').readAsBytesSync())!,
      );
    }
  }

  final previewFrames = <String, List<img.Image>>{};
  for (final group in _groups) {
    final processed = <img.Image>[];
    for (final f in group.frames) {
      var im = img.copyCrop(
        sources[f.file]!,
        x: f.x,
        y: f.y,
        width: f.w,
        height: f.h,
      );
      // JPG 解码结果是 3 通道，没有 alpha 通道；必须显式转 4 通道，
      // 否则后续 setPixelRgba(..., 0) 会静默失败（背景抠不掉）。
      im = im.convert(numChannels: 4);
      _removeBackground(im);
      _keepMainComponents(im);
      im = _trimTransparent(im);
      if (f.rotate == 90) {
        im = img.copyRotate(im, angle: 90);
      } else if (f.rotate == 180) {
        im = img.copyRotate(im, angle: 180);
      } else if (f.rotate == 270) {
        im = img.copyRotate(im, angle: 270);
      }
      processed.add(im);
    }

    final maxW = processed.map((e) => e.width).reduce(max);
    final maxH = processed.map((e) => e.height).reduce(max);
    final scale = group.maxSide / max(maxW, maxH);
    final canvasW = max(1, (maxW * scale).round());
    final canvasH = max(1, (maxH * scale).round());

    final outFrames = <img.Image>[];
    for (var i = 0; i < processed.length; i++) {
      final resized = img.copyResize(
        processed[i],
        width: max(1, (processed[i].width * scale).round()),
        height: max(1, (processed[i].height * scale).round()),
        interpolation: img.Interpolation.cubic,
      );
      // 机头对齐：玩家机头朝上 → 顶部对齐；敌机/Boss 旋转后机头朝下 → 底部对齐。
      // 火焰长短只会向尾部伸缩，机身不会因为各帧包围盒不同而上下漂移。
      final palette = img.Image(
        width: canvasW,
        height: canvasH,
        numChannels: 4,
      );
      final headUp = group.frames[i].rotate == 0;
      img.compositeImage(
        palette,
        resized,
        dstX: (canvasW - resized.width) ~/ 2,
        dstY: headUp ? 0 : canvasH - resized.height,
      );
      final canvas = palette;
      final path = '$_outDir/${group.id}_${i + 1}.png';
      File(path).writeAsBytesSync(img.encodePng(canvas));
      outFrames.add(canvas);
      stdout.writeln('$path  ${canvas.width}x${canvas.height}'
          '  aspect=${(canvas.width / canvas.height).toStringAsFixed(3)}'
          '  bytes=${img.encodePng(canvas).length}');
    }
    previewFrames[group.id] = outFrames;
  }

  _writeBackground();
  _writeExplosions();

  if (preview) {
    _writePreview(previewFrames);
  }
}

/// 星云背景：等比缩到 720 宽（约 2x 屏幕密度），JPEG 质量 85。
/// 原图 1440x2912 / 2.4MB 直接打包太浪费；运行时仍按世界画布铺满绘制。
void _writeBackground() {
  const src = '$_srcDir/plane-bg.jpg';
  const out = '$_outDir/bg.jpg';
  final file = File(src);
  if (!file.existsSync()) {
    stdout.writeln('skip background: $src not found');
    return;
  }
  final original = img.decodeJpg(file.readAsBytesSync())!;
  final resized = img.copyResize(
    original,
    width: 720,
    interpolation: img.Interpolation.cubic,
  );
  final bytes = img.encodeJpg(resized, quality: 85);
  File(out).writeAsBytesSync(bytes);
  stdout.writeln('$out  ${resized.width}x${resized.height}  bytes=${bytes.length}');
}

/// 从四边泛洪去掉棋盘格背景。只处理与画布边缘连通的灰白像素，
/// 机身内部被描边包围的浅色不会被误删。
void _removeBackground(img.Image im) {
  final w = im.width;
  final h = im.height;
  final visited = Uint8List(w * h);
  final queue = <int>[];

  bool isBg(int idx) {
    final p = im.getPixel(idx % w, idx ~/ w);
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    final mx = max(r, max(g, b));
    final mn = min(r, min(g, b));
    // 设计稿的棋盘格是中性深灰(63/88)与浅灰(229)交替；
    // 下限 45 是为了不把飞机轮廓的深色描边（<40）当成背景啃掉。
    return mx - mn <= 30 && mx >= 45;
  }

  void seed(int x, int y) {
    final idx = y * w + x;
    if (visited[idx] == 1) return;
    if (!isBg(idx)) return;
    visited[idx] = 1;
    queue.add(idx);
  }

  for (var x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }
  while (queue.isNotEmpty) {
    final idx = queue.removeLast();
    final x = idx % w;
    final y = idx ~/ w;
    im.setPixelRgba(x, y, 0, 0, 0, 0);
    if (x > 0) seed(x - 1, y);
    if (x < w - 1) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y < h - 1) seed(x, y + 1);
  }
}

/// 只保留面积足够大的连通区域：机身 + 火焰是最大块，标注文字是小块被丢弃。
void _keepMainComponents(img.Image im) {
  final w = im.width;
  final h = im.height;
  final label = Int32List(w * h)..fillRange(0, w * h, -1);
  final areas = <int>[];
  final stack = <int>[];

  for (var i = 0; i < w * h; i++) {
    if (label[i] != -1) continue;
    if (im.getPixel(i % w, i ~/ w).a == 0) continue;
    final id = areas.length;
    var area = 0;
    label[i] = id;
    stack.add(i);
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      area++;
      final x = idx % w;
      final y = idx ~/ w;
      void tryAdd(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
        final ni = ny * w + nx;
        if (label[ni] != -1) return;
        if (im.getPixel(nx, ny).a == 0) return;
        label[ni] = id;
        stack.add(ni);
      }

      tryAdd(x - 1, y);
      tryAdd(x + 1, y);
      tryAdd(x, y - 1);
      tryAdd(x, y + 1);
    }
    areas.add(area);
  }
  if (areas.isEmpty) return;

  final maxArea = areas.reduce(max);
  // 阈值放宽到 5%：机翼末端的导弹/挂架可能只通过细线与机身相连，
  // 按 15% 过滤会把它们当成杂点删掉，造成机翼残缺。
  final keep = <int>{
    for (var i = 0; i < areas.length; i++)
      if (areas[i] >= maxArea * 0.05) i,
  };
  for (var i = 0; i < w * h; i++) {
    final id = label[i];
    if (id >= 0 && !keep.contains(id)) {
      im.setPixelRgba(i % w, i ~/ w, 0, 0, 0, 0);
    }
  }
}

/// 裁掉四周全透明的留白，保留 2px 安全边。
img.Image _trimTransparent(img.Image im) {
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a <= 8) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return im;
  const pad = 2;
  final x0 = max(0, minX - pad);
  final y0 = max(0, minY - pad);
  final x1 = min(im.width - 1, maxX + pad);
  final y1 = min(im.height - 1, maxY + pad);
  return img.copyCrop(
    im,
    x: x0,
    y: y0,
    width: x1 - x0 + 1,
    height: y1 - y0 + 1,
  );
}

/// 爆炸雪碧图：黑底 4x4 序列（最后一格空），按格切帧并做亮度抠底。
/// 黑底发光素材不适合用颜色键硬切，这里把亮度映射成 alpha，
/// 亮核心不透明、暗烟雾半透明、纯黑背景完全透明。
void _writeExplosions() {
  const src = '$_srcDir/baozha.jpg';
  const int cols = 4;
  const int rows = 4;
  const int maxSide = 192;
  final file = File(src);
  if (!file.existsSync()) {
    stdout.writeln('skip explosions: $src not found');
    return;
  }
  final im = img.decodeJpg(file.readAsBytesSync())!;
  final cellW = im.width ~/ cols;
  final cellH = im.height ~/ rows;
  final frames = <img.Image>[];

  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      var cell = img.copyCrop(
        im,
        x: col * cellW,
        y: row * cellH,
        width: cellW,
        height: cellH,
      ).convert(numChannels: 4);
      _removeBlackBackground(cell);
      if (_opaqueArea(cell) < 300) continue; // 空白格
      cell = _trimTransparent(cell);
      frames.add(cell);
    }
  }
  if (frames.isEmpty) return;

  final maxW = frames.map((e) => e.width).reduce(max);
  final maxH = frames.map((e) => e.height).reduce(max);
  final scale = maxSide / max(maxW, maxH);
  final canvasW = (maxW * scale).round();
  final canvasH = (maxH * scale).round();

  for (var i = 0; i < frames.length; i++) {
    final resized = img.copyResize(
      frames[i],
      width: (frames[i].width * scale).round(),
      height: (frames[i].height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
    final canvas = img.Image(
      width: canvasW,
      height: canvasH,
      numChannels: 4,
    );
    img.compositeImage(
      canvas,
      resized,
      dstX: (canvasW - resized.width) ~/ 2,
      dstY: (canvasH - resized.height) ~/ 2,
    );
    final name = (i + 1).toString().padLeft(2, '0');
    final path = '$_outDir/explosion_$name.png';
    File(path).writeAsBytesSync(img.encodePng(canvas));
  }
  stdout.writeln('explosions: ${frames.length} frames, '
      '${canvasW}x$canvasH');
}

void _removeBlackBackground(img.Image im) {
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final mx = max(r, max(g, b));
      if (mx <= 16) {
        im.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      final a = ((mx - 12) * 5).clamp(0, 255).toInt();
      im.setPixelRgba(x, y, r, g, b, a);
    }
  }
}

int _opaqueArea(img.Image im) {
  var n = 0;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a > 16) n++;
    }
  }
  return n;
}

class _Band {
  const _Band(this.start, this.end);
  final int start, end;
}

/// 按行/列的前景像素投影切出行带或列带，用于自动定位每架飞机的包围盒。
List<_Band> _detectBands(
  img.Image im, {
  required bool horizontal,
  required int gap,
  required int minSize,
  int? from,
  int? to,
}) {
  if (horizontal) {
    final counts = List<int>.filled(im.height, 0);
    final y0 = from ?? 0;
    final y1 = to ?? im.height;
    for (var y = y0; y < y1; y++) {
      var n = 0;
      for (var x = 0; x < im.width; x += 2) {
        if (im.getPixel(x, y).a > 8) n++;
      }
      counts[y] = n;
    }
    return _bandsFromCounts(counts, gap, minSize);
  }
  final counts = List<int>.filled(im.width, 0);
  final y0 = from ?? 0;
  final y1 = to ?? im.height;
  for (var x = 0; x < im.width; x++) {
    var n = 0;
    for (var y = y0; y < y1; y += 2) {
      if (im.getPixel(x, y).a > 8) n++;
    }
    counts[x] = n;
  }
  return _bandsFromCounts(counts, gap, minSize);
}

List<_Band> _bandsFromCounts(List<int> counts, int gap, int minSize) {
  final bands = <_Band>[];
  int? start;
  var last = -1;
  for (var i = 0; i < counts.length; i++) {
    if (counts[i] <= 3) continue;
    if (start == null) {
      start = i;
    } else if (i - last > gap) {
      if (last - start + 1 >= minSize) bands.add(_Band(start, last));
      start = i;
    }
    last = i;
  }
  if (start != null && last - start + 1 >= minSize) {
    bands.add(_Band(start, last));
  }
  return bands;
}

/// 在给定窗口内求不透明像素的紧密包围盒。
(int, int, int, int)? _foregroundBox(
  img.Image im,
  int y0,
  int y1,
  int x0,
  int x1,
) {
  var minX = x1;
  var maxX = x0;
  var minY = y1;
  var maxY = y0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      if (im.getPixel(x, y).a <= 8) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < minX || maxY < minY) return null;
  return (minX, minY, maxX - minX + 1, maxY - minY + 1);
}

/// 深色底拼图预览，便于人工核对裁切与朝向。
void _writePreview(Map<String, List<img.Image>> frames) {
  const rowH = 150;
  const padX = 16;
  const padY = 10;
  final rows = <List<img.Image>>[];
  var maxW = 0;
  for (final list in frames.values) {
    final scaled = <img.Image>[];
    for (final f in list) {
      final s = rowH / f.height;
      scaled.add(img.copyResize(
        f,
        width: max(1, (f.width * s).round()),
        height: rowH,
        interpolation: img.Interpolation.cubic,
      ));
    }
    rows.add(scaled);
    final rowW = scaled.fold<int>(0, (a, b) => a + b.width + padX) + padX;
    if (rowW > maxW) maxW = rowW;
  }
  final height = rows.length * (rowH + padY) + padY;
  final out = img.Image(width: maxW, height: height, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(12, 22, 44, 255));
  var y = padY;
  for (final row in rows) {
    var x = padX;
    for (final f in row) {
      img.compositeImage(out, f, dstX: x, dstY: y);
      x += f.width + padX;
    }
    y += rowH + padY;
  }
  final tmp = Platform.environment['TEMP'] ?? Directory.systemTemp.path;
  final path = '$tmp\\plane_sprites_preview.png';
  File(path).writeAsBytesSync(img.encodePng(out));
  stdout.writeln('preview -> $path');
}
