# GameBox

纯单机离线的 Flutter 小游戏合集，主要面向 Android。画面全部由 `CustomPaint` 手绘，无网络请求、无广告、无图片素材。

## 下载安装

**[下载最新 Android 安装包 GameBox.apk](https://github.com/jinghh/GameBox/releases/latest)**

每次推送到 `master`，GitHub Actions 会自动构建 prod release APK 并更新 `latest` Release；推送 `v*` 标签会额外生成带版本号的正式 Release。也可以在 Actions 页面手动触发构建。

- 手机：下载 `GameBox.apk`，允许「安装未知来源应用」后点击安装
- adb：`adb install -r GameBox.apk`

包名 `com.jhh.tank_app`。CI 与本地 Flutter 构建使用的 debug 签名不同，若覆盖安装提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，先卸载旧版再安装。

## 游戏

坦克大战（单人 / 双人 / 蓝牙联机）、泡泡堂、2048、贪吃蛇、扫雷、俄罗斯方块、五子棋、吃豆人、飞机大战。

飞机大战：拖拽或 WASD / 方向键移动、自动射击，火力 / 护盾 / 炸弹 / 生命道具，每 4 波出现 Boss，最高分本地保存。

## 本地开发

```bash
flutter pub get
flutter run
flutter build apk --flavor prod --release   # 线上包 com.jhh.tank_app
flutter build apk --flavor dev --release    # 开发包 com.jhh.tank_app.dev，可与线上版共存
flutter analyze
flutter test
```

修改 Dart 代码后出包前建议先 `flutter clean`，避免增量快照缓存复用旧代码。

## 结构

- `lib/app/games.dart`：游戏注册表 `kGames`，新增游戏只需在列表追加一项
- `lib/games/<游戏>/`：各游戏实现
- `lib/shared/`：音效池、成绩存储、虚拟摇杆、联机等公共模块
- `.github/workflows/release.yml`：自动构建 APK 并发布到 Releases
