import 'package:flutter/services.dart';

/// 屏幕方向控制。
///
/// 关键背景：MIUI/部分国产 ROM 会忽略 Flutter 的
/// `SystemChrome.setPreferredOrientations`，但原生层的
/// `Activity.setRequestedOrientation` 可靠生效。因此这里通过 MethodChannel
/// 让 Dart 侧直接驱动原生方向，确保各页面（尤其吃豆人竖屏）稳定锁死方向。
enum AppOrientation { portrait, landscape, sensor }

class OrientationChannel {
  static const MethodChannel _c = MethodChannel('app/orientation');

  /// 强制设置方向。失败时静默忽略（不影响主流程）。
  static Future<void> set(AppOrientation o) async {
    final mode = switch (o) {
      AppOrientation.portrait => 'portrait',
      AppOrientation.landscape => 'landscape',
      AppOrientation.sensor => 'sensor',
    };
    try {
      await _c.invokeMethod(mode);
    } catch (_) {
      // 原生通道不可用时忽略，退化为 SystemChrome 行为。
    }
  }
}
