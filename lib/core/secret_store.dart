import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 敏感信息本地存储（API 令牌 / OIDC Client Secret）。
/// 抽象为接口：Windows 构建在无 ATL 环境等特殊情况下可整体替换实现。
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 系统安全存储（Windows DPAPI / macOS Keychain / Android Keystore / Linux libsecret）。
///
/// Linux 桌面没有运行 Secret Service（gnome-keyring / KWallet）时，libsecret 会直接报错
/// 或长时间阻塞；这里给每次调用加超时，失败后降级到应用数据目录下的本地文件，
/// 避免令牌读写把登录流程卡在「一直转圈」。
class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  static const _storage = FlutterSecureStorage();
  static const _timeout = Duration(seconds: 4);

  static bool _useFileFallback = false;
  static File? _fallbackFile;
  static Map<String, String>? _fallbackCache;

  @override
  Future<String?> read(String key) async {
    if (!_useFileFallback) {
      try {
        return await _storage.read(key: key).timeout(_timeout);
      } catch (e) {
        _switchToFile('read', e);
      }
    }
    return (await _fallbackData())[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_useFileFallback) {
      try {
        await _storage.write(key: key, value: value).timeout(_timeout);
        return;
      } catch (e) {
        _switchToFile('write', e);
      }
    }
    final data = await _fallbackData();
    data[key] = value;
    await _persistFallback(data);
  }

  @override
  Future<void> delete(String key) async {
    if (!_useFileFallback) {
      try {
        await _storage.delete(key: key).timeout(_timeout);
      } catch (e) {
        _switchToFile('delete', e);
      }
    }
    final data = await _fallbackData();
    if (data.remove(key) != null) {
      await _persistFallback(data);
    }
  }

  static void _switchToFile(String action, Object error) {
    if (_useFileFallback) {
      return;
    }
    _useFileFallback = true;
    debugPrint('SecretStore: secure storage $action failed, using file fallback: $error');
  }

  static Future<Map<String, String>> _fallbackData() async {
    final cached = _fallbackCache;
    if (cached != null) {
      return cached;
    }
    final data = <String, String>{};
    try {
      final file = await _file();
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((k, v) => data[k.toString()] = v.toString());
        }
      }
    } catch (e) {
      debugPrint('SecretStore: fallback read failed: $e');
    }
    return _fallbackCache = data;
  }

  static Future<void> _persistFallback(Map<String, String> data) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', file.path]);
      }
    } catch (e) {
      // 落盘失败时保持内存态，本次会话内仍可正常登录
      debugPrint('SecretStore: fallback write failed: $e');
    }
  }

  static Future<File> _file() async {
    final cached = _fallbackFile;
    if (cached != null) {
      return cached;
    }
    final dir = await getApplicationSupportDirectory();
    return _fallbackFile = File('${dir.path}/.secrets.json');
  }
}
