/// 各游戏向全局调试面板暴露的状态与操作。
///
/// 仅在开发包通过 [GameDebugMixin] 实例化;线上包无任何实现/调用。
abstract class GameDebug {
  /// 游戏标识(对应 GameSpec.id,如 'bomber' / 'tank')。
  String get id;

  /// 自由键值对,渲染成调试面板的信息表(关卡/得分/状态等)。
  Map<String, String> info();

  /// 当前关卡;`null` 表示该游戏没有关卡概念(调试面板隐藏跳关区)。
  int? get currentLevel;

  /// 最大关卡数;`null` 表示无尽模式。用于跳关输入的范围提示。
  int? get maxLevel;

  /// 跳到第 n 关。仅关卡游戏实现;无关卡的游戏面板不会调用此方法。
  void jumpToLevel(int n);
}
