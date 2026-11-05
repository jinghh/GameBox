# GameBox

纯单机离线的 Flutter 小游戏合集，面向 Android。9 款游戏的画面全部由 `CustomPaint` 手绘，无网络请求、无账号、无广告、无图片素材；蓝牙联机只在两台手机之间建立点对点连接，不经过服务器。

- 9 款游戏：坦克大战、泡泡堂、2048、贪吃蛇、扫雷、俄罗斯方块、五子棋、吃豆人、飞机大战
- 本地双人同屏、经典蓝牙 SPP 双机联机
- 最高分 / 最佳时间 / 全局静音本地持久化（`SharedPreferences`）
- 音效为代码合成的 WAV，BGM 为实时合成 chiptune，零音频素材版权
- 首页由 `kGames` 注册表驱动，新增游戏只需在列表追加一项

## 目录

- [下载安装](#下载安装)
- [游戏一览](#游戏一览)
- [蓝牙联机](#蓝牙联机)
- [技术栈与架构](#技术栈与架构)
- [本地开发](#本地开发)
- [dev 包与调试面板](#dev-包与调试面板)
- [自动发布](#自动发布)
- [新增游戏](#新增游戏)
- [测试](#测试)
- [常见问题](#常见问题)
- [已知限制](#已知限制)

## 下载安装

**[下载最新 Android 安装包 GameBox.apk](https://github.com/jinghh/GameBox/releases/latest)**

| 项目 | 说明 |
| --- | --- |
| 应用名 / 包名 | GAMEBOX / `com.jhh.tank_app` |
| 当前版本 | `1.0.0+1` |
| 安装方式 | 下载 APK 后允许「安装未知来源应用」；或 `adb install -r GameBox.apk` |
| 屏幕方向 | 全局竖屏锁定（贪吃蛇进入后强制横屏，退出恢复竖屏） |
| 权限 | 仅蓝牙联机需要 `BLUETOOTH_CONNECT`，不做扫描发现，无需定位权限 |

每次推送到 `master`，GitHub Actions 会自动构建 prod release APK 并更新 `latest` Release；推送 `v*` 标签会额外生成带版本号的正式 Release，也可在 Actions 页面手动触发。详见「自动发布」。

release 构建使用 Android debug 签名。CI 与本地各自生成 debug keystore，签名不同；覆盖安装若提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，先卸载旧版再安装。

## 游戏一览

| 游戏 | 玩法 | 操作 | 模式 | 成绩 |
| --- | --- | --- | --- | --- |
| 坦克大战 | Battle City 复刻：闯关、守护基地、共享生命与得分 | 左半屏虚拟摇杆 + 右下开火键（按住连发）；键盘 WASD / 方向键 + 空格 / J；P / Esc 暂停、M 静音 | 单人 / 双人同屏 / 蓝牙联机 | 不记录 |
| 泡泡堂 | 网格移动、放置炸弹十字爆炸、炸砖块与敌人、收集道具、过关递增 | 虚拟摇杆 + 空格 / 回车放雷；键盘 WASD / 方向键 | 单人 / 双人同屏 / 蓝牙 1v1 | 最高分 |
| 2048 | 四向滑动合并相同数字，目标 2048，带滑入与合并动画 | 四向滑动 / 方向键 / WASD | 单人 | 最高分 |
| 贪吃蛇 | 关卡制：吃够目标数量过关，蛇身保留、新增障碍并提速；撞墙 / 自身 / 障碍判负 | 横屏虚拟摇杆 / 方向键 | 单人 | 最高分 |
| 扫雷 | 首次点击安全、0 邻格自动展开、翻开全部非雷格通关 | 点击翻开、长按或旗帜模式插旗 | 单人（简单 / 中等） | 最佳时间 mm:ss |
| 俄罗斯方块 | 下落、旋转、消行、等级提速，堆顶判负 | 屏幕按钮 + 方向键 / WASD / 空格 | 单人 | 最高分 |
| 五子棋 | 15×15 棋盘，横 / 竖 / 斜先连 5 子胜，人机使用启发式 AI | 点击落子，页面内切换人机 / 双人 | 人机 / 双人对弈 | 最高分 |
| 吃豆人 | 迷宫吃豆、幽灵 scatter / chase 交替、能量豆反吃幽灵、经典樱桃 | 虚拟摇杆 + 方向键 / WASD | 单人 | 最高分 |
| 飞机大战 | 竖版弹幕射击：自动开火、3 类敌机、每 4 波 Boss、火力 / 护盾 / 炸弹 / 生命道具 | 拖拽移动 / WASD / 方向键；空格 / B 放炸弹；P / Esc 暂停 | 单人 | 最高分 |

## 蓝牙联机

只有坦克大战和泡泡堂支持，从首页卡片进入「联机版」：

1. 两台手机先在**系统蓝牙设置**里完成配对（一次性）
2. 一台点「创建房间」开始监听
3. 另一台点「加入房间」，从已配对设备列表选择对方
4. 连接成功自动进入对战：host 运行权威模拟，guest 只上报输入并渲染快照

实现链路：Android 原生 Kotlin 经典蓝牙 SPP（标准 SPP UUID，服务名 `TankBattle`）→ MethodChannel / EventChannel → 4 字节长度前缀帧化的 `P2pLink` 抽象。权限只申请 `BLUETOOTH_CONNECT`，旧版本兼容 `BLUETOOTH` / `BLUETOOTH_ADMIN`（`maxSdkVersion=30`）；不做设备扫描，因此不需要定位权限。

## 技术栈与架构

| 项 | 说明 |
| --- | --- |
| 框架 | Flutter stable（本机 3.44.0 / Dart 3.12.0，`environment: sdk: ^3.12.0`），Material 3 暗色主题 |
| 状态 / 路由 | 原生 `StatefulWidget` + `ValueNotifier`，Navigator 1.0；无 Provider / Riverpod / go_router |
| 渲染 | `CustomPaint` 手绘 + `RepaintBoundary` 分层；`shouldRepaint => false`，由 `ValueNotifier` 逐帧驱动重绘，不逐帧 `setState` 整页 |
| 主循环 | `Ticker`（对齐 vsync，坦克 / 飞机）或 `Timer.periodic`（吃豆人等） |
| 资源 | 音效由代码合成；飞机大战使用设计稿裁切的精灵图（`assets/image/plane/`，火焰 2~3 帧循环），其余游戏仍为纯手绘；BGM 由 `bgm_synth.dart` 实时合成 |
| 持久化 | `shared_preferences`，成绩与静音设置仅存本机 |
| 平台 | Android 完整可用；`web/` / `windows/` 仍是 Flutter 模板，未适配蓝牙与方向通道 |

主要依赖：`audioplayers`（音效 / BGM）、`wakelock_plus`（游戏中保持亮屏）、`shared_preferences`（本地存储）、`permission_handler`（蓝牙权限）；开发期 `flutter_lints`、`flutter_launcher_icons`、`image`（仅 `tool/` 图标脚本使用，不进 APK）。

### 目录结构

```
lib/
  main.dart              入口：竖屏锁定、预热本地存储、dev 调试浮层
  app/                   主题、构建模式、游戏注册表 kGames
  home/                  首页网格、多模式入口
  games/<id>/            各游戏：常量 / 实体 / 绘制 / 音效 / 页面
  shared/                音效池、BGM、成绩、摇杆、滑动、外壳、方向、联机
  debug/                 FPS 浮层、跳关面板、调试注册接口
assets/sounds/           代码合成的短音效 wav
assets/image/plane/      飞机大战精灵图（设计稿裁切生成，火焰多帧）
tool/                    构建与素材生成脚本
test/                    注册表冒烟、联机协议、吃豆人引擎
.github/workflows/       APK 自动构建发布
```

`lib/shared/` 常用模块：`best_score_store`（成绩）、`sound_store`（全局静音）、`sfx_pool`（自管 AudioPlayer 池，规避部分 ROM 的 AudioPool native 崩溃）、`bgm_synth`（芯片音乐合成）、`joystick` / `swipe_detector`（输入）、`game_shell`（统一页面外壳 + 返回确认）、`orientation`（MethodChannel 强制横竖屏，规避国产 ROM 忽略 Flutter 方向设置）、`net/`（P2P 抽象、蓝牙 SPP 帧化）。

## 本地开发

环境：Flutter stable（Dart ≥ 3.12）、JDK 17、Android SDK。

```bash
flutter pub get
flutter run
flutter analyze
flutter test

# 线上包：com.jhh.tank_app
flutter build apk --flavor prod --release

# 开发包：com.jhh.tank_app.dev，带调试面板
flutter build apk --flavor dev --release --dart-define=MODE=dev
```

产物：

- `build/app/outputs/flutter-apk/app-prod-release.apk`
- `build/app/outputs/flutter-apk/app-dev-release.apk`

`tool/` 脚本：

| 脚本 | 用途 |
| --- | --- |
| `build_prod.bat` | 构建 prod release，并打印产物与 adb 安装命令 |
| `build_dev.bat` | 构建 dev release（已带 `--dart-define=MODE=dev`） |
| `gen_sounds.dart` | `dart run tool/gen_sounds.dart` 重新合成 `assets/sounds/*.wav` |
| `gen_plane_sprites.dart` | `dart run tool/gen_plane_sprites.dart` 从 `assets/image/*.jpg` 设计稿裁切、去棋盘格背景、按机头对齐并导出 `assets/image/plane/*.png`；加 `--preview` 输出拼图预览 |
| `gen_dev_icon.dart` | 生成 dev 版红色角标启动图标 |
| `sync_web_icons.dart` | 以 Android 主图标为源同步 `web/icons/` |

修改 Dart 代码后出包前建议先 `flutter clean`：本项目曾出现增量快照缓存复用旧代码、导致 APK 里缺少新游戏的情况。

## dev 包与调试面板

`--dart-define=MODE=dev` 注入后 `kIsDev` 为编译期 true；prod 包不传该参数，dev-only 分支会被 tree-shake。dev 包名 `com.jhh.tank_app.dev`、应用名 `GAMEBOX Dev`、红色角标图标，可与 prod 版共存安装。

dev 包会挂载可拖动的调试浮层：实时显示 FPS，点击展开面板可查看当前游戏信息与关卡，并给已接入 `GameDebugMixin` 的游戏提供跳关能力（无尽关卡类游戏为调整关卡，纯分数类游戏隐藏跳关区）。

## 自动发布

`.github/workflows/release.yml`：

- 触发：push `master`、push `v*` 标签、Actions 页面手动触发
- 流程：checkout → JDK 17 + Flutter → `flutter pub get` → `flutter analyze` + `flutter test` → `flutter build apk --flavor prod --release` → 重命名为 `GameBox.apk` → 发布到 Releases
- push `master` 更新 `latest` Release 并覆盖同名附件；push `v*` 生成带版本号的正式 Release
- 同一 ref 的连续推送通过 `concurrency` 取消旧任务；仅申请 `contents: write` 权限

发布正式版：

```bash
git tag v1.0.0
git push origin v1.0.0
```

若首次构建因权限失败，在仓库 Settings → Actions → General → Workflow permissions 中选择 Read and write，然后重跑该 workflow。

## 新增游戏

1. 新建 `lib/games/<id>/`，可参考 `games/plane/` 的拆分：`constants` / `entities` / `painter` / `sound` / `game`
2. 页面优先使用 `shared/game_shell.dart` 的 `GameShell` 外壳（需要全屏 HUD 的游戏可自管 Scaffold）
3. 在 `lib/app/games.dart` 的 `kGames` 追加一条 `GameSpec`（id、标题、emoji、accent、builder、bestKey），首页网格与「N 款游戏」徽标自动更新
4. 复用 `lib/shared/`：音效 `SfxPool`、成绩 `BestScoreStore`、输入 `Joystick` / `SwipeDetector`、方向 `OrientationChannel`
5. 渲染约定：`CustomPaint` + 复用的 Paint / Path，`ValueNotifier` 驱动重绘、`shouldRepaint => false`；HUD 用 `ValueListenableBuilder` 局部重建
6. 释放资源：`Ticker` / `Timer` / `ValueNotifier` / `FocusNode` / 音效池在 `dispose()` 中全部释放
7. 可选：接入 `GameDebugMixin` 支持 dev 跳关；在 `test/widget_test.dart` 补一条注册断言

## 测试

`flutter test` 覆盖三组：

- `widget_test.dart`：注册表 id 唯一、包含坦克大战与飞机大战
- `tank_wire_test.dart`：联机线协议版本识别、旧版本 / 空包 / 噪声包不误报、输入帧与快照编解码往返
- `pacman_engine_test.dart`：30 秒引擎模拟不越界 / 不穿墙、无幽灵滞留鬼屋、输入正确转向

注册表冒烟测试刻意不 pump 整个 App，避免平台插件依赖。

## 常见问题

**首页看不到新游戏？** 覆盖安装后完全退出应用再打开；若本地包仍缺少改动，先 `flutter clean` 再构建。

**提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`？** CI 与本地 Flutter 生成的 debug 签名不同，先卸载旧版再安装。

**蓝牙联机连不上？** 两台手机需先在系统蓝牙设置里配对；Android 12+ 需授予蓝牙连接权限；host 必须先创建房间再让 guest 加入。

**无线调试装包？** 手机开启无线调试后取得 IP:端口，执行 `adb connect <ip>:<port>`，再 `adb install -r <apk>`。

**能跑 Web / Windows 吗？** 目前只有 Android 完整可用；`web/` / `windows/` 仍是模板，蓝牙与屏幕方向依赖 Android 原生通道，暂无对应实现。

## 已知限制

- release 包使用 debug 签名，尚未配置正式 keystore
- 无网络、无账号、无云存档，成绩只保存在本机
- 联机仅支持经典蓝牙 SPP 且需系统预先配对，不支持 iOS 或互联网对战
- `web/` / `windows/` 目录未适配，`web/` 文案仍是早期「坦克大战」
