import 'dart:async';

import 'package:flutter/material.dart';

import '../core/updater.dart';
import '../frpc/frpc_manager.dart';
import 'common.dart';

String _fmtBytes(int bytes) {
  if (bytes >= 1 << 30) {
    return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

bool _isBrowserFlow(String platform) =>
    platform == 'macos' || platform == 'linux' || platform == 'ohos';

String _appUpdateHint(UpdateEntry e) {
  final platform = currentUpdatePlatform();
  if (platform == 'windows') {
    return e.channel == 'installer'
        ? '将下载安装包并静默安装，App 会自动退出，完成后请重新打开。'
        : '将下载新版本，App 退出后自动替换并重启。';
  }
  if (platform == 'android') {
    return '将下载 APK 并调起系统安装器，请在系统界面完成安装。';
  }
  if (platform == 'ohos') {
    return '将打开下载页，请在浏览器中下载 HAP 安装包后手动安装。';
  }
  return '将打开下载页，请下载对应安装包后手动更新。';
}

/// 进度对话框包裹任意更新任务；返回是否成功
Future<bool> _runWithProgress(
  BuildContext context, {
  required Future<void> Function(void Function(int received, int total) onProgress) task,
  required String doneMessage,
}) async {
  final progress = ValueNotifier<double?>(null);
  final detail = ValueNotifier<String>('正在下载…');
  var dialogOpen = true;

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在更新'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, v, _) => LinearProgressIndicator(value: v),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<String>(
              valueListenable: detail,
              builder: (_, t, _) => Align(
                alignment: Alignment.centerLeft,
                child: Text(t, style: Theme.of(ctx).textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
    ),
  ));

  void closeDialog() {
    if (!dialogOpen || !context.mounted) {
      return;
    }
    dialogOpen = false;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  try {
    await task((received, total) {
      progress.value = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
      final got = _fmtBytes(received);
      detail.value = total > 0 ? '已下载 $got / ${_fmtBytes(total)}' : '已下载 $got';
    });
    closeDialog();
    if (context.mounted) {
      snack(context, doneMessage);
    }
    return true;
  } on UpdateException catch (e) {
    closeDialog();
    if (context.mounted) {
      snack(context, e.message, error: true);
    }
    return false;
  } catch (e) {
    closeDialog();
    if (context.mounted) {
      snack(context, '更新失败：$e', error: true);
    }
    return false;
  }
}

/// frpc 核心更新确认 + 执行
Future<void> frpcUpdateFlow(
  BuildContext context, {
  required FrpcUpdateCheck check,
}) async {
  final e = check.entry;
  final running = frpcManager.running;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('更新 frpc 核心到 ${e.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 ${check.currentVersion}${e.sizeText.isEmpty ? '' : ' · 安装包 ${e.sizeText}'}'),
            if (e.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(e.notes.trim(), style: Theme.of(ctx).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Text(
              running ? '更新会先断开当前隧道连接，需重新连接。' : '更新后使用新的 frpc 核心进行连接。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍后')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('更新')),
      ],
    ),
  );
  if (go != true || !context.mounted) {
    return;
  }
  await _runWithProgress(
    context,
    task: (onProgress) => applyFrpcUpdate(e, onProgress: onProgress),
    doneMessage: 'frpc 已更新到 ${e.version}',
  );
}

/// 软件更新确认 + 执行（启动静默检查与设置页手动检查共用）
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required String baseUrl,
  required AppUpdateCheck check,
}) async {
  final e = check.entry;
  final browserFlow = _isBrowserFlow(currentUpdatePlatform());
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 ${e.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 ${check.currentVersion}${e.sizeText.isEmpty ? '' : ' · 安装包 ${e.sizeText}'}'),
            if (e.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(e.notes.trim(), style: Theme.of(ctx).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Text(_appUpdateHint(e), style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍后')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(browserFlow ? '打开下载页' : '立即更新'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) {
    return;
  }

  final platform = currentUpdatePlatform();
  final done = browserFlow
      ? '已在浏览器打开下载页'
      : platform == 'android'
          ? '已调起系统安装器，请按提示完成安装'
          : '安装程序已启动';
  await _runWithProgress(
    context,
    task: (onProgress) => performAppUpdate(baseUrl, e, onProgress: onProgress),
    doneMessage: done,
  );
}
