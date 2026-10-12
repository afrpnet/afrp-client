import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../frpc/frpc_manager.dart';
import 'sha256.dart';

/// App 版本号（发版时与 pubspec.yaml、安装脚本同步更新）
const String kAppVersion = '1.1.7';

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

String manifestUrl(String baseUrl) => '${_trimBase(baseUrl)}/download/manifest.json';

String downloadPageUrl(String baseUrl) => '${_trimBase(baseUrl)}/download/';

// ---------------------------------------------------------------------------
// Cloudflare R2 下载源（不限流量，优先使用）
// ---------------------------------------------------------------------------

/// R2 自定义域名
const String kR2BaseUrl = 'https://dl.afrp.net';

/// 构建 R2 下载 URL
String r2DownloadUrl(String filename, {String subdir = ''}) {
  if (subdir.isNotEmpty) {
    return '$kR2BaseUrl/$subdir/$filename';
  }
  return '$kR2BaseUrl/$filename';
}

/// 判断文件名是否属于 frpc 类别
bool isFrpcFile(String filename) {
  return filename.startsWith('frp_') || 
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

/// GitHub Release 下载源：先试官方，不通再用代理
const List<String> kGitHubSources = [
  'https://github.com/',
  'https://ghfast.top/https://github.com/',
  'https://gh-proxy.com/https://github.com/',
  'https://ghproxy.net/https://github.com/',
];

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
    final atomUrl = '${_trimBase(base)}$repo/releases.atom';
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
  String repo = 'afrpnet/afrp-client',
}) {
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
      final url = '${_trimBase(kGitHubSources[0])}$repo/releases/download/${release.tag}/$name';
      return [name, url];
    }
  }
  return null;
}

/// 构造 GitHub 下载 URL（指定源）
String githubDownloadUrl(
  GitHubReleaseInfo release,
  String assetName, {
  String repo = 'afrpnet/afrp-client',
  int sourceIndex = 0,
}) {
  final base = kGitHubSources[sourceIndex % kGitHubSources.length];
  return '${_trimBase(base)}$repo/releases/download/${release.tag}/$assetName';
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
  if (abi == Abi.windowsIA32 || abi == Abi.linuxIA32 || abi == Abi.androidIA32) {
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
  return v
      .trim()
      .replaceFirst(RegExp('^[vV]'), '')
      .split('.')
      .map((s) {
        final m = RegExp(r'^\d+').firstMatch(s);
        return m == null ? 0 : int.parse(m.group(0)!);
      })
      .toList();
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
      .where((e) => e.kind == kind && e.platform == platform && e.latest && e.url.isNotEmpty)
      .toList();
  if (pool.isEmpty) {
    return null;
  }

  final wantArch = arch == null ? null : _normalizeArch(arch);

  UpdateEntry? pick(Iterable<UpdateEntry> src) {
    UpdateEntry? best;
    for (final e in src) {
      if (wantArch != null && e.arch.isNotEmpty && _normalizeArch(e.arch) != 'all' && _normalizeArch(e.arch) != wantArch) {
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

  var best = channel == null ? null : pick(pool.where((e) => e.channel == channel));
  best ??= pick(pool);
  return best;
}

// ---------------------------------------------------------------------------
// 下载与解压
// ---------------------------------------------------------------------------

/// 下载条目到临时目录并校验 SHA-256（清单未提供 sha256 时跳过校验）
/// 支持多源回退：R2（站内镜像）→ GitHub URL 会依次尝试官方和代理
Future<File> downloadUpdateFile(
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
  http.Client? client,
}) async {
  if (entry.url.isEmpty) {
    throw UpdateException('该条目没有下载地址');
  }

  // 构建下载 URL 列表：优先 R2，其次 GitHub
  final urls = <String>[];
  
  // 1. 添加 R2 站内镜像（如果 mirrors 中有）
  final r2Mirror = entry.mirrors.firstWhere(
    (m) => m['name'] == '站内镜像',
    orElse: () => <String, dynamic>{},
  );
  if (r2Mirror.isNotEmpty && r2Mirror['url'] != null) {
    urls.add(r2Mirror['url'] as String);
  } else {
    // 如果没有 mirror，根据文件类型构造 R2 URL
    final subdir = r2SubdirForFile(entry.file);
    urls.add(r2DownloadUrl(entry.file, subdir: subdir));
  }
  
  // 2. 如果是 GitHub URL，添加多源列表
  if (entry.url.contains('github.com/')) {
    // 从 URL 提取 repo/tag/name
    final ghMatch = RegExp(
      r'github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/(.+)',
    ).firstMatch(entry.url);
    if (ghMatch != null) {
      final repo = ghMatch.group(1)!;
      final tag = ghMatch.group(2)!;
      final name = ghMatch.group(3)!;
      for (final base in kGitHubSources) {
        urls.add('${_trimBase(base)}$repo/releases/download/$tag/$name');
      }
    } else {
      urls.add(entry.url);
    }
  } else if (!urls.contains(entry.url)) {
    // 3. 添加原始 URL（如果不是 GitHub 且不在列表中）
    urls.add(entry.url);
  }

  final tmpDir = await getTemporaryDirectory();
  final dir = Directory('${tmpDir.path}${Platform.pathSeparator}afrp_updates');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final out = File('${dir.path}${Platform.pathSeparator}${entry.file.isEmpty ? 'update.bin' : entry.file}');

  final c = client ?? http.Client();
  IOSink? sink;
  var success = false;
  String lastErr = '';

  for (final url in urls) {
    try {
      final res = await c.send(http.Request('GET', Uri.parse(url)));
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
      if (entry.sha256.isNotEmpty && sha.hexDigest() != entry.sha256.toLowerCase()) {
        lastErr = 'SHA-256 不一致';
        if (out.existsSync()) out.deleteSync();
        continue;
      }
      success = true;
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
Future<File> extractExecutable(File archiveFile, {required String preferredName}) async {
  final lower = archiveFile.path.toLowerCase();
  List<ArchiveFile>? files;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    files = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(await archiveFile.readAsBytes())).files;
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

/// 查询 frpc 更新；优先从 GitHub Release 获取，失败回退到网站清单
Future<FrpcUpdateCheck?> checkFrpcUpdate(String baseUrl, {http.Client? client}) async {
  final platform = currentUpdatePlatform();
  final arch = currentUpdateArch();

  // Android/Ohos 使用 Linux 对应架构的 frpc
  String frpcPlatform = platform;
  if (platform == 'android' || platform == 'ohos') {
    frpcPlatform = 'linux';
    // arch 保持原样（arm/arm64/amd64），由 currentUpdateArch() 返回
  }

  // 先试 GitHub
  try {
    final release = await fetchGitHubRelease('fatedier/frp', client: client);
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
    // GitHub 失败，回退到网站
  }

  // 回退：网站 manifest
  final manifest = await fetchUpdateManifest(baseUrl, client: client);
  final entry = chooseEntry(manifest, kind: 'frpc', platform: frpcPlatform, arch: arch);
  if (entry == null) {
    return null;
  }
  final current = await frpcManager.refreshInstalledVersion();
  return FrpcUpdateCheck(entry, current);
}

/// 匹配 frpc GitHub 资产
List<String>? _matchFrpcAsset(GitHubReleaseInfo release, String platform, String arch) {
  String ghOs(String p) => p == 'macos' ? 'darwin' : p;
  final os = ghOs(platform);

  // frpc 官方命名：frp_{ver}_{os}_{arch}.tar.gz 或 .zip
  final candidates = <String>[
    'frp_${release.version}_${os}_$arch.tar.gz',
    'frp_${release.version}_${os}_$arch.zip',
  ];

  for (final name in candidates) {
    if (release.assetNames.contains(name)) {
      final url = githubDownloadUrl(release, name, repo: 'fatedier/frp');
      return [name, url];
    }
  }
  return null;
}

/// 下载并替换 frpc 二进制（会先断开当前隧道连接）
Future<void> applyFrpcUpdate(
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
}) async {
  final file = await downloadUpdateFile(entry, onProgress: onProgress);
  final exeName = Platform.isWindows ? 'frpc.exe' : 'frpc';
  final binary = await extractExecutable(file, preferredName: exeName);
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
Future<AppUpdateCheck?> checkAppUpdate(String baseUrl, {http.Client? client}) async {
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

  // 先试 GitHub
  try {
    final release = await fetchGitHubRelease('afrpnet/afrp-client', client: client);
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
    // GitHub 失败，回退到网站
  }

  // 回退：网站 manifest
  final manifest = await fetchUpdateManifest(baseUrl, client: client);
  final entry = chooseEntry(manifest, kind: 'app', platform: platform, channel: channel, arch: arch);
  if (entry == null) {
    return null;
  }
  return AppUpdateCheck(entry, kAppVersion);
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
      final name = 'afrp-oidc-client_${release.version}_${platform}_$arch$suffix';
      if (release.assetNames.contains(name)) {
        final url = githubDownloadUrl(release, name);
        return [name, url];
      }
    }
  }
  return null;
}

/// 执行 App 更新。
/// Windows（安装版静默安装 / 免安装版替换重启）与 Android（调起系统安装器）
/// 走自动流程；macOS/Linux/鸿蒙打开下载页手动更新。
/// 注意：Windows 两条路径都会在启动安装/替换后让本进程退出。
Future<void> performAppUpdate(
  String baseUrl,
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
}) async {
  final platform = currentUpdatePlatform();

  if (platform == 'windows') {
    final file = await downloadUpdateFile(entry, onProgress: onProgress);
    final isSetup = entry.channel == 'installer' ||
        RegExp('setup|install', caseSensitive: false).hasMatch(entry.file);
    if (await isWindowsInstalled() && isSetup) {
      await Process.start(
        file.path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
    } else {
      final binary = await extractExecutable(file, preferredName: 'afrp_oidc.exe');
      await _replacePortableAndRestart(binary);
    }
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

/// Windows 免安装版：临时 bat 等本进程退出后覆盖文件并重启
Future<void> _replacePortableAndRestart(File newBinary) async {
  final current = File(Platform.resolvedExecutable);
  final tmpDir = await getTemporaryDirectory();
  final bat = File(
    '${tmpDir.path}${Platform.pathSeparator}afrp_update_${DateTime.now().millisecondsSinceEpoch}.bat',
  );
  final currentPid = pid;
  await bat.writeAsString('''
@echo off
timeout /t 2 /nobreak >nul
:waitloop
tasklist /fi "PID eq $currentPid" 2>nul | find "$currentPid" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto waitloop
)
copy /y "${newBinary.path}" "${current.path}" >nul
start "" "${current.path}"
del "%~f0"
''', flush: true);
  await Process.start('cmd', ['/c', bat.path], mode: ProcessStartMode.detached);
  exit(0);
}

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
