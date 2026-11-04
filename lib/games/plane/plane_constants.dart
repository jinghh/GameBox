// 飞机大战 —— 逻辑坐标与数值配置。
// 画布由 [planeTransform] 等比缩放到实际屏幕，游戏逻辑只认 360x640 的世界坐标，
// 因此碰撞、速度、刷怪位置与机型尺寸完全不依赖设备分辨率。
library;

import 'dart:math';

import 'package:flutter/material.dart';

const double kPlaneW = 360.0;
const double kPlaneH = 640.0;

/// 逻辑画布 → 实际画布的等比变换参数（居中，短边适配）。
({double scale, Offset origin}) planeTransform(Size size) {
  final s = min(size.width / kPlaneW, size.height / kPlaneH);
  return (
    scale: s,
    origin: Offset(
      (size.width - kPlaneW * s) / 2,
      (size.height - kPlaneH * s) / 2,
    ),
  );
}

/// HUD 快照。record 按值相等：数值未变时 [ValueNotifier] 不会通知，避免逐帧重建 HUD。
typedef PlaneHud = ({
  int score,
  int best,
  int lives,
  int wave,
  int power,
  int bombs,
});

enum PlanePhase { ready, playing, paused, gameOver }

enum EnemyKind { scout, zigzag, heavy, boss }

enum PowerKind { power, shield, bomb, life }

// ---- 难度曲线 ----
double planeSpawnInterval(int wave) => max(0.34, 1.05 - wave * 0.065);

double planeSpeedScale(int wave) => min(2.1, 1.0 + (wave - 1) * 0.065);

int planeWaveQuota(int wave) => 10 + wave * 2;

int planeBossHp(int wave) => 70 + wave * 12;

const double kPlayerSpeed = 265.0;
const double kPowerFallSpeed = 82.0;
const int kMaxParticles = 360;
const int kBossEveryWaves = 4;
