@echo off
cd /d %~dp0..
flutter build apk --release --flavor dev
