import 'dart:io';

/// 开机自启：Windows 写 HKCU Run 键，Linux 写 XDG autostart 条目。
const String _kRunKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const String _kValueName = 'AfrpOidcClient';
const String _kLinuxAppId = 'net.afrp.frp_oidc_app';

bool get bootAutostartSupported => Platform.isWindows || Platform.isLinux;

File? _linuxAutostartFile() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return null;
  }
  final configEnv = Platform.environment['XDG_CONFIG_HOME'];
  final configHome = (configEnv != null && configEnv.isNotEmpty)
      ? configEnv
      : '$home/.config';
  return File('$configHome/autostart/$_kLinuxAppId.desktop');
}

Future<bool> isBootAutostartEnabled() async {
  if (Platform.isLinux) {
    final file = _linuxAutostartFile();
    if (file == null) {
      return false;
    }
    try {
      if (!await file.exists()) {
        return false;
      }
      final content = await file.readAsString();
      // Hidden=true 的条目桌面环境会跳过
      return !RegExp(r'^Hidden\s*=\s*true\s*$', multiLine: true)
          .hasMatch(content);
    } catch (_) {
      return false;
    }
  }
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
  if (Platform.isLinux) {
    final file = _linuxAutostartFile();
    if (file == null) {
      return;
    }
    try {
      if (!on) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }
      await file.parent.create(recursive: true);
      final exec = Platform.resolvedExecutable
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"');
      await file.writeAsString('''
[Desktop Entry]
Type=Application
Name=AFRP OIDC Client
Name[zh_CN]=AFRP OIDC 客户端
Exec="$exec"
Icon=$_kLinuxAppId
Terminal=false
X-GNOME-Autostart-enabled=true
Hidden=false
''', flush: true);
    } catch (_) {
      // 写入失败时设置页会重新查询实际状态
    }
    return;
  }
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
