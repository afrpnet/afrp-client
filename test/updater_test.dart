import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frp_oidc_app/core/sha256.dart';
import 'package:frp_oidc_app/core/updater.dart';
import 'package:frp_oidc_app/frpc/frpc_manager.dart';

String _sha256Hex(List<int> bytes) {
  final s = Sha256();
  s.update(bytes);
  return s.hexDigest();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test binding 默认安装 HttpOverrides（所有请求返回 400），
  // 这里需要真实访问本地测试服务器，故解除。
  HttpOverrides.global = null;

  late Directory tmpRoot;
  late Directory supportDir;
  late Directory tempDir;
  late HttpServer server;
  late String baseUrl;
  late String manifestJson;
  final files = <String, List<int>>{};

  final hostPlatform = currentUpdatePlatform();
  final hostArch = currentUpdateArch();
  final exeName = Platform.isWindows ? 'frpc.exe' : 'frpc';

  setUp(() async {
    tmpRoot = Directory.systemTemp.createTempSync('afrp_update_test_');
    supportDir = Directory('${tmpRoot.path}${Platform.pathSeparator}support')..createSync(recursive: true);
    tempDir = Directory('${tmpRoot.path}${Platform.pathSeparator}temp')..createSync(recursive: true);
    files.clear();
    manifestJson = '';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        switch (call.method) {
          case 'getTemporaryDirectory':
            return tempDir.path;
          case 'getApplicationSupportDirectory':
            return supportDir.path;
        }
        return null;
      },
    );

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) {
      final resp = req.response;
      final path = req.uri.path;
      if (path == '/download/manifest.json') {
        if (manifestJson.isEmpty) {
          resp.statusCode = HttpStatus.notFound;
        } else {
          resp.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
          resp.write(manifestJson);
        }
      } else if (path.startsWith('/download/files/')) {
        final data = files[path.substring('/download/files/'.length)];
        if (data == null) {
          resp.statusCode = HttpStatus.notFound;
        } else {
          resp.add(data);
        }
      } else {
        resp.statusCode = HttpStatus.notFound;
      }
      resp.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    try {
      tmpRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> mkEntry({
    required String kind,
    required String platform,
    String channel = '',
    String arch = '',
    required String version,
    required String file,
    required String sha256,
    String notes = '',
    int size = 0,
    bool latest = true,
  }) {
    return <String, dynamic>{
      'id': '$kind-$platform-$channel-$arch-$version',
      'kind': kind,
      'platform': platform,
      'channel': channel,
      'arch': arch,
      'version': version,
      'file': file,
      'url': file.isEmpty ? '' : '$baseUrl/download/files/$file',
      'sha256': sha256,
      'date': '2026-10-09',
      'notes': notes,
      'size': size,
      'latest': latest,
    };
  }

  String wrapManifest(List<Map<String, dynamic>> items) => jsonEncode({
        'schema': 1,
        'site': 'test',
        'updated': '2026-10-09 00:00:00',
        'count': items.length,
        'items': items,
      });

  group('版本比较与条目挑选', () {
    test('compareVersions 语义比较', () {
      expect(compareVersions('1.10.0', '1.9.2'), 1);
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('0.71.0', '0.99.0'), -1);
      expect(compareVersions('2.0.0', '2.0.0'), 0);
    });

    test('chooseEntry：arch 优先、忽略非 latest 与空 url', () {
      final manifest = UpdateManifest.fromJson({
        'schema': 1,
        'items': [
          mkEntry(kind: 'frpc', platform: 'windows', arch: '386', version: '0.99.0', file: 'a.exe', sha256: ''),
          mkEntry(kind: 'frpc', platform: 'windows', arch: 'amd64', version: '0.80.0', file: 'b.exe', sha256: ''),
          mkEntry(kind: 'frpc', platform: 'windows', arch: 'amd64', version: '9.9.9', file: 'c.exe', sha256: '', latest: false),
          mkEntry(kind: 'frpc', platform: 'windows', arch: 'amd64', version: '8.8.8', file: '', sha256: ''),
          mkEntry(kind: 'app', platform: 'windows', channel: 'installer', arch: 'amd64', version: '1.2.0', file: 'd.exe', sha256: ''),
        ],
      });
      expect(chooseEntry(manifest, kind: 'frpc', platform: 'windows', arch: 'amd64')?.version, '0.80.0');
      expect(chooseEntry(manifest, kind: 'frpc', platform: 'windows')?.version, '0.99.0');
      expect(chooseEntry(manifest, kind: 'app', platform: 'windows')?.channel, 'installer');
      expect(chooseEntry(manifest, kind: 'frpc', platform: 'linux'), isNull);
    });
  });

  group('清单获取', () {
    test('fetchUpdateManifest 解析网站端 JSON 结构', () async {
      manifestJson = jsonEncode({
        'schema': 1,
        'site': 'AFRP',
        'updated': '2026-10-09 10:00:00',
        'count': 1,
        'items': [
          mkEntry(
            kind: 'frpc',
            platform: 'windows',
            channel: 'zip',
            arch: 'amd64',
            version: '0.99.0',
            file: 'frpc_0.99.0_windows_amd64.zip',
            sha256: 'abcdef',
            notes: '测试版本',
            size: 123,
          ),
        ],
      });
      final m = await fetchUpdateManifest(baseUrl);
      expect(m.schema, 1);
      expect(m.items, hasLength(1));
      final e = m.items.first;
      expect(e.kind, 'frpc');
      expect(e.platform, 'windows');
      expect(e.channel, 'zip');
      expect(e.arch, 'amd64');
      expect(e.version, '0.99.0');
      expect(e.file, 'frpc_0.99.0_windows_amd64.zip');
      expect(e.url, '$baseUrl/download/files/frpc_0.99.0_windows_amd64.zip');
      expect(e.sha256, 'abcdef');
      expect(e.notes, '测试版本');
      expect(e.size, 123);
      expect(e.sizeText, '123 B');
      expect(e.latest, isTrue);
    });

    test('清单 404 或非法 JSON 抛 UpdateException', () async {
      await expectLater(fetchUpdateManifest(baseUrl), throwsA(isA<UpdateException>()));
      manifestJson = '<html>not json</html>';
      await expectLater(fetchUpdateManifest(baseUrl), throwsA(isA<UpdateException>()));
    });
  });

  group('frpc 更新流程', () {
    test('checkFrpcUpdate + applyFrpcUpdate 正常流（含 SHA-256 校验与版本标记）', () async {
      final bytes = utf8.encode('FAKE-FRPC-BINARY-v0.99.0');
      files['frpc_0.99.0.exe'] = bytes;
      manifestJson = wrapManifest([
        mkEntry(
          kind: 'frpc',
          platform: hostPlatform,
          arch: hostArch,
          version: '0.99.0',
          file: 'frpc_0.99.0.exe',
          sha256: _sha256Hex(bytes),
          notes: '测试包',
          size: bytes.length,
        ),
      ]);

      final check = await checkFrpcUpdate(baseUrl);
      expect(check, isNotNull);
      expect(check!.currentVersion, FrpcManager.frpcVersion);
      expect(check.hasUpdate, isTrue);
      expect(check.entry.version, '0.99.0');

      final progress = <int>[];
      await applyFrpcUpdate(check.entry, onProgress: (r, _) => progress.add(r));

      final dir = '${supportDir.path}${Platform.pathSeparator}frpc';
      expect(File('$dir${Platform.pathSeparator}$exeName').readAsBytesSync(), bytes);
      expect(File('$dir${Platform.pathSeparator}.version').readAsStringSync(), '0.99.0');
      expect(frpcManager.installedVersion, '0.99.0');
      expect(await frpcManager.refreshInstalledVersion(), '0.99.0');
      expect(progress, isNotEmpty);
      expect(progress.last, bytes.length);
    });

    test('SHA-256 不匹配时失败且不落地任何文件', () async {
      final bytes = utf8.encode('FAKE-BINARY');
      files['frpc_bad.exe'] = bytes;
      manifestJson = wrapManifest([
        mkEntry(
          kind: 'frpc',
          platform: hostPlatform,
          arch: hostArch,
          version: '9.9.9',
          file: 'frpc_bad.exe',
          sha256: 'deadbeef',
        ),
      ]);

      final check = await checkFrpcUpdate(baseUrl);
      expect(check, isNotNull);
      await expectLater(applyFrpcUpdate(check!.entry), throwsA(isA<UpdateException>()));

      final dir = '${supportDir.path}${Platform.pathSeparator}frpc';
      expect(File('$dir${Platform.pathSeparator}$exeName').existsSync(), isFalse);
      expect(File('$dir${Platform.pathSeparator}.version').existsSync(), isFalse);
      final updateDir = Directory('${tempDir.path}${Platform.pathSeparator}afrp_updates');
      expect(updateDir.existsSync() && updateDir.listSync().isNotEmpty, isFalse);
    });

    test('清单版本不高于当前时 hasUpdate=false', () async {
      manifestJson = wrapManifest([
        mkEntry(
          kind: 'frpc',
          platform: hostPlatform,
          arch: hostArch,
          version: '0.1.0',
          file: 'frpc_old.exe',
          sha256: '',
        ),
      ]);
      final check = await checkFrpcUpdate(baseUrl);
      expect(check, isNotNull);
      expect(check!.hasUpdate, isFalse);
      expect(check.currentVersion, FrpcManager.frpcVersion);
    });
  });

  group('App 更新检查', () {
    test('chooseEntry 选中的版本高于当前 → hasUpdate=true', () async {
      manifestJson = wrapManifest([
        mkEntry(
          kind: 'app',
          platform: hostPlatform,
          channel: 'portable',
          arch: hostArch,
          version: '9.9.9',
          file: 'afrp_oidc.zip',
          sha256: '',
        ),
        mkEntry(
          kind: 'app',
          platform: hostPlatform,
          channel: 'installer',
          arch: hostArch,
          version: '9.9.8',
          file: 'setup.exe',
          sha256: '',
        ),
      ]);
      final check = await checkAppUpdate(baseUrl);
      expect(check, isNotNull);
      expect(check!.currentVersion, kAppVersion);
      expect(check.hasUpdate, isTrue);
      expect(check.entry.version, '9.9.9');
      if (Platform.isWindows) {
        // 测试进程所在目录无 unins*.exe → 视为免安装版，挑选 portable 通道
        expect(check.entry.channel, 'portable');
      }
    });

    test('清单版本等于当前 → hasUpdate=false', () async {
      manifestJson = wrapManifest([
        mkEntry(
          kind: 'app',
          platform: hostPlatform,
          arch: hostArch,
          version: kAppVersion,
          file: 'same.exe',
          sha256: '',
        ),
      ]);
      final check = await checkAppUpdate(baseUrl);
      expect(check, isNotNull);
      expect(check!.hasUpdate, isFalse);
    });
  });

  group('解压', () {
    test('extractExecutable：zip 解出目标文件、非压缩包原样返回', () async {
      final content = utf8.encode('PORTABLE-APP-BINARY');
      final archive = Archive()
        ..addFile(ArchiveFile.noCompress('afrp_oidc.exe', content.length, content));
      final zipFile = File('${tmpRoot.path}${Platform.pathSeparator}pkg.zip');
      await zipFile.writeAsBytes(ZipEncoder().encodeBytes(archive));

      final out = await extractExecutable(zipFile, preferredName: 'afrp_oidc.exe');
      expect(out.path, '${zipFile.path}.bin');
      expect(out.readAsBytesSync(), content);

      final plain = File('${tmpRoot.path}${Platform.pathSeparator}frpc.exe');
      await plain.writeAsBytes(content);
      final same = await extractExecutable(plain, preferredName: 'frpc.exe');
      expect(same.path, plain.path);

      final missing = File('${tmpRoot.path}${Platform.pathSeparator}other.zip');
      await missing.writeAsBytes(ZipEncoder().encodeBytes(Archive()));
      await expectLater(
        extractExecutable(missing, preferredName: 'afrp_oidc.exe'),
        throwsA(isA<UpdateException>()),
      );
    });
  });
}
