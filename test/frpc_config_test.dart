import 'package:flutter_test/flutter_test.dart';

import 'package:frp_oidc_app/core/models.dart';
import 'package:frp_oidc_app/frpc/frpc_config.dart';

void main() {
  final server = ServerInfo(
    id: 1,
    name: '节点A',
    addr: 'frp.example.com',
    port: 7000,
    location: 'CN',
    group: 'free',
    visibility: 1,
    subdomain: 'demo',
    authMethod: 'oidc',
  );
  final user = UserInfo(
    id: 1,
    username: 'apptest',
    email: '',
    emailVerified: false,
    role: 'user',
    isActive: true,
    authEnabled: true,
    secretSet: true,
    groups: const [],
    groupLevel: 0,
    topGroup: '',
    expiries: const {},
    memberLabel: '',
  );
  final config = PublicConfig(
    siteName: '测试站',
    oidcIssuer: 'https://frp.example.com',
    oidcAudience: 'frps',
    oidcScope: 'openid',
    tokenEndpoint: 'https://frp.example.com/oidc/token.php',
    membershipEnabled: true,
    apiVersion: 1,
    logoType: 'text',
    logoTextA: 'afrp',
    logoTextB: '.net',
  );

  test('OIDC 认证字段自动填充且引号转义', () {
    final toml = buildFrpcToml(
      server: server,
      user: user,
      config: config,
      clientSecret: 'abc"123',
      tunnels: const [],
    );
    expect(toml, contains('serverAddr = "frp.example.com"'));
    expect(toml, contains('serverPort = 7000'));
    expect(toml, contains('user = "apptest"'));
    expect(toml, contains('auth.method = "oidc"'));
    expect(toml, contains('auth.oidc.clientID = "apptest"'));
    expect(toml, contains(r'auth.oidc.clientSecret = "abc\"123"'));
    expect(toml, contains('auth.oidc.tokenEndpointURL = "https://frp.example.com/oidc/token.php"'));
  });

  test('TCP 隧道写 remotePort，HTTP 隧道写 subdomain', () {
    final toml = buildFrpcToml(
      server: server,
      user: user,
      config: config,
      clientSecret: 's',
      tunnels: [
        Tunnel(name: 'ssh', type: 'tcp', localPort: 22, remotePort: 6000),
        Tunnel(name: 'web', type: 'http', localPort: 8080, subdomain: 'myapp'),
      ],
    );
    expect(toml, contains('name = "ssh"'));
    expect(toml, contains('remotePort = 6000'));
    expect(toml, contains('name = "web"'));
    expect(toml, contains('subdomain = "myapp"'));
    expect(toml, isNot(contains('customDomains')));
  });

  test('自定义域名优先于子域名', () {
    final toml = buildFrpcToml(
      server: server,
      user: user,
      config: config,
      clientSecret: 's',
      tunnels: [
        Tunnel(
          name: 'web',
          type: 'https',
          localPort: 8443,
          subdomain: 'ignored',
          customDomain: 'dev.example.com',
        ),
      ],
    );
    expect(toml, contains('customDomains = ["dev.example.com"]'));
    expect(toml, isNot(contains('subdomain = "ignored"')));
  });

  test('P2P 类型（stcp/sudp/xtcp）写 secretKey，不写 remotePort', () {
    final toml = buildFrpcToml(
      server: server,
      user: user,
      config: config,
      clientSecret: 's',
      tunnels: [
        Tunnel(name: 'p1', type: 'stcp', localPort: 22, secretKey: 'key-1'),
        Tunnel(name: 'p2', type: 'xtcp', localPort: 3389, secretKey: 'key-2'),
      ],
    );
    expect(toml, contains('type = "stcp"'));
    expect(toml, contains('secretKey = "key-1"'));
    expect(toml, contains('type = "xtcp"'));
    expect(toml, contains('secretKey = "key-2"'));
    expect(toml, isNot(contains('remotePort')));
    expect(toml, isNot(contains('subdomain')));
  });

  test('隧道摘要：子域名/自定义域名/P2P/远程端口', () {
    expect(
      Tunnel(name: 'w', type: 'http', localPort: 8080, subdomain: 'myapp').summaryFor(server),
      contains('demo-myapp'),
    );
    expect(
      Tunnel(name: 'w', type: 'https', localPort: 8443, customDomain: 'dev.example.com').summaryFor(server),
      contains('dev.example.com'),
    );
    expect(
      Tunnel(name: 'p', type: 'stcp', localPort: 22, secretKey: 'k').summaryFor(server),
      contains('已设置'),
    );
    expect(
      Tunnel(name: 't', type: 'tcp', localPort: 22, remotePort: 6000).summaryFor(server),
      contains(':6000'),
    );
  });
}
