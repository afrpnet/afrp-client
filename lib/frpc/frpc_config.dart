import 'dart:io';

import '../core/models.dart';

/// 安卓/鸿蒙上 frpc 是 Go 静态二进制，读不到系统 DNS（无 /etc/resolv.conf），
/// 会回落到 localhost:53 报 "connection refused"。这里改用 Dart（走系统解析器）
/// 预解析主机名为 IP；桌面端 Go 解析正常，返回 null 保持主机名。
Future<String?> resolveServerAddr(String host) async {
  final os = Platform.operatingSystem;
  final isMobile = Platform.isAndroid || os == 'ohos' || os.contains('harmony');
  if (!isMobile) {
    return null;
  }
  if (InternetAddress.tryParse(host) != null) {
    return null;
  }
  try {
    final addrs = await InternetAddress.lookup(host);
    for (final a in addrs) {
      if (a.type == InternetAddressType.IPv4) {
        return a.address;
      }
    }
    return addrs.isEmpty ? null : addrs.first.address;
  } catch (_) {
    return null;
  }
}

/// 客户端类型标识：随 Token 请求上报，网站后台据此显示用户用哪种客户端连接
String _clientType() {
  final os = Platform.operatingSystem.toLowerCase();
  if (os == 'android') return 'app-android';
  if (os == 'ios') return 'app-ios';
  if (os == 'windows') return 'app-windows';
  if (os == 'linux') return 'app-linux';
  if (os == 'macos') return 'app-macos';
  if (os.contains('ohos') || os.contains('harmony')) return 'app-ohos';
  return 'app-unknown';
}

/// 生成 frpc.toml：
/// - 服务器地址 / 端口 / user 来自所选服务器与账号
/// - OIDC 认证字段全部自动填充（对应网页端 frpc_snippet 模板）
/// - [[proxies]] 来自用户自建隧道
/// - [resolvedAddr] 非空时 serverAddr 写 IP，并用 transport.tls.serverName 保留主机名，
///   保证 TLS 证书校验 / SNI 仍按主机名进行
String buildFrpcToml({
  required ServerInfo server,
  required UserInfo user,
  required PublicConfig? config,
  required String clientSecret,
  required List<Tunnel> tunnels,
  String? resolvedAddr,
}) {
  final tokenEndpoint = (config?.tokenEndpoint ?? '').isNotEmpty
      ? config!.tokenEndpoint
      : '${config?.oidcIssuer ?? ''}/oidc/token.php';

  final addr = (resolvedAddr != null && resolvedAddr.isNotEmpty) ? resolvedAddr : server.addr;

  final b = StringBuffer()
    ..writeln('# 由 AFRP OIDC App 自动生成，请勿手动修改（修改会在下次连接时覆盖）')
    ..writeln('serverAddr = "${_esc(addr)}"')
    ..writeln('serverPort = ${server.port}')
    ..writeln('user = "${_esc(user.username)}"')
    // 开机自启时网络/DNS 可能尚未就绪，首连易写超时；默认 loginFailExit=true 会一次失败即退出不重试，
    // 置 false 让 frpc 持续重试直到连上。
    ..writeln('loginFailExit = false');
  if (addr != server.addr) {
    b.writeln('transport.tls.serverName = "${_esc(server.addr)}"');
  }
  b
    ..writeln()
    ..writeln('auth.method = "oidc"')
    ..writeln('auth.oidc.clientID = "${_esc(user.username)}"')
    ..writeln('auth.oidc.clientSecret = "${_esc(clientSecret)}"')
    ..writeln('auth.oidc.tokenEndpointURL = "${_esc(tokenEndpoint)}"')
    ..writeln('auth.oidc.audience = "${_esc(config?.oidcAudience ?? '')}"')
    ..writeln('auth.oidc.scope = "${_esc(config?.oidcScope ?? '')}"')
    // 上报客户端类型，网站后台可显示该账号在用哪种客户端连接
    ..writeln('auth.oidc.additionalEndpointParams.client_type = "${_esc(_clientType())}"')
    // 同一份信息随 frp 登录包上报，网站「连接记录」可按接入方式筛选
    ..writeln('metadatas = { client_type = "${_esc(_clientType())}" }');

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
