#!/usr/bin/env bash
# 构建前检查 frpc 二进制程序版本。
#
# 对比四个来源：仓库固定版本 / App 内置常量 / 上游最新 / 网站清单。
# 用法：
#   bash tool/check-frpc.sh            只检查并打印报告
#   bash tool/check-frpc.sh --update   检查后把固定版本与内置常量更新为上游最新
#   bash tool/check-frpc.sh --sync     检查后顺便把新版本同步到网站（需要 CI_API_URL/CI_API_SECRET）
# 环境变量：
#   FRPC_VERSION  显式指定版本（跳过上游检测）
#   GH_TOKEN      GitHub 令牌，提高 API 限额
#   MANIFEST_URL  网站清单地址，默认 https://www.afrp.net/download/manifest.json
#   CI_API_URL    网站基址（如 https://www.afrp.net），--sync 时必填
#   CI_API_SECRET 网站 CI 令牌（Bearer），--sync 时必填
#
# 退出码恒为 0：检查只用于提示，不阻断构建（真正的构建版本由 frpc-version.sh 解析）。
set -uo pipefail
cd "$(dirname "$0")/.."

PIN_FILE="tool/frpc-version.txt"
DART_FILE="lib/frpc/frpc_manager.dart"
MANIFEST_URL="${MANIFEST_URL:-https://www.afrp.net/download/manifest.json}"
UPDATE=0
SYNC=0
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    --sync) SYNC=1 ;;
  esac
done

# 清单里 frpc(windows/amd64) 的版本
fetch_site_version() {
  curl -fsSL --max-time 20 "$MANIFEST_URL" 2>/dev/null | awk '
    /"kind"[[:space:]]*:[[:space:]]*"frpc"/ { inblk=1; plat=""; ver=""; next }
    inblk && /"platform"[[:space:]]*:/ { v=$0; sub(/.*:[[:space:]]*"/,"",v); sub(/".*/,"",v); plat=v }
    inblk && /"version"[[:space:]]*:/ { v=$0; sub(/.*:[[:space:]]*"/,"",v); sub(/".*/,"",v); ver=v }
    inblk && /}/ { if (plat == "windows") { print ver; exit } inblk=0 }
  '
}

pin=$(tr -d '[:space:]' < "$PIN_FILE")
pin=${pin#v}

dart=$(grep -oE "static const String frpcVersion = '[^']+'" "$DART_FILE" \
  | head -1 | sed -E "s/.*'([^']+)'.*/\1/")

latest=$(bash tool/frpc-version.sh 2>/dev/null || echo "$pin")
site=$(fetch_site_version)

echo "🔎 frpc 二进制程序版本检查"
echo "  仓库固定版本 (tool/frpc-version.txt) : $pin"
echo "  App 内置常量 (frpc_manager.dart)     : $dart"
echo "  上游最新 (fatedier/frp)               : $latest"
echo "  网站清单 (manifest.json)              : ${site:-读取失败}"

if [ "$latest" != "$pin" ]; then
  echo "ℹ️ 上游有新版 $pin → $latest"
else
  echo "✅ 固定版本已是上游最新"
fi

if [ -n "$dart" ] && [ "$dart" != "$latest" ]; then
  echo "ℹ️ App 内置常量落后于上游：$dart → $latest"
fi

NEEDS_SYNC=false
if [ -n "$site" ] && [ "$site" != "$latest" ]; then
  echo "ℹ️ 网站清单还没同步到 $latest"
  NEEDS_SYNC=true
elif [ -z "$site" ]; then
  echo "⚠️ 读取网站清单失败，跳过网站同步判断"
fi

if [ "$UPDATE" = "1" ] && [ "$latest" != "$pin" ]; then
  printf '%s\n' "$latest" > "$PIN_FILE"
  sed -i.bak -E "s/(static const String frpcVersion = ')[^']*(';)/\1${latest}\2/" "$DART_FILE"
  rm -f "$DART_FILE.bak"
  echo "✅ 已更新固定版本与内置常量 → $latest"
fi

# 同步到网站：网站接口负责上传 R2 并更新清单，可能耗时几分钟
if [ "$SYNC" = "1" ] && [ "$NEEDS_SYNC" = "true" ]; then
  if [ -z "${CI_API_URL:-}" ] || [ -z "${CI_API_SECRET:-}" ]; then
    echo "⚠️ 缺少 CI_API_URL / CI_API_SECRET，无法同步到网站"
  else
    BASE="${CI_API_URL%/}"
    echo "🌐 同步 frpc $latest 到网站 …"
    RESP=$(curl -fsS --max-time 900 -X POST "${BASE}/api/ci/sync-frpc.php" \
      -H "Authorization: Bearer ${CI_API_SECRET}" \
      --data-urlencode "version=${latest}" 2>&1)
    RC=$?
    echo "  网站接口返回：${RESP:0:400}"
    if [ $RC -ne 0 ]; then
      echo "  ⚠️ 接口调用失败（rc=$RC），改为轮询网站清单确认"
    fi
    # 接口可能因超时断开但服务端仍在跑，轮询清单确认结果
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      NOW=$(fetch_site_version)
      if [ "$NOW" = "$latest" ]; then
        echo "✅ 网站清单已同步到 frpc $latest"
        NEEDS_SYNC=false
        break
      fi
      sleep 30
    done
    if [ "$NEEDS_SYNC" = "true" ]; then
      echo "⚠️ 等待超时，网站清单仍是 ${NOW:-未知}，稍后由每日同步兜底"
    fi
  fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$latest" >> "$GITHUB_OUTPUT"
  echo "needs_sync=$NEEDS_SYNC" >> "$GITHUB_OUTPUT"
  echo "site_version=$site" >> "$GITHUB_OUTPUT"
fi

exit 0
