#!/usr/bin/env bash
# 新版 Flutter 引擎把 Wayland 变成硬依赖，系统缺库时启动即退出；随包携带兜底。
# 引擎 RUNPATH 为 $ORIGIN，bundle/lib 内的同 soname 库可被加载器找到；
# 系统已加载同 soname 时加载器去重，仍优先使用系统库。
# 用法: tool/bundle-wayland.sh <bundle-dir>
set -euo pipefail

STAGE="${1:?usage: bundle-wayland.sh <bundle-dir>}"
[ -d "$STAGE/lib" ] || { echo "bundle lib dir not found: $STAGE/lib" >&2; exit 1; }

MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
for lib in libwayland-client.so.0 libwayland-egl.so.1; do
	src="/usr/lib/${MULTIARCH}/${lib}"
	[ -f "$src" ] || { echo "missing system lib: $src (apt install libwayland-client0 libwayland-egl1)" >&2; exit 1; }
	cp -L "$src" "$STAGE/lib/$lib"
done