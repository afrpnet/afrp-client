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
const String kAppVersion = '1.1.0';

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
  });

  factory UpdateEntry.fromJson(Map<String, dynamic> json) {
    String s(String k) => '${json[k] ?? ''}';
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

  UpdateEntry? pick(Iterable<UpdateEntry> src) {
    UpdateEntry? best;
    for (final e in src) {
      if (arch != null && e.arch.isNotEmpty && e.arch != arch) {
        continue;
      }
      if (best == null) {
        best = e;
        continue;
      }
      final eExact = arch != null && e.arch == arch;
      final bExact = arch != null && best.arch == arch;
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
Future<File> downloadUpdateFile(
  UpdateEntry entry, {
  void Function(int received, int total)? onProgress,
  http.Client? client,
}) async {
  if (entry.url.isEmpty) {
    throw UpdateException('该条目没有下载地址');
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
  try {
    final res = await c.send(http.Request('GET', Uri.parse(entry.url)));
    if (res.statusCode != 200) {
      throw UpdateException('下载失败：HTTP ${res.statusCode}');
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
      throw UpdateException('文件校验失败（SHA-256 不一致）');
    }
    success = true;
    return out;
  } on UpdateException {
    rethrow;
  } catch (e) {
    throw UpdateException('下载失败：$e');
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    if (!success && out.existsSync()) {
      try {
        out.deleteSync();
      } catch (_) {}
    }
    if (client == null) {
      c.close();
    }
  }
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

/// 查询 frpc 更新；清单中无适用条目时返回 null（Android 不内置 frpc）
Future<FrpcUpdateCheck?> checkFrpcUpdate(String baseUrl, {http.Client? client}) async {
  final platform = currentUpdatePlatform();
  if (platform == 'android') {
    return null;
  }
  final manifest = await fetchUpdateManifest(baseUrl, client: client);
  final entry = chooseEntry(manifest, kind: 'frpc', platform: platform, arch: currentUpdateArch());
  if (entry == null) {
    return null;
  }
  final current = await frpcManager.refreshInstalledVersion();
  return FrpcUpdateCheck(entry, current);
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

/// 查询 App 更新；清单中无适用条目时返回 null
Future<AppUpdateCheck?> checkAppUpdate(String baseUrl, {http.Client? client}) async {
  final platform = currentUpdatePlatform();
  final manifest = await fetchUpdateManifest(baseUrl, client: client);
  String? channel;
  switch (platform) {
    case 'windows':
      channel = await isWindowsInstalled() ? 'installer' : 'portable';
    case 'android':
      channel = 'apk';
    case 'ohos':
      channel = 'hap';
  }
  final entry = chooseEntry(manifest, kind: 'app', platform: platform, channel: channel, arch: currentUpdateArch());
  if (entry == null) {
    return null;
  }
  return AppUpdateCheck(entry, kAppVersion);
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
