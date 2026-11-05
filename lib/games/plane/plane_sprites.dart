// 飞机大战精灵图资源。
//
// 图片由 `dart run tool/gen_plane_sprites.dart` 从设计稿生成后提交进仓库，
// 运行期只做一次解码，之后是 GPU 纹理绘制，不再做任何裁切/缩放运算。
// 解码完成前 painter 会退回几何绘制，所以加载失败不影响游戏可玩性。
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 一帧精灵图。预存源矩形与宽高比，避免绘制时重复计算和分配 Rect。
class SpriteFrame {
  SpriteFrame(this.image)
      : src = ui.Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        aspect = image.width / image.height;

  final ui.Image image;
  final ui.Rect src;
  final double aspect;
}

class PlaneSprites {
  PlaneSprites._(this._frames);

  final Map<String, List<SpriteFrame>> _frames;

  /// 星云背景，独立于机型帧；加载失败时 painter 回退渐变背景。
  SpriteFrame? background;

  static const Map<String, List<String>> _manifest = {
    'player': [
      'assets/image/plane/player_1.png',
      'assets/image/plane/player_2.png',
    ],
    'scout': [
      'assets/image/plane/enemy_scout_1.png',
      'assets/image/plane/enemy_scout_2.png',
    ],
    'zigzag': [
      'assets/image/plane/enemy_zigzag_1.png',
      'assets/image/plane/enemy_zigzag_2.png',
      'assets/image/plane/enemy_zigzag_3.png',
    ],
    'heavy': [
      'assets/image/plane/enemy_heavy_1.png',
      'assets/image/plane/enemy_heavy_2.png',
      'assets/image/plane/enemy_heavy_3.png',
    ],
    'boss': [
      'assets/image/plane/boss_1.png',
      'assets/image/plane/boss_2.png',
    ],
  };

  bool get isEmpty => _frames.isEmpty && background == null;

  /// 逐帧加载；单帧失败只跳过该帧，painter 会退回几何绘制。
  static Future<PlaneSprites> load() async {
    final map = <String, List<SpriteFrame>>{};
    for (final entry in _manifest.entries) {
      final list = <SpriteFrame>[];
      for (final asset in entry.value) {
        try {
          final data = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          try {
            final frame = await codec.getNextFrame();
            list.add(SpriteFrame(frame.image));
          } finally {
            codec.dispose();
          }
        } on Object {
          // 忽略单帧加载失败，不影响其余帧与游戏逻辑
        }
      }
      if (list.isNotEmpty) map[entry.key] = list;
    }
    final sprites = PlaneSprites._(map);
    try {
      final data = await rootBundle.load('assets/image/plane/bg.jpg');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      try {
        final frame = await codec.getNextFrame();
        sprites.background = SpriteFrame(frame.image);
      } finally {
        codec.dispose();
      }
    } on Object {
      // 背景缺失时 painter 使用渐变兜底，不影响游戏
    }
    return sprites;
  }

  /// 按时间取动画帧：火焰状态循环播放。
  SpriteFrame? pick(String id, double time, double fps) {
    final list = _frames[id];
    if (list == null || list.isEmpty) return null;
    final i = (time * fps).floor() % list.length;
    return list[i];
  }

  void dispose() {
    for (final list in _frames.values) {
      for (final frame in list) {
        frame.image.dispose();
      }
    }
    _frames.clear();
    background?.image.dispose();
    background = null;
  }
}
