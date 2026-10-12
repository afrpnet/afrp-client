#!/bin/bash
# 上传文件到 123 云盘 WebDAV
# 用法：upload-123.sh <文件路径>

set -e

FILE="$1"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "错误：文件不存在 - $FILE"
  exit 1
fi

if [ -z "$PAN123_USERNAME" ] || [ -z "$PAN123_PASSWORD" ]; then
  echo "错误：请设置环境变量 PAN123_USERNAME 和 PAN123_PASSWORD"
  exit 1
fi

FILENAME=$(basename "$FILE")
URL="https://webdav.123pan.cn/webdav/${FILENAME}"

echo "上传 $FILENAME 到 123 云盘..."
curl -f --user "${PAN123_USERNAME}:${PAN123_PASSWORD}" \
  -T "$FILE" \
  "$URL"

echo "✅ 上传成功"
