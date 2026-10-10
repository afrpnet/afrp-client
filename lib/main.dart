import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'core/tray_service.dart';
import 'core/updater.dart';
import 'frpc/frpc_manager.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/update_dialogs.dart';

/// 全局导航 key：启动静默检查等场景下没有页面级 context 时使用
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (TrayService.supported) {
    await TrayService.instance.init();
  }
  runApp(const FrpApp());
}

class FrpApp extends StatefulWidget {
  const FrpApp({super.key});

  @override
  State<FrpApp> createState() => _FrpAppState();
}

class _FrpAppState extends State<FrpApp> {
  AppLifecycleListener? _lifecycle;
  String _windowTitle = '';
  bool _updatePrompted = false;

  @override
  void initState() {
    super.initState();
    appState.init().then((_) async {
      await frpcManager.refreshInstalledVersion();
      await _silentAppUpdateCheck();
    });
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await frpcManager.stop();
        return AppExitResponse.exit;
      },
    );
  }

  /// 启动静默检查 App 更新；任何失败都不打扰用户（设置页可手动检查）
  Future<void> _silentAppUpdateCheck() async {
    if (_updatePrompted || !mounted || !appState.booted) {
      return;
    }
    try {
      final check = await checkAppUpdate(appState.baseUrl);
      if (check == null || !check.hasUpdate || !mounted) {
        return;
      }
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) {
        return;
      }
      _updatePrompted = true;
      await showAppUpdateDialog(ctx, baseUrl: appState.baseUrl, check: check);
    } catch (_) {
      // 静默失败：网络不可用或清单缺失时忽略
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// 窗口标题跟随站点名（后台可改）；桌面端经 window_manager 生效
  void _syncWindowTitle(String title) {
    if (title == _windowTitle || !TrayService.supported) {
      return;
    }
    _windowTitle = title;
    WidgetsBinding.instance.addPostFrameCallback((_) => TrayService.instance.setTitle(title));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final brand = appState.config?.brandName ?? 'AFRP OIDC';
        _syncWindowTitle(brand);
        return MaterialApp(
          title: brand,
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
            useMaterial3: true,
          ),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: !appState.booted
              ? const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                )
              : appState.loggedIn
                  ? const HomeShell()
                  : const LoginPage(),
        );
      },
    );
  }
}
