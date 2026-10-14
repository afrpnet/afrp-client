import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Android / 鸿蒙上的 frpc 是纯 Go 静态 linux 二进制，读不到系统 DNS
/// （无 /etc/resolv.conf），会回落到 [::1]:53 导致 OIDC token 端点域名解析失败：
/// `lookup www.afrp.net on [::1]:53: connection refused`。
///
/// serverAddr 已由 Dart 预解析为 IP，但 token 端点是 HTTPS URL，直接换成 IP
/// 会破坏 TLS 证书校验。这里改为：在回环地址起一个本地 HTTP 代理，frpc 把
/// token 请求发到 `http://127.0.0.1:<port>`（无需 DNS、无需 TLS），由 Dart 转发
/// 到真实端点（Dart 走系统解析器 + 正常校验证书），并把响应原样回传。
class OidcTokenProxy {
  HttpServer? _server;
  String? _realEndpoint;

  bool get running => _server != null;

  /// 启动代理并返回供 frpc 使用的本地 tokenEndpointURL。
  /// [realEndpoint] 为真实的 https token 端点。失败抛异常，由调用方决定是否回退。
  Future<String> start(String realEndpoint) async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _realEndpoint = realEndpoint;
    server.listen(_handle);
    return 'http://127.0.0.1:${server.port}/oidc/token.php';
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _realEndpoint = null;
    try {
      await s?.close(force: true);
    } catch (_) {
      // 已关闭
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final target = _realEndpoint;
    if (target == null) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      return;
    }
    final client = http.Client();
    try {
      final body = await req.fold<List<int>>(
        [],
        (acc, chunk) => acc..addAll(chunk),
      );
      final upstream = http.Request(req.method, Uri.parse(target));
      final ct = req.headers.contentType?.toString();
      if (ct != null) {
        upstream.headers['content-type'] = ct;
      }
      final auth = req.headers.value(HttpHeaders.authorizationHeader);
      if (auth != null) {
        upstream.headers[HttpHeaders.authorizationHeader] = auth;
      }
      final accept = req.headers.value(HttpHeaders.acceptHeader);
      if (accept != null) {
        upstream.headers[HttpHeaders.acceptHeader] = accept;
      }
      upstream.bodyBytes = body;

      final streamed = await client
          .send(upstream)
          .timeout(const Duration(seconds: 20));
      final resp = await http.Response.fromStream(streamed);

      req.response.statusCode = resp.statusCode;
      final respCt = resp.headers[HttpHeaders.contentTypeHeader];
      if (respCt != null) {
        req.response.headers.set(HttpHeaders.contentTypeHeader, respCt);
      }
      final cache = resp.headers['cache-control'];
      if (cache != null) {
        req.response.headers.set('cache-control', cache);
      }
      final pragma = resp.headers['pragma'];
      if (pragma != null) {
        req.response.headers.set('pragma', pragma);
      }
      req.response.add(resp.bodyBytes);
      await req.response.close();
    } catch (e) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        req.response.write('{"error":"proxy_failed"}');
        await req.response.close();
      } catch (_) {
        // 连接可能已被 frpc 关闭
      }
    } finally {
      client.close();
    }
  }
}

/// 全局单例：同一时刻只有一个 frpc 进程，故只需一个代理
final OidcTokenProxy oidcProxy = OidcTokenProxy();
