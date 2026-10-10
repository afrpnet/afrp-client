import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../frpc/frpc_config.dart';
import '../frpc/frpc_manager.dart';
import 'common.dart';

/// 连接页：选服务器 → OIDC 认证字段自动填充 → 配置隧道 → 一键连接
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  Future<void> _initialLoad() async {
    try {
      if (appState.config == null) {
        await appState.loadConfig();
      }
      if (appState.servers.isEmpty) {
        await appState.loadServers();
      }
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
        title: const Text('连接'),
        actions: [
          IconButton(
            tooltip: '刷新服务器列表',
            icon: const Icon(Icons.refresh),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await appState.loadServers();
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        snack(context, e.message, error: true);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _busy = false);
                      }
                    }
                  },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([appState, frpcManager]),
        builder: (context, _) {
          final server = appState.selectedServer;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _serverCard(server),
              const SizedBox(height: 12),
              _oidcCard(),
              const SizedBox(height: 12),
              _tunnelsCard(server),
              const SizedBox(height: 12),
              _connectCard(server),
              const SizedBox(height: 12),
              _logCard(),
            ],
          );
        },
      ),
    );
  }

  /* ==================== 服务器选择 ==================== */

  Widget _serverCard(ServerInfo? server) {
    final servers = appState.servers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_outlined, size: 20),
                const SizedBox(width: 8),
                Text('服务器', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (server != null) GroupBadge(server.group),
              ],
            ),
            const SizedBox(height: 12),
            if (servers.isEmpty)
              Text(
                '暂无可用服务器。免费账号可能仅显示部分节点，请检查账号等级或稍后刷新。',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: server?.id,
                decoration: const InputDecoration(
                  labelText: '选择服务器',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in servers)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${s.name}  ·  ${s.endpoint}${s.location.isEmpty ? '' : '  ·  ${s.location}'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: frpcManager.running
                    ? null
                    : (id) {
                        if (id != null) {
                          appState.selectServer(id);
                        }
                      },
              ),
            if (frpcManager.running) ...[
              const SizedBox(height: 8),
              Text(
                '连接中不可切换服务器，请先断开连接。',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ],
            if (server != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.lan_outlined, size: 16),
                    label: Text(server.endpoint),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.security, size: 16),
                    label: Text('认证 ${server.authMethod.toUpperCase()}'),
                  ),
                  if (server.subdomain.isNotEmpty)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.link, size: 16),
                      label: Text('子域名 ${server.subdomain}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /* ==================== OIDC 自动填充 ==================== */

  Widget _oidcCard() {
    final user = appState.user;
    final config = appState.config;
    final hasSecret = appState.hasLocalSecret;
    final tokenEndpoint = (config?.tokenEndpoint ?? '').isNotEmpty
        ? config!.tokenEndpoint
        : '${config?.oidcIssuer ?? ''}/oidc/token.php';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 20),
                const SizedBox(width: 8),
                Text('OIDC 认证', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('自动填充', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '连接时认证字段由 App 自动写入 frpc 配置，无需手动设置。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            if (user == null)
              const Text('未登录')
            else ...[
              InfoRow('认证方式', 'OIDC（${(appState.selectedServer?.authMethod ?? 'oidc').toUpperCase()}）'),
              InfoRow('用户名 (clientID)', user.username),
              InfoRow('Client Secret', hasSecret ? '•••••••••••• 已保存' : '未设置'),
              InfoRow('Token Endpoint', tokenEndpoint.isEmpty ? '(待加载)' : tokenEndpoint),
              InfoRow('Audience', config?.oidcAudience ?? '(待加载)'),
              InfoRow('Scope', config?.oidcScope ?? '(待加载)'),
            ],
            if (user != null && !user.authEnabled) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '该账号未开启 OIDC 认证，无法连接，请联系管理员。',
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ],
            if (user != null && !hasSecret) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  user.secretSet
                      ? '服务器上已存在密钥但本机未保存。可「粘贴已有密钥」，或「一键生成新密钥」（旧密钥将立即失效）。'
                      : '尚未设置 OIDC 密钥，请「粘贴已有密钥」或「一键生成新密钥」。',
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onTertiaryContainer),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (user != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('粘贴已有密钥'),
                    onPressed: () => promptPasteSecret(context),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: const Text('一键生成新密钥'),
                    onPressed: () => rotateSecretFlow(context),
                  ),
                  if (hasSecret)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清除本机密钥'),
                      onPressed: () async {
                        await appState.clearClientSecret();
                        if (mounted) {
                          snack(context, '已清除本机保存的密钥');
                        }
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /* ==================== 隧道 ==================== */

  Widget _tunnelsCard(ServerInfo? server) {
    final tunnels = server == null ? <Tunnel>[] : appState.tunnelsOf(server.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined, size: 20),
                const SizedBox(width: 8),
                Text('隧道（${tunnels.length}）', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加隧道'),
                  onPressed: server == null || frpcManager.running ? null : () => _editTunnel(server, null),
                ),
              ],
            ),
            if (tunnels.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有隧道。添加后连接时会自动写入 frpc 配置，例如把本机 127.0.0.1:8080 映射到远程端口。',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                ),
              )
            else ...[
              if (frpcManager.running)
                Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 2),
                  child: Text(
                    '连接中不可修改隧道，断开后可编辑或删除（修改在下次连接时生效）。',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                  ),
                ),
              for (var i = 0; i < tunnels.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: _typeIcon(tunnels[i].type),
                  title: Text(tunnels[i].name),
                  subtitle: Text(tunnels[i].summaryFor(server), style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '编辑',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: frpcManager.running || server == null
                            ? null
                            : () => _editTunnel(server, tunnels[i]),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: server == null ? null : () => _deleteTunnel(server, tunnels[i]),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeIcon(String type) {
    final icon = switch (type) {
      'tcp' => Icons.swap_vert,
      'udp' => Icons.swap_horiz,
      'http' => Icons.language,
      'https' => Icons.lock,
      'stcp' => Icons.enhanced_encryption,
      'sudp' => Icons.enhanced_encryption,
      'xtcp' => Icons.bolt,
      _ => Icons.device_hub,
    };
    return CircleAvatar(radius: 16, child: Icon(icon, size: 16));
  }

  Future<void> _editTunnel(ServerInfo server, Tunnel? existing) async {
    final result = await showDialog<Tunnel>(
      context: context,
      builder: (_) => TunnelEditDialog(server: server, existing: existing),
    );
    if (result == null || !mounted) {
      return;
    }
    // tunnelsOf 每次返回新解码对象，须按名称定位（名称即 frp 代理名，需唯一）
    final tunnels = appState.tunnelsOf(server.id);
    final i = existing == null ? -1 : tunnels.indexWhere((t) => t.name == existing.name);
    final dup = tunnels.asMap().entries.any((e) => e.key != i && e.value.name == result.name);
    if (dup) {
      snack(context, '已存在同名隧道「${result.name}」，请换一个名称', error: true);
      return;
    }
    if (i >= 0) {
      tunnels[i] = result;
    } else {
      tunnels.add(result);
    }
    await appState.saveTunnels(server.id, tunnels);
  }

  Future<void> _deleteTunnel(ServerInfo server, Tunnel tunnel) async {
    final ok = await confirmDialog(context, '删除隧道', '确定删除「${tunnel.name}」吗？', okText: '删除', dangerous: true);
    if (ok != true) {
      return;
    }
    final tunnels = appState.tunnelsOf(server.id)..removeWhere((t) => t.name == tunnel.name);
    await appState.saveTunnels(server.id, tunnels);
  }

  /* ==================== 连接控制 ==================== */

  Widget _connectCard(ServerInfo? server) {
    final scheme = Theme.of(context).colorScheme;
    final running = frpcManager.running;
    final ok = frpcManager.connectOk;
    final dotColor = ok ? Colors.green : (running ? Colors.orange : scheme.outline);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.power_settings_new, size: 20),
                const SizedBox(width: 8),
                Text('连接', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(frpcManager.status, style: const TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: Icon(running ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                    label: Text(running ? '断开连接' : '连接服务器'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: running ? scheme.error : null,
                    ),
                    onPressed: server == null ? null : _toggleConnect,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('查看配置'),
                  onPressed: () => _showConfig(server),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'frpc ${frpcManager.installedVersion} · ${Platform.operatingSystem}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleConnect() async {
    if (frpcManager.running) {
      await frpcManager.stop();
      return;
    }
    if (!mounted) {
      return;
    }
    final server = appState.selectedServer;
    final user = appState.user;
    if (server == null || user == null) {
      snack(context, '请先选择服务器并登录', error: true);
      return;
    }
    if (!user.authEnabled) {
      snack(context, '账号未开启 OIDC 认证，无法连接', error: true);
      return;
    }
    if (appState.config == null) {
      try {
        await appState.loadConfig();
      } on ApiException catch (e) {
        if (mounted) {
          snack(context, '加载站点配置失败：${e.message}', error: true);
        }
        return;
      }
      if (!mounted) {
        return;
      }
    }
    if (!appState.hasLocalSecret) {
      snack(context, '请先设置 OIDC 密钥（粘贴已有密钥或一键生成）', error: true);
      return;
    }
    final tunnels = appState.tunnelsOf(server.id);
    if (tunnels.isEmpty) {
      final go = await confirmDialog(context, '未配置隧道', '当前没有隧道，仅验证登录连接。继续连接吗？', okText: '继续');
      if (go != true) {
        return;
      }
    }
    final toml = buildFrpcToml(
      server: server,
      user: user,
      config: appState.config,
      clientSecret: appState.clientSecret ?? '',
      tunnels: tunnels,
    );
    try {
      await frpcManager.start(toml);
    } on UnsupportedError catch (e) {
      if (mounted) {
        snack(context, e.message.toString(), error: true);
      }
    } on ProcessException catch (e) {
      if (mounted) {
        snack(context, '无法启动 frpc：${e.message}', error: true);
      }
    }
  }

  void _showConfig(ServerInfo? server) {
    final user = appState.user;
    if (server == null || user == null) {
      snack(context, '请先选择服务器并登录', error: true);
      return;
    }
    final secret = appState.clientSecret ?? '';
    final toml = buildFrpcToml(
      server: server,
      user: user,
      config: appState.config,
      clientSecret: secret,
      tunnels: appState.tunnelsOf(server.id),
    );
    showDialog<void>(
      context: context,
      builder: (_) => _TomlDialog(toml: toml, secret: secret),
    );
  }

  /* ==================== 日志 ==================== */

  Widget _logCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('清空'),
                  onPressed: frpcManager.clearLog,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LogView(lines: frpcManager.logLines),
          ],
        ),
      ),
    );
  }
}

/// 隧道编辑对话框
class TunnelEditDialog extends StatefulWidget {
  const TunnelEditDialog({super.key, required this.server, this.existing});

  final ServerInfo server;
  final Tunnel? existing;

  @override
  State<TunnelEditDialog> createState() => _TunnelEditDialogState();
}

class _TunnelEditDialogState extends State<TunnelEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _localIp;
  late final TextEditingController _localPort;
  late final TextEditingController _remotePort;
  late final TextEditingController _subdomain;
  late final TextEditingController _customDomain;
  late final TextEditingController _secretKey;
  late String _type;

  static const _types = ['tcp', 'udp', 'http', 'https', 'stcp', 'sudp', 'xtcp'];

  static const _typeDesc = {
    'tcp': 'TCP：把本地 TCP 服务映射到服务器端口（如 SSH、数据库）',
    'udp': 'UDP：把本地 UDP 服务映射到服务器端口（如游戏、DNS）',
    'http': 'HTTP：通过子域名 / 自定义域名访问本地网站',
    'https': 'HTTPS：同 HTTP，按 HTTPS 转发',
    'stcp': 'STCP（加密 TCP · P2P）：不占服务器端口，访问方用相同密钥连接',
    'sudp': 'SUDP（加密 UDP · P2P）：不占服务器端口，访问方用相同密钥连接',
    'xtcp': 'XTCP（点对点直连）：NAT 打洞直连，失败时经服务器转发',
  };

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _name = TextEditingController(text: t?.name ?? '');
    _localIp = TextEditingController(text: t?.localIp ?? '127.0.0.1');
    _localPort = TextEditingController(text: t == null || t.localPort == 0 ? '' : '${t.localPort}');
    _remotePort = TextEditingController(text: t?.remotePort == null ? '' : '${t!.remotePort}');
    _subdomain = TextEditingController(text: t?.subdomain ?? '');
    _customDomain = TextEditingController(text: t?.customDomain ?? '');
    _secretKey = TextEditingController(text: t?.secretKey ?? '');
    _type = t?.type ?? 'tcp';
  }

  @override
  void dispose() {
    _name.dispose();
    _localIp.dispose();
    _localPort.dispose();
    _remotePort.dispose();
    _subdomain.dispose();
    _customDomain.dispose();
    _secretKey.dispose();
    super.dispose();
  }

  bool get _isWeb => _type == 'http' || _type == 'https';

  bool get _isP2P => _type == 'stcp' || _type == 'sudp' || _type == 'xtcp';

  static String _randomKey() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String? _portValidator(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < 1 || n > 65535) {
      return '端口需为 1-65535';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_isWeb &&
        _subdomain.text.trim().isEmpty &&
        _customDomain.text.trim().isEmpty) {
      snack(context, 'HTTP/HTTPS 隧道需要填写子域名或自定义域名', error: true);
      return;
    }
    Navigator.pop(
      context,
      Tunnel(
        name: _name.text.trim(),
        type: _type,
        localIp: _localIp.text.trim().isEmpty ? '127.0.0.1' : _localIp.text.trim(),
        localPort: int.parse(_localPort.text.trim()),
        remotePort: _isWeb || _isP2P ? null : int.parse(_remotePort.text.trim()),
        subdomain: _isWeb ? _subdomain.text.trim() : '',
        customDomain: _isWeb ? _customDomain.text.trim() : '',
        secretKey: _isP2P ? _secretKey.text.trim() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    return AlertDialog(
      title: Text(widget.existing == null ? '添加隧道' : '编辑隧道'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in _types)
                      ChoiceChip(
                        label: Text(t.toUpperCase()),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_typeDesc[_type] ?? '', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '隧道名称',
                    hintText: '例如 web、rdp（英文/数字）',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) {
                      return '请输入隧道名称';
                    }
                    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(s)) {
                      return '仅支持字母、数字、_ . -';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _localIp,
                        decoration: const InputDecoration(
                          labelText: '本地 IP',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _localPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '本地端口',
                          hintText: '8080',
                          border: OutlineInputBorder(),
                        ),
                        validator: _portValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isWeb) ...[
                  if (server.subdomain.isNotEmpty)
                    TextFormField(
                      controller: _subdomain,
                      decoration: InputDecoration(
                        labelText: '子域名前缀',
                        hintText: '例如 ${server.subdomain}-abc',
                        helperText: '将得到 ${server.subdomain}-${_subdomain.text.isEmpty ? 'xxx' : _subdomain.text} 形式的地址',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  else
                    TextFormField(
                      controller: _customDomain,
                      decoration: const InputDecoration(
                        labelText: '自定义域名',
                        hintText: '该服务器未提供子域名，请填写已解析的域名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  if (server.subdomain.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customDomain,
                      decoration: const InputDecoration(
                        labelText: '自定义域名（可选，优先于子域名）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ] else if (_isP2P) ...[
                  TextFormField(
                    controller: _secretKey,
                    decoration: InputDecoration(
                      labelText: '访问密钥（secretKey）',
                      hintText: '任意字符串，访问方需一致',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '随机生成',
                        icon: const Icon(Icons.casino_outlined, size: 20),
                        onPressed: () => setState(() => _secretKey.text = _randomKey()),
                      ),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? '请设置访问密钥' : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '该类型不占用服务器端口；访问方需以 visitor 方式、用相同密钥与隧道名称连接。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  TextFormField(
                    controller: _remotePort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '远程端口',
                      hintText: '服务器上对外开放的端口',
                      border: OutlineInputBorder(),
                    ),
                    validator: _portValidator,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 生成的 frpc.toml 预览（密钥默认打码）
class _TomlDialog extends StatefulWidget {
  const _TomlDialog({required this.toml, required this.secret});

  final String toml;
  final String secret;

  @override
  State<_TomlDialog> createState() => _TomlDialogState();
}

class _TomlDialogState extends State<_TomlDialog> {
  bool _showSecret = false;

  String get _display {
    if (_showSecret || widget.secret.isEmpty) {
      return widget.toml;
    }
    return widget.toml.replaceAll(widget.secret, '•' * widget.secret.length);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('frpc.toml（自动生成）'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: SelectableText(
            _display,
            style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace'], fontSize: 12.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _showSecret = !_showSecret),
          child: Text(_showSecret ? '隐藏密钥' : '显示密钥'),
        ),
        TextButton(
          onPressed: () => copyText(context, widget.toml, label: '配置'),
          child: const Text('复制完整配置'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}

/// 日志视图：等宽字体 + 自动滚动到底部
class _LogView extends StatefulWidget {
  const _LogView({required this.lines});

  final List<String> lines;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  final _controller = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (lines.length != _lastCount) {
      _lastCount = lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      });
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 240,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: lines.isEmpty
          ? Center(
              child: Text('暂无日志', style: TextStyle(color: scheme.outline, fontSize: 13)),
            )
          : Scrollbar(
              controller: _controller,
              child: ListView.builder(
                controller: _controller,
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final line = lines[i];
                  final l = line.toLowerCase();
                  Color? color;
                  if (l.contains('error') || l.contains('failed') || l.contains('panic')) {
                    color = scheme.error;
                  } else if (l.contains('success')) {
                    color = Colors.green.shade700;
                  }
                  return Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: 12,
                      color: color,
                    ),
                  );
                },
              ),
            ),
    );
  }
}
