import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String _appId = 'net.afrp.frp_oidc_app';

/// Linux 的 ELF 不能内嵌图标：把品牌图标和 .desktop 启动器注册到用户目录，
/// 应用菜单、任务栏和 Wayland 下的图标才会显示成专用图标。
Future<void> registerLinuxDesktopEntry() async {
  if (!Platform.isLinux) {
    return;
  }
  try {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return;
    }
    // deb 安装版已有系统级 .desktop 时不再写用户菜单条目，避免出现两个图标
    final hasSystemEntry =
        File('/usr/share/applications/$_appId.desktop').existsSync() ||
            File('/usr/local/share/applications/$_appId.desktop').existsSync();
    final dataEnv = Platform.environment['XDG_DATA_HOME'];
    final dataHome = (dataEnv != null && dataEnv.isNotEmpty)
        ? dataEnv
        : '$home/.local/share';

    final iconFile = File('$dataHome/icons/hicolor/512x512/apps/$_appId.png');
    await iconFile.parent.create(recursive: true);
    final bytes = (await rootBundle.load('assets/brand/app_icon.png'))
        .buffer
        .asUint8List();
    if (!_sameBytes(await _readBytesOrNull(iconFile), bytes)) {
      await iconFile.writeAsBytes(bytes, flush: true);
    }

    final exec = Platform.resolvedExecutable
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    final content = '''
[Desktop Entry]
Version=1.0
Type=Application
Name=AFRP OIDC Client
Name[zh_CN]=AFRP OIDC 客户端
GenericName=FRP Tunneling Client
GenericName[zh_CN]=内网穿透客户端
Comment=AFRP OIDC 内网穿透客户端
Comment[zh_CN]=AFRP OIDC 内网穿透客户端
Exec="$exec"
Icon=$_appId
Terminal=false
Categories=Network;RemoteAccess;
Keywords=frp;tunnel;内网穿透;穿透;OIDC;
StartupNotify=true
StartupWMClass=$_appId
''';
    if (!hasSystemEntry) {
      final desktopDir = Directory('$dataHome/applications');
      await desktopDir.create(recursive: true);
      final desktopFile = File('${desktopDir.path}/$_appId.desktop');
      if (await _readTextOrNull(desktopFile) != content) {
        await desktopFile.writeAsString(content, flush: true);
        // 桌面环境要求启动器带可执行位，拖到桌面后才允许双击运行
        await Process.run('chmod', ['755', desktopFile.path]);
      }
    }

    // 首次运行时在用户桌面放一个启动图标（XFCE/GNOME/KDE 都认这个目录）
    final desktopDirPath = _xdgDesktopDir(home);
    if (desktopDirPath != null) {
      final shortcut = File('$desktopDirPath/$_appId.desktop');
      if (!await shortcut.exists()) {
        await shortcut.writeAsString(content, flush: true);
        await Process.run('chmod', ['755', shortcut.path]);
      }
    }
  } catch (e) {
    debugPrint('Linux desktop integration skipped: $e');
  }
}

/// 读取 XDG 桌面目录（中文系统一般是 ~/桌面），没有配置时退回 ~/Desktop
String? _xdgDesktopDir(String home) {
  final configEnv = Platform.environment['XDG_CONFIG_HOME'];
  final configHome = (configEnv != null && configEnv.isNotEmpty)
      ? configEnv
      : '$home/.config';
  final userDirs = File('$configHome/user-dirs.dirs');
  try {
    if (userDirs.existsSync()) {
      for (final line in userDirs.readAsLinesSync()) {
        if (!line.startsWith('XDG_DESKTOP_DIR=')) {
          continue;
        }
        var value = line.substring('XDG_DESKTOP_DIR='.length).trim();
        if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
          value = value.substring(1, value.length - 1);
        }
        value = value.replaceFirst(r'$HOME', home);
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
  } catch (_) {}
  final fallback = Directory('$home/Desktop');
  return fallback.existsSync() ? fallback.path : null;
}

Future<List<int>?> _readBytesOrNull(File file) async {
  try {
    return await file.exists() ? await file.readAsBytes() : null;
  } catch (_) {
    return null;
  }
}

Future<String?> _readTextOrNull(File file) async {
  try {
    return await file.exists() ? await file.readAsString() : null;
  } catch (_) {
    return null;
  }
}

bool _sameBytes(List<int>? a, List<int> b) {
  if (a == null || a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
