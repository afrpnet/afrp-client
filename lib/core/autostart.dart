import 'dart:io';

/// Windows 开机自启：写/删 HKCU Run 键。其他平台不支持（返回 false / 空操作）。
const String _kRunKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const String _kValueName = 'AfrpOidcClient';

bool get bootAutostartSupported => Platform.isWindows;

Future<bool> isBootAutostartEnabled() async {
  if (!Platform.isWindows) {
    return false;
  }
  try {
    final r = await Process.run('reg', ['query', _kRunKey, '/v', _kValueName]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<void> setBootAutostart(bool on) async {
  if (!Platform.isWindows) {
    return;
  }
  try {
    if (on) {
      final exe = Platform.resolvedExecutable;
      await Process.run('reg', [
        'add', _kRunKey, '/v', _kValueName, '/t', 'REG_SZ', '/d', '"$exe"', '/f',
      ]);
    } else {
      await Process.run('reg', ['delete', _kRunKey, '/v', _kValueName, '/f']);
    }
  } catch (_) {
    // 注册表不可用时静默失败，设置页开关状态以查询结果为准
  }
}
