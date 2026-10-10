import 'dart:io';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/tray_service.dart';
import '../core/updater.dart';
import '../frpc/frpc_manager.dart';
import 'common.dart';
import 'update_dialogs.dart';

/// 设置页：账号信息、服务器地址、OIDC 密钥状态、组件更新、关于与退出登录
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl = TextEditingController(text: appState.baseUrl);
  bool _checking = false;
  bool _checkingFrpc = false;
  bool _checkingApp = false;

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _saveBaseUrl() async {
    final url = _baseUrl.text.trim();
    if (url.isEmpty) {
      snack(context, '请输入服务器地址', error: true);
      return;
    }
    setState(() => _checking = true);
    try {
      await appState.setBaseUrl(url);
      await appState.loadConfig();
      if (!mounted) {
        return;
      }
      final name = appState.config?.siteName ?? '';
      snack(context, name.isEmpty ? '已保存并连接成功' : '已保存，站点：$name');
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, '连接失败：${e.message}（地址已保存）', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final user = appState.user;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _accountCard(user),
              const SizedBox(height: 12),
              _serverCard(),
              const SizedBox(height: 12),
              _secretCard(),
              const SizedBox(height: 12),
              _updateCard(),
              const SizedBox(height: 12),
              if (TrayService.supported) ...[
                _trayCard(),
                const SizedBox(height: 12),
              ],
              _aboutCard(),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _logout,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _accountCard(UserInfo? user) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 8),
                Text('账号', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: '刷新账号信息',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () async {
                    try {
                      await appState.refreshUser();
                      if (mounted) {
                        snack(context, '已刷新');
                      }
                    } on ApiException catch (e) {
                      if (mounted) {
                        snack(context, e.message, error: true);
                      }
                    }
                  },
                ),
              ],
            ),
            if (user == null)
              const Text('未登录')
            else ...[
              _row('用户名', user.username),
              _row('邮箱', user.email.isEmpty ? '未绑定' : user.email),
              _row('OIDC 认证', user.authEnabled ? '已开启' : '未开启（联系管理员）'),
              _row('服务器密钥', user.secretSet ? '已设置' : '未设置'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _serverCard() {
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
                Text('服务器地址', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'https://www.afrp.net',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: _checking
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('保存并测试连接'),
                onPressed: _checking ? null : _saveBaseUrl,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secretCard() {
    final theme = Theme.of(context);
    final has = appState.hasLocalSecret;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key_outlined, size: 20),
                const SizedBox(width: 8),
                Text('OIDC 密钥', style: theme.textTheme.titleMedium),
                const Spacer(),
                Icon(has ? Icons.check_circle : Icons.warning_amber, size: 18, color: has ? Colors.green : Colors.orange),
                const SizedBox(width: 4),
                Text(has ? '已保存' : '未设置', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '密钥仅保存在本机系统安全存储中，用于 frpc 连接时的 OIDC 认证。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
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
                if (has)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清除'),
                    onPressed: () async {
                      await appState.clearClientSecret();
                      if (mounted) {
                        snack(context, '已清除本机密钥');
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

  Widget _updateCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt, size: 20),
                const SizedBox(width: 8),
                Text('组件更新', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '从服务器检查 frpc 核心与 App 的新版本，按提示下载安装。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: frpcManager,
              builder: (context, _) => _updateRow(
                title: 'frpc 核心',
                version: frpcManager.installedVersion,
                checking: _checkingFrpc,
                onPressed: _checkingFrpc ? null : _checkFrpc,
              ),
            ),
            const SizedBox(height: 6),
            _updateRow(
              title: 'App',
              version: kAppVersion,
              checking: _checkingApp,
              onPressed: _checkingApp ? null : _checkApp,
            ),
          ],
        ),
      ),
    );
  }

  Widget _updateRow({
    required String title,
    required String version,
    required bool checking,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 92, child: Text(title, style: theme.textTheme.bodySmall)),
        Expanded(child: Text(version)),
        OutlinedButton.icon(
          icon: checking
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined, size: 18),
          label: Text(checking ? '检查中…' : '检查更新'),
          onPressed: onPressed,
        ),
      ],
    );
  }

  Future<void> _checkFrpc() async {
    setState(() => _checkingFrpc = true);
    try {
      final check = await checkFrpcUpdate(appState.baseUrl);
      if (!mounted) {
        return;
      }
      if (check == null) {
        snack(context, '当前平台暂不支持在线更新 frpc', error: true);
      } else if (!check.hasUpdate) {
        snack(context, 'frpc 已是最新版本（${check.currentVersion}）');
      } else {
        await frpcUpdateFlow(context, check: check);
      }
    } on UpdateException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) {
        snack(context, '检查更新失败：$e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _checkingFrpc = false);
      }
    }
  }

  Future<void> _checkApp() async {
    setState(() => _checkingApp = true);
    try {
      final check = await checkAppUpdate(appState.baseUrl);
      if (!mounted) {
        return;
      }
      if (check == null) {
        snack(context, '当前平台暂不支持在线更新 App', error: true);
      } else if (!check.hasUpdate) {
        snack(context, 'App 已是最新版本（${check.currentVersion}）');
      } else {
        await showAppUpdateDialog(context, baseUrl: appState.baseUrl, check: check);
      }
    } on UpdateException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) {
        snack(context, '检查更新失败：$e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _checkingApp = false);
      }
    }
  }

  Widget _trayCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.desktop_windows_outlined, size: 20),
                const SizedBox(width: 8),
                Text('后台运行', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '隐藏到系统托盘后 App 继续在后台运行，frpc 隧道保持连接；'
              '从托盘菜单可恢复主界面或退出。',
              style: theme.textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('关闭窗口时隐藏到托盘'),
              subtitle: Text(
                TrayService.instance.closeToTray ? '关闭后仍在后台运行（托盘菜单可退出）' : '关闭窗口即退出程序',
                style: theme.textTheme.bodySmall,
              ),
              value: TrayService.instance.closeToTray,
              onChanged: (v) async {
                await TrayService.instance.setCloseToTray(v);
                if (mounted) {
                  setState(() {});
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('最小化时隐藏到托盘'),
              value: TrayService.instance.minimizeToTray,
              onChanged: (v) async {
                await TrayService.instance.setMinimizeToTray(v);
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text('关于', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            _row('站点', appState.config?.brandName ?? '未获取'),
            _row('App 版本', kAppVersion),
            _row('frpc 版本', frpcManager.installedVersion),
            _row('运行平台', '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(
      context,
      '退出登录',
      '退出后需要重新输入账号密码，本机保存的隧道配置不会丢失。确定退出吗？',
      okText: '退出',
      dangerous: true,
    );
    if (ok != true) {
      return;
    }
    if (frpcManager.running) {
      await frpcManager.stop();
    }
    await appState.logout();
  }
}
