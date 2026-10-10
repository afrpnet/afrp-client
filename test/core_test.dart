import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:frp_oidc_app/core/api_client.dart';
import 'package:frp_oidc_app/core/models.dart';
import 'package:frp_oidc_app/frpc/frpc_config.dart';

/// 本地站点地址（flutter test 在宿主机运行，可直连本地 PHP）
const localBase = 'http://127.0.0.1:8000';

/// 本地测试账号（仅存在于本地数据库）
const testUser = 'apptest';
const testPass = 'AppTest_2026!';

Future<bool> _serverUp() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final req = await client.getUrl(Uri.parse('$localBase/api/config.php'));
    final resp = await req.close().timeout(const Duration(seconds: 3));
    await resp.drain<void>();
    client.close();
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  group('frpc.toml 生成', () {
    final server = ServerInfo(
      id: 1,
      name: '测试',
      addr: 'frp.example.com',
      port: 7000,
      location: 'HK',
      group: 'vip',
      visibility: 1,
      subdomain: 'demo',
      authMethod: 'oidc',
    );
    final user = UserInfo(
      id: 1,
      username: 'apptest',
      email: 'a@b.c',
      emailVerified: true,
      role: 'user',
      isActive: true,
      authEnabled: true,
      secretSet: true,
      groups: const ['vip'],
      groupLevel: 1,
      topGroup: 'vip',
      expiries: const {'vip': '2027-01-01 00:00:00'},
      memberLabel: 'VIP',
    );
    final config = PublicConfig(
      siteName: '演示',
      oidcIssuer: 'https://afrp.net',
      oidcAudience: 'frps',
      oidcScope: 'openid profile',
      tokenEndpoint: 'https://afrp.net/oidc/token.php',
      membershipEnabled: true,
      apiVersion: 1,
    );

    test('OIDC 认证字段自动填充', () {
      final toml = buildFrpcToml(
        server: server,
        user: user,
        config: config,
        clientSecret: 'secret"with\\escape',
        tunnels: const [],
      );
      expect(toml, contains('serverAddr = "frp.example.com"'));
      expect(toml, contains('serverPort = 7000'));
      expect(toml, contains('user = "apptest"'));
      expect(toml, contains('auth.method = "oidc"'));
      expect(toml, contains('auth.oidc.clientID = "apptest"'));
      expect(toml, contains(r'auth.oidc.clientSecret = "secret\"with\\escape"'));
      expect(toml, contains('auth.oidc.tokenEndpointURL = "https://afrp.net/oidc/token.php"'));
      expect(toml, contains('auth.oidc.audience = "frps"'));
      expect(toml, contains('auth.oidc.scope = "openid profile"'));
    });

    test('隧道渲染：tcp / http 子域名 / http 自定义域名', () {
      final toml = buildFrpcToml(
        server: server,
        user: user,
        config: config,
        clientSecret: 's',
        tunnels: [
          Tunnel(name: 'rdp', type: 'tcp', localPort: 3389, remotePort: 13389),
          Tunnel(name: 'web', type: 'http', localPort: 8080, subdomain: 'demo-ab12'),
          Tunnel(name: 'site', type: 'https', localPort: 443, customDomain: 'x.example.com', subdomain: 'ignored'),
        ],
      );
      expect(toml, contains('[[proxies]]'));
      expect(toml, contains('name = "rdp"'));
      expect(toml, contains('remotePort = 13389'));
      expect(toml, contains('name = "web"'));
      expect(toml, contains('subdomain = "demo-ab12"'));
      expect(toml, contains('customDomains = ["x.example.com"]'));
      expect(toml, isNot(contains('subdomain = "ignored"')));
    });
  });

  group('模型解析', () {
    test('PayInstruction：qr', () {
      final p = PayInstruction.fromJson(const {
        'type': 'qr',
        'code_url': 'weixin://wxpay/bizpayurl?pr=abc',
        'poll_seconds': 3,
      });
      expect(p.type, 'qr');
      expect(p.codeUrl, contains('weixin://'));
      expect(p.pollSeconds, 3);
    });

    test('PayInstruction：crypto', () {
      final p = PayInstruction.fromJson(const {
        'type': 'crypto',
        'poll_seconds': 8,
        'network': 'usdt',
        'addr': 'TXxx',
        'amount': 7.05,
        'rate': 7.1,
        'cny': 50,
      });
      expect(p.type, 'crypto');
      expect(p.crypto!.networkName, 'USDT (TRC20)');
      expect(p.crypto!.amount, closeTo(7.05, 1e-9));
    });

    test('UserInfo 到期标签', () {
      final u = UserInfo.fromJson(const {
        'id': 1,
        'username': 'x',
        'expiries': {'vip': '9999-12-31 23:59:59', 'svip': null},
      });
      expect(u.groupExpiryLabel('vip'), '永久');
      expect(u.groupExpiryLabel('svip'), '未开通');
      expect(u.groupExpiryLabel('pro'), '未开通');
    });

    test('Tunnel JSON 往返', () {
      final t = Tunnel(name: 'web', type: 'http', localPort: 8080, subdomain: 'a-b');
      final back = Tunnel.fromJson(t.toJson());
      expect(back.name, t.name);
      expect(back.type, t.type);
      expect(back.localPort, 8080);
      expect(back.subdomain, 'a-b');
      expect(back.remotePort, isNull);
    });
  });

  group('内置 frpc 资源', () {
    test('各平台二进制/压缩包存在且非空', () {
      for (final p in const [
        'assets/frpc/windows/frpc.exe',
        'assets/frpc/linux/frpc',
        'assets/frpc/macos/frpc_darwin_amd64.tar.gz',
      ]) {
        final f = File(p);
        expect(f.existsSync(), isTrue, reason: '$p 不存在');
        expect(f.lengthSync(), greaterThan(1000000), reason: '$p 异常偏小');
      }
    });
  });

  group('本地 API 联调（需本地站点运行）', () {
    test('登录 → me → servers → plans → messages → orders → logout', () async {
      if (!await _serverUp()) {
        // ignore: avoid_print
        print('[skip] 本地站点 $localBase 未运行，跳过联调');
        return;
      }
      final api = ApiClient(baseUrl: localBase);

      // 1. 公共配置（无鉴权）
      final cfg = await api.get('/api/config.php');
      expect(cfg['api_version'], isNotNull);

      // 2. 登录
      final login = await api.post('/api/login.php', {
        'identity': testUser,
        'password': testPass,
        'device': 'flutter-test',
      });
      final token = login['token'] as String;
      expect(token, startsWith('afrp_'));
      api.token = token;

      final loginUser = UserInfo.fromJson(login['user'] as Map<String, dynamic>);
      expect(loginUser.username, testUser);
      expect(loginUser.secretSet, isTrue);

      // 3. me
      final me = await api.get('/api/me.php');
      final meUser = UserInfo.fromJson((me['user'] as Map<String, dynamic>));
      expect(meUser.id, greaterThan(0));

      // 4. servers：至少能拿到列表（测试账号可能为空）
      final servers = await api.get('/api/servers.php');
      expect(servers['servers'], isA<List<dynamic>>());
      expect(servers['group_level'], isNotNull);

      // 5. plans
      final plans = await api.get('/api/plans.php');
      expect(plans.containsKey('membership_enabled'), isTrue);
      expect(plans['groups'], isA<List<dynamic>>());
      expect(plans['pay_methods'], isA<List<dynamic>>());

      // 6. messages
      final msgs = await api.get('/api/messages.php');
      expect(msgs['unread'], isA<num>());
      expect(msgs['messages'], isA<List<dynamic>>());

      // 7. orders
      final orders = await api.get('/api/orders.php', query: {'action': 'list'});
      expect(orders['orders'], isA<List<dynamic>>());

      // 8. 错误路径：未带令牌 / 错误密码
      final anon = ApiClient(baseUrl: localBase);
      await expectLater(
        anon.get('/api/me.php'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      await expectLater(
        ApiClient(baseUrl: localBase).post('/api/login.php', {
          'identity': testUser,
          'password': 'wrong-password',
        }),
        throwsA(isA<ApiException>()),
      );

      // 9. logout
      await api.post('/api/logout.php');
      await expectLater(
        api.get('/api/me.php'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    });
  });
}
