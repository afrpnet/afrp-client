<?php
/**
 * App 图标生成器
 *
 * 安装（install）使用用户提供的源图 assets/brand/app_icon_source.png
 * （珊瑚橙底 + 白色小写 a）：居中裁方、铺满画布，再套 squircle 圆角遮罩。
 * 其余基于 Comfortaa Bold 字体的设计函数为早期候选方案，仅 preview 时展示对比。
 *
 * 用法（本地 PHP）：
 *   php tool/gen_app_icon.php preview   # 候选方案预览 → build/icon_preview/
 *   php tool/gen_app_icon.php install   # 写入各平台图标（Windows/Android/OHOS/macOS）
 */

$ROOT = dirname(__DIR__);
$FONT = $ROOT . '/assets/fonts/ComfortaaBold.ttf';
$SOURCE = $ROOT . '/assets/brand/app_icon_source.png';

const CORAL = [0xFF, 0x74, 0x52];
const GREEN = [0x1C, 0xC8, 0x8A];
const WHITE = [0xFF, 0xFF, 0xFF];
const BLACK = [0x00, 0x00, 0x00];

/* ---------------- 基础绘图 ---------------- */

function canvas(int $size): GdImage
{
    $im = imagecreatetruecolor($size, $size);
    imagealphablending($im, false);
    imagesavealpha($im, true);
    imagefill($im, 0, 0, imagecolorallocatealpha($im, 0, 0, 0, 127));
    return $im;
}

function rgb(GdImage $im, array $c): int
{
    return imagecolorallocate($im, $c[0], $c[1], $c[2]);
}

/** 圆角方形（margin 为画布比例，0 = 满幅） */
function squircle(GdImage $im, int $size, float $margin, array $bg): void
{
    $m = (int) round($size * $margin);
    $x0 = $m;
    $y0 = $m;
    $x1 = $size - 1 - $m;
    $y1 = $size - 1 - $m;
    $r = (int) round(($x1 - $x0) * 0.2252);
    $d = $r * 2;
    $col = rgb($im, $bg);
    imagealphablending($im, false);
    imagefilledrectangle($im, $x0 + $r, $y0, $x1 - $r, $y1, $col);
    imagefilledrectangle($im, $x0, $y0 + $r, $x1, $y1 - $r, $col);
    imagefilledellipse($im, $x0 + $r, $y0 + $r, $d, $d, $col);
    imagefilledellipse($im, $x1 - $r, $y0 + $r, $d, $d, $col);
    imagefilledellipse($im, $x0 + $r, $y1 - $r, $d, $d, $col);
    imagefilledellipse($im, $x1 - $r, $y1 - $r, $d, $d, $col);
}

/** 文字墨迹包围盒（相对基线原点）：[left, top, right, bottom] */
function ink_box(int $pt, string $font, string $text): array
{
    $b = imagettfbbox($pt, 0, $font, $text);
    return [min($b[0], $b[6]), min($b[5], $b[7]), max($b[2], $b[4]), max($b[1], $b[3])];
}

/** 按墨迹宽目标求字号 */
function fit_pt(string $font, string $text, float $targetW, int $guess): int
{
    [$l, , $r] = ink_box($guess, $font, $text);
    return max(1, (int) round($guess * $targetW / ($r - $l)));
}

/** 以墨迹中心渲染文字，(cx,cy) 为画布坐标 */
function draw_centered(GdImage $im, int $pt, array $color, string $font, string $text, float $cx, float $cy): array
{
    [$l, $t, $r, $b] = ink_box($pt, $font, $text);
    $x = (int) round($cx - ($l + $r) / 2);
    $y = (int) round($cy - ($t + $b) / 2);
    imagealphablending($im, true);
    imagettftext($im, $pt, 0, $x, $y, rgb($im, $color), $font, $text);
    return [$r - $l, $b - $t];
}

/* ---------------- 设计方案 ---------------- */

/** 方案一/二：两行字标，「afrp」上一行、「.net」下一行 */
function design_two_line(int $size, array $bg): GdImage
{
    global $FONT;
    $im = canvas($size);
    squircle($im, $size, 0, $bg);
    $target = $size * 0.60;
    $pt = min(
        fit_pt($FONT, 'afrp', $target, (int) ($size * 0.32)),
        fit_pt($FONT, '.net', $target, (int) ($size * 0.32))
    );
    [, $t1, , $b1] = ink_box($pt, $FONT, 'afrp');
    [, $t2, , $b2] = ink_box($pt, $FONT, '.net');
    $h1 = $b1 - $t1;
    $h2 = $b2 - $t2;
    $gap = $size * 0.045;
    $total = $h1 + $gap + $h2;
    $cy = $size / 2;
    draw_centered($im, $pt, CORAL, $FONT, 'afrp', $size / 2, $cy - $total / 2 + $h1 / 2);
    draw_centered($im, $pt, GREEN, $FONT, '.net', $size / 2, $cy + $total / 2 - $h2 / 2);
    return $im;
}

/** 方案三/四：单字母组合「a.」 */
function design_monogram(int $size, array $bg): GdImage
{
    global $FONT;
    $im = canvas($size);
    squircle($im, $size, 0, $bg);
    $pt = fit_pt($FONT, 'a.', $size * 0.52, (int) ($size * 0.35));
    // 用整串「a.」的墨迹定位，点的步进 = 整串右缘 - 点自身右缘，保证原字距
    [$l, $t, $r, $b] = ink_box($pt, $FONT, 'a.');
    $advA = $r - ink_box($pt, $FONT, '.')[2];
    $x0 = (int) round($size / 2 - ($l + $r) / 2);
    $y0 = (int) round($size / 2 - ($t + $b) / 2);
    imagealphablending($im, true);
    imagettftext($im, $pt, 0, $x0, $y0, rgb($im, CORAL), $FONT, 'a');
    imagettftext($im, $pt, 0, $x0 + $advA, $y0, rgb($im, GREEN), $FONT, '.');
    return $im;
}

/** 方案五：一行「afrp」+ 末尾绿点（afrp.） */
function design_one_line(int $size, array $bg): GdImage
{
    global $FONT;
    $im = canvas($size);
    squircle($im, $size, 0, $bg);
    $pt = fit_pt($FONT, 'afrp.', $size * 0.66, (int) ($size * 0.28));
    [$l, $t, $r, $b] = ink_box($pt, $FONT, 'afrp.');
    $rd = ink_box($pt, $FONT, '.')[2];
    $advA = $r - $rd; // 点相对整串原点的偏移
    $x0 = (int) round($size / 2 - ($l + $r) / 2);
    $y0 = (int) round($size / 2 - ($t + $b) / 2);
    imagealphablending($im, true);
    imagettftext($im, $pt, 0, $x0, $y0, rgb($im, CORAL), $FONT, 'afrp');
    imagettftext($im, $pt, 0, $x0 + $advA, $y0, rgb($im, GREEN), $FONT, '.');
    return $im;
}

/** 方案（当前采用）：源图居中裁方 → 铺满画布 → squircle 圆角遮罩 */
function design_from_image(int $size): GdImage
{
    global $SOURCE;
    $src = @imagecreatefrompng($SOURCE);
    if ($src === false) {
        fwrite(STDERR, "无法读取源图：$SOURCE\n");
        exit(1);
    }
    $sw = imagesx($src);
    $sh = imagesy($src);
    $side = min($sw, $sh);
    $im = canvas($size);
    imagecopyresampled($im, $src, 0, 0, intdiv($sw - $side, 2), intdiv($sh - $side, 2), $size, $size, $side, $side);
    imagedestroy($src);
    mask_squircle($im, $size);
    return $im;
}

/** squircle 圆角遮罩：半径 = 0.2252×边长（与既有设计一致），四角外透明、边缘 1px 渐隐抗锯齿 */
function mask_squircle(GdImage $im, int $size): void
{
    $max = $size - 1;
    $r = $max * 0.2252;
    for ($y = 0; $y < $size; $y++) {
        $py = $y + 0.5;
        if ($py >= $r && $py <= $max - $r) {
            continue; // 中间横带：整行全覆盖
        }
        $cory = $py < $r ? $r : $max - $r;
        for ($x = 0; $x < $size; $x++) {
            $px = $x + 0.5;
            if ($px >= $r && $px <= $max - $r) {
                continue; // 中间竖带：全覆盖
            }
            $corx = $px < $r ? $r : $max - $r;
            $cov = $r + 0.5 - hypot($px - $corx, $py - $cory);
            if ($cov >= 1) {
                continue;
            }
            $c = imagecolorat($im, $x, $y);
            $a = $cov <= 0 ? 127 : (int) round((1 - $cov) * 127);
            imagesetpixel($im, $x, $y, ($c & 0x00FFFFFF) | ($a << 24));
        }
    }
}

/* ---------------- 缩放 ---------------- */

function downscale(GdImage $im, int $size): GdImage
{
    $w = imagesx($im);
    while (intdiv($w, 2) >= $size) {
        $nw = intdiv($w, 2);
        $tmp = canvas($nw);
        imagealphablending($tmp, false);
        imagecopyresampled($tmp, $im, 0, 0, 0, 0, $nw, $nw, $w, $w);
        $im = $tmp;
        $w = $nw;
    }
    if ($w !== $size) {
        $tmp = canvas($size);
        imagealphablending($tmp, false);
        imagecopyresampled($tmp, $im, 0, 0, 0, 0, $size, $size, $w, $w);
        $im = $tmp;
    }
    return $im;
}

/* ---------------- 预览 ---------------- */

function preview(): void
{
    global $ROOT;
    $variants = [
        'V0-source-round'   => fn(int $s) => design_from_image($s),
        'V1-two-line-white' => fn(int $s) => design_two_line($s, WHITE),
        'V2-two-line-navy'  => fn(int $s) => design_two_line($s, [0x11, 0x22, 0x38]),
        'V3-monogram-white' => fn(int $s) => design_monogram($s, WHITE),
        'V4-monogram-navy'  => fn(int $s) => design_monogram($s, [0x11, 0x22, 0x38]),
        'V5-one-line-white' => fn(int $s) => design_one_line($s, WHITE),
    ];
    $outDir = $ROOT . '/build/icon_preview';
    if (!is_dir($outDir)) {
        mkdir($outDir, 0777, true);
    }
    foreach ($variants as $name => $fn) {
        $master = $fn(1024);
        imagepng(downscale($master, 512), $outDir . '/' . $name . '.png');
        imagedestroy($master);
    }

    // 拼相册：512 主图一行 + 48/32/16 小图一行
    $pad = 24;
    $cell = 512;
    $sheetW = count($variants) * ($cell + $pad) + $pad;
    $rowH = $cell + 40;
    $smallRowH = 120;
    $sheetH = $rowH + $smallRowH + $pad * 2;
    $sheet = imagecreatetruecolor($sheetW, $sheetH);
    imagefilledrectangle($sheet, 0, 0, $sheetW, $sheetH, imagecolorallocate($sheet, 0xE8, 0xEC, 0xF1));
    $x = $pad;
    $x2 = $pad;
    foreach ($variants as $name => $fn) {
        $big = imagecreatefrompng($outDir . '/' . $name . '.png');
        imagealphablending($sheet, true);
        imagecopy($sheet, $big, $x, $pad, 0, 0, 512, 512);
        imagestring($sheet, 4, $x + 8, $pad + 512 + 8, $name, imagecolorallocate($sheet, 0x22, 0x2A, 0x33));
        imagedestroy($big);
        $master = $fn(1024);
        $ms = [48, 32, 16];
        $sx = $x2;
        foreach ($ms as $s) {
            $sm = downscale($master, $s);
            imagecopy($sheet, $sm, $sx, $rowH + $pad + 8, 0, 0, $s, $s);
            $sx += $s + 16;
            imagedestroy($sm);
        }
        imagedestroy($master);
        $x += $cell + $pad;
        $x2 += $cell + $pad;
    }
    imagepng($sheet, $outDir . '/_sheet.png');
    echo "preview -> $outDir\n";
}

/* ---------------- 安装 ---------------- */

function png_bytes(GdImage $im): string
{
    ob_start();
    imagepng($im);
    return ob_get_clean();
}

/** ICO 条目数据：≤128 用 32bpp BMP(DIB)，256 用 PNG（Windows 全兼容） */
function ico_dib(GdImage $im, int $w, int $h): string
{
    $xor = '';
    for ($y = $h - 1; $y >= 0; $y--) {
        $row = '';
        for ($x = 0; $x < $w; $x++) {
            $c = imagecolorat($im, $x, $y);
            $a = (($c >> 24) & 0x7F);
            $a8 = (int) round((127 - $a) * 255 / 127);
            $row .= chr($c & 0xFF) . chr(($c >> 8) & 0xFF) . chr(($c >> 16) & 0xFF) . chr($a8);
        }
        $xor .= $row;
    }
    $maskRow = str_repeat("\x00", ((int) ceil($w / 32)) * 4);
    $mask = str_repeat($maskRow, $h);
    $header = pack('VVVvvVVVVVV', 40, $w, $h * 2, 1, 32, 0, strlen($xor), 0, 0, 0, 0);
    return $header . $xor . $mask;
}

function write_ico(string $path, GdImage $master, array $sizes): void
{
    $images = [];
    foreach ($sizes as $s) {
        $img = downscale($master, $s);
        $images[$s] = $s === 256 ? png_bytes($img) : ico_dib($img, $s, $s);
        imagedestroy($img);
    }
    $count = count($images);
    $out = pack('vvv', 0, 1, $count);
    $offset = 6 + $count * 16;
    foreach ($images as $s => $data) {
        $b = $s === 256 ? 0 : $s;
        $out .= pack('CCCCvvVV', $b, $b, 0, 0, 1, 32, strlen($data), $offset);
        $offset += strlen($data);
    }
    foreach ($images as $data) {
        $out .= $data;
    }
    file_put_contents($path, $out);
}

function install(): void
{
    global $ROOT;
    // 选定方案：源图（橙底白 a）+ squircle 圆角
    $masterWin = design_from_image(2048);
    $masterMac = canvas(1024);
    // macOS 风格：内容按 824/1024 留边
    $sub = design_from_image(824);
    imagealphablending($masterMac, false);
    imagecopy($masterMac, $sub, 100, 100, 0, 0, 824, 824);
    imagedestroy($sub);

    write_ico($ROOT . '/windows/runner/resources/app_icon.ico', $masterWin, [16, 24, 32, 48, 64, 128, 256]);

    $android = ['mdpi' => 48, 'hdpi' => 72, 'xhdpi' => 96, 'xxhdpi' => 144, 'xxxhdpi' => 192];
    foreach ($android as $dpi => $s) {
        $img = downscale($masterWin, $s);
        imagepng($img, $ROOT . "/android/app/src/main/res/mipmap-$dpi/ic_launcher.png");
        imagedestroy($img);
    }

    foreach ([
        '/ohos/AppScope/resources/base/media/app_icon.png' => 216,
        '/ohos/entry/src/main/resources/base/media/icon.png' => 216,
    ] as $path => $s) {
        $img = downscale($masterWin, $s);
        imagepng($img, $ROOT . $path);
        imagedestroy($img);
    }

    $set = $ROOT . '/macos/Runner/Assets.xcassets/AppIcon.appiconset';
    foreach ([16, 32, 64, 128, 256, 512, 1024] as $s) {
        $img = downscale($masterMac, $s);
        imagepng($img, "$set/app_icon_$s.png");
        imagedestroy($img);
    }

    imagedestroy($masterWin);
    imagedestroy($masterMac);
    echo "installed: windows ico / android mipmaps / ohos icons / macos appiconset\n";
}

$mode = $argv[1] ?? 'preview';
$mode === 'install' ? install() : preview();
