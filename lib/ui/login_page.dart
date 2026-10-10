import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';

/// 登录页：账号密码登录；服务器地址默认使用后台配置（OIDC Issuer 所属站点）
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _identity = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onStateChanged);
    _loadConfig();
  }

  @override
  void dispose() {
    appState.removeListener(_onStateChanged);
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 站点配置（名称 / Logo）加载完成后重绘品牌区
  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadConfig() async {
    try {
      await appState.loadConfig();
    } on ApiException {
      // 登录页静默；点击登录时会给出具体错误
    }
  }

  Future<void> _login() async {
    final identity = _identity.text.trim();
    final password = _password.text;
    if (identity.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入账号与密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await appState.login(identity, password);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brand(theme, appState.config),
                const SizedBox(height: 12),
                Text(
                  '内网穿透 · 登录客户端',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _identity,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '账号 / 邮箱',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_busy ? '登录中…' : '登录'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                if (appState.config != null && (appState.config!.oidcIssuer).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '认证服务：${appState.config!.oidcIssuer}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 品牌区：优先后台设置的图片 Logo → 双色文字 Logo（afrp.net 风格）→ 站点名
  Widget _brand(ThemeData theme, PublicConfig? config) {
    if (config != null && config.hasImageLogo) {
      return Column(
        children: [
          Image.network(
            config.resolvedLogoUrl(appState.baseUrl),
            height: 64,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _textBrand(theme, config),
          ),
          if (config.siteName.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              config.siteName.trim(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ],
      );
    }
    return _textBrand(theme, config);
  }

  /// 文字 Logo：A 段主色 #FF7452 + B 段绿色 #1cc88a（与网站 logo_text 同款字体）
  Widget _textBrand(ThemeData theme, PublicConfig? config) {
    final a = (config?.logoTextA ?? '').trim();
    final b = (config?.logoTextB ?? '').trim();
    if (a.isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: a),
          if (b.isNotEmpty)
            TextSpan(text: b, style: const TextStyle(color: Color(0xFF1CC88A))),
        ]),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: const Color(0xFFFF7452),
          fontFamily: 'Comfortaa',
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return Text(
      config?.brandName ?? 'AFRP OIDC',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
