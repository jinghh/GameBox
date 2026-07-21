// 生成开发版图标:读取线上版 ic_launcher(192),右下角叠加红色角标,
// 输出到 dev flavor 资源集 android/app/src/dev/res/mipmap-*/ic_launcher.png。
// 用法:dart run tool/gen_dev_icon.dart
import 'dart:io';

import 'package:image/image.dart';

void main() {
  const resRoot = 'android/app/src/main/res';
  const devRoot = 'android/app/src/dev/res';
  final base = decodePng(
      File('$resRoot/mipmap-xxxhdpi/ic_launcher.png').readAsBytesSync());
  if (base == null) {
    print('错误:找不到主图标 $resRoot/mipmap-xxxhdpi/ic_launcher.png');
    exit(1);
  }
  const sizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final e in sizes.entries) {
    final img = copyResize(base, width: e.value);
    _drawDevBadge(img);
    final dir = '$devRoot/mipmap-${e.key}';
    Directory(dir).createSync(recursive: true);
    File('$dir/ic_launcher.png').writeAsBytesSync(encodePng(img));
    print('wrote $dir/ic_launcher.png (${e.value}x${e.value})');
  }
  print('done');
}

void _drawDevBadge(Image img) {
  final s = img.width;
  final r = (s * 0.17).round();
  final cx = s - r - (s * 0.06).round();
  final cy = s - r - (s * 0.06).round();
  fillCircle(img, x: cx, y: cy, radius: r, color: ColorRgba8(235, 40, 40, 255));
  drawCircle(img, x: cx, y: cy, radius: r, color: ColorRgba8(255, 255, 255, 255));
}
