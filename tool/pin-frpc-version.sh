#!/usr/bin/env bash
# 把本次构建实际内置的 frpc 版本写入 Dart 常量，保证 App 上报与更新判断和二进制一致。
# 用法：bash tool/pin-frpc-version.sh <version>
set -euo pipefail

VER=${1:?usage: pin-frpc-version.sh <version>}
VER=${VER#v}

cd "$(dirname "$0")/.."

sed -i.bak -E "s/(static const String frpcVersion = ')[^']*(';)/\1${VER}\2/" lib/frpc/frpc_manager.dart
rm -f lib/frpc/frpc_manager.dart.bak

grep -q "static const String frpcVersion = '${VER}';" lib/frpc/frpc_manager.dart
echo "frpcVersion -> ${VER}"
