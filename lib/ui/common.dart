import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';

void snack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: error ? 4 : 2),
    ));
}

Future<void> copyText(BuildContext context, String text, {String label = '内容'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    snack(context, '$label已复制');
  }
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String content, {
  String okText = '确定',
  bool dangerous = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: dangerous
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          child: Text(okText),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 只读信息行（用于 OIDC 自动填充面板）
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.mono = true, this.trailing});

  final String label;
  final String value;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace'], fontSize: 12.5)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: SelectableText(value, style: style)),
          ?trailing,
        ],
      ),
    );
  }
}

/// 会员分组徽标
class GroupBadge extends StatelessWidget {
  const GroupBadge(this.group, {super.key, this.level});

  final String group;
  final int? level;

  static const _names = {'free': '免费', 'vip': 'VIP', 'svip': 'SVIP', 'pro': 'Pro', 'admin': '管理员'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFree = group == 'free' || group.isEmpty;
    final color = switch (group) {
      'svip' => const Color(0xFFB8860B),
      'vip' => const Color(0xFF2E7D32),
      'pro' => const Color(0xFF6A1B9A),
      'admin' => const Color(0xFF7C3AED),
      _ => scheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _names[group] ?? group,
        style: TextStyle(fontSize: 11, color: isFree ? scheme.outline : color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/* ==================== OIDC 密钥流程（连接页 / 设置页共用） ==================== */

/// 粘贴已有 Client Secret 并保存到本机安全存储
Future<void> promptPasteSecret(BuildContext context) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('粘贴 Client Secret'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '在网页端「连接说明」处可查看或生成密钥，粘贴到此处即可（仅保存在本机安全存储）。',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Client Secret',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
      ],
    ),
  );
  if (ok == true && controller.text.trim().isNotEmpty && context.mounted) {
    await appState.saveClientSecret(controller.text);
    if (context.mounted) {
      snack(context, '密钥已保存到本机');
    }
  }
  controller.dispose();
}

/// 一键生成新密钥（旧密钥立即失效），生成后弹出明文供保存
Future<void> rotateSecretFlow(BuildContext context) async {
  final ok = await confirmDialog(
    context,
    '生成新密钥',
    '旧密钥将立即失效，所有使用旧密钥的客户端会断开。确定生成新密钥吗？',
    okText: '生成',
    dangerous: true,
  );
  if (ok != true) {
    return;
  }
  try {
    final secret = await appState.rotateSecret();
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新密钥已生成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请妥善保存以下密钥（服务端只保存哈希，本页面关闭后无法再次查看明文；本机已自动保存）：'),
            const SizedBox(height: 12),
            SelectableText(
              secret,
              style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => copyText(ctx, secret, label: '密钥'),
            child: const Text('复制'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('我已保存')),
        ],
      ),
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      snack(context, e.message, error: true);
    }
  }
}
