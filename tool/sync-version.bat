@echo off
REM 版本同步 / 校验由 tool/sync-version.sh 统一实现（需要 Git Bash）
REM 用法：
REM   sync-version.bat <ver>           设置版本并同步所有落点
REM   sync-version.bat                  按 pubspec.yaml 当前版本同步
REM   sync-version.bat --check [ver]    只校验，任一处不一致退出码 1

cd /d "%~dp0.."

where bash >nul 2>&1
if errorlevel 1 (
  echo 未找到 bash，请用 Git Bash 执行: bash tool/sync-version.sh %*
  exit /b 1
)

bash tool/sync-version.sh %*
exit /b %errorlevel%
