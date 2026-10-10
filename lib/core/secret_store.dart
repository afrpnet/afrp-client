import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感信息本地存储（API 令牌 / OIDC Client Secret）。
/// 抽象为接口：Windows 构建在无 ATL 环境等特殊情况下可整体替换实现。
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
