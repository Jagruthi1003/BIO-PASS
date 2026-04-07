@echo off
REM Bio Pass Flutter Build and Run Script
REM This script builds and runs the Bio Pass app on Android device

cd /d C:\bio_pass

echo.
echo ========================================
echo    BiO Pass - Build and Run Script
echo ========================================
echo.

REM Clean
echo [1/4] Cleaning Flutter and Gradle...
call flutter clean 2>&1

REM Get dependencies
echo.
echo [2/4] Getting Flutter dependencies...
call flutter pub get 2>&1

REM Set better Gradle settings
echo.
echo [3/4] Configuring Gradle...
setlocal enabledelayedexpansion

REM Build APK
echo.
echo [4/4] Building and running on device...
call flutter run -d CPH2495

echo.
echo ========================================
echo    Build Complete
echo ========================================
echo.
pause
