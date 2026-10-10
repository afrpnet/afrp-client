#!/bin/bash
# 从 pubspec.yaml 读取版本号，同步更新所有相关文件
# 用法：bash tool/sync-version.sh [version]
#   不带参数：从 pubspec.yaml 读取当前版本
#   带参数：先更新 pubspec.yaml 再同步

set -euo pipefail
cd "$(dirname "$0")/.."

# 读取或设置版本
if [ $# -gt 0 ]; then
  NEW_VER="$1"
  # 更新 pubspec.yaml
  sed -i "s/^version: .*/version: ${NEW_VER}+1/" pubspec.yaml
  echo "pubspec.yaml → ${NEW_VER}+1"
else
  NEW_VER=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
fi

echo "同步版本: ${NEW_VER}"

# 1. lib/core/updater.dart - kAppVersion 常量
if [ -f lib/core/updater.dart ]; then
  sed -i "s/const String kAppVersion = '[^']*'/const String kAppVersion = '${NEW_VER}'/" lib/core/updater.dart
  echo "  lib/core/updater.dart → kAppVersion = '${NEW_VER}'"
fi

# 2. installer/setup.iss - MyAppVersion 和 VersionInfoVersion
if [ -f installer/setup.iss ]; then
  sed -i "s/#define MyAppVersion \"[^\"]*\"/#define MyAppVersion \"${NEW_VER}\"/" installer/setup.iss
  sed -i "s/VersionInfoVersion=[0-9.]*/VersionInfoVersion=${NEW_VER}.0/" installer/setup.iss
  echo "  installer/setup.iss → MyAppVersion = \"${NEW_VER}\", VersionInfoVersion = ${NEW_VER}.0"
fi

# 3. openwrt/luci-app-afrp/Makefile - PKG_VERSION
if [ -f openwrt/luci-app-afrp/Makefile ]; then
  sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=${NEW_VER}/" openwrt/luci-app-afrp/Makefile
  echo "  openwrt/luci-app-afrp/Makefile → PKG_VERSION:=${NEW_VER}"
fi

echo "版本同步完成: ${NEW_VER}"
