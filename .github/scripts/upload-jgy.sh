#!/bin/bash
# 上传文件到坚果云 WebDAV
# 用法：upload-jgy.sh <文件路径>

set -e

FILE="$1"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "错误：文件不存在 - $FILE"
  exit 1
fi

if [ -z "$JGY_USERNAME" ] || [ -z "$JGY_PASSWORD" ]; then
  echo "错误：请设置环境变量 JGY_USERNAME 和 JGY_PASSWORD（应用密码）"
  exit 1
fi

FILENAME=$(basename "$FILE")

# 创建目录（如果不存在）
echo "创建目录 /Afrp-Oidc-Client..."
curl -s --user "${JGY_USERNAME}:${JGY_PASSWORD}" \
  --request MKCOL \
  "https://dav.jianguoyun.com/dav/Afrp-Oidc-Client/" || true

URL="https://dav.jianguoyun.com/dav/Afrp-Oidc-Client/${FILENAME}"

echo "上传 $FILENAME 到坚果云..."
curl -f --user "${JGY_USERNAME}:${JGY_PASSWORD}" \
  -T "$FILE" \
  "$URL"

echo "✅ 上传成功"
