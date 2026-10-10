import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'secret_store.dart';

/// 全局应用状态：登录态、配置、服务器、套餐、消息、隧道与本地设置。
/// 全部网络请求经由本类，UI 通过 ListenableBuilder 监听刷新。
class AppState extends ChangeNotifier {
  AppState({SecretStore secretStore = const PlatformSecretStore()})
      : _secrets = secretStore;

  static const String defaultBaseUrl = 'https://www.afrp.net';

  final SecretStore _secrets;
  SharedPreferences? _prefs;

  /// 服务器地址（可在设置页修改，默认生产站）
  String baseUrl = defaultBaseUrl;

  late ApiClient api;

  PublicConfig? config;
  UserInfo? user;

  List<ServerInfo> servers = [];
  int? selectedServerId;

  // 会员购买页数据（plans.php）
  bool membershipEnabled = false;
  bool canBuy = false;
  bool isTester = false;
  bool plansLoaded = false;
  List<String> permanentGroups = [];
  List<PlanGroup> groups = [];
  List<PayMethod> payMethods = [];
  OrderInfo? pendingOrder;

  // 消息
  List<MessageItem> messages = [];
  int unreadCount = 0;

  /// 当前用户 OIDC Client Secret（内存缓存；持久化在系统安全存储）
  String? clientSecret;

  bool booted = false;
  bool loggedIn = false;

  static String _secretKey(String username) => 'client_secret_$username';
  static const _kToken = 'api_token';
  static const _kBaseUrl = 'api_base_url';
  static const _kServerId = 'selected_server_id';

  bool get hasLocalSecret => (clientSecret ?? '').isNotEmpty;

  ServerInfo? get selectedServer {
    if (selectedServerId == null) {
      return servers.isEmpty ? null : servers.first;
    }
    for (final s in servers) {
      if (s.id == selectedServerId) {
        return s;
      }
    }
    return servers.isEmpty ? null : servers.first;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs!.getString(_kBaseUrl) ?? defaultBaseUrl;
    final token = await _secrets.read(_kToken);
    api = ApiClient(baseUrl: baseUrl, token: token);
    selectedServerId = _prefs!.getInt(_kServerId);
    loggedIn = (token ?? '').isNotEmpty;
    booted = true;
    notifyListeners();

    if (loggedIn) {
      try {
        await refreshUser();
        await loadServers();
        await loadUnread();
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          await logout(silent: true);
        }
      }
    }
  }

  /* ==================== 登录 / 登出 ==================== */

  /// 登录成功返回 null；失败返回错误消息
  Future<String?> login(String identity, String password, {String device = ''}) async {
    try {
      final data = await api.post('/api/login.php', {
        'identity': identity,
        'password': password,
        'device': device.isEmpty ? _deviceDesc() : device,
      });
      final token = (data['token'] ?? '').toString();
      if (token.isEmpty) {
        return '登录响应异常：未获取到令牌';
      }
      api.token = token;
      await _secrets.write(_kToken, token);
      loggedIn = true;
      await refreshUser();
      await loadServers();
      await loadUnread();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> logout({bool silent = false}) async {
    if (!silent && loggedIn) {
      try {
        await api.post('/api/logout.php');
      } on ApiException {
        // 服务端不可达时也允许本地登出
      }
    }
    await _secrets.delete(_kToken);
    api.token = null;
    user = null;
    servers = [];
    groups = [];
    payMethods = [];
    membershipEnabled = false;
    canBuy = false;
    isTester = false;
    plansLoaded = false;
    permanentGroups = [];
    messages = [];
    unreadCount = 0;
    pendingOrder = null;
    clientSecret = null;
    loggedIn = false;
    notifyListeners();
  }

  static String _deviceDesc() {
    try {
      final os = defaultTargetPlatform.name;
      return 'frp-oidc-app ($os)';
    } catch (_) {
      return 'frp-oidc-app';
    }
  }

  /* ==================== 基础数据 ==================== */

  Future<void> loadConfig() async {
    final data = await api.get('/api/config.php');
    config = PublicConfig.fromJson(data);
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final data = await api.get('/api/me.php');
    final u = data['user'] is Map<String, dynamic>
        ? UserInfo.fromJson(data['user'] as Map<String, dynamic>)
        : UserInfo.fromJson(data);
    user = u;
    clientSecret = await _secrets.read(_secretKey(u.username));
    notifyListeners();
  }

  Future<void> loadServers() async {
    final data = await api.get('/api/servers.php');
    servers = ((data['servers'] as List?) ?? const [])
        .map((e) => ServerInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    if (selectedServerId == null ||
        !servers.any((s) => s.id == selectedServerId)) {
      selectedServerId = servers.isEmpty ? null : servers.first.id;
      if (selectedServerId != null) {
        await _prefs?.setInt(_kServerId, selectedServerId!);
      }
    }
    notifyListeners();
  }

  Future<void> selectServer(int id) async {
    selectedServerId = id;
    await _prefs?.setInt(_kServerId, id);
    notifyListeners();
  }

  Future<void> loadPlans() async {
    final data = await api.get('/api/plans.php');
    membershipEnabled = data['membership_enabled'] == true;
    canBuy = data['can_buy'] == true;
    isTester = data['is_tester'] == true;
    plansLoaded = true;
    permanentGroups = ((data['permanent_groups'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    groups = ((data['groups'] as List?) ?? const [])
        .map((e) => PlanGroup.fromJson(e as Map<String, dynamic>))
        .toList();
    payMethods = ((data['pay_methods'] as List?) ?? const [])
        .map((e) => PayMethod.fromJson(e as Map<String, dynamic>))
        .toList();
    pendingOrder = data['pending_order'] is Map<String, dynamic>
        ? OrderInfo.fromJson(data['pending_order'] as Map<String, dynamic>)
        : null;
    if (data['user'] is Map<String, dynamic>) {
      user = UserInfo.fromJson(data['user'] as Map<String, dynamic>);
    }
    notifyListeners();
  }

  /// 静默预载套餐数据：会员模块开关未确认前不显示入口，失败时保持隐藏
  Future<void> ensurePlansLoaded() async {
    if (plansLoaded || !loggedIn) {
      return;
    }
    try {
      await loadPlans();
    } on ApiException {
      // 忽略：无法确认开关状态时保持会员模块隐藏
    }
  }

  /* ==================== 消息 ==================== */

  Future<void> loadUnread() async {
    try {
      final data = await api.get('/api/messages.php', query: {'unread': '1'});
      unreadCount = (data['unread'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } on ApiException {
      // 未读数失败不打扰用户
    }
  }

  Future<void> loadMessages() async {
    final data = await api.get('/api/messages.php');
    messages = ((data['messages'] as List?) ?? const [])
        .map((e) => MessageItem.fromJson(e as Map<String, dynamic>))
        .toList();
    unreadCount = (data['unread'] as num?)?.toInt() ?? 0;
    notifyListeners();
  }

  Future<void> markMessageRead(int id) async {
    final data = await api.post('/api/messages.php', {'action': 'read', 'id': id});
    unreadCount = (data['unread'] as num?)?.toInt() ?? unreadCount;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.id == id && !m.isRead) {
        messages[i] = MessageItem(
          id: m.id,
          title: m.title,
          content: m.content,
          isRead: true,
          createdAt: m.createdAt,
        );
      }
    }
    notifyListeners();
  }

  Future<void> markAllMessagesRead() async {
    final data = await api.post('/api/messages.php', {'action': 'read_all'});
    unreadCount = (data['unread'] as num?)?.toInt() ?? 0;
    await loadMessages();
  }

  Future<void> deleteMessage(int id) async {
    await api.post('/api/messages.php', {'action': 'delete', 'id': id});
    messages.removeWhere((m) => m.id == id);
    notifyListeners();
    await loadUnread();
  }

  /* ==================== 订单 ==================== */

  Future<OrderInfo> loadOrderStatus({int? orderId, String? orderNo, bool auto = false}) async {
    final data = await api.get('/api/orders.php', query: {
      'action': 'status',
      'no': ?orderNo,
      'id': ?orderId?.toString(),
      if (auto) 'auto': '1',
    });
    final o = OrderInfo.fromJson(data['order'] as Map<String, dynamic>);
    if (data['user'] is Map<String, dynamic>) {
      user = UserInfo.fromJson(data['user'] as Map<String, dynamic>);
    }
    if (o.isPaid) {
      pendingOrder = null;
    }
    notifyListeners();
    return o;
  }

  /// 创建订单并返回 (订单, 支付指引)
  Future<(OrderInfo, PayInstruction)> createOrder(int planId, String payMethod) async {
    final data = await api.post('/api/orders.php', {
      'action': 'create',
      'plan_id': planId,
      'pay_method': payMethod,
    });
    final o = OrderInfo.fromJson(data['order'] as Map<String, dynamic>);
    final pay = data['pay'] is Map<String, dynamic>
        ? PayInstruction.fromJson(data['pay'] as Map<String, dynamic>)
        : PayInstruction(type: 'error', message: '服务端未返回支付参数');
    pendingOrder = o.isPending ? o : null;
    notifyListeners();
    return (o, pay);
  }

  /// 对待支付订单重新发起支付
  Future<(OrderInfo, PayInstruction)> startPay(int orderId) async {
    final data = await api.post('/api/orders.php', {'action': 'pay', 'id': orderId});
    final o = OrderInfo.fromJson(data['order'] as Map<String, dynamic>);
    final pay = data['pay'] is Map<String, dynamic>
        ? PayInstruction.fromJson(data['pay'] as Map<String, dynamic>)
        : PayInstruction(type: 'error', message: '服务端未返回支付参数');
    return (o, pay);
  }

  Future<void> cancelOrder(int orderId) async {
    await api.post('/api/orders.php', {'action': 'cancel', 'id': orderId});
    if (pendingOrder?.id == orderId) {
      pendingOrder = null;
    }
    notifyListeners();
  }

  Future<List<OrderInfo>> loadOrders() async {
    final data = await api.get('/api/orders.php', query: {'action': 'list'});
    return ((data['orders'] as List?) ?? const [])
        .map((e) => OrderInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /* ==================== Client Secret ==================== */

  /// 生成新密钥（旧密钥立即失效）；成功后本地保存并返回明文
  Future<String> rotateSecret() async {
    final data = await api.post('/api/secret.php');
    final secret = (data['client_secret'] ?? '').toString();
    if (secret.isEmpty) {
      throw ApiException('bad_response', '服务端未返回新密钥');
    }
    await saveClientSecret(secret);
    return secret;
  }

  Future<void> saveClientSecret(String secret) async {
    final name = user?.username ?? '';
    if (name.isEmpty) {
      return;
    }
    clientSecret = secret.trim();
    await _secrets.write(_secretKey(name), clientSecret!);
    notifyListeners();
  }

  Future<void> clearClientSecret() async {
    final name = user?.username ?? '';
    clientSecret = null;
    if (name.isNotEmpty) {
      await _secrets.delete(_secretKey(name));
    }
    notifyListeners();
  }

  /* ==================== 隧道（按服务器保存） ==================== */

  static String _tunnelKey(int serverId) => 'tunnels_$serverId';

  List<Tunnel> tunnelsOf(int serverId) {
    final raw = _prefs?.getString(_tunnelKey(serverId));
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Tunnel.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTunnels(int serverId, List<Tunnel> tunnels) async {
    await _prefs?.setString(
      _tunnelKey(serverId),
      jsonEncode(tunnels.map((t) => t.toJson()).toList()),
    );
    notifyListeners();
  }

  /* ==================== 设置 ==================== */

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim();
    await _prefs?.setString(_kBaseUrl, baseUrl);
    api.baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    canBuy = false;
    plansLoaded = false;
    notifyListeners();
  }
}

/// 全局单例
final AppState appState = AppState();
