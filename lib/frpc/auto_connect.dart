import '../core/app_state.dart';
import '../core/api_client.dart';
import 'frpc_config.dart';
import 'frpc_manager.dart';

/// 启动时静默自动连接 frpc（无 UI 反馈）；任一前置条件不满足或失败都直接返回，
/// 不打扰用户（用户仍可在连接页手动连接）。
Future<void> autoConnectFrpc() async {
  if (!appState.loggedIn || frpcManager.running) {
    return;
  }
  final server = appState.selectedServer;
  final user = appState.user;
  if (server == null || user == null || !user.authEnabled) {
    return;
  }
  if (!appState.hasLocalSecret) {
    return;
  }
  if (appState.config == null) {
    try {
      await appState.loadConfig();
    } on ApiException {
      return;
    }
  }
  final tunnels = appState.tunnelsOf(server.id);
  final resolvedAddr = await resolveServerAddr(server.addr);
  final toml = buildFrpcToml(
    server: server,
    user: user,
    config: appState.config,
    clientSecret: appState.clientSecret ?? '',
    tunnels: tunnels,
    resolvedAddr: resolvedAddr,
  );
  try {
    await frpcManager.start(toml);
  } catch (_) {
    // 自动连接失败不报错；loginFailExit=false 会让 frpc 自行重试
  }
}
