#!/bin/bash
# 上传文件到 Cloudflare R2（带重试机制）
# 用法：upload-r2.sh <文件路径> [子目录]

set -e

FILE="$1"
SUBDIR="${2:-}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "❌ 错误：文件不存在 - $FILE"
  exit 1
fi

if [ -z "$R2_ACCOUNT_ID" ] || [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_BUCKET" ]; then
  echo "❌ 错误：请设置环境变量 R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET"
  exit 1
fi

FILENAME=$(basename "$FILE")

# 构建对象键（带子目录）
if [ -n "$SUBDIR" ]; then
  OBJECT_KEY="${SUBDIR}/${FILENAME}"
else
  OBJECT_KEY="${FILENAME}"
fi

# Cloudflare R2 S3 兼容端点
ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
PUBLIC_URL="https://dl.afrp.net/${OBJECT_KEY}"

echo "📤 上传 ${FILENAME} 到 Cloudflare R2 (${OBJECT_KEY})..."

# 设置 AWS CLI 所需的环境变量
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="auto"

# 最多重试 3 次
MAX_RETRIES=3
UPLOADED=false

for attempt in $(seq 1 $MAX_RETRIES); do
  echo "  尝试 $attempt/$MAX_RETRIES..."
  
  # 使用 aws-cli 或 s3cmd 上传
  if command -v aws &> /dev/null; then
    # 使用 AWS CLI
    if aws s3 cp "$FILE" "s3://${R2_BUCKET}/${OBJECT_KEY}" \
      --endpoint-url "${ENDPOINT}" \
      --storage-class STANDARD 2>&1; then
      UPLOADED=true
      break
    fi
  elif command -v s3cmd &> /dev/null; then
    # 使用 s3cmd
    if s3cmd put "$FILE" "s3://${R2_BUCKET}/${OBJECT_KEY}" \
      --access_key="${R2_ACCESS_KEY_ID}" \
      --secret_key="${R2_SECRET_ACCESS_KEY}" \
      --host="${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" \
      --host-bucket="%(bucket)s.${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" 2>&1; then
      UPLOADED=true
      break
    fi
  else
    echo "❌ 错误：未找到 aws-cli 或 s3cmd"
    exit 1
  fi
  
  # 如果还有重试机会，等待后继续
  if [ $attempt -lt $MAX_RETRIES ]; then
    remaining=$((MAX_RETRIES - attempt))
    echo "  ⚠️ 第 $attempt 次尝试失败，${remaining} 秒后重试..."
    sleep 5
  fi
done

if [ "$UPLOADED" = true ]; then
  echo "✅ 上传成功"
  echo "📥 下载链接：${PUBLIC_URL}"
  exit 0
else
  echo "❌ R2 上传失败（已重试 $MAX_RETRIES 次）"
  exit 1
fi
