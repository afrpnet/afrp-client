<?php
/**
 * 生成生产下载清单 manifest.json：
 *  - 拉取线上清单（默认 https://www.afrp.net/download/manifest.json）
 *  - 关闭旧「客户端」条目的最新标记（保留条目本体）
 *  - 扫描 dist/ 中的构建产物，登记/更新为最新条目（sha256/size 本地实时计算）
 * 输出：dist/manifest.json —— 经 1Panel 上传覆盖 web/download/manifest.json
 *
 * 用法：php tool/gen-manifest.php [站点URL]
 */

$site = rtrim($argv[1] ?? 'https://www.afrp.net', '/');
$root = dirname(__DIR__);
$dist = $root . '/dist';
$date = date('Y-m-d');

// 文件名正则 => [平台, 通道, 架构, 备注]
$rules = [
    ['~^afrp-oidc-client_([0-9.]+)_windows_amd64_setup\.exe$~', 'windows', 'installer', 'x64', 'Windows 10/11 x64 安装版（自动配置 Defender 排除）'],
    ['~^afrp-oidc-client_([0-9.]+)_windows_amd64_portable\.zip$~', 'windows', 'portable', 'x64', 'Windows 10/11 x64 免安装版（解压即用）'],
    ['~^afrp-oidc-client_([0-9.]+)_linux_amd64_portable\.tar\.gz$~', 'linux', 'portable', 'amd64', 'Linux x86_64 免安装版（解压后运行 afrp-oidc.sh）'],
    ['~^afrp-oidc-client_([0-9.]+)_linux_amd64\.appimage$~', 'linux', 'appimage', 'amd64', 'Linux x86_64 AppImage（chmod +x 后直接运行）'],
    ['~^afrp-oidc-client_([0-9.]+)_linux_arm64_portable\.tar\.gz$~', 'linux', 'portable', 'arm64', 'Linux ARM64 免安装版（解压后运行 afrp-oidc.sh）'],
    ['~^afrp-oidc-client_([0-9.]+)_android_all\.apk$~', 'android', 'apk', 'all', 'Android 7.0+ 通用安装包（全架构）'],
    ['~^afrp-oidc-client_([0-9.]+)_ohos_arm64\.hap$~', 'ohos', 'hap', 'arm64', 'HarmonyOS 侧载安装（测试签名）'],
    ['~^luci-app-afrp_([0-9.]+)-1_all\.ipk$~', 'openwrt', 'ipk', 'all', 'LuCI 插件（opkg install 安装）'],
    ['~^luci-app-afrp-([0-9.]+)\.tar\.gz$~', 'openwrt', 'tar.gz', 'all', 'LuCI 插件包（手动/离线安装）'],
];

// 1. 拉取线上清单
$ctx = stream_context_create(['http' => ['timeout' => 30, 'user_agent' => 'afrp-gen-manifest/1.0']]);
$live = @file_get_contents($site . '/download/manifest.json', false, $ctx);
if ($live === false) {
    fwrite(STDERR, "[错误] 无法拉取 {$site}/download/manifest.json\n");
    exit(1);
}
$manifest = json_decode($live, true);
if (!is_array($manifest) || !isset($manifest['items']) || !is_array($manifest['items'])) {
    fwrite(STDERR, "[错误] 线上 manifest 解析失败\n");
    exit(1);
}
$items = $manifest['items'];
echo "线上条目 " . count($items) . " 条\n";

// 2. 关闭旧「客户端」条目的最新标记
foreach ($items as $i => $it) {
    if (($it['kind'] ?? '') === 'app' && !empty($it['latest'])) {
        $items[$i]['latest'] = false;
        echo "  取消最新：" . ($it['file'] ?? '?') . "\n";
    }
}

// 3. 登记 dist/ 产物（同 file 条目原位更新，否则新增）
$n = 0;
foreach (glob($dist . '/*') ?: [] as $path) {
    if (!is_file($path)) {
        continue;
    }
    $file = basename($path);
    foreach ($rules as [$re, $platform, $channel, $arch, $notes]) {
        if (!preg_match($re, $file, $m)) {
            continue;
        }
        $entry = [
            'kind' => 'app',
            'platform' => $platform,
            'channel' => $channel,
            'arch' => $arch,
            'version' => $m[1],
            'file' => $file,
            'url' => $site . '/download/files/' . rawurlencode($file),
            'sha256' => hash_file('sha256', $path),
            'size' => (int)filesize($path),
            'date' => $date,
            'notes' => $notes,
            'latest' => true,
        ];
        $found = false;
        foreach ($items as $i => $it) {
            if (($it['file'] ?? '') === $file) {
                $entry['id'] = $it['id'] ?? bin2hex(random_bytes(6));
                $items[$i] = $entry;
                $found = true;
                break;
            }
        }
        if (!$found) {
            $entry = ['id' => bin2hex(random_bytes(6))] + $entry;
            $items[] = $entry;
        }
        echo "  登记：" . $file . "（" . $entry['sha256'] . "）\n";
        $n++;
        break;
    }
}
echo "本次登记/更新 {$n} 条\n";

// 4. 按后台规则排序（客户端在前；平台→通道→架构→日期倒序）
$order = array_flip(['windows', 'macos', 'linux', 'android', 'ohos', 'openwrt']);
usort($items, function (array $a, array $b) use ($order): int {
    if ($a['kind'] !== $b['kind']) {
        return $a['kind'] === 'app' ? -1 : 1;
    }
    $pa = $order[$a['platform']] ?? 99;
    $pb = $order[$b['platform']] ?? 99;
    if ($pa !== $pb) { return $pa <=> $pb; }
    if ($a['channel'] !== $b['channel']) { return strcmp($a['channel'], $b['channel']); }
    if ($a['arch'] !== $b['arch']) { return strcmp($a['arch'], $b['arch']); }
    if ($a['date'] !== $b['date']) { return strcmp($b['date'], $a['date']); }
    return strcmp($a['file'], $b['file']);
});

$out = [
    'schema' => 1,
    'site' => $site,
    'updated' => date('Y-m-d H:i:s'),
    'count' => count($items),
    'items' => $items,
];
$json = json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
$target = $dist . '/manifest.json';
file_put_contents($target, $json);

echo "共 " . count($items) . " 条 → {$target}\n";
foreach ($items as $it) {
    printf("  [%s] %-8s %-8s %-9s %-5s %s%s\n",
        $it['kind'], $it['platform'], $it['channel'], $it['arch'], $it['version'], $it['file'],
        !empty($it['latest']) ? '  ← 最新' : '');
}
