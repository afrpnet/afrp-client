#!/bin/bash
# 增量更新 manifest.json：每上传一个文件就更新一次 manifest
# 用法：update-manifest-incremental.sh <file_path> <subdir>

set -e

FILE="$1"
SUBDIR="${2:-app}"  # app 或 frpc

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "❌ 错误：文件不存在 - $FILE"
  exit 1
fi

SITE_URL="${SITE_URL:-https://www.afrp.net}"
MANIFEST_URL="${SITE_URL}/download/manifest.json"

FILENAME=$(basename "$FILE")
VER=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
DATE=$(date +%Y-%m-%d)

# 检查文件版本是否与当前版本匹配（跳过旧版本文件）
if [[ "$FILENAME" =~ _([0-9]+\.[0-9]+\.[0-9]+) ]]; then
  FILE_VER="${BASH_REMATCH[1]}"
  if [ "$FILE_VER" != "$VER" ]; then
    echo "⏭️ 跳过旧版本文件：$FILENAME（当前版本：$VER）"
    exit 0
  fi
fi

# 判断文件类型
case "$FILENAME" in
  afrp-oidc-client_*)
    KIND="app"
    # 解析平台、通道、架构
    if [[ "$FILENAME" == *windows*setup.exe ]]; then
      PLATFORM="windows"; CHANNEL="installer"; ARCH="amd64"
      NOTES="Windows 10/11 x64 安装版"
    elif [[ "$FILENAME" == *windows*portable.zip ]]; then
      PLATFORM="windows"; CHANNEL="portable"; ARCH="amd64"
      NOTES="Windows 10/11 x64 免安装版"
    elif [[ "$FILENAME" == *macos*arm64.zip ]]; then
      PLATFORM="macos"; CHANNEL="portable"; ARCH="arm64"
      NOTES="macOS Apple Silicon 免安装版"
    elif [[ "$FILENAME" == *macos*amd64.zip ]]; then
      PLATFORM="macos"; CHANNEL="portable"; ARCH="amd64"
      NOTES="macOS x64 免安装版"
    elif [[ "$FILENAME" == *linux*amd64*.tar.gz ]]; then
      PLATFORM="linux"; CHANNEL="portable"; ARCH="amd64"
      NOTES="Linux x86_64 免安装版"
    elif [[ "$FILENAME" == *linux*arm64*.tar.gz ]]; then
      PLATFORM="linux"; CHANNEL="portable"; ARCH="arm64"
      NOTES="Linux ARM64 免安装版"
    elif [[ "$FILENAME" == *android*.apk ]]; then
      PLATFORM="android"; CHANNEL="apk"; ARCH="all"
      NOTES="Android 7.0+ 通用安装包"
    elif [[ "$FILENAME" == *ohos*.hap ]]; then
      PLATFORM="ohos"; CHANNEL="hap"; ARCH="arm64"
      NOTES="HarmonyOS 侧载安装"
    else
      echo "⚠️ 未知 App 文件格式：$FILENAME"
      exit 0
    fi
    ;;
  luci-app-afrp_*)
    KIND="app"
    PLATFORM="openwrt"
    if [[ "$FILENAME" == *.ipk ]]; then
      CHANNEL="ipk"; ARCH="all"
      NOTES="OpenWrt LuCI 插件（opkg 安装）"
    elif [[ "$FILENAME" == *.tar.gz ]]; then
      CHANNEL="tar.gz"; ARCH="all"
      NOTES="OpenWrt LuCI 插件包（手动安装）"
    else
      echo "⚠️ 未知 OpenWrt 文件格式：$FILENAME"
      exit 0
    fi
    ;;
  frp_*)
    KIND="frpc"
    PLATFORM="linux"
    CHANNEL=""
    if [[ "$FILENAME" == *_amd64.* ]]; then
      ARCH="amd64"
    elif [[ "$FILENAME" == *_arm64.* ]]; then
      ARCH="arm64"
    elif [[ "$FILENAME" == *_arm.* ]]; then
      ARCH="arm"
    elif [[ "$FILENAME" == *_mipsle.* ]]; then
      ARCH="mipsle"
    elif [[ "$FILENAME" == *_mips.* ]]; then
      ARCH="mips"
    else
      ARCH="unknown"
    fi
    NOTES="frpc ${VER} (Linux ${ARCH})"
    ;;
  *)
    echo "⚠️ 未知文件类型：$FILENAME"
    exit 0
    ;;
esac

echo "📦 处理文件：$FILENAME"
echo "   类型：$KIND, 平台：$PLATFORM, 通道：$CHANNEL, 架构：$ARCH"

# 计算 SHA256 和文件大小
SHA256=$(sha256sum "$FILE" | awk '{print $1}')
SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE")

# 构建 R2 URL
R2_URL="https://dl.afrp.net/${SUBDIR}/${FILENAME}"

# 构建 GitHub URL
if [ "$KIND" = "app" ]; then
  GH_REPO="afrpnet/afrp-client"
else
  GH_REPO="afrpnet/afrp-client"
fi
GH_URL="https://github.com/${GH_REPO}/releases/download/v${VER}/${FILENAME}"

# 下载现有 manifest（如果已有本地更新则使用本地版本）
echo "📥 下载现有 manifest..."
MANIFEST_TMP=$(mktemp)
if [ -f /tmp/manifest-updated.json ]; then
  echo "  使用本地已更新的 manifest"
  cp /tmp/manifest-updated.json "$MANIFEST_TMP"
elif ! curl -sS -o "$MANIFEST_TMP" "$MANIFEST_URL" 2>/dev/null; then
  echo "⚠️ 无法下载 manifest，创建新的"
  echo '{"schema":1,"items":[]}' > "$MANIFEST_TMP"
fi

# 导出所有变量供 PHP 使用
export FILE FILENAME KIND PLATFORM CHANNEL ARCH VER DATE NOTES SHA256 SIZE R2_URL GH_URL SITE_URL MANIFEST_TMP

# 使用 PHP 更新 manifest（更安全）
php <<'PHP_SCRIPT'
<?php
$file = getenv('FILE');
$filename = getenv('FILENAME');
$kind = getenv('KIND');
$platform = getenv('PLATFORM');
$channel = getenv('CHANNEL');
$arch = getenv('ARCH');
$ver = getenv('VER');
$date = getenv('DATE');
$notes = getenv('NOTES');
$sha256 = getenv('SHA256');
$size = intval(getenv('SIZE'));
$r2_url = getenv('R2_URL');
$gh_url = getenv('GH_URL');
$site_url = getenv('SITE_URL');
$manifest_tmp = getenv('MANIFEST_TMP');

// 读取现有 manifest
$manifest = json_decode(file_get_contents($manifest_tmp), true) ?: ['schema' => 1, 'items' => []];
$items = $manifest['items'] ?? [];

// 移除同 kind+platform+channel+arch 的旧条目（只保留最新版本）
$filteredItems = [];
foreach ($items as $it) {
    // 如果与当前文件是同类型同平台同通道同架构，跳过（用新版本替换）
    if ($it['kind'] === $kind && $it['platform'] === $platform && 
        $it['channel'] === $channel && $it['arch'] === $arch) {
        continue;
    }
    $filteredItems[] = $it;
}
$items = $filteredItems;

// 添加新条目（标记为 latest）
$newItem = [
    'id' => md5("{$kind}-{$platform}-{$channel}-{$arch}"),
    'kind' => $kind,
    'platform' => $platform,
    'channel' => $channel,
    'arch' => $arch,
    'version' => $ver,
    'file' => $filename,
    'url' => "{$site_url}/download/files/" . rawurlencode($filename),
    'sha256' => $sha256,
    'size' => $size,
    'date' => $date,
    'notes' => $notes,
    'latest' => true,
    'mirrors' => [
        ['name' => 'GitHub', 'url' => $gh_url],
        ['name' => '站内镜像', 'url' => $r2_url]
    ]
];

$items[] = $newItem;

// 排序：App 在前，按平台→通道→架构→日期
$order = array_flip(['windows', 'macos', 'linux', 'android', 'ohos', 'openwrt']);
usort($items, function($a, $b) use ($order) {
    if ($a['kind'] !== $b['kind']) return $a['kind'] === 'app' ? -1 : 1;
    $pa = $order[$a['platform']] ?? 99;
    $pb = $order[$b['platform']] ?? 99;
    if ($pa !== $pb) return $pa <=> $pb;
    if ($a['channel'] !== $b['channel']) return strcmp($a['channel'], $b['channel']);
    if ($a['arch'] !== $b['arch']) return strcmp($a['arch'], $b['arch']);
    if ($a['date'] !== $b['date']) return strcmp($b['date'], $a['date']);
    return strcmp($a['file'], $b['file']);
});

$manifest['items'] = $items;
$manifest['updated'] = date('Y-m-d H:i:s');
$manifest['count'] = count($items);

// 保存为固定路径供 CI 上传
file_put_contents('/tmp/manifest-updated.json', json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");
echo "✅ Manifest 已更新（共 {$manifest['count']} 个条目）\n";
PHP_SCRIPT

# 不需要上传 manifest（由后续步骤统一推送）
rm -f "$MANIFEST_TMP"
echo "✅ 完成：$FILENAME"
