import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import 'common.dart';

/// 会员页：套餐选购、支付（链接/微信扫码/加密币自动核对）、订单记录
class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  bool _loading = false;
  bool _ordersExpanded = false;
  List<OrderInfo> _orders = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!appState.loggedIn) {
      return;
    }
    setState(() => _loading = true);
    try {
      await appState.loadPlans();
      _orders = await appState.loadOrders();
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会员'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          if (_loading && appState.groups.isEmpty && appState.pendingOrder == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _statusCard(),
              if (!appState.canBuy) ...[
                const SizedBox(height: 12),
                _closedBanner(),
              ],
              if (appState.pendingOrder != null) ...[
                const SizedBox(height: 12),
                _pendingCard(appState.pendingOrder!),
              ],
              if (appState.canBuy) ...[
                const SizedBox(height: 12),
                ..._planCards(),
              ],
              const SizedBox(height: 12),
              _ordersCard(),
            ],
          );
        },
      ),
    );
  }

  /* ==================== 会员状态 ==================== */

  Widget _statusCard() {
    final user = appState.user;
    if (user == null) {
      return const Card(child: ListTile(title: Text('未登录')));
    }
    final theme = Theme.of(context);
    // 仅展示已开通的会员等级（未开通的隐藏）
    final owned = const ['vip', 'svip', 'pro']
        .where((g) => (user.expiries[g] ?? '').isNotEmpty)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(user.username.isEmpty ? '?' : user.username[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username, style: theme.textTheme.titleMedium),
                      Text(
                        user.email.isEmpty ? '未绑定邮箱' : user.email,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                GroupBadge(user.topGroup.isEmpty ? 'free' : user.topGroup),
              ],
            ),
            if (owned.isNotEmpty) ...[
              const Divider(height: 24),
              for (final g in owned)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          g == 'pro' ? 'Pro' : g.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(child: Text(_expiryText(user, g))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 会员到期文案：永久 / yyyy-MM-dd 到期 / yyyy-MM-dd 已过期
  static String _expiryText(UserInfo user, String group) {
    final v = user.expiries[group] ?? '';
    if (v.isEmpty) {
      return '未开通';
    }
    if (v == '9999-12-31 23:59:59') {
      return '永久';
    }
    final date = v.split(' ').first;
    final d = DateTime.tryParse(date);
    if (d == null) {
      return v;
    }
    final now = DateTime.now();
    final expired = d.isBefore(DateTime(now.year, now.month, now.day));
    return expired ? '$date 已过期' : '$date 到期';
  }

  Widget _closedBanner() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 10),
            Expanded(child: Text('开通会员功能暂未开放（测试模式），仅测试人员可开通。')),
          ],
        ),
      ),
    );
  }

  /* ==================== 套餐 ==================== */

  List<Widget> _planCards() {
    if (appState.groups.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '暂无可购买的套餐（可能已是永久会员或套餐已下架）。',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      ];
    }
    return [
      for (final g in appState.groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GroupBadge(g.key),
                      const SizedBox(width: 8),
                      Text(g.name, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  if (g.desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(g.desc, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const Divider(height: 20),
                  for (final p in g.plans)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(p.periodName)),
                          Text(
                            '¥${_fmt(p.price)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                            onPressed: () => _buy(p),
                            child: const Text('购买'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _buy(Plan plan) async {
    if (appState.payMethods.isEmpty) {
      snack(context, '暂无可用支付方式，请联系管理员', error: true);
      return;
    }
    final method = await showDialog<PayMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('选择支付方式 · ${plan.periodName} ¥${_fmt(plan.price)}'),
        children: [
          for (final m in appState.payMethods)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(m.name),
                ],
              ),
            ),
        ],
      ),
    );
    if (method == null || !mounted) {
      return;
    }
    try {
      final (order, pay) = await appState.createOrder(plan.id, method.key);
      if (!mounted) {
        return;
      }
      await _showPaySheet(order, pay);
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    }
  }

  /* ==================== 待支付订单 ==================== */

  Widget _pendingCard(OrderInfo order) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions),
                const SizedBox(width: 8),
                Text('待支付订单', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text('订单号：${order.orderNo}'),
            Text('内容：${order.groupName.toUpperCase()} ${order.period} · ¥${_fmt(order.amount)}'),
            Text('创建时间：${order.createdAt}'),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: () => _continuePay(order),
                  child: const Text('继续支付'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _cancelOrder(order),
                  child: const Text('取消订单'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _continuePay(OrderInfo order) async {
    try {
      final (o, pay) = await appState.startPay(order.id);
      if (!mounted) {
        return;
      }
      await _showPaySheet(o, pay);
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    }
  }

  Future<void> _cancelOrder(OrderInfo order) async {
    final ok = await confirmDialog(context, '取消订单', '确定取消订单 ${order.orderNo} 吗？', okText: '取消订单', dangerous: true);
    if (ok != true) {
      return;
    }
    try {
      await appState.cancelOrder(order.id);
      if (mounted) {
        snack(context, '订单已取消');
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    }
  }

  /* ==================== 支付面板 ==================== */

  Future<void> _showPaySheet(OrderInfo order, PayInstruction pay) async {
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayDialog(order: order, pay: pay),
    );
    if (paid == true && mounted) {
      snack(context, '支付成功，会员已开通');
    }
    if (mounted) {
      await _load();
    }
  }

  /* ==================== 订单记录 ==================== */

  Widget _ordersCard() {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('订单记录'),
            subtitle: Text('最近 ${_orders.length} 笔'),
            trailing: Icon(_ordersExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _ordersExpanded = !_ordersExpanded),
          ),
          if (_ordersExpanded) ...[
            const Divider(height: 1),
            if (_orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无订单'),
              )
            else
              for (final o in _orders)
                ListTile(
                  dense: true,
                  leading: Icon(
                    o.isPaid ? Icons.check_circle_outline : Icons.schedule,
                    color: o.isPaid ? Colors.green : theme.colorScheme.outline,
                  ),
                  title: Text('${o.orderNo}  ${o.groupName.toUpperCase()} ${o.period}'),
                  subtitle: Text('${o.payMethodName} · ${o.createdAt}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('¥${_fmt(o.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(o.statusName, style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                    ],
                  ),
                  onTap: o.isPending
                      ? () async {
                          await _continuePay(o);
                        }
                      : null,
                ),
          ],
        ],
      ),
    );
  }
}

/* ==================== 支付对话框 / 轮询 ==================== */

class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.order, required this.pay});

  final OrderInfo order;
  final PayInstruction pay;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  Timer? _timer;
  bool _checking = false;
  bool _paid = false;
  String _hint = '';
  int _polls = 0;

  bool get _isCrypto => widget.order.payMethod == 'usdt' || widget.order.payMethod == 'usdt_bep20';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    final type = widget.pay.type;
    if (type != 'qr' && type != 'crypto' && type != 'url') {
      return;
    }
    final seconds = widget.pay.pollSeconds ??
        switch (type) {
          'qr' => 3,
          'crypto' => 8,
          _ => 5,
        };
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_checking || _paid || !mounted) {
      return;
    }
    setState(() => _checking = true);
    try {
      final order = await appState.loadOrderStatus(
        orderNo: widget.order.orderNo,
        auto: _isCrypto,
      );
      if (!mounted) {
        return;
      }
      if (order.isPaid) {
        _timer?.cancel();
        setState(() => _paid = true);
      } else {
        _polls++;
        setState(() => _hint = '正在等待支付确认…（已查询 $_polls 次）');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _hint = '查询失败：${e.message}（将自动重试）');
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(context, '取消订单', '取消后需要重新下单，确定吗？', okText: '取消订单', dangerous: true);
    if (ok != true) {
      return;
    }
    try {
      await appState.cancelOrder(widget.order.id);
      if (mounted) {
        Navigator.pop(context, false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        snack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_paid ? '支付成功' : '支付订单 ${widget.order.orderNo}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: _paid ? _successBody() : _payBody(),
        ),
      ),
      actions: _paid
          ? [
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('完成'),
              ),
            ]
          : [
              TextButton(
                onPressed: _cancel,
                child: const Text('取消订单'),
              ),
              TextButton(
                onPressed: _checking ? null : _poll,
                child: const Text('我已支付，立即查询'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后支付'),
              ),
            ],
    );
  }

  Widget _successBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 56),
        const SizedBox(height: 12),
        Text('已到账，会员已开通', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('订单号：${widget.order.orderNo}'),
      ],
    );
  }

  Widget _payBody() {
    final pay = widget.pay;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.order.groupName.toUpperCase()} ${widget.order.period} · ¥${_fmt(widget.order.amount)}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(widget.order.payMethodName, style: theme.textTheme.bodySmall),
          ],
        ),
        const Divider(height: 20),
        switch (pay.type) {
          'url' => _urlBody(pay),
          'qr' => _qrBody(pay),
          'crypto' => _cryptoBody(pay),
          _ => _errorBody(pay),
        },
        if (_hint.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text(_hint, style: theme.textTheme.bodySmall)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _urlBody(PayInstruction pay) {
    final url = pay.url ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('点击下方按钮打开支付页面完成付款，支付完成后本窗口会自动确认。'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开支付页面'),
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri == null) {
                snack(context, '支付链接无效', error: true);
                return;
              }
              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && mounted) {
                snack(context, '无法打开支付页面，请复制链接到浏览器', error: true);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
            IconButton(
              tooltip: '复制链接',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => copyText(context, url, label: '支付链接'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _qrBody(PayInstruction pay) {
    return Column(
      children: [
        Text('请使用${widget.order.payMethodName}扫码支付', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: pay.codeUrl ?? '',
            version: QrVersions.auto,
            size: 220,
          ),
        ),
        const SizedBox(height: 10),
        Text('支付完成后会自动开通（每 ${pay.pollSeconds ?? 3} 秒自动查询）', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _cryptoBody(PayInstruction pay) {
    final c = pay.crypto;
    if (c == null) {
      return _errorBody(pay);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${c.networkName} 转账', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        _cryptoRow('收款地址', c.addr, copyable: true),
        _cryptoRow('转账金额', '${_fmt(c.amount)} USDT', copyable: true),
        _cryptoRow('参考汇率', '1 USDT ≈ ¥${_fmt(c.rate)}'),
        _cryptoRow('应付金额', '¥${_fmt(c.cny)}'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '请务必按「转账金额」精确转账（金额是自动核对到账的唯一依据）。转账后一般 1-3 分钟自动到账开通。',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 8),
        Text('每 ${pay.pollSeconds ?? 8} 秒自动核对链上到账', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _cryptoRow(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 76, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: SelectableText(value, style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace']))),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '复制',
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => copyText(context, value, label: label),
            ),
        ],
      ),
    );
  }

  Widget _errorBody(PayInstruction pay) {
    return Row(
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 10),
        Expanded(child: Text(pay.message ?? '支付发起失败，请更换支付方式重试。')),
      ],
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
