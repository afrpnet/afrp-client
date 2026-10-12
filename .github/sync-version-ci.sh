#!/bin/bash
# CI: 从 git tag 提取版本号并同步到所有文件
# 确保构建产物中的版本号始终与 tag 一致
set -euo pipefail

TAG="${GITHUB_REF_NAME:-}"
if [ -z "$TAG" ]; then
  TAG="${GITHUB_REF#refs/tags/}"
fi
VER="${TAG#v}"

# 如果不是从 tag 触发，尝试从 pubspec.yaml 读取版本号
if ! echo "$VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  if [ -f pubspec.yaml ]; then
    VER=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    echo "从 pubspec.yaml 读取版本: $VER"
  else
    echo "⚠️  无法确定版本号，使用文件中的当前版本"
    exit 0
  fi
else
  echo "从 tag 同步版本: $VER"
fi

# pubspec.yaml (保留 build number)
if [ -f pubspec.yaml ]; then
  BUILD=$(grep '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
  [ -z "$BUILD" ] && BUILD="1"
  sed "s/^version: .*/version: ${VER}+${BUILD}/" pubspec.yaml > pubspec.yaml.tmp
  mv pubspec.yaml.tmp pubspec.yaml
fi

# lib/core/updater.dart
if [ -f lib/core/updater.dart ]; then
  sed "s/const String kAppVersion = '[^']*'/const String kAppVersion = '${VER}'/" lib/core/updater.dart > lib/core/updater.dart.tmp
  mv lib/core/updater.dart.tmp lib/core/updater.dart
fi

# installer/setup.iss
if [ -f installer/setup.iss ]; then
  sed "s/#define MyAppVersion \"[^\"]*\"/#define MyAppVersion \"${VER}\"/" installer/setup.iss > installer/setup.iss.tmp
  mv installer/setup.iss.tmp installer/setup.iss
  sed "s/VersionInfoVersion=[0-9.]*/VersionInfoVersion=${VER}.0/" installer/setup.iss > installer/setup.iss.tmp
  mv installer/setup.iss.tmp installer/setup.iss
fi

# openwrt/luci-app-afrp/Makefile
if [ -f openwrt/luci-app-afrp/Makefile ]; then
  sed "s/^PKG_VERSION:=.*/PKG_VERSION:=${VER}/" openwrt/luci-app-afrp/Makefile > openwrt/luci-app-afrp/Makefile.tmp
  mv openwrt/luci-app-afrp/Makefile.tmp openwrt/luci-app-afrp/Makefile
fi

echo "✅ 版本已同步: $VER"
