import '../core/models.dart';

/// 生成 frpc.toml：
/// - 服务器地址 / 端口 / user 来自所选服务器与账号
/// - OIDC 认证字段全部自动填充（对应网页端 frpc_snippet 模板）
/// - [[proxies]] 来自用户自建隧道
String buildFrpcToml({
  required ServerInfo server,
  required UserInfo user,
  required PublicConfig? config,
  required String clientSecret,
  required List<Tunnel> tunnels,
}) {
  final tokenEndpoint = (config?.tokenEndpoint ?? '').isNotEmpty
      ? config!.tokenEndpoint
      : '${config?.oidcIssuer ?? ''}/oidc/token.php';

  final b = StringBuffer()
    ..writeln('# 由 AFRP OIDC App 自动生成，请勿手动修改（修改会在下次连接时覆盖）')
    ..writeln('serverAddr = "${_esc(server.addr)}"')
    ..writeln('serverPort = ${server.port}')
    ..writeln('user = "${_esc(user.username)}"')
    ..writeln()
    ..writeln('auth.method = "oidc"')
    ..writeln('auth.oidc.clientID = "${_esc(user.username)}"')
    ..writeln('auth.oidc.clientSecret = "${_esc(clientSecret)}"')
    ..writeln('auth.oidc.tokenEndpointURL = "${_esc(tokenEndpoint)}"')
    ..writeln('auth.oidc.audience = "${_esc(config?.oidcAudience ?? '')}"')
    ..writeln('auth.oidc.scope = "${_esc(config?.oidcScope ?? '')}"');

  for (final t in tunnels) {
    b
      ..writeln()
      ..writeln('[[proxies]]')
      ..writeln('name = "${_esc(t.name)}"')
      ..writeln('type = "${_esc(t.type)}"')
      ..writeln('localIP = "${_esc(t.localIp)}"')
      ..writeln('localPort = ${t.localPort}');
    if (t.isWeb) {
      if (t.customDomain.trim().isNotEmpty) {
        b.writeln('customDomains = ["${_esc(t.customDomain.trim())}"]');
      } else if (t.subdomain.trim().isNotEmpty) {
        b.writeln('subdomain = "${_esc(t.subdomain.trim())}"');
      }
    } else if (t.isP2P) {
      // stcp/sudp/xtcp：不占用服务器端口，由访问方（visitor）用同一密钥连接
      if (t.secretKey.trim().isNotEmpty) {
        b.writeln('secretKey = "${_esc(t.secretKey.trim())}"');
      }
    } else {
      b.writeln('remotePort = ${t.remotePort ?? 0}');
    }
  }

  return b.toString();
}

String _esc(String s) => s.replaceAll('\\', r'\\').replaceAll('"', r'\"');
