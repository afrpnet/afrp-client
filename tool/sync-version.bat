@echo off
REM 从 pubspec.yaml 读取版本号，同步更新所有相关文件
REM 用法：sync-version.bat [version]
REM   不带参数：从 pubspec.yaml 读取当前版本
REM   带参数：先更新 pubspec.yaml 再同步

cd /d "%~dp0.."

REM 读取或设置版本
if "%~1"=="" (
  for /f "tokens=2" %%v in ('findstr /b "version:" pubspec.yaml') do set FULLVER=%%v
  for /f "tokens=1 delims=+" %%v in ("%FULLVER%") do set NEW_VER=%%v
) else (
  set NEW_VER=%~1
  REM 更新 pubspec.yaml
  powershell -Command "(Get-Content pubspec.yaml) -replace '^version: .*', 'version: %NEW_VER%+1' | Set-Content pubspec.yaml"
  echo pubspec.yaml -^> %NEW_VER%+1
)

echo 同步版本: %NEW_VER%

REM 1. lib/core/updater.dart - kAppVersion 常量
if exist lib\core\updater.dart (
  powershell -Command "(Get-Content lib\core\updater.dart) -replace \"const String kAppVersion = '[^']*'\", \"const String kAppVersion = '%NEW_VER%'\" | Set-Content lib\core\updater.dart"
  echo   lib/core/updater.dart -^> kAppVersion = '%NEW_VER%'
)

REM 2. installer/setup.iss - MyAppVersion 和 VersionInfoVersion
if exist installer\setup.iss (
  powershell -Command "(Get-Content installer\setup.iss) -replace '#define MyAppVersion \"[^\"]*\"', '#define MyAppVersion \"%NEW_VER%\"' | Set-Content installer\setup.iss"
  powershell -Command "(Get-Content installer\setup.iss) -replace 'VersionInfoVersion=[0-9.]*', 'VersionInfoVersion=%NEW_VER%.0' | Set-Content installer\setup.iss"
  echo   installer/setup.iss -^> MyAppVersion = "%NEW_VER%", VersionInfoVersion = %NEW_VER%.0
)

REM 3. openwrt/luci-app-afrp/Makefile - PKG_VERSION
if exist openwrt\luci-app-afrp\Makefile (
  powershell -Command "(Get-Content openwrt\luci-app-afrp\Makefile) -replace '^PKG_VERSION:=.*', 'PKG_VERSION:=%NEW_VER%' | Set-Content openwrt\luci-app-afrp\Makefile"
  echo   openwrt/luci-app-afrp/Makefile -^> PKG_VERSION:=%NEW_VER%
)

echo 版本同步完成: %NEW_VER%
