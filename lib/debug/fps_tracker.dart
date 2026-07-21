import 'package:flutter/foundation.dart';

/// 全局 FPS 采集(纯逻辑):由持有 [Ticker] 的 widget 每帧回调 [onFrame]。
///
/// 每 500ms 更新一次 [fps] / [frameMs],并通过 [label] 通知监听者刷新文本。
class FpsTracker {
  FpsTracker._();
  static final FpsTracker instance = FpsTracker._();

  /// 形如 "60 fps · 16.7ms",供悬浮按钮/面板直接显示。
  final ValueNotifier<String> label = ValueNotifier<String>('-- fps');

  double fps = 0;
  double frameMs = 0;

  int _frames = 0;
  Duration _acc = Duration.zero;

  /// [dt] 为本帧相对上一帧的间隔。
  void onFrame(Duration dt) {
    if (dt == Duration.zero) return;
    _frames++;
    _acc += dt;
    if (_acc.inMilliseconds >= 500) {
      final s = _acc.inMicroseconds / 1e6;
      fps = _frames / s;
      frameMs = _frames > 0 ? s * 1000 / _frames : 0;
      label.value = '${fps.toStringAsFixed(0)} fps · ${frameMs.toStringAsFixed(1)}ms';
      _frames = 0;
      _acc = Duration.zero;
    }
  }
}
