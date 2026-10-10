<?php
error_reporting(E_ALL);

$ftpHost = 'bt.kw.ke';
$ftpUser = 'darny';
$ftpPass = 'eSrWTdXGCEFw';

$manifestLocal = 'D:/ProjectData/frp-oidc-php/web/download/manifest.json';
$manifest = json_decode(file_get_contents($manifestLocal), true);

// Remove openwrt app entries (kind=app, platform=openwrt)
$before = count($manifest['items']);
$manifest['items'] = array_values(array_filter($manifest['items'], function ($item) {
    return !(($item['kind'] ?? '') === 'app' && ($item['platform'] ?? '') === 'openwrt');
}));
$after = count($manifest['items']);
$manifest['count'] = $after;
$manifest['updated'] = date('Y-m-d H:i:s');

echo "Removed " . ($before - $after) . " openwrt app entries, now {$after} items\n";

// Save updated manifest locally
$json = json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
file_put_contents($manifestLocal, $json . "\n");
echo "Updated local manifest.json\n";

// Connect FTP
$conn = ftp_connect($ftpHost);
if (!$conn) { die("FTP connect failed\n"); }
if (!ftp_login($conn, $ftpUser, $ftpPass)) { die("FTP login failed\n"); }
ftp_pasv($conn, true);
echo "FTP connected to {$ftpHost}\n";

// Delete openwrt files from FTP
$filesToDelete = [
    'luci-app-afrp_1.1.0-1_all.ipk',
    'luci-app-afrp-1.1.0.tar.gz',
];
foreach ($filesToDelete as $f) {
    $path = "files/{$f}";
    if (@ftp_delete($conn, $path)) {
        echo "Deleted: {$path}\n";
    } else {
        echo "Not found or delete failed: {$path}\n";
    }
}

// Upload updated manifest
if (ftp_put($conn, 'manifest.json', $manifestLocal, FTP_BINARY)) {
    echo "Uploaded manifest.json\n";
} else {
    echo "FAILED to upload manifest.json\n";
}

ftp_close($conn);
echo "Done.\n";
