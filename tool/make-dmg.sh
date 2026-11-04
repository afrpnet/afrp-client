#!/bin/bash
# 生成品牌化 dmg：白底 logo 背景 + 固定图标布局。
# .DS_Store 是二进制且随系统版本变，不手写——先出可写 dmg 挂载，指挥 Finder 设好
# 窗口/图标位置/背景图（Finder 自己把 .DS_Store 写进卷里），再转成 UDZO 成品。
# 用法: bash tool/make-dmg.sh <已构建的 .app 路径> <输出 dmg 路径>
set -euo pipefail

APP_SRC="$1"
OUT_DMG="$2"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BG_DIR="$REPO/macos/dmg"
VOL="AFRP OIDC Client"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP_SRC" "$STAGE/$VOL.app"
# 拖进「应用程序」的快捷方式，用户挂载后直接拖拽即可
ln -s /Applications "$STAGE/Applications"

# 1x/2x 背景合成多分辨率 tiff，Finder 按屏幕倍率自选，Retina 下不糊
sips -s format tiff "$BG_DIR/background.png" --out "$WORK/bg1.tiff" >/dev/null
sips -s format tiff "$BG_DIR/background@2x.png" --out "$WORK/bg2.tiff" >/dev/null
tiffutil -cathidpicheck "$WORK/bg1.tiff" "$WORK/bg2.tiff" -out "$STAGE/.background/background.tiff"

RW="$WORK/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -format UDRW -ov -o "$RW" >/dev/null

MOUNT="$(hdiutil attach -readwrite -noverify -nobrowse "$RW" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | tail -1)"
echo "mounted: $MOUNT"
# Finder 布局脚本偶发 -1708（window doesn't understand the "update" message），重试一次；
# 仍失败也只影响外观（保持系统默认），不阻断打包。
osascript "$BG_DIR/layout.applescript" \
  || osascript "$BG_DIR/layout.applescript" \
  || echo "::warning::Finder 布局脚本失败，dmg 保持系统默认外观"
# 卸载前先关掉可能仍打开着该卷的 Finder 窗口，否则脚本中途失败留下的窗口会让 detach "Resource busy"。
osascript -e "tell application \"Finder\" to close (every window whose name is \"$VOL\")" 2>/dev/null || true
# 多次强制卸载：偶发占用不该让整个 job 失败。
detached=0
for _ in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT" -force -quiet 2>/dev/null; then detached=1; break; fi
  sleep 3
done
[ "$detached" = "1" ] || { echo "::error::无法卸载 $MOUNT"; exit 1; }

mkdir -p "$(dirname "$OUT_DMG")"
hdiutil convert "$RW" -format UDZO -ov -o "$OUT_DMG" >/dev/null
ls -la "$OUT_DMG"
