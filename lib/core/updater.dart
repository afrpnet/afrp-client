import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../frpc/frpc_manager.dart';
import 'models.dart';
import 'sha256.dart';

/// App 版本号（发版时与 pubspec.yaml、安装脚本同步更新）
const String kAppVersion = '1.3.26';

const MethodChannel _installerChannel = MethodChannel('afrp_oidc/installer');

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);

  @override
  String toString() => message;
}

/// 下载页更新清单（web/download/manifest.json）中的一个条目
class UpdateEntry {
  final String id;
  final String kind;
  final String platform;
  final String channel;
  final String arch;
  final String version;
  final String file;
  final String url;
  final String sha256;
  final String date;
  final String notes;
  final int size;
  final bool latest;
  final List<Map<String, dynamic>> mirrors;

  const UpdateEntry({
    required this.id,
    required this.kind,
    required this.platform,
    required this.channel,
    required this.arch,
    required this.version,
    required this.file,
    required this.url,
    required this.sha256,
    required this.date,
    required this.notes,
    required this.size,
    required this.latest,
    this.mirrors = const [],
  });

  factory UpdateEntry.fromJson(Map<String, dynamic> json) {
    String s(String k) => '${json[k] ?? ''}';
    final rawMirrors = json['mirrors'];
    final mirrors = <Map<String, dynamic>>[];
    if (rawMirrors is List) {
      for (final m in rawMirrors) {
        if (m is Map<String, dynamic>) {
          mirrors.add(m);
        }
      }
    }
    return UpdateEntry(
      id: s('id'),
      kind: s('kind'),
      platform: s('platform'),
      channel: s('channel'),
      arch: s('arch'),
      version: s('version'),
      file: s('file'),
      url: s('url'),
      sha256: s('sha256'),
      date: s('date'),
      notes: s('notes'),
      size: json['size'] is num ? (json['size'] as num).toInt() : 0,
      latest: json['latest'] == true,
      mirrors: mirrors,
    );
  }

  String get sizeText {
    if (size >= 1 << 30) {
      return '${(size / (1 << 30)).toStringAsFixed(2)} GB';
    }
    if (size >= 1 << 20) {
      return '${(size / (1 << 20)).toStringAsFixed(1)} MB';
    }
    if (size >= 1 << 10) {
      return '${(size / (1 << 10)).toStringAsFixed(0)} KB';
    }
    return size > 0 ? '$size B' : '';
  }
}

class UpdateManifest {
  final int schema;
  final List<UpdateEntry> items;

  const UpdateManifest({required this.schema, required this.items});

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final items = <UpdateEntry>[];
    final raw = json['items'];
    if (raw is List) {
      for (final it in raw) {
        if (it is Map<String, dynamic>) {
          items.add(UpdateEntry.fromJson(it));
        }
      }
    }
    return UpdateManifest(
      schema: json['schema'] is num ? (json['schema'] as num).toInt() : 0,
      items: items,
    );
  }
}

String _trimBase(String baseUrl) => baseUrl.replaceAll(RegExp(r'/+$'), '');

/// GitHub 源基址：形如 https://github.com/ 或 https://ghfast.top/https://github.com/
/// 末尾必须保留斜杠，否则拼出来的 URL 会少一个分隔符
String _ghBase(String base) {
  final b = base.trim();
  return b.endsWith('/') ? b : '$b/';
}

String manifestUrl(String baseUrl) =>
    '${_trimBase(baseUrl)}/download/manifest.json';

String downloadPageUrl(String baseUrl) => '${_trimBase(baseUrl)}/download/';

// ---------------------------------------------------------------------------
// Cloudflare R2 下载源（不限流量，优先使用）
// ---------------------------------------------------------------------------

/// R2 自定义域名（后台「APP 设置」可下发覆盖）
String kR2BaseUrl = 'https://dl.afrp.net';

/// 构建 R2 下载 URL
String r2DownloadUrl(String filename, {String subdir = ''}) {
  if (subdir.isNotEmpty) {
    return '$kR2BaseUrl/$subdir/$filename';
  }
  return '$kR2BaseUrl/$filename';
}

/// 判断文件名是否属于 frpc 类别
bool isFrpcFile(String filename) {
  // R2 上的 frpc 产物名统一是 frpc_ 前缀（frpc_x_windows_amd64.exe），
  // 上游整包是 frp_ 前缀（frp_x_windows_amd64.zip），两者都要归到 frpc 子目录
  return filename.startsWith('frp_') ||
      filename.startsWith('frpc_') ||
      filename.endsWith('.ipk') ||
      filename.contains('luci-app-afrp');
}

/// 根据文件类型确定 R2 子目录
String r2SubdirForFile(String filename) {
  if (isFrpcFile(filename)) {
    return 'frpc';
  }
  return 'app';
}

// ---------------------------------------------------------------------------
// GitHub Release 更新源（官方 + 代理，按序回退）
// ---------------------------------------------------------------------------

/// GitHub Release 下载源：先试官方，不通再用代理（后台「APP 设置」可下发覆盖）
List<String> kGitHubSources = [
  'https://github.com/',
  'https://ghfast.top/https://github.com/',
  'https://gh-proxy.com/https://github.com/',
  'https://ghproxy.net/https://github.com/',
];

/// App 自更新仓库 / frpc 内核仓库（后台可下发覆盖）
String kGhRepo = 'afrpnet/afrp-client';
String kFrpcRepo = 'fatedier/frp';

/// 后台下发的最低可用版本与强制更新开关（空表示不限制）
String kMinVersion = '';
bool kForceUpdate = false;

/// 用 /api/config.php 下发的运行参数覆盖内置默认值；留空字段保持默认。
/// 在 AppState.loadConfig() 解析配置后调用一次。
void applyRemoteConfig(PublicConfig cfg) {
  final r2 = cfg.r2BaseUrl.trim();
  if (r2.isNotEmpty) {
    kR2BaseUrl = r2.replaceAll(RegExp(r'/+$'), '');
  }
  final repo = cfg.ghRepo.trim();
  if (repo.isNotEmpty) {
    kGhRepo = repo;
  }
  final frpcRepo = cfg.frpcRepo.trim();
  if (frpcRepo.isNotEmpty) {
    kFrpcRepo = frpcRepo;
  }
  if (cfg.ghMirrors.isNotEmpty) {
    kGitHubSources = List<String>.from(cfg.ghMirrors);
  }
  kMinVersion = cfg.minVersion.trim();
  kForceUpdate = cfg.forceUpdate;
}

/// GitHub Release 信息（从 Atom feed 解析）
class GitHubReleaseInfo {
  final String tag;
  final String version;
  final List<String> assetNames;
  final String source;

  const GitHubReleaseInfo({
    required this.tag,
    required this.version,
    required this.assetNames,
    required this.source,
  });
}

/// 从 GitHub Atom feed 获取最新 release 信息；依次尝试各源
Future<GitHubReleaseInfo> fetchGitHubRelease(
  String repo, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final c = client ?? http.Client();
  String lastErr = '';
  for (final base in kGitHubSources) {
    final atomUrl = '${_ghBase(base)}$repo/releases.atom';
    try {
      final res = await c.get(Uri.parse(atomUrl)).timeout(timeout);
      if (res.statusCode != 200) {
        lastErr = '$base → HTTP ${res.statusCode}';
        continue;
      }
      final body = utf8.decode(res.bodyBytes);
      final tagMatch = RegExp(
        r'<entry>.*?<title[^>]*>(v[0-9][0-9.]*)</title>.*?</entry>',
        dotAll: true,
      ).firstMatch(body);
      if (tagMatch == null) {
        lastErr = '$base → 未匹配到 release entry';
        continue;
      }
      final tag = tagMatch.group(1)!;
      final version = tag.replaceFirst(RegExp('^[vV]'), '');
      // 提取资产文件名
      final assetNames = <String>[];
      final assetRegex = RegExp(
        r'<link[^>]+href="[^"]*/releases/download/[^"]+/([^"]+)"[^>]*type="application/',
      );
      for (final m in assetRegex.allMatches(body)) {
        final name = Uri.decodeComponent(m.group(1)!);
        if (!assetNames.contains(name)) {
          assetNames.add(name);
        }
      }
      if (client == null) c.close();
      return GitHubReleaseInfo(
        tag: tag,
        version: version,
        assetNames: assetNames,
        source: base,
      );
    } on TimeoutException {
      lastErr = '$base → 超时';
    } catch (e) {
      lastErr = '$base → $e';
    }
  }
  if (client == null) c.close();
  throw UpdateException('无法从 GitHub 获取 release 信息：$lastErr');
}

/// 在 GitHub release 资产列表中匹配当前平台/架构的条目
/// 返回 [assetName, downloadUrl] 或 null
List<String>? matchGitHubAsset(
  GitHubReleaseInfo release, {
  required String kind,
  required String platform,
  required String arch,
  String? channel,
  String? repo,
}) {
  repo ??= kGhRepo;
  // 平台名映射：app 用 macos，GitHub 用 darwin
  String ghOs(String p) {
    if (p == 'macos') return 'darwin';
    return p;
  }

  // 资产名模式
  String assetPattern(String p, String a, String ch, String ext) {
    if (kind == 'frpc') {
      // frpc: frp_{ver}_{os}_{arch}.{ext}
      return 'frp_${release.version}_${ghOs(p)}_$a.$ext';
    }
    // app: afrp-oidc-client_{ver}_{platform}_{arch}_{channel?}.{ext}
    if (ch.isNotEmpty) {
      return 'afrp-oidc-client_${release.version}_${p}_$a\_$ch.$ext';
    }
    return 'afrp-oidc-client_${release.version}_${p}_$a.$ext';
  }

  // 可能的扩展名
  final exts = <String>['exe', 'zip', 'tar.gz', 'apk', 'hap', 'ipk'];

  for (final ext in exts) {
    final name = assetPattern(platform, arch, channel ?? '', ext);
    if (release.assetNames.contains(name)) {
      // 构造下载 URL（用第一个源，下载时会回退）
      final url =
          '${_ghBase(kGitHubSources[0])}$repo/releases/download/${release.tag}/$name';
      return [name, url];
    }
  }
  return null;
}

/// 构造 GitHub 下载 URL（指定源）
String githubDownloadUrl(
  GitHubReleaseInfo release,
  String assetName, {
  String? repo,
  int sourceIndex = 0,
}) {
  repo ??= kGhRepo;
  final base = kGitHubSources[sourceIndex % kGitHubSources.length];
  return '${_ghBase(base)}$repo/releases/download/${release.tag}/$assetName';
}

/// 拉取并解析更新清单；网络/格式错误统一抛 [UpdateException]
Future<UpdateManifest> fetchUpdateManifest(
  String baseUrl, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse(manifestUrl(baseUrl))).timeout(timeout);
    if (res.statusCode != 200) {
      throw UpdateException('获取更新清单失败：HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw UpdateException('更新清单格式不正确');
    }
    return UpdateManifest.fromJson(decoded);
  } on UpdateException {
    rethrow;
  } on TimeoutException {
    throw UpdateException('连接更新服务器超时');
  } catch (e) {
    throw UpdateException('无法获取更新清单：$e');
  } finally {
    if (client == null) {
      c.close();
    }
  }
}

/// 当前平台在清单中的表示（与网站 download.php 的 DOWNLOAD_PLATFORMS 对齐）
String currentUpdatePlatform() {
  final os = Platform.operatingSystem;
  if (os == 'ohos' || os.contains('harmony')) {
    return 'ohos';
  }
  if (Platform.isWindows) {
    return 'windows';
  }
  if (Platform.isAndroid) {
    return 'android';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  if (Platform.isLinux) {
    return 'linux';
  }
  return os;
}

/// 当前 CPU 架构（清单 arch 字段用 amd64/arm64/arm/386 命名，与 frpc 官方命名一致）
String currentUpdateArch() {
  final abi = Abi.current();
  if (abi == Abi.windowsX64 ||
      abi == Abi.linuxX64 ||
      abi == Abi.macosX64 ||
      abi == Abi.androidX64) {
    return 'amd64';
  }
  if (abi == Abi.windowsArm64 ||
      abi == Abi.linuxArm64 ||
      abi == Abi.macosArm64 ||
      abi == Abi.androidArm64) {
    return 'arm64';
  }
  if (abi == Abi.androidArm) {
    return 'arm';
  }
  if (abi == Abi.windowsIA32 ||
      abi == Abi.linuxIA32 ||
      abi == Abi.androidIA32) {
    return '386';
  }
  return abi.toString();
}

/// 语义版本比较：1.10.0 > 1.9.2；非数字段视为 0
int compareVersions(String a, String b) {
  final pa = _versionParts(a);
  final pb = _versionParts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) {
      return x < y ? -1 : 1;
    }
  }
  return 0;
}

List<int> _versionParts(String v) {
  return v.trim().replaceFirst(RegExp('^[vV]'), '').split('.').map((s) {
    final m = RegExp(r'^\d+').firstMatch(s);
    return m == null ? 0 : int.parse(m.group(0)!);
  }).toList();
}

/// 架构别名归一化：清单中可能用 x64/amd64、arm64/aarch64 等不同命名
String _normalizeArch(String arch) {
  final a = arch.toLowerCase();
  if (a == 'x64' || a == 'x86_64') return 'amd64';
  if (a == 'aarch64') return 'arm64';
  if (a == 'armv7' || a == 'armhf') return 'arm';
  if (a == 'i386' || a == 'i686' || a == 'x86') return '386';
  return a;
}

/// 从清单挑选最新条目：按 kind+platform 过滤，可选 channel / arch 优先
UpdateEntry? chooseEntry(
  UpdateManifest manifest, {
  required String kind,
  required String platform,
  String? channel,
  String? arch,
}) {
  final pool = manifest.items
      .where(
        (e) =>
            e.kind == kind &&
            e.platform == platform &&
            e.latest &&
            e.url.isNotEmpty,
      )
      .toList();
  if (pool.isEmpty) {
    return null;
  }

  final wantArch = arch == null ? null : _normalizeArch(arch);

  UpdateEntry? pick(Iterable<UpdateEntry> src) {
    UpdateEntry? best;
    for (final e in src) {
      if (wantArch != null &&
          e.arch.isNotEmpty &&
          _normalizeArch(e.arch) != 'all' &&
          _normalizeArch(e.arch) != wantArch) {
        continue;
      }
      if (best == null) {
        best = e;
        continue;
      }
      final eExact = wantArch != null && _normalizeArch(e.arch) == wantArch;
      final bExact = wantArch != null && _normalizeArch(best.arch) == wantArch;
      if (eExact != bExact) {
        if (eExact) {
          best = e;
        }
      } else if (compareVersions(e.version, best.version) > 0) {
        best = e;
      }
    }
    return best;
  }

  var best = channel == null
      ? null
      : pick(pool.where((e) => e.channel == channel));
  best ??= pick(pool);
  return best;
}

// ---------------------------------------------------------------------------
// 下载与解压
// ---------------------------------------------------------------------------

/// 下载候选源：URL + 本地文件名。
/// 同一个版本在不同站点可能是不同封装（R2 直接给二进制，GitHub 给上游整包），
/// 文件名必须各自保留，否则整包会被当成二进制直接覆盖 frpc。
class _DownloadSource {
  final String url;
  final String fileName;
  const _DownloadSource(this.url, this.fileName);
}

/// 取 URL 末段作为文件名；取不到就用条目文件名
String _sourceFileName(String url, String fallback) {
  try {
    final segs = Uri.parse(url).pathSegments;
    if (segs.isNotEmpty) {
      final name = segs.last;
      if (name.isNotEmpty && name.contains('.')) {
        return name;
      }
    }
  } catch (_) {}
  return fallback;
}

/// 清理更新临时目录里的陈旧文件
///
/// 每次更新下载的安装包/内核都会留在临时目录里，攒多了既占空间，
/// 未签名的旧安装包长时间躺在 Temp 下也容易被安全软件当成可疑文件处理。
/// 只删超过 [maxAge] 的文件，正在用的（刚下载的）不会被动到。
Future<void> cleanupUpdateTempDir({
  Duration maxAge = const Duration(days: 1),
}) async {
  try {
    final tmpDir = await getTemporaryDirectory();
    final dir = Directory(
      '${tmpDir.path}${Platform.pathSeparator}afrp_updates',
    );
    if (!dir.existsSync()) {
      return;
    }
    final now = DateTime.now();
    for (final e in dir.listSync()) {
      if (e is! File) {
        continue;
      }
      try {
        if (now.difference(e.statSync().modified) > maxAge) {
          e.deleteSync();
        }
      } catch (_) {}
    }
  } catch (_) {}
}

/// 下载条目到临时目录并校验 SHA-256（清单未提供 sha256 时跳过校验）
/// 支持多源回退：R2（站内镜像）→ 清单其它镜像 → 条目主地址，GitHub 地址还会展开官方 + 代理
Future<File> downloadUpdateFile(
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
  http.Client? client,
}) async {
  if (entry.url.isEmpty) {
    throw UpdateException('该条目没有下载地址');
  }

  final sources = <_DownloadSource>[];
  void addSource(String url) {
    final u = url.trim();
    if (u.isEmpty) {
      return;
    }
    if (sources.any((s) => s.url == u)) {
      return;
    }
    sources.add(_DownloadSource(u, _sourceFileName(u, entry.file)));
  }

  // 1. R2 站内镜像优先：清单给了就用，否则按文件类型构造
  final r2Mirror = entry.mirrors.firstWhere(
    (m) => m['name'] == '站内镜像',
    orElse: () => <String, dynamic>{},
  );
  if (r2Mirror.isNotEmpty && r2Mirror['url'] != null) {
    addSource(r2Mirror['url'] as String);
  } else {
    addSource(r2DownloadUrl(entry.file, subdir: r2SubdirForFile(entry.file)));
  }

  // 2. 清单里的其它镜像（GitHub 官方 / 代理 / 网盘）逐个尝试
  for (final m in entry.mirrors) {
    final u = m['url'];
    if (u is String) {
      addSource(u);
    }
  }

  // 3. 条目主地址
  addSource(entry.url);

  // 4. GitHub 地址展开为「官方 + 代理」多源
  final urls = <_DownloadSource>[];
  for (final s in sources) {
    if (!s.url.contains('github.com/')) {
      urls.add(s);
      continue;
    }
    final ghMatch = RegExp(
      r'github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/(.+)',
    ).firstMatch(s.url);
    if (ghMatch == null) {
      urls.add(s);
      continue;
    }
    final repo = ghMatch.group(1)!;
    final tag = ghMatch.group(2)!;
    final name = ghMatch.group(3)!;
    for (final base in kGitHubSources) {
      final u = '${_ghBase(base)}$repo/releases/download/$tag/$name';
      if (urls.any((e) => e.url == u)) {
        continue;
      }
      urls.add(_DownloadSource(u, name));
    }
  }

  final tmpDir = await getTemporaryDirectory();
  final dir = Directory('${tmpDir.path}${Platform.pathSeparator}afrp_updates');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  await cleanupUpdateTempDir();

  final c = client ?? http.Client();
  String lastErr = '';

  for (final s in urls) {
    final out = File(
      '${dir.path}${Platform.pathSeparator}${s.fileName.isEmpty ? 'update.bin' : s.fileName}',
    );
    IOSink? sink;
    try {
      final res = await c.send(http.Request('GET', Uri.parse(s.url)));
      if (res.statusCode != 200) {
        lastErr = 'HTTP ${res.statusCode}';
        continue;
      }
      var total = res.contentLength ?? 0;
      if (total <= 0) {
        total = entry.size;
      }
      final sha = Sha256();
      sink = out.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        sha.update(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // 清单里的 sha256 对应 entry.file 本身；换封装（上游整包）时无法直接比对，
      // 那种情况留给解包后按二进制校验。
      if (entry.sha256.isNotEmpty &&
          s.fileName == entry.file &&
          sha.hexDigest() != entry.sha256.toLowerCase()) {
        lastErr = 'SHA-256 不一致';
        if (out.existsSync()) out.deleteSync();
        continue;
      }
      if (client == null) c.close();
      return out;
    } on UpdateException {
      rethrow;
    } catch (e) {
      lastErr = '$e';
      try {
        await sink?.close();
      } catch (_) {}
      sink = null;
      if (out.existsSync()) {
        try {
          out.deleteSync();
        } catch (_) {}
      }
    }
  }

  if (client == null) c.close();
  throw UpdateException('下载失败（已尝试 ${urls.length} 个源）：$lastErr');
}

/// 若为 .tar.gz/.tgz/.zip 则解出 [preferredName] 文件，否则原样返回
Future<File> extractExecutable(
  File archiveFile, {
  required String preferredName,
}) async {
  final lower = archiveFile.path.toLowerCase();
  List<ArchiveFile>? files;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    files = TarDecoder()
        .decodeBytes(GZipDecoder().decodeBytes(await archiveFile.readAsBytes()))
        .files;
  } else if (lower.endsWith('.zip')) {
    files = ZipDecoder().decodeBytes(await archiveFile.readAsBytes()).files;
  } else {
    return archiveFile;
  }

  final want = preferredName.toLowerCase();
  final prefix = want.split('.').first;
  ArchiveFile? fallback;
  for (final f in files) {
    if (!f.isFile) {
      continue;
    }
    final name = f.name.split('/').last.toLowerCase();
    if (name == want) {
      fallback = f;
      break;
    }
    if (fallback == null && name.startsWith(prefix)) {
      fallback = f;
    }
  }
  if (fallback == null) {
    throw UpdateException('压缩包中未找到 $preferredName');
  }
  final out = File('${archiveFile.path}.bin');
  await out.writeAsBytes(fallback.content as List<int>, flush: true);
  return out;
}

// ---------------------------------------------------------------------------
// frpc 核心更新
// ---------------------------------------------------------------------------

class FrpcUpdateCheck {
  final UpdateEntry entry;
  final String currentVersion;

  const FrpcUpdateCheck(this.entry, this.currentVersion);

  bool get hasUpdate => compareVersions(entry.version, currentVersion) > 0;
}

/// 查询 frpc 更新；优先用网站清单（版本与下载页一致），失败回退到 GitHub Release
Future<FrpcUpdateCheck?> checkFrpcUpdate(
  String baseUrl, {
  http.Client? client,
}) async {
  // Android：frpc 作为 native lib 随 APK 打包，运行于只读的 nativeLibraryDir，
  // 受 W^X 限制无法在线替换，版本随 App 升级而更新。
  if (Platform.isAndroid) {
    return null;
  }

  final platform = currentUpdatePlatform();
  final arch = currentUpdateArch();

  // Android/Ohos 使用 Linux 对应架构的 frpc
  String frpcPlatform = platform;
  if (platform == 'android' || platform == 'ohos') {
    frpcPlatform = 'linux';
    // arch 保持原样（arm/arm64/amd64），由 currentUpdateArch() 返回
  }

  // 1. 网站清单为准
  try {
    final manifest = await fetchUpdateManifest(baseUrl, client: client);
    final entry = chooseEntry(
      manifest,
      kind: 'frpc',
      platform: frpcPlatform,
      arch: arch,
    );
    if (entry != null) {
      final current = await frpcManager.refreshInstalledVersion();
      return FrpcUpdateCheck(entry, current);
    }
  } catch (_) {
    // 清单不可用，回退到 GitHub
  }

  // 2. 回退：GitHub Release
  try {
    final release = await fetchGitHubRelease(kFrpcRepo, client: client);
    final match = _matchFrpcAsset(release, frpcPlatform, arch);
    if (match != null) {
      final [assetName, url] = match;
      final entry = UpdateEntry(
        id: 'gh-frpc-$frpcPlatform-$arch',
        kind: 'frpc',
        platform: frpcPlatform,
        channel: '',
        arch: arch,
        version: release.version,
        file: assetName,
        url: url,
        sha256: '', // GitHub Atom 无 SHA-256，跳过校验
        date: '',
        notes: 'frpc 官方 ${release.version}（$frpcPlatform/$arch）',
        size: 0,
        latest: true,
      );
      final current = await frpcManager.refreshInstalledVersion();
      return FrpcUpdateCheck(entry, current);
    }
  } catch (_) {
    // GitHub 也没有可用版本
  }

  return null;
}

/// 匹配 frpc GitHub 资产
List<String>? _matchFrpcAsset(
  GitHubReleaseInfo release,
  String platform,
  String arch,
) {
  String ghOs(String p) => p == 'macos' ? 'darwin' : p;
  final os = ghOs(platform);

  // frpc 官方命名：frp_{ver}_{os}_{arch}.tar.gz 或 .zip
  final candidates = <String>[
    'frp_${release.version}_${os}_$arch.tar.gz',
    'frp_${release.version}_${os}_$arch.zip',
  ];

  for (final name in candidates) {
    if (release.assetNames.contains(name)) {
      final url = githubDownloadUrl(release, name, repo: kFrpcRepo);
      return [name, url];
    }
  }
  return null;
}

/// 是否为压缩包名（整包）
bool _isArchiveName(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.zip') || n.endsWith('.tar.gz') || n.endsWith('.tgz');
}

/// 下载并替换 frpc 二进制（会先断开当前隧道连接）
Future<void> applyFrpcUpdate(
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
}) async {
  final file = await downloadUpdateFile(entry, onProgress: onProgress);
  final exeName = Platform.isWindows ? 'frpc.exe' : 'frpc';
  final binary = await extractExecutable(file, preferredName: exeName);
  // 走的是上游整包（zip/tar.gz）时，清单里的 sha256 对应解出来的二进制，这里补校验
  if (entry.sha256.isNotEmpty &&
      !_isArchiveName(entry.file) &&
      _isArchiveName(file.path)) {
    final digest = await sha256OfFile(binary.path);
    if (digest != entry.sha256.toLowerCase()) {
      throw UpdateException('SHA-256 校验失败，请重试或到下载页手动下载');
    }
  }
  await frpcManager.applyUpdate(binary, entry.version);
}

// ---------------------------------------------------------------------------
// App 软件更新
// ---------------------------------------------------------------------------

class AppUpdateCheck {
  final UpdateEntry entry;
  final String currentVersion;

  const AppUpdateCheck(this.entry, this.currentVersion);

  bool get hasUpdate => compareVersions(entry.version, currentVersion) > 0;

  /// 是否强制更新：后台开启强更，或当前版本低于后台下发的最低可用版本
  bool get isMandatory {
    if (!hasUpdate) {
      return false;
    }
    if (kForceUpdate) {
      return true;
    }
    return kMinVersion.isNotEmpty &&
        compareVersions(currentVersion, kMinVersion) < 0;
  }
}

/// Windows 安装版判定：安装目录存在 Inno 卸载器 unins*.exe
Future<bool> isWindowsInstalled() async {
  if (!Platform.isWindows) {
    return false;
  }
  try {
    final dir = File(Platform.resolvedExecutable).parent;
    for (final f in dir.listSync()) {
      if (f is! File) {
        continue;
      }
      final name = f.uri.pathSegments.last.toLowerCase();
      if (name.startsWith('unins') && name.endsWith('.exe')) {
        return true;
      }
    }
  } catch (_) {}
  return false;
}

/// 查询 App 更新；优先从 GitHub Release 获取，失败回退到网站清单
Future<AppUpdateCheck?> checkAppUpdate(
  String baseUrl, {
  http.Client? client,
}) async {
  final platform = currentUpdatePlatform();
  final arch = currentUpdateArch();
  String? channel;
  switch (platform) {
    case 'windows':
      channel = await isWindowsInstalled() ? 'installer' : 'portable';
    case 'android':
      channel = 'apk';
    case 'ohos':
      channel = 'hap';
  }

  // 1. 网站清单为准（与下载页、与本站发布的版本一致）
  try {
    final manifest = await fetchUpdateManifest(baseUrl, client: client);
    final entry = chooseEntry(
      manifest,
      kind: 'app',
      platform: platform,
      channel: channel,
      arch: arch,
    );
    if (entry != null) {
      return AppUpdateCheck(entry, kAppVersion);
    }
  } catch (_) {
    // 清单不可用，回退到 GitHub
  }

  // 2. 回退：GitHub Release
  try {
    final release = await fetchGitHubRelease(
      kGhRepo,
      client: client,
    );
    final match = _matchAppAsset(release, platform, arch, channel);
    if (match != null) {
      final [assetName, url] = match;
      final entry = UpdateEntry(
        id: 'gh-app-$platform-${channel ?? ''}-$arch',
        kind: 'app',
        platform: platform,
        channel: channel ?? '',
        arch: arch,
        version: release.version,
        file: assetName,
        url: url,
        sha256: '', // GitHub Atom 无 SHA-256，跳过校验
        date: '',
        notes: '',
        size: 0,
        latest: true,
      );
      return AppUpdateCheck(entry, kAppVersion);
    }
  } catch (_) {
    // GitHub 也没有可用版本
  }

  return null;
}

/// 匹配 App GitHub 资产
List<String>? _matchAppAsset(
  GitHubReleaseInfo release,
  String platform,
  String arch,
  String? channel,
) {
  // 资产名模式：afrp-oidc-client_{ver}_{platform}_{arch}[_{channel}].{ext}
  final exts = <String>['exe', 'zip', 'tar.gz', 'apk', 'hap'];
  final channels = channel != null ? [channel, ''] : [''];

  for (final ch in channels) {
    for (final ext in exts) {
      final suffix = ch.isNotEmpty ? '_$ch.$ext' : '.$ext';
      final name =
          'afrp-oidc-client_${release.version}_${platform}_$arch$suffix';
      if (release.assetNames.contains(name)) {
        final url = githubDownloadUrl(release, name);
        return [name, url];
      }
    }
  }
  return null;
}

/// 执行 App 更新。
/// Windows（安装版静默安装后自动重启 / 免安装版替换重启）与 Android（调起系统安装器）
/// 走自动流程；macOS/Linux/鸿蒙打开下载页手动更新。
/// 注意：Windows 两条路径都会让本进程退出，并在安装/替换完成后自动重新拉起。
Future<void> performAppUpdate(
  String baseUrl,
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
  void Function(String message)? onStatus,
  Future<bool> Function(String message)? confirm,
}) async {
  final platform = currentUpdatePlatform();

  if (platform == 'windows') {
    final file = await downloadUpdateFile(entry, onProgress: onProgress);
    final isSetup =
        entry.channel == 'installer' ||
        RegExp('setup|install', caseSensitive: false).hasMatch(entry.file);
    if (await isWindowsInstalled() && isSetup) {
      // 安装到 Program Files 必须提权，系统会弹「用户账户控制」窗口；
      // 先让用户确认一次，避免 App 退出后没人知道要授权什么。
      if (confirm != null) {
        final go = await confirm(
          '系统将弹出「用户账户控制」窗口，需要点击「是」才能把新版本写入 Program Files。\n'
          '点击「开始安装」后 AFRP OIDC Client 会自动退出，安装完成会自动重新打开。',
        );
        if (!go) {
          throw UpdateException('已取消本次更新');
        }
      }
      onStatus?.call('即将启动安装程序，请在系统弹出的管理员授权窗口点击「是」');
      await _runInstallerAndRestart(
        file,
        Platform.resolvedExecutable,
        entry.version,
      );
    } else {
      final binary = await extractExecutable(
        file,
        preferredName: 'afrp_oidc.exe',
      );
      onStatus?.call('正在替换程序文件，App 稍后会自动重新打开');
      await _replacePortableAndRestart(binary, entry.version);
    }
    // 等待更新脚本启动后再退出，避免脚本还没运行程序就退出了
    await Future.delayed(const Duration(seconds: 2));
    // 退出前先停掉 frpc、销毁托盘图标：
    // 托盘进程会一直占着 Program Files 下的 exe/dll，安装程序会因此判定文件被占用而放弃安装
    try {
      await frpcManager.stop();
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    exit(0);
  }

  if (platform == 'android') {
    final file = await downloadUpdateFile(entry, onProgress: onProgress);
    await _installApk(file.path);
    return;
  }

  final ok = await openDownloadPage(baseUrl);
  if (!ok) {
    throw UpdateException('无法自动打开浏览器，请手动访问：${downloadPageUrl(baseUrl)}');
  }
}

/// 上次更新的结果（由更新脚本写入，App 启动时读取）
class UpdateResult {
  final bool ok;
  final String code;
  final String logPath;
  final String version;

  const UpdateResult({
    required this.ok,
    required this.code,
    required this.logPath,
    required this.version,
  });

  /// 面向用户的原因说明
  String get message {
    switch (code) {
      case 'denied':
        return '更新未执行：没有获得管理员授权。\n\n'
            'Windows 会在安装时弹出「用户账户控制」窗口，需要点击「是」才能写入 Program Files。\n'
            '你可以重新发起更新，或到下载页手动下载安装包安装。';
      case 'uactimeout':
        return '更新未执行：等待管理员授权超时。\n\n'
            'Windows 弹出「用户账户控制」窗口后 5 分钟内没有确认，本次更新已取消。\n'
            '请重新发起更新，并在弹窗出现时点击「是」。';
      case 'timeout':
        return '更新超时：10 分钟内没有完成安装。\n\n'
            '通常是管理员授权窗口一直没有被确认。\n'
            '你可以重新发起更新，或到下载页手动下载安装包安装。';
      case 'noinstaller':
        return '更新未执行：安装包未能启动。\n\n'
            '安装包可能刚下载完就被 Windows 安全中心隔离删除了。\n'
            '请到「Windows 安全中心 → 病毒和威胁防护 → 保护历史记录」查看并放行，'
            '或到下载页手动下载安装包安装。';
      case 'nohelper':
        return '更新未执行：安装脚本未能生成。\n'
            '请到下载页手动下载安装包安装。';
      case 'installfailed':
        return '更新未完成：安装程序没有成功写入文件。\n\n'
            '一般是旧进程仍占用着程序文件（关闭主窗口只是缩到托盘，进程不会退出），'
            '已尝试强制结束并重试一次。\n'
            '若安装时 Windows 安全中心弹出过红色警告，说明安装包被当成威胁拦下了，'
            '请到「Windows 安全中心 → 病毒和威胁防护 → 保护历史记录」把安装包设为允许后重试，'
            '或到下载页手动下载安装包安装。\n'
            '安装日志：${logPath.isEmpty ? '（无）' : logPath}';
      case 'done':
        return '更新未完成：安装程序已运行，但程序文件没有更新到目标版本。\n\n'
            '请重启电脑后重试更新，或到下载页手动下载安装包安装。\n'
            '安装日志：${logPath.isEmpty ? '（无）' : logPath}';
      case 'replace':
        return '更新未完成：程序文件替换失败（文件可能仍被占用）。\n'
            '请关闭所有 AFRP OIDC Client 进程后重试，或到下载页手动下载。';
      case 'appbusy':
        return '更新未执行：程序仍在运行，文件被占用。\n'
            '请完全退出 AFRP OIDC Client 后重新发起更新。';
      default:
        return '更新未完成：安装程序没有成功写入文件。\n\n'
            '请重启电脑后重试更新，或到下载页手动下载安装包安装。\n'
            '安装日志：${logPath.isEmpty ? '（无）' : logPath}';
    }
  }
}

/// 更新结果文件所在路径（App 数据目录，避免装到 Program Files 里没有写权限）
Future<File> _updateStatusFile() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}updates');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return File('${dir.path}${Platform.pathSeparator}status.txt');
}

/// 读取上次更新的结果；读后即删除，避免重复提示
Future<UpdateResult?> readUpdateResult() async {
  try {
    final f = await _updateStatusFile();
    if (!f.existsSync()) {
      return null;
    }
    final content = await f.readAsString();
    f.deleteSync();
    final kv = <String, String>{};
    for (final line in const LineSplitter().convert(content)) {
      final i = line.indexOf('=');
      if (i > 0) {
        kv[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
    }
    if (kv.isEmpty) {
      return null;
    }
    return UpdateResult(
      ok: kv['ok'] == 'true',
      code: kv['code'] ?? '',
      logPath: kv['log'] ?? '',
      version: kv['version'] ?? '',
    );
  } catch (_) {
    return null;
  }
}

/// PowerShell 单引号字符串转义
String _psQuote(String s) => s.replaceAll("'", "''");

/// 写 .ps1 脚本文件。
/// 必须带 UTF-8 BOM：Windows PowerShell 5.1 读取无 BOM 的脚本时按系统 ANSI 代码页解码，
/// 脚本里的中文注释会变成乱码并把后续代码解析坏（曾导致 $ok 等变量静默变空）。
Future<void> _writePsScript(File file, String content) async {
  await file.writeAsString('\uFEFF$content', flush: true);
}
/// Windows 安装版：脚本等本进程退出 → 以管理员身份静默安装 → 从注册表读取安装路径并重启。
/// 安装到 Program Files 必须提权，Windows 会弹 UAC 授权窗，用户点「是」才会真正安装；
/// 脚本带超时并把失败原因写盘，保证 App 一定会被重新拉起，不会停在「已退出」状态。
/// 安装与「强制结束残留进程」都放在提权的辅助脚本里：只有管理员才能结束任意权限的进程。
Future<void> _runInstallerAndRestart(
  File installer,
  String exePath,
  String version,
) async {
  final tmpDir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final script = File(
    '${tmpDir.path}${Platform.pathSeparator}afrp_update_$stamp.ps1',
  );
  final helper = File(
    '${tmpDir.path}${Platform.pathSeparator}afrp_update_install_$stamp.ps1',
  );
  final logFile = File(
    '${tmpDir.path}${Platform.pathSeparator}afrp_setup_$stamp.log',
  );
  final status = await _updateStatusFile();
  // AppId 与 installer/setup.iss 中的 AppId 一致
  const appId = 'A6C5E7B2-3F41-4D8E-9B07-5C2A8F16D9E3';
  final startedMarker = File('${script.path}.started');

  final helperPs = _psInstallerHelper
      .replaceAll('__INSTALLER__', _psQuote(installer.path))
      .replaceAll('__UPDATEDIR__', _psQuote(installer.parent.path))
      .replaceAll('__LOG__', _psQuote(logFile.path))
      .replaceAll('__STATUS__', _psQuote(status.path))
      .replaceAll('__APPID__', appId)
      .replaceAll('__EXENAME__', 'afrp_oidc.exe')
      .replaceAll('__FALLBACK__', _psQuote(exePath))
      .replaceAll('__VERSION__', _psQuote(version));
  await _writePsScript(helper, helperPs);

  final ps = _psInstallerUpdate
      .replaceAll('__INSTALLER__', _psQuote(installer.path))
      .replaceAll('__HELPER__', _psQuote(helper.path))
      .replaceAll('__LOG__', _psQuote(logFile.path))
      .replaceAll('__STATUS__', _psQuote(status.path))
      .replaceAll('__STARTED__', _psQuote(startedMarker.path))
      .replaceAll('__FALLBACK__', _psQuote(exePath))
      .replaceAll('__PID__', pid.toString())
      .replaceAll('__VERSION__', _psQuote(version));
  await _writePsScript(script, ps);
  if (!await _startHiddenScript(script, startedMarker)) {
    throw UpdateException('更新脚本未能启动，请重试或到下载页手动下载安装包');
  }
}

/// Windows 免安装版：脚本等本进程退出后覆盖文件并重启
Future<void> _replacePortableAndRestart(
  File newBinary,
  String version,
) async {
  final current = File(Platform.resolvedExecutable);
  final tmpDir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final script = File(
    '${tmpDir.path}${Platform.pathSeparator}afrp_update_$stamp.ps1',
  );
  final status = await _updateStatusFile();
  final startedMarker = File('${script.path}.started');

  final ps = _psPortableUpdate
      .replaceAll('__NEWBIN__', _psQuote(newBinary.path))
      .replaceAll('__TARGET__', _psQuote(current.path))
      .replaceAll('__STATUS__', _psQuote(status.path))
      .replaceAll('__STARTED__', _psQuote(startedMarker.path))
      .replaceAll('__PID__', pid.toString())
      .replaceAll('__VERSION__', _psQuote(version));
  await _writePsScript(script, ps);
  if (!await _startHiddenScript(script, startedMarker)) {
    throw UpdateException('更新脚本未能启动，请重试或到下载页手动下载');
  }
}

/// 完全隐藏地启动更新脚本，并确认它确实开始执行。
/// Dart 的 detached 方式直接跑 powershell.exe 会因无控制台而失败，
/// 故仍用 wscript.exe（GUI 子系统，无控制台）执行一段 VBS，由 VBS 以窗口样式 0（隐藏）
/// 运行 PowerShell，全程不弹窗口、不占任务栏。
/// 脚本启动后会立刻写 started 标记；等不到标记说明脚本没跑起来，
/// 此时不能让 App 直接退出，否则用户只会看到「程序没了，什么也没发生」。
Future<bool> _startHiddenScript(File script, File startedMarker) async {
  final vbs = File('${script.path}.vbs');
  // VBS 字符串里双引号需成对转义；脚本路径含空格也已由内层引号包住。
  // WSH 按系统 ANSI 代码页读取 .vbs，故用 systemEncoding 写，避免用户目录含中文时路径乱码。
  await vbs.writeAsString(
    'CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""${script.path}""", 0, False\r\n',
    flush: true,
    encoding: systemEncoding,
  );
  await Process.start('wscript.exe', [
    vbs.path,
  ], mode: ProcessStartMode.detached);

  for (var i = 0; i < 100; i++) {
    if (startedMarker.existsSync()) {
      return true;
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// 安装版更新主脚本：等旧进程退出 → 提权跑辅助脚本 → 重新拉起 App
const String _psInstallerUpdate = r'''
$ErrorActionPreference = 'SilentlyContinue'
$installer = '__INSTALLER__'
$helper = '__HELPER__'
$logFile = '__LOG__'
$statusFile = '__STATUS__'
$startedFile = '__STARTED__'
$fallback = '__FALLBACK__'
$version = '__VERSION__'
$appPid = __PID__

# 0) 打标记：让 App 知道脚本确实开始执行了
try { Set-Content -Path $startedFile -Value 'started' -ErrorAction Stop } catch { }

# 1) 等旧进程退出（最多 15 秒）；App 关闭主窗口只是缩到托盘，进程不会自己退出，
#    真正收尾由提权后的辅助脚本强制结束
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
  if (-not (Get-Process -Id $appPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 500
}

# 2) 以管理员身份跑辅助脚本：写 Program Files、结束残留进程都需要管理员权限，
#    Windows 会弹 UAC 授权窗，需用户点「是」。
#    Start-Process -Verb RunAs 会一直阻塞到用户做出选择，所以放进后台 Job，
#    主脚本才能对「用户一直不点授权」设超时兜底（否则 App 退出后就再也没人拉起）。
$code = 'noinstaller'
if (-not (Test-Path $installer)) {
  $code = 'noinstaller'
} elseif (-not (Test-Path $helper)) {
  $code = 'nohelper'
} else {
  $job = Start-Job -ScriptBlock {
    param($helper)
    try {
      # Start-Process 会用空格拼接参数，脚本路径含空格时必须自己加引号
      # 提权后是新起的进程，会自带一个控制台窗口（UAC 点「是」后闪出黑窗）；
      # 两层都隐藏：Start-Process 的 -WindowStyle 让进程创建时就不可见，
      # 参数里的 -WindowStyle 再让 PowerShell 自己隐藏一次，兜住创建瞬间的闪烁
      $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"' + $helper + '"'))
      return @{ ok = $true; id = $p.Id }
    } catch {
      return @{ ok = $false; id = 0 }
    }
  } -ArgumentList $helper

  # 等用户在 UAC 窗口点「是」/「否」，最多 5 分钟
  if (Wait-Job $job -Timeout 300) {
    $r = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($r -and $r.ok) {
      # 等提权脚本跑完（最多 15 分钟）
      $deadline = (Get-Date).AddSeconds(900)
      $finished = $false
      while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $r.id -ErrorAction SilentlyContinue)) { $finished = $true; break }
        Start-Sleep -Milliseconds 500
      }
      $code = if ($finished) { 'done' } else { 'timeout' }
    } else {
      $code = 'denied'
    }
  } else {
    # 用户一直没确认授权：放弃本次安装，但 App 仍会被重新拉起
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $code = 'uactimeout'
  }
}

# 3) 辅助脚本会自己写状态文件；它没能写时兜底
if (-not (Test-Path $statusFile)) {
  Set-Content -Path $statusFile -Value ("ok=False`ncode=$code`nlog=`nversion=$version`ntarget=$fallback")
}

# 4) 重新拉起 App（普通权限启动，避免 App 变成管理员运行）
$target = $fallback
if (Test-Path $statusFile) {
  try {
    foreach ($line in [System.IO.File]::ReadAllLines($statusFile)) {
      if ($line -like 'target=*') {
        $t = $line.Substring(7).Trim()
        if ($t) { $target = $t }
      }
    }
  } catch { }
}
if (Test-Path $target) { Start-Process $target }
''';

/// 安装版更新辅助脚本（管理员权限运行）：强制结束残留进程 → 静默安装 → 写结果
const String _psInstallerHelper = r'''
$ErrorActionPreference = 'SilentlyContinue'
$installer = '__INSTALLER__'
$updateDir = '__UPDATEDIR__'
$logFile = '__LOG__'
$statusFile = '__STATUS__'
$appId = '__APPID__'
$exeName = '__EXENAME__'
$fallback = '__FALLBACK__'
$version = '__VERSION__'

# 结束所有还在运行的客户端进程。
# App 关闭主窗口时只是缩到托盘，进程不会退出；安装程序替换 Program Files 下的
# exe/dll 时发现进程还在，会提示「无法关闭所有应用程序」并直接放弃安装。
function Stop-App {
  Get-Process -Name 'afrp_oidc' -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
}

# 找安装目录：注册表 64 位视图优先，再退 32 位视图，最后用当前程序路径
$instDir = ''
foreach ($view in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
  if ($instDir) { break }
  $p = Get-ItemProperty -Path (Join-Path $view ('{' + $appId + '}_is1')) -ErrorAction SilentlyContinue
  if ($p -and $p.InstallLocation) { $instDir = $p.InstallLocation }
}
if (-not $instDir) { $instDir = Split-Path -Parent $fallback }
$target = Join-Path $instDir $exeName
if (-not (Test-Path $target)) { $target = $fallback }

# 给更新包所在目录加 Windows 安全中心排除项。
# 安装包没有代码签名，被 Defender 的行为启发式误判（Trojan:Win32/Bearfoos.A!ml 之类）
# 的概率不低，一旦在启动安装包时被拦，更新会直接失败。排除项加不上也不阻断：
# 安装器已改用 /SILENT，有窗口的启动方式不会命中这类误报。
try { Add-MpPreference -ExclusionPath $updateDir -ErrorAction Stop } catch { }

# 读已安装版本：先看注册表的 DisplayVersion，缺失时退到 exe 的文件版本
function Get-InstalledVersion {
  foreach ($view in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    $p = Get-ItemProperty -Path (Join-Path $view ('{' + $appId + '}_is1')) -ErrorAction SilentlyContinue
    if ($p -and $p.DisplayVersion) { return ([string]$p.DisplayVersion).Trim() }
  }
  try {
    if (Test-Path $target) {
      return [System.Diagnostics.FileVersionInfo]::GetVersionInfo($target).FileVersion
    }
  } catch { }
  return ''
}

# 是否已装上目标版本：判断更新成败只看这个，不看安装日志。
# 安装程序刚退出时日志可能还没落盘、或仍被安装程序占用而读不出来，
# 拿日志判断会把「已装成功」误报成失败（用户会看到「更新未完成」但版本其实已升级）。
function Test-VersionInstalled {
  $inst = Get-InstalledVersion
  if (-not $inst) { return $false }
  $t = $version.Trim()
  $plus = $t.IndexOf('+')
  if ($plus -gt 0) { $t = $t.Substring(0, $plus) }
  $t = $t.TrimStart('v').TrimStart('V')
  if ($inst -eq $t) { return $true }
  if ($inst -like ($t + '*')) { return $true }
  return $false
}

function Install-Package($waitSecs) {
  if (-not (Test-Path $installer)) { return $false }
  if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }
  # /LOG 路径含空格时必须自己加引号，Start-Process 只用空格拼接参数。
  # 用 /SILENT 而不是 /VERYSILENT：完全无窗口的静默安装是杀软行为启发式的高危特征，
  # 未签名的安装包常被 Defender 当成木马拦下（Trojan:Win32/Bearfoos.A!ml）。
  # /SILENT 会显示一个正常的安装进度窗口，属于常规软件行为，不会触发这类误报；
  # /SP- 跳过「是否继续安装」的确认框，用户全程不用操作。
  $p = Start-Process -FilePath $installer -ArgumentList @('/SILENT','/SP-','/NORESTART','/CLOSEAPPLICATIONS',('/LOG="{0}"' -f $logFile)) -PassThru
  $p.WaitForExit()
  # 等注册表里的版本被改成目标版本
  $deadline = (Get-Date).AddSeconds($waitSecs)
  while ((Get-Date) -lt $deadline) {
    if (Test-VersionInstalled) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

Stop-App
$ok = Install-Package 60
if (-not $ok) {
  # 版本没变：多半是有进程占用安装目录（或安装被中断），强制结束后再试一次
  Stop-App
  $ok = Install-Package 30
}

$code = if ($ok) { 'done' } else { 'installfailed' }
Set-Content -Path $statusFile -Value ("ok=$ok`ncode=$code`nlog=$logFile`nversion=$version`ntarget=$target")
''';

/// 免安装版更新脚本：等待旧进程退出 → 覆盖程序文件 → 重新拉起 App
const String _psPortableUpdate = r'''
$ErrorActionPreference = 'SilentlyContinue'
$newBin = '__NEWBIN__'
$target = '__TARGET__'
$statusFile = '__STATUS__'
$startedFile = '__STARTED__'
$version = '__VERSION__'
$appPid = __PID__

try { Set-Content -Path $startedFile -Value 'started' -ErrorAction Stop } catch { }

# 等旧进程退出（最多 15 秒）
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
  if (-not (Get-Process -Id $appPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 500
}
# 还没退出就强制结束：关闭主窗口只是缩到托盘，进程不会自己退出，
# 而正在运行的 exe 无法被覆盖
Stop-Process -Id $appPid -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ok = $false
try {
  Copy-Item -Path $newBin -Destination $target -Force -ErrorAction Stop
  $ok = $true
} catch { }

Set-Content -Path $statusFile -Value ("ok=$ok`ncode=replace`nlog=`nversion=$version")
if (Test-Path $target) { Start-Process $target }
''';

Future<void> _installApk(String path) async {
  try {
    await _installerChannel.invokeMethod<bool>('installApk', {'path': path});
  } on MissingPluginException {
    throw UpdateException('当前运行环境不支持自动安装，请到下载页手动更新');
  } on PlatformException catch (e) {
    throw UpdateException('调起系统安装器失败：${e.message ?? e.code}');
  }
}

/// 打开下载页（鸿蒙/桌面兜底路径）；返回是否成功调起浏览器
Future<bool> openDownloadPage(String baseUrl) async {
  try {
    return await launchUrl(
      Uri.parse(downloadPageUrl(baseUrl)),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
