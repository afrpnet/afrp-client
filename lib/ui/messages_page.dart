import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import 'common.dart';

/// 消息页：站内信列表、已读/删除
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  bool _loading = false;
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!appState.loggedIn) {
      return;
    }
    setState(() => _loading = true);
    try {
      await appState.loadMessages();
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _tap(MessageItem m) async {
    setState(() {
      if (_expanded.contains(m.id)) {
        _expanded.remove(m.id);
      } else {
        _expanded.add(m.id);
      }
    });
    if (!m.isRead) {
      try {
        await appState.markMessageRead(m.id);
      } on ApiException {
        // 已读标记失败不打扰
      }
    }
  }

  Future<void> _delete(MessageItem m) async {
    final ok = await confirmDialog(context, '删除消息', '确定删除「${m.title}」吗？', okText: '删除', dangerous: true);
    if (ok != true) {
      return;
    }
    try {
      await appState.deleteMessage(m.id);
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) => TextButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('全部已读'),
              onPressed: appState.unreadCount == 0 ? null : _markAll,
            ),
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final messages = appState.messages;
          if (_loading && messages.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_email_read_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('暂无消息'),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                    onPressed: _load,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _tile(messages[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _markAll() async {
    try {
      await appState.markAllMessagesRead();
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    }
  }

  Widget _tile(MessageItem m) {
    final theme = Theme.of(context);
    final expanded = _expanded.contains(m.id);
    return Card(
      elevation: m.isRead ? 0.5 : 2,
      color: m.isRead ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tap(m),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Icon(
                  m.isRead ? Icons.drafts_outlined : Icons.mark_email_unread,
                  size: 18,
                  color: m.isRead ? theme.colorScheme.outline : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.title,
                            style: TextStyle(
                              fontWeight: m.isRead ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          m.createdAt,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.content,
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _delete(m),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
