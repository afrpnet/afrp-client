#!/bin/bash
# AFRP 客户端版本号统一同步 / 校验
#
# 唯一真源：pubspec.yaml（发布时必须与 git tag 一致）
#
# 同步落点：
#   pubspec.yaml                    version: X.Y.Z+N
#   lib/core/updater.dart           kAppVersion
#   installer/setup.iss             MyAppVersion / VersionInfoVersion
#   openwrt/luci-app-afrp/Makefile  PKG_VERSION
#   ohos/AppScope/app.json5         versionName / versionCode
#   openwrt/.../client.js           页面版本号（打包时由 build-ipk.php 注入，不在此维护）
#
# 用法：
#   bash tool/sync-version.sh <ver>           设置版本并同步所有落点（版本变化时 build 号 +1）
#   bash tool/sync-version.sh                  按 pubspec.yaml 当前版本同步所有落点
#   bash tool/sync-version.sh --check [ver]    只校验不修改，任一处不一致则退出码 1
#                                           ver 省略或不是合法版本号时以 pubspec.yaml 为准

set -euo pipefail
cd "$(dirname "$0")/.."

PUBSPEC="pubspec.yaml"
UPDATER="lib/core/updater.dart"
SETUP="installer/setup.iss"
MAKEFILE="openwrt/luci-app-afrp/Makefile"
APPJSON5="ohos/AppScope/app.json5"
LUCICLIENT="openwrt/luci-app-afrp/htdocs/luci-static/resources/view/afrp/client.js"

VER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

fail() { echo "❌ $*" >&2; exit 1; }

CHECK_ONLY=0
NEW_VER=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -*) fail "未知参数: $arg" ;;
    *) NEW_VER="$arg" ;;
  esac
done

# ---------------- 读取 ----------------

read_pub_version() {
  grep -E '^version:' "$PUBSPEC" | head -1 | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

read_pub_build() {
  local b
  b=$(grep -E '^version:' "$PUBSPEC" | head -1 | sed -E 's/.*\+([0-9]+).*/\1/')
  case "$b" in ''|*[!0-9]*) echo 1 ;; *) echo "$b" ;; esac
}

cur_updater() {
  grep -oE "const String kAppVersion = '[^']+'" "$UPDATER" | head -1 | sed -E "s/.*'([^']+)'.*/\1/"
}

cur_setup() {
  grep -oE '^#define MyAppVersion "[^"]+"' "$SETUP" | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

cur_setup_info() {
  grep -oE '^VersionInfoVersion=[0-9.]+' "$SETUP" | head -1 | sed -E 's/^VersionInfoVersion=//'
}

cur_makefile() {
  grep -oE '^PKG_VERSION:=[0-9.]+' "$MAKEFILE" | head -1 | sed -E 's/^PKG_VERSION:=//'
}

cur_appjson5() {
  grep -oE '"versionName":[[:space:]]*"[^"]+"' "$APPJSON5" | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

cur_appjson5_code() {
  grep -oE '"versionCode":[[:space:]]*[0-9]+' "$APPJSON5" | head -1 | sed -E 's/.*:[[:space:]]*//'
}

version_code() {
  local maj min pat
  maj=$(echo "$1" | cut -d. -f1)
  min=$(echo "$1" | cut -d. -f2)
  pat=$(echo "$1" | cut -d. -f3)
  echo $(( maj * 1000000 + min * 1000 + pat ))
}

# ---------------- 写入 ----------------

write_pubspec() {
  sed -E "s/^version:.*/version: ${1}+${2}/" "$PUBSPEC" > "$PUBSPEC.tmp"
  mv "$PUBSPEC.tmp" "$PUBSPEC"
}

write_updater() {
  sed -E "s/const String kAppVersion = '[^']*'/const String kAppVersion = '${1}'/" "$UPDATER" > "$UPDATER.tmp"
  mv "$UPDATER.tmp" "$UPDATER"
}

write_setup() {
  sed -E "s/#define MyAppVersion \"[^\"]*\"/#define MyAppVersion \"${1}\"/" "$SETUP" > "$SETUP.tmp"
  mv "$SETUP.tmp" "$SETUP"
  sed -E "s/VersionInfoVersion=[0-9.]+/VersionInfoVersion=${1}.0/" "$SETUP" > "$SETUP.tmp"
  mv "$SETUP.tmp" "$SETUP"
}

write_makefile() {
  sed -E "s/^PKG_VERSION:=.*/PKG_VERSION:=${1}/" "$MAKEFILE" > "$MAKEFILE.tmp"
  mv "$MAKEFILE.tmp" "$MAKEFILE"
}

write_appjson5() {
  local code
  code=$(version_code "$1")
  sed -E "s/\"versionCode\"[[:space:]]*:[[:space:]]*[0-9]+/\"versionCode\": ${code}/" "$APPJSON5" > "$APPJSON5.tmp"
  mv "$APPJSON5.tmp" "$APPJSON5"
  sed -E "s/\"versionName\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"versionName\": \"${1}\"/" "$APPJSON5" > "$APPJSON5.tmp"
  mv "$APPJSON5.tmp" "$APPJSON5"
}

# ---------------- 校验 ----------------

check_all() {
  local expect="$1" bad=0
  local pairs=(
    "$PUBSPEC|$(read_pub_version)"
    "$UPDATER|$(cur_updater)"
    "$SETUP|$(cur_setup)"
    "$MAKEFILE|$(cur_makefile)"
    "$APPJSON5|$(cur_appjson5)"
  )
  local item f v
  for item in "${pairs[@]}"; do
    f="${item%%|*}"
    v="${item##*|}"
    if [ "$v" != "$expect" ]; then
      echo "  $f: 当前 $v，期望 $expect" >&2
      bad=1
    fi
  done

  local vi vc want
  vi=$(cur_setup_info)
  if [ "$vi" != "${expect}.0" ]; then
    echo "  $SETUP (VersionInfoVersion): 当前 $vi，期望 ${expect}.0" >&2
    bad=1
  fi

  vc=$(cur_appjson5_code)
  want=$(version_code "$expect")
  if [ "$vc" != "$want" ]; then
    echo "  $APPJSON5 (versionCode): 当前 $vc，期望 $want" >&2
    bad=1
  fi

  # LuCI 页面版本号由打包时注入，源码里必须留占位符，避免写死后漂移
  if ! grep -q '__AFRP_VERSION__' "$LUCICLIENT"; then
    echo "  $LUCICLIENT: 缺少 __AFRP_VERSION__ 占位符（页面版本号应在打包时注入）" >&2
    bad=1
  fi

  return $bad
}

# ---------------- 主流程 ----------------

if [ "$CHECK_ONLY" = "1" ]; then
  EXPECT="$NEW_VER"
  if ! echo "$EXPECT" | grep -qE "$VER_RE"; then
    if [ -n "$EXPECT" ]; then
      echo "ℹ️  \"$EXPECT\" 不是合法版本号，改以 pubspec.yaml 为准" >&2
    fi
    EXPECT=$(read_pub_version)
  fi
  echo "$EXPECT" | grep -qE "$VER_RE" || fail "pubspec.yaml 版本号非法"

  if check_all "$EXPECT"; then
    echo "✅ 版本一致: $EXPECT"
    exit 0
  fi
  echo "" >&2
  echo "❌ 版本号不一致，修复后重新提交：" >&2
  echo "     bash tool/sync-version.sh $EXPECT" >&2
  exit 1
fi

BUILD=$(read_pub_build)
if [ -n "$NEW_VER" ]; then
  echo "$NEW_VER" | grep -qE "$VER_RE" || fail "版本号非法: $NEW_VER"
  OLD_VER=$(read_pub_version)
  if [ "$OLD_VER" != "$NEW_VER" ]; then
    BUILD=$(( BUILD + 1 ))
  fi
  write_pubspec "$NEW_VER" "$BUILD"
  echo "  $PUBSPEC → ${NEW_VER}+${BUILD}"
else
  NEW_VER=$(read_pub_version)
  echo "$NEW_VER" | grep -qE "$VER_RE" || fail "pubspec.yaml 版本号非法"
  write_pubspec "$NEW_VER" "$BUILD"
  echo "  $PUBSPEC → ${NEW_VER}+${BUILD}"
fi

write_updater "$NEW_VER"
echo "  $UPDATER → kAppVersion = '${NEW_VER}'"

write_setup "$NEW_VER"
echo "  $SETUP → MyAppVersion = \"${NEW_VER}\", VersionInfoVersion = ${NEW_VER}.0"

write_makefile "$NEW_VER"
echo "  $MAKEFILE → PKG_VERSION:=${NEW_VER}"

write_appjson5 "$NEW_VER"
echo "  $APPJSON5 → versionName = \"${NEW_VER}\", versionCode = $(version_code "$NEW_VER")"

echo "✅ 版本同步完成: ${NEW_VER}"
