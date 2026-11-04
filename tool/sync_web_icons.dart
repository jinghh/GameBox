// 以 Android 现有图标为权威源，同步 Web 端图标与 favicon。
// 源: android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png (192px)
// 运行: dart run tool/sync_web_icons.dart
import 'dart:io';

import 'package:image/image.dart';

const String src = 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

void main() {
  final base = decodeImage(File(src).readAsBytesSync());
  if (base == null) {
    print('错误: 找不到源图标 $src');
    exit(1);
  }

  void out(String path, int size) {
    final img =
        copyResize(base, width: size, height: size, interpolation: Interpolation.cubic);
    File(path).writeAsBytesSync(encodePng(img));
    print('wrote $path (${size}x$size)');
  }

  out('web/icons/Icon-192.png', 192);
  out('web/icons/Icon-512.png', 512);
  out('web/icons/Icon-maskable-192.png', 192);
  out('web/icons/Icon-maskable-512.png', 512);
  out('web/favicon.png', 64);
  print('done');
}
