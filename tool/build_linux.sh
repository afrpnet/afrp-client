#!/usr/bin/env bash
# 构建 Linux release 版本（需要在 Linux 环境中运行，需要 GTK3 开发库）
# 依赖：flutter, clang, cmake, ninja-build, pkg-config, libgtk-3-dev
# 产物：dist/afrp-oidc-client_<ver>_linux_amd64_portable.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH_NAME="amd64" ;;
    aarch64) ARCH_NAME="arm64" ;;
    *) ARCH_NAME="$ARCH" ;;
esac

VER=$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml | head -1)
echo "[1/5] 构建 Linux ${ARCH_NAME} 版本 ${VER}..."

# 检查依赖
if ! command -v flutter &> /dev/null; then
    echo "[错误] flutter 未找到，请先安装 Flutter SDK"
    exit 1
fi

if ! pkg-config --exists gtk+-3.0; then
    echo "[错误] GTK3 开发库未安装"
    echo "       Ubuntu/Debian: sudo apt install libgtk-3-dev"
    echo "       Fedora: sudo dnf install gtk3-devel"
    echo "       Arch: sudo pacman -S gtk3"
    exit 1
fi

# 临时移除非 Linux 平台的 frpc 资产（减小包体积）
HOLD=build/frpc-hold-linux
BACKUP=build/pubspec.yaml.linux-bak

restore() {
    local d
    for d in windows macos; do
        if [ -d "$HOLD/$d" ]; then
            rmdir "assets/frpc/$d" 2>/dev/null || true
            mv "$HOLD/$d" "assets/frpc/$d" 2>/dev/null || true
        fi
    done
    rmdir "$HOLD" 2>/dev/null || true
    if [ -f "$BACKUP" ]; then
        cp -f "$BACKUP" pubspec.yaml
        rm -f "$BACKUP"
    fi
}
trap restore EXIT

[ -d assets/frpc/linux ] || { echo "[错误] assets/frpc/linux 不存在，请先恢复资产"; exit 1; }

cp -f pubspec.yaml "$BACKUP"
mkdir -p "$HOLD"
for d in windows macos; do
    if [ -d "assets/frpc/$d" ]; then
        mv "assets/frpc/$d" "$HOLD/$d"
    fi
done
sed -i -E 's@^([[:space:]]*-[[:space:]]+assets/frpc/(windows|macos)/.*)$@#\1@' pubspec.yaml
echo "[2/5] 已临时移除非 Linux frpc 资产"

# 构建
flutter build linux --release
echo "[3/5] Linux 构建完成"

# 打包
STAGE="build/linux/${ARCH}/release/bundle"
if [ ! -d "$STAGE" ]; then
    echo "[错误] 构建产物目录不存在: $STAGE"
    exit 1
fi

# 复制 .desktop 文件和图标
mkdir -p "$STAGE/usr/share/applications"
mkdir -p "$STAGE/usr/share/icons/hicolor/256x256/apps"
cp tool/afrp-oidc.desktop "$STAGE/usr/share/applications/" 2>/dev/null || true
cp assets/brand/tray_icon.png "$STAGE/usr/share/icons/hicolor/256x256/apps/afrp-oidc.png" 2>/dev/null || true

# 创建启动脚本
cat > "$STAGE/afrp-oidc.sh" << 'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${DIR}/lib:${LD_LIBRARY_PATH}"
exec "${DIR}/afrp_oidc" "$@"
LAUNCHER
chmod +x "$STAGE/afrp-oidc.sh"

echo "[4/5] 正在打包..."
mkdir -p dist
OUT="dist/afrp-oidc-client_${VER}_linux_${ARCH_NAME}_portable.tar.gz"
tar -czf "$OUT" -C "$STAGE" .

echo "[5/5] 产物：${OUT}"
ls -lh "$OUT"
echo ""
echo "安装说明："
echo "  1. 解压: tar -xzf $(basename "$OUT") -d ~/afrp-oidc"
echo "  2. 运行: ~/afrp-oidc/afrp-oidc.sh"
echo "  3. (可选) 复制 .desktop 文件: cp ~/afrp-oidc/usr/share/applications/afrp-oidc.desktop ~/.local/share/applications/"
