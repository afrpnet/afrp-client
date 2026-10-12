#!/bin/bash
# 上传文件到 123 云盘 WebDAV
# 用法：upload-123.sh <文件路径> [子目录]

set -e

FILE="$1"
SUBDIR="${2:-app}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "错误：文件不存在 - $FILE"
  exit 1
fi

if [ -z "$PAN123_USERNAME" ] || [ -z "$PAN123_PASSWORD" ]; then
  echo "错误：请设置环境变量 PAN123_USERNAME 和 PAN123_PASSWORD"
  exit 1
fi

FILENAME=$(basename "$FILE")
URL="https://webdav.123pan.cn/webdav/${SUBDIR}/${FILENAME}"

echo "上传 $FILENAME 到 123 云盘 (${SUBDIR}/)..."

# 最多重试 3 次，每次超时 60 秒
MAX_RETRIES=3
UPLOADED=false

for attempt in $(seq 1 $MAX_RETRIES); do
  echo "  尝试 $attempt/$MAX_RETRIES..."
  
  if curl -f --connect-timeout 10 --max-time 60 \
    --user "${PAN123_USERNAME}:${PAN123_PASSWORD}" \
    -T "$FILE" \
    "$URL" 2>&1; then
    UPLOADED=true
    break
  fi
  
  if [ $attempt -lt $MAX_RETRIES ]; then
    remaining=$((MAX_RETRIES - attempt))
    echo "  ⚠️ 第 $attempt 次尝试失败，5 秒后重试..."
    sleep 5
  fi
done

if [ "$UPLOADED" = true ]; then
  echo "✅ 上传成功"
  echo " 下载链接：https://www.123pan.com/s/${SUBDIR}/${FILENAME}"
  exit 0
else
  echo "❌ 123 云盘上传失败（已重试 $MAX_RETRIES 次）"
  exit 1
fi
