import 'package:flutter/widgets.dart';

import '../app/build_mode.dart';
import 'game_debug.dart';

/// 当前活动游戏的调试句柄(全局单例)。
///
/// 游戏页 State 通过 [GameDebugMixin] 在 initState 注册、dispose 注销;
/// 调试面板监听它来显示当前游戏信息。
final ValueNotifier<GameDebug?> kActiveGameDebug =
    ValueNotifier<GameDebug?>(null);

/// 游戏 State 混入此 mixin,即自动注册/注销为当前活动游戏,并强制实现 [GameDebug]。
///
/// 仅开发包注册(`kIsDev` 守卫),线上包零开销。
mixin GameDebugMixin<T extends StatefulWidget> on State<T>
    implements GameDebug {
  @override
  void initState() {
    super.initState();
    if (kIsDev) kActiveGameDebug.value = this;
  }

  @override
  void dispose() {
    if (identical(kActiveGameDebug.value, this)) {
      kActiveGameDebug.value = null;
    }
    super.dispose();
  }
}
