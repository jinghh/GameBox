@echo off
REM 开发包:独立包名 com.jhh.tank_app.dev + DEV 图标角标 + 调试面板可见
REM 可与线上版并存在同一部手机(包名不同)。
flutter build apk --flavor dev --dart-define=MODE=dev --release
if errorlevel 1 exit /b 1
echo.
echo 产物: build\app\outputs\flutter-apk\app-dev-release.apk
echo 安装: adb install -r build\app\outputs\flutter-apk\app-dev-release.apk
