import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 服务端统一响应 {ok:true,data:{...}} / {ok:false,error,message}
class ApiException implements Exception {
  ApiException(this.code, this.message, [this.status = 0]);

  final String code;
  final String message;
  final int status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, this.token})
      : baseUrl = _normalize(baseUrl);

  static String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  String baseUrl;
  String? token;

  final http.Client _client = http.Client();
  static const Duration _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    return _send(() => _client.get(uri, headers: _headers()));
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) {
    final uri = Uri.parse('$baseUrl$path');
    return _send(() => _client.post(
          uri,
          headers: _headers(json: true),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        ));
  }

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if ((token ?? '').isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() run) async {
    http.Response resp;
    try {
      resp = await run().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('network_timeout', '连接超时，请检查网络或服务器地址');
    } catch (_) {
      throw ApiException('network_error', '网络连接失败，请检查服务器地址与网络');
    }

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      throw ApiException('bad_response', '服务器返回异常（HTTP ${resp.statusCode}）', resp.statusCode);
    }

    if (body['ok'] == true) {
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return body;
    }
    throw ApiException(
      (body['error'] ?? 'unknown_error').toString(),
      (body['message'] ?? '请求失败（HTTP ${resp.statusCode}）').toString(),
      resp.statusCode,
    );
  }

  void close() => _client.close();
}
