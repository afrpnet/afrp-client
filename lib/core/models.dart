// 与服务端 web/api/*.php 响应一一对应的数据模型（字段名保持 snake_case 原始 key）

class PublicConfig {
  PublicConfig({
    required this.siteName,
    required this.oidcIssuer,
    required this.oidcAudience,
    required this.oidcScope,
    required this.tokenEndpoint,
    required this.membershipEnabled,
    required this.apiVersion,
    this.logoType = 'text',
    this.logoUrl = '',
    this.logoTextA = '',
    this.logoTextB = '',
  });

  factory PublicConfig.fromJson(Map<String, dynamic> j) => PublicConfig(
        siteName: (j['site_name'] ?? '').toString(),
        oidcIssuer: (j['oidc_issuer'] ?? '').toString(),
        oidcAudience: (j['oidc_audience'] ?? '').toString(),
        oidcScope: (j['oidc_scope'] ?? '').toString(),
        tokenEndpoint: (j['token_endpoint'] ?? '').toString(),
        membershipEnabled: j['membership_enabled'] == true,
        apiVersion: (j['api_version'] as num?)?.toInt() ?? 1,
        logoType: (j['logo_type'] ?? '').toString() == 'image' ? 'image' : 'text',
        logoUrl: (j['logo_url'] ?? '').toString(),
        logoTextA: (j['logo_text_a'] ?? '').toString(),
        logoTextB: (j['logo_text_b'] ?? '').toString(),
      );

  final String siteName;
  final String oidcIssuer;
  final String oidcAudience;
  final String oidcScope;
  final String tokenEndpoint;
  final bool membershipEnabled;
  final int apiVersion;

  /// 后台「站点设置」的 Logo 模式：text（文字，A/B 双色）| image（图片）
  final String logoType;
  final String logoUrl;
  final String logoTextA;
  final String logoTextB;

  /// App 内展示名称：站点名优先，未设置时用默认名
  String get brandName => siteName.trim().isEmpty ? 'AFRP OIDC' : siteName.trim();

  bool get hasImageLogo => logoType == 'image' && logoUrl.trim().isNotEmpty;

  /// logo_url 可能是相对路径（如 /assets/logo.png），按服务器地址解析为绝对 URL
  String resolvedLogoUrl(String baseUrl) {
    final url = logoUrl.trim();
    if (url.isEmpty) {
      return '';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }
}

class UserInfo {
  UserInfo({
    required this.id,
    required this.username,
    required this.email,
    required this.emailVerified,
    required this.role,
    required this.isActive,
    required this.authEnabled,
    required this.secretSet,
    required this.groups,
    required this.groupLevel,
    required this.topGroup,
    required this.expiries,
    required this.memberLabel,
  });

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: (j['username'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        emailVerified: j['email_verified'] == true,
        role: (j['role'] ?? 'user').toString(),
        isActive: j['is_active'] != false,
        authEnabled: j['auth_enabled'] != false,
        secretSet: j['secret_set'] == true,
        groups: ((j['groups'] as List?) ?? const []).map((e) => e.toString()).toList(),
        groupLevel: (j['group_level'] as num?)?.toInt() ?? 0,
        topGroup: (j['top_group'] ?? '').toString(),
        expiries: ((j['expiries'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v?.toString())),
        memberLabel: (j['member_label'] ?? '').toString(),
      );

  final int id;
  final String username;
  final String email;
  final bool emailVerified;
  final String role;
  final bool isActive;
  final bool authEnabled;
  final bool secretSet;
  final List<String> groups;
  final int groupLevel;
  final String topGroup;

  /// vip/svip/pro => 到期时间串；null=未开通，'9999-12-31 23:59:59'=永久
  final Map<String, String?> expiries;
  final String memberLabel;

  bool get isAdmin => role == 'admin';

  String groupExpiryLabel(String group) {
    final v = expiries[group];
    if (v == null) {
      return '未开通';
    }
    if (v == '9999-12-31 23:59:59') {
      return '永久';
    }
    return v;
  }
}

class ServerInfo {
  ServerInfo({
    required this.id,
    required this.name,
    required this.addr,
    required this.port,
    required this.location,
    required this.group,
    required this.visibility,
    required this.subdomain,
    required this.authMethod,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        addr: (j['addr'] ?? '').toString(),
        port: (j['port'] as num?)?.toInt() ?? 7000,
        location: (j['location'] ?? '').toString(),
        group: (j['group'] ?? 'free').toString(),
        visibility: (j['visibility'] as num?)?.toInt() ?? 1,
        subdomain: (j['subdomain'] ?? '').toString(),
        authMethod: (j['auth_method'] ?? 'oidc').toString(),
      );

  final int id;
  final String name;
  final String addr;
  final int port;
  final String location;
  final String group;
  final int visibility;

  /// 服务器可用子域名前缀（为空则需自备 customDomain）
  final String subdomain;
  final String authMethod;

  String get endpoint => '$addr:$port';
}

class Plan {
  Plan({
    required this.id,
    required this.groupName,
    required this.period,
    required this.periodName,
    required this.price,
  });

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: (j['id'] as num?)?.toInt() ?? 0,
        groupName: (j['group_name'] ?? '').toString(),
        period: (j['period'] ?? '').toString(),
        periodName: (j['period_name'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
      );

  final int id;
  final String groupName;
  final String period;
  final String periodName;
  final double price;
}

class PlanGroup {
  PlanGroup({
    required this.key,
    required this.name,
    required this.desc,
    required this.plans,
  });

  factory PlanGroup.fromJson(Map<String, dynamic> j) => PlanGroup(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        desc: (j['desc'] ?? '').toString(),
        plans: ((j['plans'] as List?) ?? const [])
            .map((e) => Plan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String key;
  final String name;
  final String desc;
  final List<Plan> plans;
}

class PayMethod {
  PayMethod({required this.key, required this.name});

  factory PayMethod.fromJson(Map<String, dynamic> j) => PayMethod(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
      );

  final String key;
  final String name;
}

class CryptoInfo {
  CryptoInfo({
    required this.network,
    required this.addr,
    required this.amount,
    required this.rate,
    required this.cny,
  });

  factory CryptoInfo.fromJson(Map<String, dynamic> j) => CryptoInfo(
        network: (j['network'] ?? '').toString(),
        addr: (j['addr'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        rate: (j['rate'] as num?)?.toDouble() ?? 0,
        cny: (j['cny'] as num?)?.toDouble() ?? 0,
      );

  final String network; // usdt | usdt_bep20
  final String addr;
  final double amount;
  final double rate;
  final double cny;

  String get networkName => network == 'usdt_bep20' ? 'USDT (BEP20)' : 'USDT (TRC20)';
}

class OrderInfo {
  OrderInfo({
    required this.id,
    required this.orderNo,
    required this.planId,
    required this.groupName,
    required this.period,
    required this.amount,
    required this.payMethod,
    required this.payMethodName,
    required this.status,
    required this.createdAt,
    required this.paidAt,
    this.crypto,
  });

  factory OrderInfo.fromJson(Map<String, dynamic> j) => OrderInfo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        orderNo: (j['order_no'] ?? '').toString(),
        planId: (j['plan_id'] as num?)?.toInt() ?? 0,
        groupName: (j['group_name'] ?? '').toString(),
        period: (j['period'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        payMethod: (j['pay_method'] ?? '').toString(),
        payMethodName: (j['pay_method_name'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        paidAt: j['paid_at']?.toString(),
        crypto: j['crypto'] is Map<String, dynamic>
            ? CryptoInfo.fromJson(j['crypto'] as Map<String, dynamic>)
            : null,
      );

  final int id;
  final String orderNo;
  final int planId;
  final String groupName;
  final String period;
  final double amount;
  final String payMethod;
  final String payMethodName;
  final String status; // pending | paid | cancelled | ...
  final String createdAt;
  final String? paidAt;
  final CryptoInfo? crypto;

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';

  String get statusName => switch (status) {
        'pending' => '待支付',
        'paid' => '已支付',
        'cancelled' => '已取消',
        'expired' => '已过期',
        _ => status,
      };
}

/// 下单/发起支付返回的支付指引（orders.php 的 pay 字段）
class PayInstruction {
  PayInstruction({
    required this.type,
    this.url,
    this.codeUrl,
    this.pollSeconds,
    this.message,
    this.crypto,
  });

  factory PayInstruction.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] ?? '').toString();
    return PayInstruction(
      type: type,
      url: j['url']?.toString(),
      codeUrl: j['code_url']?.toString(),
      pollSeconds: (j['poll_seconds'] as num?)?.toInt(),
      message: j['message']?.toString(),
      crypto: type == 'crypto' && j['addr'] != null
          ? CryptoInfo.fromJson(j)
          : null,
    );
  }

  final String type; // url | qr | crypto | error
  final String? url;
  final String? codeUrl;
  final int? pollSeconds;
  final String? message;
  final CryptoInfo? crypto;
}

class MessageItem {
  MessageItem({
    required this.id,
    required this.title,
    required this.content,
    required this.isRead,
    required this.createdAt,
  });

  factory MessageItem.fromJson(Map<String, dynamic> j) => MessageItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        isRead: j['is_read'] == true,
        createdAt: (j['created_at'] ?? '').toString(),
      );

  final int id;
  final String title;
  final String content;
  final bool isRead;
  final String createdAt;
}

/// 用户自建隧道（对应 frpc.toml 的 [[proxies]]）
class Tunnel {
  Tunnel({
    required this.name,
    required this.type,
    this.localIp = '127.0.0.1',
    required this.localPort,
    this.remotePort,
    this.subdomain = '',
    this.customDomain = '',
    this.secretKey = '',
  });

  factory Tunnel.fromJson(Map<String, dynamic> j) => Tunnel(
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? 'tcp').toString(),
        localIp: (j['localIp'] ?? '127.0.0.1').toString(),
        localPort: (j['localPort'] as num?)?.toInt() ?? 0,
        remotePort: (j['remotePort'] as num?)?.toInt(),
        subdomain: (j['subdomain'] ?? '').toString(),
        customDomain: (j['customDomain'] ?? '').toString(),
        secretKey: (j['secretKey'] ?? '').toString(),
      );

  String name;
  String type; // tcp | udp | http | https | stcp | sudp | xtcp
  String localIp;
  int localPort;
  int? remotePort;
  String subdomain;
  String customDomain;

  /// stcp / sudp / xtcp（P2P 类）的访问密钥，访问方需一致
  String secretKey;

  bool get isWeb => type == 'http' || type == 'https';

  /// 点对点类型：不占服务器端口，由访问方（visitor）用密钥连接
  bool get isP2P => type == 'stcp' || type == 'sudp' || type == 'xtcp';

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'localIp': localIp,
        'localPort': localPort,
        'remotePort': remotePort,
        'subdomain': subdomain,
        'customDomain': customDomain,
        'secretKey': secretKey,
      };

  /// 列表摘要；server 用于补全子域名的完整前缀（可传 null）
  String summaryFor(ServerInfo? server) {
    final local = '本地 $localIp:$localPort';
    if (isWeb) {
      if (customDomain.trim().isNotEmpty) {
        return '$type  $local → ${customDomain.trim()}';
      }
      if (subdomain.trim().isNotEmpty) {
        final prefix = (server == null || server.subdomain.isEmpty)
            ? subdomain.trim()
            : '${server.subdomain}-${subdomain.trim()}';
        return '$type  $local → 子域名 $prefix';
      }
      return '$type  $local → （未设域名）';
    }
    if (isP2P) {
      return '$type  $local → 访问密钥${secretKey.isEmpty ? '未设置' : '已设置'}';
    }
    return '$type  $local → 远程 :${remotePort ?? 0}';
  }
}
