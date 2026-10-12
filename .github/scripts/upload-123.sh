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

# 123 云盘上传较慢，设置较长超时
# 连接超时 30 秒，总超时 10 分钟（大文件可能需要更久）
if curl -f --connect-timeout 30 --max-time 600 \
  --user "${PAN123_USERNAME}:${PAN123_PASSWORD}" \
  -T "$FILE" \
  "$URL" 2>&1; then
  echo "✅ 上传成功"
  echo " 下载链接：https://www.123pan.com/s/${SUBDIR}/${FILENAME}"
  exit 0
else
  echo "❌ 123 云盘上传失败"
  exit 1
fi
