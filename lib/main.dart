// 经典小游戏 —— 纯单机离线游戏集合（坦克大战 / 2048 / 贪吃蛇 / 扫雷）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/build_mode.dart';
import 'app/theme.dart';
import 'debug/debug_overlay.dart';
import 'home/home_page.dart';
import 'shared/best_score_store.dart';
import 'shared/sound_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 纯移动端：锁定竖屏
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  // 预热本地存储（最高分持久化），在各游戏页读取前就绪
  await BestScoreStore.ensureLoaded();
  await SoundStore.load(); // 全局静音开关
  runApp(const MiniGamesApp());
}

class MiniGamesApp extends StatelessWidget {
  const MiniGamesApp({super.key});

  // 根 Navigator 的 key:DebugOverlay 挂在 MaterialApp.builder 中,
  // 其 context 上方没有 Navigator(Navigator 是它的 child),无法直接 showDialog。
  // 用此 key 的 currentContext 命中 Navigator.of 的「自身即 Navigator」特判。
  static final GlobalKey<NavigatorState> navKey =
      GlobalKey<NavigatorState>(debugLabel: 'rootNav');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAMEBOX',
      debugShowCheckedModeBanner: false,
      theme: kAppTheme,
      navigatorKey: navKey,
      builder: (ctx, child) => kIsDev
          ? DebugOverlay(navigatorKey: navKey, child: child!)
          : child!,
      home: const HomePage(),
    );
  }
}
