#!/usr/bin/env bash
# 构建 HarmonyOS HAP（debug + OpenHarmony 测试签名）。
# 与 build_apk.sh 相同：临时移出 desktop 平台 frpc 资产并在 pubspec 注释声明，
# 构建后恢复（trap EXIT 保证失败也恢复）。
# 产物：dist/afrp-oidc-client_<ver>_ohos_arm64.hap
set -euo pipefail
cd "$(dirname "$0")/.."

HOLD=build/frpc-hold
BACKUP=build/pubspec.yaml.hap-bak

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

# 鸿蒙工具链（flutter-ohos 必须优先于标准版 flutter）
export JAVA_HOME="D:\\dev\\jdk-17.0.2"
export PATH="/d/dev/flutter-ohos/bin:/d/dev/node18:/d/dev/jdk-17.0.2/bin:/d/dev/harmony-tools/oh-command-line-tools/ohpm/bin:$PATH"
unset PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL || true
MSYS_NO_PATHCONV=1 flutter build hap --debug
echo "[2/3] HAP 构建完成"

mkdir -p dist
cp -f build/ohos/hap/entry-default-signed.hap "dist/afrp-oidc-client_${VER}_ohos_arm64.hap"
echo "[3/3] 产物：dist/afrp-oidc-client_${VER}_ohos_arm64.hap"
ls -la "dist/afrp-oidc-client_${VER}_ohos_arm64.hap"
