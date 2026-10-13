<?php
/**
 * build-ipk.php — luci-app-afrp 打包脚本（Windows/Linux 通用，无需 OpenWrt SDK）
 *
 * 用法：
 *   php build-ipk.php
 *       仅打包，产物输出到 openwrt/dist/：
 *         luci-app-afrp_{ver}_all.ipk   （opkg 安装）
 *         luci-app-afrp-{ver}.tar.gz          （通用压缩包，含 install.sh）
 *
 *   php build-ipk.php --verify
 *       打包后自检产物：解析 ar / 解压 tar.gz / 校验 control 字段与文件权限
 *
 *   php build-ipk.php --site-root <web目录> --site-url <站点地址> [--date YYYY-MM-DD] [--notes 说明]
 *       打包并把两个文件拷入 <web目录>/download/files/，
 *       同时登记 <web目录>/download/manifest.json
 *       （kind=app platform=openwrt channel=ipk|portable arch=all，
 *         id 为确定性 hex，同组只保留一个 latest）
 *       示例：php build-ipk.php --site-root D:/ProjectData/frp-oidc-php/web --site-url https://www.afrp.net
 */

error_reporting(E_ALL);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "只能在命令行运行。\n");
    exit(1);
}

$ROOT   = str_replace('\\', '/', dirname(__DIR__));          // openwrt/
$PKGDIR = $ROOT . '/luci-app-afrp';
$DIST   = $ROOT . '/dist';

function out(string $s): void { echo $s . "\n"; }
function die_msg(string $s): void { fwrite(STDERR, $s . "\n"); exit(1); }
function starts_with(string $h, string $n): bool { return strncmp($h, $n, strlen($n)) === 0; }
function cut(string $s, int $n): string { return function_exists('mb_substr') ? mb_substr($s, 0, $n) : substr($s, 0, $n); }

function usage(): void
{
    out('用法:');
    out('  php build-ipk.php                                  打包到 openwrt/dist/');
    out('  php build-ipk.php --verify                         打包并自检产物');
    out('  php build-ipk.php --site-root <web目录> --site-url <站点地址>');
    out('                    [--date YYYY-MM-DD] [--notes 说明]  打包并发布到下载站');
}

// ---------------------------------------------------------------- 版本号

function pkg_version(string $mkPath): array
{
    $mk  = (string)@file_get_contents($mkPath);
    $ver = '1.0.0';
    $rel = '1';
    if (preg_match('/^PKG_VERSION\s*:=\s*(.+)$/m', $mk, $m)) { $ver = trim($m[1]); }
    if (preg_match('/^PKG_RELEASE\s*:=\s*(.+)$/m', $mk, $m)) { $rel = trim($m[1]); }
    if (!preg_match('/^[A-Za-z0-9._+()-]{1,32}$/', $ver)) { die_msg('PKG_VERSION 非法: ' . $ver); }
    if (!preg_match('/^[0-9]+$/', $rel)) { die_msg('PKG_RELEASE 非法: ' . $rel); }
    return [$ver, $rel];
}

// ---------------------------------------------------------------- 收集安装载荷

/** 安装到路由器的文件权限（Windows 无 exec 位，按规则给定） */
function perm_for(string $dst): int
{
    if ($dst === 'etc/afrp/config.json') { return 0600; }
    if (starts_with($dst, 'etc/init.d/')) { return 0755; }
    if (starts_with($dst, 'usr/libexec/')) { return 0755; }
    return 0644;
}

/** 收集 root/ → / 与 htdocs/ → /www/ 的映射，返回 dst => ['src','mode'] */
function collect_payload(string $pkgDir): array
{
    $files = [];
    $map = [['root', ''], ['htdocs', 'www/']];
    foreach ($map as $entry) {
        [$sub, $prefix] = $entry;
        $base = $pkgDir . '/' . $sub;
        if (!is_dir($base)) { continue; }
        $it = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS)
        );
        foreach ($it as $f) {
            if (!$f->isFile()) { continue; }
            $rel = str_replace('\\', '/', substr($f->getPathname(), strlen($base) + 1));
            $dst = $prefix . $rel;
            $files[$dst] = ['src' => str_replace('\\', '/', $f->getPathname()), 'mode' => perm_for($dst)];
        }
    }
    ksort($files);
    return $files;
}

function payload_dirs(array $files): array
{
    $dirs = [];
    foreach (array_keys($files) as $dst) {
        $p = $dst;
        while (($pos = strrpos($p, '/')) !== false) {
            $p = substr($p, 0, $pos);
            $dirs[$p] = true;
        }
    }
    $dirs = array_keys($dirs);
    sort($dirs);
    return $dirs;
}

// ---------------------------------------------------------------- ustar tar 写入

function tar_oct(int $v, int $len): string
{
    return str_pad(decoct($v), $len - 1, '0', STR_PAD_LEFT) . "\0";
}

function tar_header(string $name, int $mode, int $size, int $mtime, string $type): string
{
    $h  = str_pad($name, 100, "\0");
    $h .= tar_oct($mode, 8);
    $h .= tar_oct(0, 8);                 // uid
    $h .= tar_oct(0, 8);                 // gid
    $h .= tar_oct($size, 12);
    $h .= tar_oct($mtime, 12);
    $h .= str_repeat(' ', 8);            // chksum 占位
    $h .= $type;                         // '0' 文件 / '5' 目录
    $h .= str_repeat("\0", 100);         // linkname
    $h .= "ustar\0";                     // magic
    $h .= '00';                          // version
    $h .= str_repeat("\0", 32);          // uname
    $h .= str_repeat("\0", 32);          // gname
    $h .= tar_oct(0, 8);                 // devmajor
    $h .= tar_oct(0, 8);                 // devminor
    $h .= str_repeat("\0", 155);         // prefix
    $h .= str_repeat("\0", 12);          // 500 → 512 填充
    $sum = 0;
    for ($i = 0; $i < 512; $i++) { $sum += ord($h[$i]); }
    $chk = sprintf('%06o', $sum) . "\0 ";
    return substr($h, 0, 148) . $chk . substr($h, 156);
}

function tar_append(string &$buf, int $mtime, string $name, int $mode, string $data, string $type = '0'): void
{
    if (strlen($name) > 100) { die_msg('tar 内路径过长（>100）: ' . $name); }
    $buf .= tar_header($name, $mode, strlen($data), $mtime, $type);
    if ($data !== '') {
        $buf .= $data;
        $pad = (512 - (strlen($data) % 512)) % 512;
        $buf .= str_repeat("\0", $pad);
    }
}

function tar_finish(string $buf): string { return $buf . str_repeat("\0", 1024); }

// ---------------------------------------------------------------- ustar tar 解析（--verify 用）

function tar_parse(string $buf): array
{
    $out = [];
    $off = 0;
    $n = strlen($buf);
    while ($off + 512 <= $n) {
        $h = substr($buf, $off, 512);
        if (rtrim($h, "\0") === '') { break; }
        $name = rtrim(substr($h, 0, 100), "\0");
        $mode = (int)octdec(trim(substr($h, 100, 8), " \0"));
        $size = (int)octdec(trim(substr($h, 124, 12), " \0"));
        $type = $h[156];
        $data = ($type === '0' && $size > 0) ? substr($buf, $off + 512, $size) : '';
        $out[$name] = ['mode' => $mode, 'type' => $type, 'size' => $size, 'data' => $data];
        $off += 512 + (($size + 511) & ~511);
    }
    return $out;
}

// ---------------------------------------------------------------- ar 写入/解析

function ar_append(string &$buf, string $name, string $data, int $mtime): void
{
    $h  = str_pad(substr($name, 0, 16), 16, ' ');
    $h .= str_pad((string)$mtime, 12, ' ');
    $h .= str_pad('0', 6, ' ');
    $h .= str_pad('0', 6, ' ');
    $h .= str_pad('100644', 8, ' ');
    $h .= str_pad((string)strlen($data), 10, ' ');
    $h .= "`\n";
    $buf .= $h . $data;
    if (strlen($data) % 2 !== 0) { $buf .= "\n"; }
}

function ar_parse(string $raw, array &$errs): array
{
    if (substr($raw, 0, 8) !== "!<arch>\n") { $errs[] = '缺少 ar 魔数 "!<arch>"'; return []; }
    $members = [];
    $off = 8;
    $len = strlen($raw);
    while ($off + 60 <= $len) {
        $h = substr($raw, $off, 60);
        if (substr($h, 58, 2) !== "`\n") { break; }
        $name = rtrim(substr($h, 0, 16), ' ');
        $size = (int)trim(substr($h, 48, 10));
        if ($size < 0 || $off + 60 + $size > $len) { $errs[] = '成员长度异常: ' . $name; break; }
        $members[$name] = substr($raw, $off + 60, $size);
        $off += 60 + $size + ($size % 2);
    }
    return $members;
}

// ---------------------------------------------------------------- 构建

function build(): array
{
    global $ROOT, $PKGDIR, $DIST;

    if (!function_exists('gzencode') || !function_exists('gzdecode')) {
        die_msg('需要 zlib 扩展（gzencode/gzdecode）。');
    }
    $mkPath = $PKGDIR . '/Makefile';
    if (!is_file($mkPath)) { die_msg('未找到 ' . $mkPath); }
    [$ver, $rel] = pkg_version($mkPath);

    $files = collect_payload($PKGDIR);
    if (!$files) { die_msg('未收集到任何安装文件，请检查 ' . $PKGDIR); }
    $dirs = payload_dirs($files);

    $installSh = $ROOT . '/install.sh';
    $readme    = $ROOT . '/README.md';
    if (!is_file($installSh)) { die_msg('未找到 ' . $installSh); }
    if (!is_file($readme))    { die_msg('未找到 ' . $readme); }

    if (!is_dir($DIST) && !@mkdir($DIST, 0775, true)) { die_msg('无法创建目录: ' . $DIST); }

    $mtime = time();
    $payloadBytes = 0;
    foreach ($files as $info) { $payloadBytes += (int)@filesize($info['src']); }
    $installedKb = (int)ceil($payloadBytes / 1024);

    // ---- control 元数据
    $control = "Package: luci-app-afrp\n"
        . "Version: {$ver}\n"
        . "Depends: luci-base, uclient-fetch, ca-bundle, frpc\n"
        . "SourceName: luci-app-afrp\n"
        . "License: MIT\n"
        . "Section: luci\n"
        . "Architecture: all\n"
        . "Installed-Size: {$installedKb}\n"
        . "Maintainer: AFRP <https://www.afrp.net>\n"
        . "Description: AFRP NAT traversal support and management by afrp.net.\n"
        . " Manage frpc tunnels with OIDC authentication, auto-update\n"
        . " frpc core, and monitor connection status from LuCI.\n";

    $conffiles = "/etc/afrp/config.json\n";

    $postinst = "#!/bin/sh\n"
        . "[ -n \"\${IPKG_INSTROOT}\" ] && exit 0\n"
        . "\n"
        . "chmod 600 /etc/afrp/config.json 2>/dev/null\n"
        . "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache\n"
        . "[ -x /etc/init.d/afrp ] && /etc/init.d/afrp enable\n"
        . "/etc/init.d/rpcd restart >/dev/null 2>&1\n"
        . "[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload >/dev/null 2>&1\n"
        . "exit 0\n";

    // ---- control.tar.gz
    $ctl = '';
    tar_append($ctl, $mtime, './control', 0644, $control);
    tar_append($ctl, $mtime, './conffiles', 0644, $conffiles);
    tar_append($ctl, $mtime, './postinst', 0755, $postinst);
    $ctlGz = gzencode(tar_finish($ctl), 9);
    if ($ctlGz === false) { die_msg('control.tar.gz 压缩失败'); }

    // ---- data.tar.gz
    $dat = '';
    foreach ($dirs as $d) { tar_append($dat, $mtime, './' . $d . '/', 0755, '', '5'); }
    foreach ($files as $dst => $info) {
        $data = @file_get_contents($info['src']);
        if ($data === false) { die_msg('读取失败: ' . $info['src']); }
        tar_append($dat, $mtime, './' . $dst, $info['mode'], $data);
    }
    $datGz = gzencode(tar_finish($dat), 9);
    if ($datGz === false) { die_msg('data.tar.gz 压缩失败'); }

    // ---- .ipk（APK v2: gzip 压缩的 tar，与 OpenWrt 23.05+ 官方格式一致）
    $ipkTar = '';
    tar_append($ipkTar, $mtime, './debian-binary', 0644, "2.0\n");
    tar_append($ipkTar, $mtime, './data.tar.gz', 0644, $datGz);
    tar_append($ipkTar, $mtime, './control.tar.gz', 0644, $ctlGz);
    $ipk = gzencode(tar_finish($ipkTar), 9);
    if ($ipk === false) { die_msg('.ipk 压缩失败'); }

    $ipkName = "luci-app-afrp_{$ver}_all.ipk";
    $tgzName = "luci-app-afrp-{$ver}.tar.gz";
    $ipkPath = $DIST . '/' . $ipkName;
    $tgzPath = $DIST . '/' . $tgzName;

    if (@file_put_contents($ipkPath, $ipk) === false) { die_msg('写入失败: ' . $ipkPath); }

    // ---- 通用 tar.gz（install.sh + README.md + files/）
    $top = "luci-app-afrp-{$ver}";
    $tgz = '';
    tar_append($tgz, $mtime, $top . '/', 0755, '', '5');
    tar_append($tgz, $mtime, $top . '/install.sh', 0755, (string)file_get_contents($installSh));
    tar_append($tgz, $mtime, $top . '/README.md', 0644, (string)file_get_contents($readme));
    tar_append($tgz, $mtime, $top . '/files/', 0755, '', '5');
    foreach ($dirs as $d) { tar_append($tgz, $mtime, $top . '/files/' . $d . '/', 0755, '', '5'); }
    foreach ($files as $dst => $info) {
        tar_append($tgz, $mtime, $top . '/files/' . $dst, $info['mode'], (string)file_get_contents($info['src']));
    }
    $tgzGz = gzencode(tar_finish($tgz), 9);
    if ($tgzGz === false) { die_msg('tar.gz 压缩失败'); }
    if (@file_put_contents($tgzPath, $tgzGz) === false) { die_msg('写入失败: ' . $tgzPath); }

    // ---- opkg Packages 索引（用于 GitHub Release 作为 opkg 源）
    $desc    = 'AFRP frpc tunnel management by afrp.net';
    $ipkSize = (int)filesize($ipkPath);
    $ipkSha  = (string)hash_file('sha256', $ipkPath);
    $pkgIndex = "Package: luci-app-afrp\n"
        . "Version: {$ver}\n"
        . "Depends: luci-base, uclient-fetch, ca-bundle, frpc\n"
        . "License: MIT\n"
        . "Section: luci\n"
        . "Architecture: all\n"
        . "Installed-Size: {$installedKb}\n"
        . "Filename: {$ipkName}\n"
        . "Size: {$ipkSize}\n"
        . "SHA256sum: {$ipkSha}\n"
        . "Description: {$desc}\n\n";
    $pkgPath = $DIST . '/Packages';
    if (@file_put_contents($pkgPath, $pkgIndex) === false) { die_msg('写入失败: ' . $pkgPath); }
    $pkgGzPath = $DIST . '/Packages.gz';
    @file_put_contents($pkgGzPath, gzencode($pkgIndex, 9));

    // ---- .apk 格式（OpenWrt 25.12+ APK 包管理器）
    // APK 格式：concatenated tar.gz，包含 .PKGINFO + 控制脚本 + 数据文件
    $pkginfo = "pkgname = luci-app-afrp\n"
        . "pkgver = {$ver}-r{$rel}\n"
        . "pkgdesc = AFRP NAT traversal support and management by afrp.net\n"
        . "url = https://www.afrp.net\n"
        . "arch = noarch\n"
        . "builddate = {$mtime}\n"
        . "packager = AFRP <https://www.afrp.net>\n"
        . "size = {$payloadBytes}\n"
        . "depend = luci-base\n"
        . "depend = uclient-fetch\n"
        . "depend = ca-bundle\n"
        . "depend = frpc\n"
        . "license = MIT\n";

    $postInstall = "#!/bin/sh\n"
        . "chmod 600 /etc/afrp/config.json 2>/dev/null\n"
        . "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache\n"
        . "[ -x /etc/init.d/afrp ] && /etc/init.d/afrp enable\n"
        . "/etc/init.d/rpcd restart >/dev/null 2>&1\n"
        . "[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload >/dev/null 2>&1\n";

    // APK 控制部分：.PKGINFO + .post-install
    $apkCtl = '';
    tar_append($apkCtl, $mtime, '.PKGINFO', 0644, $pkginfo);
    tar_append($apkCtl, $mtime, '.post-install', 0755, $postInstall);
    $apkCtlGz = gzencode(tar_finish($apkCtl), 9);
    if ($apkCtlGz === false) { die_msg('APK control.tar.gz 压缩失败'); }

    // APK 数据部分：与 IPK 共用 data.tar.gz
    // APK 格式是 concatenated tar.gz：control + data
    $apkName = "luci-app-afrp-{$ver}-r{$rel}.apk";
    $apkPath = $DIST . '/' . $apkName;
    $apkContent = $apkCtlGz . $datGz;
    if (@file_put_contents($apkPath, $apkContent) === false) { die_msg('写入失败: ' . $apkPath); }

    // ---- APKINDEX.tar.gz（apk 仓库索引，未签名，安装时需 --allow-untrusted）
    $apkFileSize = (int)filesize($apkPath);
    $ctlCsum = 'Q1' . base64_encode((string)hash('sha1', $apkCtlGz, true));
    $indexEntry = "C:{$ctlCsum}\n"
        . "P:luci-app-afrp\n"
        . "V:{$ver}-r{$rel}\n"
        . "A:noarch\n"
        . "S:{$apkFileSize}\n"
        . "I:{$payloadBytes}\n"
        . "T:AFRP NAT traversal support and management by afrp.net\n"
        . "U:https://www.afrp.net\n"
        . "L:MIT\n"
        . "o:luci-app-afrp\n"
        . "m:AFRP <https://www.afrp.net>\n"
        . "t:{$mtime}\n"
        . "D:luci-base\n"
        . "D:uclient-fetch\n"
        . "D:ca-bundle\n"
        . "D:frpc\n"
        . "\n";
    $repoDesc = "AFRP repository for OpenWrt 25.12+ (apk)\n"
        . "luci-app-afrp: manage frpc tunnels with OIDC authentication\n";
    $idx = '';
    tar_append($idx, $mtime, 'APKINDEX', 0644, $indexEntry);
    tar_append($idx, $mtime, 'DESCRIPTION', 0644, $repoDesc);
    $idxGz = gzencode(tar_finish($idx), 9);
    if ($idxGz === false) { die_msg('APKINDEX.tar.gz 压缩失败'); }
    $idxPath = $DIST . '/APKINDEX.tar.gz';
    if (@file_put_contents($idxPath, $idxGz) === false) { die_msg('写入失败: ' . $idxPath); }

    out("打包完成（v{$ver}，共 " . count($files) . " 个文件，{$installedKb} KB）：");
    foreach ([[$ipkPath, $ipkName], [$apkPath, $apkName], [$tgzPath, $tgzName], [$idxPath, 'APKINDEX.tar.gz'], [$pkgPath, 'Packages'], [$pkgGzPath, 'Packages.gz']] as $e) {
        [$p, $n] = $e;
        out(sprintf('  %s  %d 字节  sha256=%s', $n, (int)filesize($p), (string)hash_file('sha256', $p)));
    }

    return ['ver' => $ver, 'rel' => $rel, 'files' => $files, 'ipk' => $ipkPath, 'apk' => $apkPath, 'tgz' => $tgzPath, 'idx' => $idxPath];
}

// ---------------------------------------------------------------- 自检

function verify(array $b): bool
{
    global $DIST;
    $ok = true;
    $errs = [];
    out('');

    // ---- .ipk（APK v2: gzip 压缩的 tar）
    $raw = (string)@file_get_contents($b['ipk']);
    $members = [];
    $tar = @gzdecode($raw);
    if ($tar === false) {
        $errs[] = '.ipk gzip 解压失败';
    } else {
        $entries = tar_parse($tar);
        foreach ($entries as $name => $info) {
            $members[$name] = $info['data'];
        }
    }
    foreach (['./debian-binary', './control.tar.gz', './data.tar.gz'] as $need) {
        if (!isset($members[$need])) { $errs[] = "缺少成员: {$need}"; }
    }
    if (!$errs && $members['./debian-binary'] !== "2.0\n") { $errs[] = 'debian-binary 内容应为 "2.0\\n"'; }

    $ctlFiles = [];
    $datFiles = [];
    if (!$errs) {
        $ctl = gzdecode($members['./control.tar.gz']);
        $dat = gzdecode($members['./data.tar.gz']);
        if ($ctl === false) { $errs[] = 'control.tar.gz 解压失败'; }
        if ($dat === false) { $errs[] = 'data.tar.gz 解压失败'; }
        if (!$errs) {
            $ctlFiles = tar_parse($ctl);
            $datFiles = tar_parse($dat);
        }
    }

    if (!$errs) {
        $control = $ctlFiles['./control']['data'] ?? '';
        foreach (['Package: luci-app-afrp', "Version: {$b['ver']}", 'Architecture: all', 'Depends: '] as $need) {
            if (strpos($control, $need) === false) { $errs[] = 'control 缺少字段: ' . $need; }
        }
        if (strpos($ctlFiles['./conffiles']['data'] ?? '', '/etc/afrp/config.json') === false) { $errs[] = 'conffiles 缺少 /etc/afrp/config.json'; }
        if (($ctlFiles['./postinst']['mode'] ?? 0) !== 0755) { $errs[] = 'postinst 权限应为 0755'; }
        if (($ctlFiles['./control']['mode'] ?? 0) !== 0644) { $errs[] = 'control 权限应为 0644'; }

        foreach ($b['files'] as $dst => $info) {
            $key = './' . $dst;
            if (!isset($datFiles[$key])) { $errs[] = "data 缺少文件: {$dst}"; continue; }
            if ($datFiles[$key]['size'] !== (int)@filesize($info['src'])) { $errs[] = "{$dst} 大小不一致"; }
            if (!in_array($datFiles[$key]['mode'], [$info['mode']], true)) {
                $errs[] = sprintf('%s 权限应为 %04o，实际 %04o', $dst, $info['mode'], $datFiles[$key]['mode']);
            }
        }
        $dirCount = 0;
        foreach ($datFiles as $n => $f) { if ($f['type'] === '5') { $dirCount++; } }
        out('[ipk] APK v2: ./debian-binary / ./data.tar.gz / ./control.tar.gz  ✓');
        out('[ipk] control 字段 + conffiles + postinst(0755)  ✓');
        out('[ipk] data: ' . count($b['files']) . ' 个文件 + ' . $dirCount . ' 个目录，权限校验 ' . ($errs ? '✗' : '✓'));
    }

    // ---- .apk（OpenWrt 25.12+ APK 格式）
    $apkErr = [];
    if (isset($b['apk']) && is_file($b['apk'])) {
        $apkSize = (int)filesize($b['apk']);
        if ($apkSize < 1000) {
            $apkErr[] = 'APK 文件过小';
        } else {
            out('[apk] 文件大小 ' . $apkSize . ' 字节  ✓');
        }
    } else {
        $apkErr[] = 'APK 文件不存在';
    }

    $errs = array_merge($errs, $apkErr);

    // ---- tar.gz
    $tgzErr = [];
    $tgzRaw = (string)@file_get_contents($b['tgz']);
    $tar = gzdecode($tgzRaw);
    if ($tar === false) {
        $tgzErr[] = 'tar.gz 解压失败';
    } else {
        $tf = tar_parse($tar);
        $top = "luci-app-afrp-{$b['ver']}";
        if (!isset($tf[$top . '/install.sh']) || $tf[$top . '/install.sh']['mode'] !== 0755) { $tgzErr[] = 'install.sh 缺失或权限非 0755'; }
        if (!isset($tf[$top . '/README.md'])) { $tgzErr[] = 'README.md 缺失'; }
        foreach ($b['files'] as $dst => $info) {
            $key = $top . '/files/' . $dst;
            if (!isset($tf[$key])) { $tgzErr[] = "files/ 缺少: {$dst}"; continue; }
            if ($tf[$key]['mode'] !== $info['mode']) {
                $tgzErr[] = sprintf('files/%s 权限应为 %04o，实际 %04o', $dst, $info['mode'], $tf[$key]['mode']);
            }
        }
        if (!$tgzErr) { out('[tar.gz] install.sh(0755) + README.md + files/ 完整  ✓'); }
    }

    $errs = array_merge($errs, $tgzErr);

    // ---- Packages 索引
    $pkgPath = $DIST . '/Packages';
    $pkgGzPath = $DIST . '/Packages.gz';
    $pkgErr = [];
    if (!is_file($pkgPath)) {
        $pkgErr[] = 'Packages 文件不存在';
    } else {
        $pkgContent = (string)file_get_contents($pkgPath);
        foreach (['Package: luci-app-afrp', "Version: {$b['ver']}", 'Architecture: all', "Filename: luci-app-afrp_{$b['ver']}_all.ipk"] as $need) {
            if (strpos($pkgContent, $need) === false) { $pkgErr[] = 'Packages 缺少: ' . $need; }
        }
        if (!is_file($pkgGzPath)) { $pkgErr[] = 'Packages.gz 不存在'; }
        if (!$pkgErr) { out('[Packages] 索引字段完整 + Packages.gz  ✓'); }
    }

    $errs = array_merge($errs, $pkgErr);
    if ($errs) {
        $ok = false;
        foreach ($errs as $e) { fwrite(STDERR, '  ✗ ' . $e . "\n"); }
    }
    out($ok ? '自检结果: PASS' : '自检结果: FAIL');
    return $ok;
}

// ---------------------------------------------------------------- 发布到下载站

function manifest_sort(array $items): array
{
    $order = array_flip(['windows', 'macos', 'linux', 'android', 'ohos', 'openwrt']);
    usort($items, function (array $a, array $b) use ($order): int {
        $ka = (string)($a['kind'] ?? '');
        $kb = (string)($b['kind'] ?? '');
        if ($ka !== $kb) { return $ka === 'app' ? -1 : 1; }
        $pa = $order[(string)($a['platform'] ?? '')] ?? 99;
        $pb = $order[(string)($b['platform'] ?? '')] ?? 99;
        if ($pa !== $pb) { return $pa <=> $pb; }
        $c = strcmp((string)($a['channel'] ?? ''), (string)($b['channel'] ?? ''));
        if ($c !== 0) { return $c; }
        $c = strcmp((string)($a['arch'] ?? ''), (string)($b['arch'] ?? ''));
        if ($c !== 0) { return $c; }
        $c = strcmp((string)($b['date'] ?? ''), (string)($a['date'] ?? ''));
        if ($c !== 0) { return $c; }
        return strcmp((string)($a['file'] ?? ''), (string)($b['file'] ?? ''));
    });
    return $items;
}

function publish(string $webRoot, string $siteUrl, string $date, ?string $notes, array $b): void
{
    $siteUrl = rtrim($siteUrl, '/');
    if (!preg_match('~^https?://~', $siteUrl)) { die_msg('--site-url 必须以 http(s):// 开头'); }
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) { die_msg('--date 格式应为 YYYY-MM-DD'); }

    $webRoot  = rtrim(str_replace('\\', '/', $webRoot), '/');
    $filesDir = $webRoot . '/download/files';
    $manifestPath = $webRoot . '/download/manifest.json';
    if (!is_dir($filesDir) && !@mkdir($filesDir, 0775, true)) { die_msg('无法创建目录: ' . $filesDir); }

    $items = [];
    $manifest = ['schema' => 1, 'site' => $siteUrl, 'updated' => '', 'count' => 0, 'items' => []];
    if (is_file($manifestPath)) {
        $j = json_decode((string)@file_get_contents($manifestPath), true);
        if (is_array($j) && isset($j['items']) && is_array($j['items'])) {
            $manifest = $j;
            foreach ($j['items'] as $it) {
                if (is_array($it) && preg_match('/^[0-9a-f]{8,16}$/', (string)($it['id'] ?? ''))) { $items[] = $it; }
            }
        } else {
            out('提示: 现有 manifest 无法解析，将按空清单重建。');
        }
    }

    $pairs = [['ipk', $b['ipk']], ['apk', $b['apk'] ?? ''], ['portable', $b['tgz']]];
    foreach ($pairs as $pair) {
        [$channel, $srcPath] = $pair;
        if ($srcPath === '' || !is_file($srcPath)) { continue; }
        $file = basename($srcPath);
        $dst = $filesDir . '/' . $file;
        if (!@copy($srcPath, $dst)) { die_msg('拷贝失败: ' . $dst); }

        $notesText = $notes !== null && $notes !== ''
            ? $notes
            : ($channel === 'ipk' ? 'LuCI 网页插件（opkg install 安装，OpenWrt 24.10 及以下）'
                : ($channel === 'apk' ? 'LuCI 网页插件（apk add 安装，OpenWrt 25.12 及以上）'
                : '通用压缩包（解压后运行 install.sh）'));

        $item = [
            'id'       => substr(md5('luci-app-afrp|' . $channel), 0, 12),
            'kind'     => 'app',
            'platform' => 'openwrt',
            'channel'  => $channel,
            'arch'     => 'all',
            'version'  => $b['ver'],
            'file'     => $file,
            'url'      => $siteUrl . '/download/files/' . rawurlencode($file),
            'sha256'   => (string)hash_file('sha256', $dst),
            'size'     => (int)filesize($dst),
            'date'     => $date,
            'notes'    => cut($notesText, 300),
            'latest'   => true,
        ];

        $found = false;
        foreach ($items as $i => $it) {
            if (($it['id'] ?? '') === $item['id']) { $items[$i] = $item; $found = true; break; }
        }
        if (!$found) { $items[] = $item; }
        foreach ($items as $i => $it) {
            if (($it['id'] ?? '') !== $item['id']
                && ($it['kind'] ?? '') === $item['kind']
                && ($it['platform'] ?? '') === $item['platform']
                && ($it['channel'] ?? '') === $item['channel']
                && ($it['arch'] ?? '') === $item['arch']) {
                $items[$i]['latest'] = false;
            }
        }
        out('已拷贝: ' . $dst);
    }

    $items = manifest_sort($items);
    $manifest['schema']  = 1;
    $manifest['site']    = $siteUrl;
    $manifest['updated'] = date('Y-m-d H:i:s');
    $manifest['count']   = count($items);
    $manifest['items']   = $items;

    $json = json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    $tmp = $manifestPath . '.tmp';
    if (@file_put_contents($tmp, $json) === false || !@rename($tmp, $manifestPath)) {
        @unlink($tmp);
        die_msg('manifest 写入失败: ' . $manifestPath);
    }
    out('已更新清单: ' . $manifestPath . '（共 ' . count($items) . ' 条）');

    $opkgDir = $webRoot . '/opkg/packages';
    if (!is_dir($opkgDir) && !@mkdir($opkgDir, 0775, true)) { die_msg('无法创建目录: ' . $opkgDir); }

    $ipkSrc = $b['ipk'];
    $ipkDst = $opkgDir . '/' . basename($ipkSrc);
    if (!@copy($ipkSrc, $ipkDst)) { die_msg('拷贝 ipk 到 opkg feed 失败: ' . $ipkDst); }

    $ipkSize = filesize($ipkDst);
    $ipkSha  = (string)hash_file('sha256', $ipkDst);
    $ipkKb   = (int)ceil($ipkSize / 1024);
    $desc    = 'AFRP NAT traversal support and management by afrp.net.';
    $descCont = ' Manage frpc tunnels with OIDC authentication, auto-update' . "\n"
              . ' frpc core, and monitor connection status from LuCI.';

    $pkgIndex = "Package: luci-app-afrp\n"
        . "Version: {$b['ver']}\n"
        . "Depends: luci-base, uclient-fetch, ca-bundle, frpc\n"
        . "License: MIT\n"
        . "Section: luci\n"
        . "Architecture: all\n"
        . "Installed-Size: {$ipkKb}\n"
        . "Filename: " . basename($ipkSrc) . "\n"
        . "Size: {$ipkSize}\n"
        . "SHA256sum: {$ipkSha}\n"
        . "Description: {$desc}\n"
        . "{$descCont}\n\n";

    $pkgPath = $opkgDir . '/Packages';
    $tmp = $pkgPath . '.tmp';
    if (@file_put_contents($tmp, $pkgIndex) === false || !@rename($tmp, $pkgPath)) {
        @unlink($tmp);
        die_msg('Packages 索引写入失败: ' . $pkgPath);
    }

    $pkgGz = $opkgDir . '/Packages.gz';
    @file_put_contents($pkgGz, gzencode($pkgIndex, 9));

    out('已更新 opkg feed: ' . $opkgDir);
    out('下载页: ' . $siteUrl . '/download/');
}

// ---------------------------------------------------------------- 入口

$opts = ['verify' => false, 'site-root' => null, 'site-url' => null, 'date' => null, 'notes' => null];
$args = array_slice((array)$argv, 1);
for ($i = 0; $i < count($args); $i++) {
    $a = $args[$i];
    if ($a === '--verify')            { $opts['verify'] = true; }
    elseif ($a === '--help' || $a === '-h') { usage(); exit(0); }
    elseif ($a === '--site-root')     { $opts['site-root'] = $args[++$i] ?? ''; }
    elseif ($a === '--site-url')      { $opts['site-url']  = $args[++$i] ?? ''; }
    elseif ($a === '--date')          { $opts['date']      = $args[++$i] ?? ''; }
    elseif ($a === '--notes')         { $opts['notes']     = $args[++$i] ?? ''; }
    else { die_msg('未知参数: ' . $a . '（--help 查看用法）'); }
}

$built = build();

$pass = true;
if ($opts['verify']) {
    $pass = verify($built);
}

if ($opts['site-root'] !== null || $opts['site-url'] !== null) {
    if (!$opts['site-root'] || !$opts['site-url']) {
        die_msg('发布需要同时提供 --site-root <web目录> 与 --site-url <站点地址>');
    }
    $date = $opts['date'] ?: date('Y-m-d');
    publish($opts['site-root'], $opts['site-url'], $date, $opts['notes'], $built);
}

exit($pass ? 0 : 1);
