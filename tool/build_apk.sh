#!/usr/bin/env bash
# 构建 Android release APK。
# 移动端不支持内置 frpc（frpc_manager.dart 抛 UnsupportedError），
# 因此构建前临时移出 desktop 平台 frpc 资产并在 pubspec 注释其声明，
# 完成后原样恢复（trap EXIT 保证失败也恢复）。
# 产物：dist/afrp-oidc-client_<ver>_android_all.apk
set -euo pipefail
cd "$(dirname "$0")/.."

HOLD=build/frpc-hold
BACKUP=build/pubspec.yaml.apk-bak

restore() {
  local d
  for d in windows linux macos; do
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

[ -d assets/frpc/windows ] || { echo "[错误] assets/frpc/windows 不存在，请先恢复资产"; exit 1; }

cp -f pubspec.yaml "$BACKUP"
mkdir -p "$HOLD"
for d in windows linux macos; do
  mv "assets/frpc/$d" "$HOLD/$d"
done
sed -i -E 's@^([[:space:]]*-[[:space:]]+assets/frpc/(windows|linux|macos)/.*)$@#\1@' pubspec.yaml
grep -q '^#[[:space:]]*-[[:space:]]*assets/frpc/windows/frpc.exe' pubspec.yaml || { echo "[错误] pubspec 注释失败"; exit 1; }
echo "[1/3] 已临时移出 desktop frpc 资产并注释声明"

VER=$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml | head -1)

export PATH="/d/dev/flutter/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-D:\\dev\\jdk-17.0.2}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-D:/dev/gradle-home}"
MSYS_NO_PATHCONV=1 flutter build apk --release
echo "[2/3] APK 构建完成"

mkdir -p dist
cp -f build/app/outputs/flutter-apk/app-release.apk "dist/afrp-oidc-client_${VER}_android_all.apk"
echo "[3/3] 产物：dist/afrp-oidc-client_${VER}_android_all.apk"
ls -la "dist/afrp-oidc-client_${VER}_android_all.apk"
