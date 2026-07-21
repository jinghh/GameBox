@echo off
REM 线上包:com.jhh.tank_app,无调试面板(if(kIsDev) 分支被 tree-shake)
flutter build apk --flavor prod --release
if errorlevel 1 exit /b 1
echo.
echo 产物: build\app\outputs\flutter-apk\app-prod-release.apk
echo 安装: adb install -r build\app\outputs\flutter-apk\app-prod-release.apk
