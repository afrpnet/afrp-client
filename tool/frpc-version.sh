#!/usr/bin/env bash
# 解析构建要内置的 frpc 二进制程序版本：优先 fatedier/frp 最新 release，失败时回退固定版本。
# 用法：bash tool/frpc-version.sh [--pin]
#   --pin   只输出 tool/frpc-version.txt 中的固定版本
# 环境变量：FRPC_VERSION 显式指定版本（最高优先级）；GH_TOKEN 提高 GitHub API 限额。
set -euo pipefail

cd "$(dirname "$0")/.."

pin=$(tr -d '[:space:]' < tool/frpc-version.txt)
pin=${pin#v}

if [ "${1:-}" = "--pin" ]; then
  echo "$pin"
  exit 0
fi

if [ -n "${FRPC_VERSION:-}" ]; then
  echo "${FRPC_VERSION#v}"
  exit 0
fi

api="https://api.github.com/repos/fatedier/frp/releases/latest"
if [ -n "${GH_TOKEN:-}" ]; then
  resp=$(curl -fsSL --max-time 20 -H "Authorization: Bearer ${GH_TOKEN}" "$api" 2>/dev/null || true)
else
  resp=$(curl -fsSL --max-time 20 "$api" 2>/dev/null || true)
fi
latest=$(printf '%s' "$resp" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([0-9][0-9.]*[0-9]\)".*/\1/p' | head -n 1)

if [ -n "$latest" ]; then
  # 发布刚创建时资产可能还在上传，确认可下载后再采用，否则回退固定版本
  if curl -fsIL --max-time 20 "https://github.com/fatedier/frp/releases/download/v${latest}/frp_${latest}_linux_amd64.tar.gz" >/dev/null 2>&1; then
    echo "$latest"
    exit 0
  fi
  echo "WARN: frpc v${latest} 资产不可下载，回退固定版本 ${pin}" >&2
else
  echo "WARN: 无法获取 frpc 最新版本，回退固定版本 ${pin}" >&2
fi

echo "$pin"
