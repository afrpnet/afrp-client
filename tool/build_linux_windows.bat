@echo off
REM Linux 版本一键构建脚本（重启后运行）
REM 前提：已运行 wsl --install -d Ubuntu-22.04 并重启系统
setlocal

echo === AFRP OIDC Client Linux 版本构建 ===
echo.

REM 检查 WSL 是否可用
wsl.exe --status >nul 2>&1
if errorlevel 1 (
    echo [错误] WSL 不可用，请确认系统已重启
    echo        并运行: wsl --install -d Ubuntu-22.04
    pause
    exit /b 1
)

REM 检查 Ubuntu 是否已安装
wsl.exe -d Ubuntu-22.04 -e echo test >nul 2>&1
if errorlevel 1 (
    echo [信息] 首次启动 Ubuntu，请设置用户名和密码...
    wsl.exe --install -d Ubuntu-22.04
    if errorlevel 1 (
        echo [错误] Ubuntu 安装失败
        pause
        exit /b 1
    )
)

echo [1/4] 在 WSL 中安装构建依赖...
wsl.exe -d Ubuntu-22.04 -- bash -c "sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev xz-utils wget git curl unzip"
if errorlevel 1 (
    echo [错误] 依赖安装失败
    pause
    exit /b 1
)

echo [2/4] 安装 Flutter SDK...
wsl.exe -d Ubuntu-22.04 -- bash -c "if [ ! -d ~/flutter ]; then git clone https://github.com/flutter/flutter.git -b stable ~/flutter; fi"
wsl.exe -d Ubuntu-22.04 -- bash -c "export PATH=$HOME/flutter/bin:$PATH && flutter precache && flutter config --enable-linux-desktop && flutter config --no-analytics"

echo [3/4] 获取项目依赖...
wsl.exe -d Ubuntu-22.04 -- bash -c "export PATH=$HOME/flutter/bin:$PATH && cd /mnt/d/ProjectData/frp-oidc-app && flutter pub get"
if errorlevel 1 (
    echo [错误] flutter pub get 失败
    pause
    exit /b 1
)

echo [4/4] 构建 Linux 版本...
wsl.exe -d Ubuntu-22.04 -- bash -c "export PATH=$HOME/flutter/bin:$PATH && cd /mnt/d/ProjectData/frp-oidc-app && bash tool/build_linux.sh"
if errorlevel 1 (
    echo [错误] 构建失败
    pause
    exit /b 1
)

echo.
echo === 构建完成 ===
echo 产物位于 D:\ProjectData\frp-oidc-app\dist\
dir D:\ProjectData\frp-oidc-app\dist\*.tar.gz 2>nul
dir D:\ProjectData\frp-oidc-app\dist\*.appimage 2>nul
echo.
pause
