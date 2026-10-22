import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'core/tray_service.dart';
import 'core/updater.dart';
import 'frpc/auto_connect.dart';
import 'frpc/frpc_manager.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/update_dialogs.dart';

/// 全局导航 key：启动静默检查等场景下没有页面级 context 时使用
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 解析 #RRGGBB 主题色；非法或留空时回退默认蓝
Color _seedColor(String hex) {
  final m = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(hex.trim());
  if (m == null) {
    return const Color(0xFF1565C0);
  }
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

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
      await appState.ensureBootAutostartDefault();
      await frpcManager.refreshInstalledVersion();
      if (appState.autoConnectOnLaunch) {
        await autoConnectFrpc();
      }
      await _silentAppUpdateCheck();
    }).catchError((e, stack) {
      debugPrint('App init failed: $e\n$stack');
      // 即使初始化失败也要标记为已启动，让用户看到登录页而不是无限转圈
      appState.booted = true;
      appState.notifyListeners();
    });
    _reportLastUpdateResult();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await frpcManager.stop();
        return AppExitResponse.exit;
      },
    );
  }

  /// 上次更新若失败（未授权/超时/替换失败），启动后提示原因，避免用户以为“更新完就没反应了”
  Future<void> _reportLastUpdateResult() async {
    final result = await readUpdateResult();
    if (result == null || result.ok) {
      return;
    }
    // 状态文件可能写于安装真正完成之前，或安装日志读早了导致误判；
    // 只要当前版本已经不低于更新目标版本，就说明更新其实成功了，不必报错。
    if (result.version.isNotEmpty &&
        compareVersions(kAppVersion, result.version) >= 0) {
      return;
    }
    // 等首帧渲染完成，此时才有可用的 Navigator context
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) {
        return;
      }
      await showDialog<void>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: const Text('更新未完成'),
          content: SingleChildScrollView(
            child: Text(result.message),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    });
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => TrayService.instance.setTitle(title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final brand = appState.config?.brandName ?? 'AFRP OIDC';
        final seed = _seedColor(appState.config?.themeColor ?? '');
        _syncWindowTitle(brand);
        return MaterialApp(
          title: brand,
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
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
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : appState.loggedIn
              ? const HomeShell()
              : const LoginPage(),
        );
      },
    );
  }
}
