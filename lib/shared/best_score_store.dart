import 'package:shared_preferences/shared_preferences.dart';

/// 最高分 / 最佳成绩本地持久化（跨启动保留）。纯单机离线，无任何网络。
///
/// 用法：key 按游戏区分，如 `best_2048` / `best_snake` / `best_mine_easy`。
/// 「越大越好」用 [setIfGreater]（分数）；「越小越好」用 [setIfSmaller]（通关时间）。
class BestScoreStore {
  static SharedPreferences? _prefs;

  /// 在 runApp 前或进入相关页面前调用一次即可；幂等。
  static Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static int get(String key) => _prefs?.getInt(key) ?? 0;

  /// 是否存在记录（用于"越小越好"时区分"未通关"与"0"）。
  static bool has(String key) => _prefs?.containsKey(key) ?? false;

  /// 仅当高于已存值时写入，返回是否破纪录。
  static Future<bool> setIfGreater(String key, int value) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    final old = prefs.getInt(key) ?? 0;
    if (value > old) {
      await prefs.setInt(key, value);
      return true;
    }
    return false;
  }

  /// 仅当小于已存值（或无记录）时写入，返回是否破纪录。用于最快时间。
  static Future<bool> setIfSmaller(String key, int value) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    final old = prefs.getInt(key);
    if (old == null || value < old) {
      await prefs.setInt(key, value);
      return true;
    }
    return false;
  }
}
