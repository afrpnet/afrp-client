// Windows 无开发者模式时，Flutter 无法为插件创建符号链接（需要管理员权限），
// 导致 `flutter build windows` 报 "Building with plugins requires symlink support"。
// 本脚本读取 .flutter-plugins-dependencies，用 mklink /J（junction，无需管理员）
// 在 windows/linux 的 .plugin_symlinks 目录下补齐插件链接；Dart 将 junction 视为
// Link，构建时的 link.existsSync() 检查通过即会跳过创建。
//
// 用法：dart tool/fix_plugin_junctions.dart
// 何时需要：首次构建前；每次新增/移除插件（flutter pub add/remove）之后。

import 'dart:convert';
import 'dart:io';

String _win(String path) => path.replaceAll('/', '\\');

void main() {
  if (!Platform.isWindows) {
    stdout.writeln('非 Windows 平台，符号链接原生可用，无需处理。');
    return;
  }
  final depsFile = File('.flutter-plugins-dependencies');
  if (!depsFile.existsSync()) {
    stderr.writeln('未找到 .flutter-plugins-dependencies，请先执行 flutter pub get');
    exit(1);
  }
  final json = jsonDecode(depsFile.readAsStringSync()) as Map<String, dynamic>;
  final plugins = json['plugins'] as Map<String, dynamic>? ?? const {};

  var created = 0;
  var removed = 0;
  for (final platform in ['windows', 'linux']) {
    if (!Directory(platform).existsSync()) {
      continue;
    }
    final entries = (plugins[platform] as List?) ?? const [];
    final wanted = <String>{};
    final linkDir = Directory('$platform/flutter/ephemeral/.plugin_symlinks');
    linkDir.createSync(recursive: true);

    for (final entry in entries.cast<Map<String, dynamic>>()) {
      final name = entry['name'] as String;
      final target = entry['path'] as String;
      wanted.add(name);
      final link = Link('${linkDir.path}/$name');
      if (link.existsSync()) {
        continue;
      }
      final r = Process.runSync('cmd', ['/c', 'mklink', '/J', _win(link.path), _win(target)]);
      if (r.exitCode == 0) {
        created++;
      } else {
        stderr.writeln('创建 junction 失败 [$platform/$name]: ${r.stderr}');
      }
    }

    for (final e in linkDir.listSync(followLinks: false)) {
      final name = e.path.replaceAll('\\', '/').split('/').last;
      if (wanted.contains(name) || e is! Link) {
        continue;
      }
      e.deleteSync();
      removed++;
    }
  }
  stdout.writeln('插件 junction 就绪：新建 $created，清理 $removed。');
}
