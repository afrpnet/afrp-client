#!/bin/bash
# 上传文件到 123 云盘
# 用法：upload-123.sh <文件路径> [父目录 ID，默认 0 根目录]

set -e

FILE="$1"
PARENT_ID="${2:-0}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "错误：文件不存在 - $FILE"
  exit 1
fi

if [ -z "$PAN123_CLIENT_ID" ] || [ -z "$PAN123_CLIENT_SECRET" ]; then
  echo "错误：请设置环境变量 PAN123_CLIENT_ID 和 PAN123_CLIENT_SECRET"
  exit 1
fi

FILENAME=$(basename "$FILE")
FILESIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE")

echo "获取 123 云盘访问令牌..."

# 获取 access_token
TOKEN_RESP=$(curl -s -X POST "https://open-api.123pan.com/api/v1/access_token" \
  -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"${PAN123_CLIENT_ID}\",
    \"clientSecret\": \"${PAN123_CLIENT_SECRET}\"
  }")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
if [ -z "$ACCESS_TOKEN" ]; then
  echo "错误：获取 access_token 失败"
  echo "$TOKEN_RESP"
  exit 1
fi

echo "创建上传任务..."

# 创建上传任务
CREATE_RESP=$(curl -s -X POST "https://open-api.123pan.com/api/v2/file/upload" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"filename\": \"${FILENAME}\",
    \"parentFileId\": ${PARENT_ID},
    \"size\": ${FILESIZE},
    \"etag\": \"\"
  }")

UPLOAD_ID=$(echo "$CREATE_RESP" | grep -o '"uploadId":"[^"]*"' | cut -d'"' -f4)
UPLOAD_URL=$(echo "$CREATE_RESP" | grep -o '"uploadUrl":"[^"]*"' | cut -d'"' -f4)

if [ -z "$UPLOAD_ID" ] || [ -z "$UPLOAD_URL" ]; then
  echo "错误：创建上传任务失败"
  echo "$CREATE_RESP"
  exit 1
fi

echo "上传文件..."

# 上传文件
curl -f -X PUT "$UPLOAD_URL" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$FILE"

echo "完成上传..."

# 完成上传
FINISH_RESP=$(curl -s -X POST "https://open-api.123pan.com/api/v2/file/upload/complete" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"uploadId\": \"${UPLOAD_ID}\",
    \"parentFileId\": ${PARENT_ID}
  }")

FILE_ID=$(echo "$FINISH_RESP" | grep -o '"fileId":[0-9]*' | cut -d: -f2)

if [ -n "$FILE_ID" ]; then
  echo "✅ 上传成功：文件 ID = $FILE_ID"
  echo "下载链接：https://www.123pan.com/s/${FILE_ID}"
else
  echo "警告：上传完成但无法获取文件 ID"
  echo "$FINISH_RESP"
fi
