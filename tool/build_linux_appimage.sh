#!/usr/bin/env bash
# 创建 Linux AppImage（需要在 Linux 环境中运行）
# 依赖：appimagetool 或 docker
# 产物：dist/afrp-oidc-client_<ver>_linux_amd64.appimage
set -euo pipefail
cd "$(dirname "$0")/.."

VER=$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml | head -1)
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH_NAME="x86_64" ;;
    aarch64) ARCH_NAME="aarch64" ;;
    *) ARCH_NAME="$ARCH" ;;
esac

BUNDLE="build/linux/${ARCH}/release/bundle"
if [ ! -d "$BUNDLE" ]; then
    echo "[错误] 构建产物不存在: $BUNDLE"
    echo "       请先运行: bash tool/build_linux.sh"
    exit 1
fi

echo "[1/4] 准备 AppImage 目录结构..."
APPIMAGE_DIR="build/appimage/AFRP_OIDC.AppDir"
rm -rf "$(dirname "$APPIMAGE_DIR")"
mkdir -p "$APPIMAGE_DIR"

# 复制 bundle 内容
cp -r "$BUNDLE"/* "$APPIMAGE_DIR/"

# 复制图标
cp assets/brand/tray_icon.png "$APPIMAGE_DIR/afrp-oidc.png" 2>/dev/null || true
cp assets/brand/tray_icon.png "$APPIMAGE_DIR/.DirIcon" 2>/dev/null || true

# 创建 .desktop 文件（AppImage 根目录需要）
cat > "$APPIMAGE_DIR/afrp-oidc.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=AFRP OIDC Client
Name[zh_CN]=AFRP OIDC 客户端
Comment=FRP OIDC 认证客户端
Exec=afrp_oidc
Icon=afrp-oidc
Terminal=false
Categories=Network;Utility;
StartupNotify=true
EOF
chmod +x "$APPIMAGE_DIR/afrp-oidc.desktop"

# 创建 AppRun
cat > "$APPIMAGE_DIR/AppRun" << 'APPRUN'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="${DIR}/lib:${LD_LIBRARY_PATH}"
exec "${DIR}/afrp_oidc" "$@"
APPRUN
chmod +x "$APPIMAGE_DIR/AppRun"

echo "[2/4] 检查 appimagetool..."
if ! command -v appimagetool &> /dev/null; then
    echo "[信息] appimagetool 未找到，尝试下载..."
    mkdir -p build/tools
    TOOL="build/tools/appimagetool-${ARCH}"
    if [ ! -f "$TOOL" ]; then
        wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" -O "$TOOL"
        chmod +x "$TOOL"
    fi
    APPIMAGETOOL="$TOOL"
else
    APPIMAGETOOL="appimagetool"
fi

echo "[3/4] 生成 AppImage..."
mkdir -p dist
OUT="dist/afrp-oidc-client_${VER}_linux_${ARCH_NAME}.appimage"

# 清理旧文件
rm -f "$OUT"

# 生成 AppImage
ARCH="$ARCH_NAME" "$APPIMAGETOOL" "$APPIMAGE_DIR" "$OUT" --appimage-extract-and-run || {
    echo "[警告] AppImage 生成失败，尝试使用 docker..."
    
    # Docker 备选方案
    if command -v docker &> /dev/null; then
        echo "[信息] 使用 docker 生成 AppImage..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            appimage/appimagebuild:latest \
            bash -c "appimagetool $APPIMAGE_DIR $OUT"
    else
        echo "[错误] 无法生成 AppImage：appimagetool 和 docker 均不可用"
        exit 1
    fi
}

echo "[4/4] 产物：${OUT}"
ls -lh "$OUT"
echo ""
echo "使用方法："
echo "  chmod +x $(basename "$OUT")"
echo "  ./$(basename "$OUT")"
