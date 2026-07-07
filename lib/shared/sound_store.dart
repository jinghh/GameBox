import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局静音开关：[ValueNotifier] 驱动 UI 即时刷新，值持久化（纯本地，无网络）。
/// 所有音效（坦克音效、方块按键音等）播放前都检查 [kMuted]。
final ValueNotifier<bool> kMuted = ValueNotifier(false);

class SoundStore {
  static const String _key = 'global_muted';

  /// 在 runApp 前调用一次（与 BestScoreStore.ensureLoaded 并列）。
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    kMuted.value = p.getBool(_key) ?? false;
  }

  static Future<void> toggle() async {
    kMuted.value = !kMuted.value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, kMuted.value);
  }
}
