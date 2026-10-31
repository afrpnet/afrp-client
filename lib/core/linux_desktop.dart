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
    // deb 安装版由系统提供 .desktop 与图标，不再写用户目录，避免重复条目
    final exe = Platform.resolvedExecutable;
    if (exe.startsWith('/usr/') || exe.startsWith('/opt/')) {
      return;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return;
    }
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

    final desktopDir = Directory('$dataHome/applications');
    await desktopDir.create(recursive: true);
    final desktopFile = File('${desktopDir.path}/$_appId.desktop');
    final exec = Platform.resolvedExecutable
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    final content = '''
[Desktop Entry]
Type=Application
Name=AFRP OIDC Client
Name[zh_CN]=AFRP OIDC 客户端
Comment=AFRP OIDC 内网穿透客户端
Comment[zh_CN]=AFRP OIDC 内网穿透客户端
Exec="$exec"
Icon=$_appId
Terminal=false
Categories=Network;RemoteAccess;
StartupNotify=true
StartupWMClass=$_appId
''';
    if (await _readTextOrNull(desktopFile) != content) {
      await desktopFile.writeAsString(content, flush: true);
      // 桌面环境要求启动器带可执行位，拖到桌面后才允许双击运行
      await Process.run('chmod', ['755', desktopFile.path]);
    }
  } catch (e) {
    debugPrint('Linux desktop integration skipped: $e');
  }
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
