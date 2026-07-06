import 'package:flutter/material.dart';

/// 合集应用统一主题：暗色 + 琥珀(#FFD54A) seed，Material 3。
/// 各游戏内部若有自定义配色（如坦克的全屏深色）不受影响。
final ThemeData kAppTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF1A1A1A),
  fontFamily: 'monospace',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFFFD54A),
    brightness: Brightness.dark,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1A1A1A),
    foregroundColor: Color(0xFFFFD54A),
    elevation: 0,
    centerTitle: true,
  ),
);
