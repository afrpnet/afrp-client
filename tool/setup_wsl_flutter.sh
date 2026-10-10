#!/usr/bin/env bash
# 在 WSL2 中自动设置 Flutter Linux 构建环境
# 用法：在 WSL Ubuntu 中运行 bash setup_wsl_flutter.sh
set -euo pipefail

echo "=== Flutter Linux 构建环境设置 ==="

# 更新系统
echo "[1/5] 更新系统包..."
sudo apt update && sudo apt upgrade -y

# 安装依赖
echo "[2/5] 安装构建依赖..."
sudo apt install -y \
    clang cmake ninja-build \
    pkg-config libgtk-3-dev \
    liblzma-dev libstdc++-12-dev \
    xz-utils wget git curl unzip

# 安装 Flutter（如果不存在）
FLUTTER_DIR="$HOME/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
    echo "[3/5] 安装 Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
else
    echo "[3/5] Flutter 已存在，更新..."
    cd "$FLUTTER_DIR"
    git pull
    cd -
fi

# 添加到 PATH
SHELL_RC="$HOME/.bashrc"
if ! grep -q 'flutter/bin' "$SHELL_RC"; then
    echo "export PATH=\"\$HOME/flutter/bin:\$PATH\"" >> "$SHELL_RC"
    echo "已添加 Flutter 到 PATH"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

# 初始化 Flutter
echo "[4/5] 初始化 Flutter..."
flutter precache
flutter config --enable-linux-desktop
flutter config --no-analytics

# 检查
echo "[5/5] 检查环境..."
flutter doctor -v

echo ""
echo "=== 设置完成 ==="
echo "请运行: source ~/.bashrc"
echo "然后进入项目目录运行: flutter pub get && bash tool/build_linux.sh"
