// 经典小游戏 —— 纯单机离线游戏集合（坦克大战 / 2048 / 贪吃蛇 / 扫雷）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAMEBOX',
      debugShowCheckedModeBanner: false,
      theme: kAppTheme,
      home: const HomePage(),
    );
  }
}
