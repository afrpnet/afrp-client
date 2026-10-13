import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/updater.dart';

/// frpc 进程管理：运行前从 App 资源释放二进制到可写目录，
/// 启动/停止进程，并把 stdout/stderr 作为日志行提供给 UI。
class FrpcManager extends ChangeNotifier {
  static const String frpcVersion = '0.71.0';
  static const int _maxLogLines = 800;
  static const MethodChannel _installerChannel = MethodChannel('afrp_oidc/installer');

  Process? _proc;
  String? _binPath;
  String? _installedVersion;
  String _status = '未连接';
  bool _connectOk = false;

  final List<String> logLines = [];

  bool get running => _proc != null;
  String get status => _status;
  bool get connectOk => _connectOk;
  String get binaryPath => _binPath ?? '(未释放)';

  /// 已安装的 frpc 版本（读 .version 标记；从未释放过则为内置版本）
  String get installedVersion => _installedVersion ?? frpcVersion;

  /// 当前平台是否支持内置 frpc（桌面端 + 移动端都支持）
  static bool get frpcSupported {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
      return true;
    }
    // 鸿蒙 OHOS
    if (Platform.operatingSystem == 'ohos' || Platform.operatingSystem.contains('harmony')) {
      return true;
    }
    return false;
  }

  /// 按当前平台返回资源 key 与释放后的文件名；macOS 用 tar.gz 分发（规避平台查杀误报）
  static (String asset, String exeName) get _platformAsset {
    if (Platform.isWindows) {
      return ('assets/frpc/windows/frpc.exe', 'frpc.exe');
    }
    if (Platform.isLinux) {
      return ('assets/frpc/linux/frpc', 'frpc');
    }
    if (Platform.isMacOS) {
      return ('assets/frpc/macos/frpc_darwin_amd64.tar.gz', 'frpc');
    }
    if (Platform.isAndroid) {
      return ('', 'frpc'); // Android 需要动态下载
    }
    // 鸿蒙 OHOS
    if (Platform.operatingSystem == 'ohos' || Platform.operatingSystem.contains('harmony')) {
      return ('', 'frpc'); // OHOS 需要动态下载
    }
    throw UnsupportedError('当前平台暂不支持内置 frpc');
  }

  Future<Directory> _workDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}frpc');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 释放 frpc 二进制（版本标记变化时重新释放），返回可执行文件路径
  Future<String> ensureBinary() async {
    final (assetKey, exeName) = _platformAsset;
    final dir = await _workDir();
    final bin = File('${dir.path}${Platform.pathSeparator}$exeName');
    final marker = File('${dir.path}${Platform.pathSeparator}.version');

    // Android：frpc 作为 native lib（libfrpc.so）随 APK 打包，从只读且可执行的
    // nativeLibraryDir 运行，绕过 Android 10+ 禁止从应用可写目录 exec 的限制（W^X）。
    // 必须放在版本标记检查之前——filesDir 里的 frpc 在 Android 上无法执行。
    if (Platform.isAndroid) {
      final path = await _androidBundledFrpc();
      _binPath = path;
      _installedVersion = frpcVersion;
      return path;
    }

    // 二进制与版本标记同时存在即信任；可能已被「frpc 核心更新」替换过，勿用内置版覆盖
    if (bin.existsSync() && marker.existsSync()) {
      _installedVersion = marker.readAsStringSync().trim();
      _binPath = bin.path;
      return bin.path;
    }

    // Android / OHOS 需要动态下载 frpc
    final isMobile = Platform.isAndroid ||
        Platform.operatingSystem == 'ohos' ||
        Platform.operatingSystem.contains('harmony');
    if (isMobile) {
      return await _downloadFrpcForMobile(bin, marker, exeName);
    }

    final data = await rootBundle.load(assetKey);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (assetKey.endsWith('.tar.gz')) {
      final tar = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      final entry = tar.files.firstWhere(
        (f) => f.isFile && f.name.endsWith('/frpc'),
        orElse: () => throw StateError('压缩包中未找到 frpc'),
      );
      bin.writeAsBytesSync(entry.content as List<int>, flush: true);
    } else {
      bin.writeAsBytesSync(bytes, flush: true);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', bin.path]);
    }
    marker.writeAsStringSync(frpcVersion);
    _installedVersion = frpcVersion;
    _binPath = bin.path;
    notifyListeners();
    return bin.path;
  }

  /// Android：返回 APK 内置 frpc（nativeLibraryDir/libfrpc.so）的可执行路径。
  /// 该目录由系统在安装时解压，只读且带执行权限，可直接 exec。
  Future<String> _androidBundledFrpc() async {
    final dir = await _installerChannel.invokeMethod<String>('nativeLibraryDir');
    if (dir == null || dir.isEmpty) {
      throw StateError('无法获取 nativeLibraryDir');
    }
    final f = File('$dir${Platform.pathSeparator}libfrpc.so');
    if (!f.existsSync()) {
      throw StateError('APK 未内置 frpc（${f.path}），请重新安装最新版 App');
    }
    return f.path;
  }

  /// Android / OHOS 平台：从 manifest 下载 frpc 二进制
  Future<String> _downloadFrpcForMobile(File bin, File marker, String exeName) async {
    try {
      // 获取设备架构
      String arch;
      final os = Platform.operatingSystem;
      final isOhos = os == 'ohos' || os.contains('harmony');

      if (Platform.version.contains('arm64') || Platform.version.contains('aarch64')) {
        arch = 'arm64';
      } else if (Platform.version.contains('arm')) {
        arch = 'arm';
      } else {
        arch = 'amd64';
      }

      // 从网站获取 manifest
      final client = http.Client();
      try {
        final manifestUrl = Uri.parse('https://www.afrp.net/download/manifest.json');
        final response = await client.get(manifestUrl);
        if (response.statusCode != 200) {
          throw StateError('无法下载 manifest (HTTP ${response.statusCode})');
        }

        final manifestJson = json.decode(response.body) as Map<String, dynamic>;
        final manifest = UpdateManifest.fromJson(manifestJson);

        // Android/OHOS 都使用 Linux 二进制（manifest 中只有 linux 平台）
        final entry = chooseEntry(manifest, kind: 'frpc', platform: 'linux', arch: arch);
        if (entry == null) {
          throw StateError('未找到适用于 $arch 架构的 frpc');
        }

        // 下载 frpc
        final tempFile = await downloadUpdateFile(entry);

        // 如果是 tar.gz，需要解压
        if (entry.file.endsWith('.tar.gz')) {
          final bytes = tempFile.readAsBytesSync();
          final tar = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
          final frpcEntry = tar.files.firstWhere(
            (f) => f.isFile && f.name.contains('frpc'),
            orElse: () => throw StateError('压缩包中未找到 frpc'),
          );
          bin.writeAsBytesSync(frpcEntry.content as List<int>, flush: true);
        } else {
          tempFile.copySync(bin.path);
        }

        // Android/OHOS 应用支持目录下的文件默认有执行权限，无需 chmod
        marker.writeAsStringSync(entry.version);
        _installedVersion = entry.version;
        _binPath = bin.path;
        notifyListeners();
        return bin.path;
      } finally {
        client.close();
      }
    } catch (e) {
      throw StateError('frpc 下载失败：$e');
    }
  }

  /// 重新读取磁盘上的已安装版本（标记缺失时回退内置版本），供设置页展示
  Future<String> refreshInstalledVersion() async {
    try {
      final dir = await _workDir();
      final marker = File('${dir.path}${Platform.pathSeparator}.version');
      _installedVersion = marker.existsSync() ? marker.readAsStringSync().trim() : frpcVersion;
    } catch (_) {
      _installedVersion = frpcVersion;
    }
    notifyListeners();
    return _installedVersion!;
  }

  /// 用新下载并校验过的二进制替换当前 frpc（先停止进程），并更新版本标记
  Future<void> applyUpdate(File newBinary, String version) async {
    if (Platform.isAndroid) {
      throw StateError('Android 上 frpc 随 App 打包（nativeLibraryDir），不支持单独更新；请升级 App 版本');
    }
    await stop();
    final (_, exeName) = _platformAsset;
    final dir = await _workDir();
    final dest = File('${dir.path}${Platform.pathSeparator}$exeName');
    final tmp = File('${dest.path}.new');
    await newBinary.copy(tmp.path);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', tmp.path]);
    }
    if (dest.existsSync()) {
      await dest.delete();
    }
    await tmp.rename(dest.path);
    final marker = File('${dir.path}${Platform.pathSeparator}.version');
    await marker.writeAsString(version, flush: true);
    _installedVersion = version;
    _binPath = dest.path;
    notifyListeners();
  }

  Future<void> start(String tomlContent) async {
    await stop();
    final binPath = await ensureBinary();
    final dir = await _workDir();
    final cfg = File('${dir.path}${Platform.pathSeparator}frpc.toml');
    cfg.writeAsStringSync(tomlContent, flush: true);

    logLines.clear();
    _connectOk = false;
    _setStatus('正在启动…');
    final proc = await Process.start(
      binPath,
      ['-c', cfg.path],
      workingDirectory: dir.path,
    );
    _proc = proc;
    notifyListeners();

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    proc.exitCode.then((code) {
      _proc = null;
      _connectOk = false;
      _addLog('[进程已退出，代码 $code]');
      _setStatus(code == 0 ? '已断开' : '连接中断（代码 $code）');
    });
  }

  Future<void> stop() async {
    final proc = _proc;
    if (proc == null) {
      return;
    }
    _proc = null;
    _connectOk = false;
    try {
      proc.kill();
      await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {
      // 进程可能已退出
    }
    _setStatus('未连接');
  }

  void _onLine(String line) {
    _addLog(line);
    final l = line.toLowerCase();
    if (l.contains('login to server success')) {
      _connectOk = true;
      _setStatus('已连接');
    } else if (l.contains('login to server failed') ||
        l.contains('connect to server error') ||
        l.contains('authentication failed')) {
      _connectOk = false;
      _setStatus('认证/连接失败，请看日志');
    } else if (l.contains('start proxy success')) {
      _setStatus('已连接（隧道已启动）');
    }
  }

  void _addLog(String line) {
    final ts = DateTime.now().toString().substring(11, 19);
    logLines.add('[$ts] $line');
    if (logLines.length > _maxLogLines) {
      logLines.removeRange(0, logLines.length - _maxLogLines);
    }
    notifyListeners();
  }

  void _setStatus(String s) {
    _status = s;
    notifyListeners();
  }

  void clearLog() {
    logLines.clear();
    notifyListeners();
  }
}

/// 全局单例：整个 App 同一时刻只有一个 frpc 进程
final FrpcManager frpcManager = FrpcManager();
