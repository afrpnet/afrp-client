import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../frpc/frpc_manager.dart';

/// 桌面端（Windows/Linux/macOS）系统托盘与后台运行。
///
/// 关闭/最小化窗口时隐藏到托盘，frpc 隧道继续在后台运行；
/// 托盘菜单可恢复主界面或彻底退出。移动端 [supported] 为 false，不会初始化。
class TrayService with TrayListener, WindowListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static const _kCloseToTray = 'desktop_close_to_tray';
  static const _kMinimizeToTray = 'desktop_minimize_to_tray';

  bool _inited = false;
  bool _quitting = false;
  bool _closeToTray = true;
  bool _minimizeToTray = false;
  String _title = 'AFRP OIDC Client';

  bool get closeToTray => _closeToTray;
  bool get minimizeToTray => _minimizeToTray;

  /// 初始化窗口拦截与托盘菜单。需在 runApp 之前调用。
  Future<void> init() async {
    if (_inited || !supported) {
      return;
    }
    _inited = true;
    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    _closeToTray = prefs.getBool(_kCloseToTray) ?? true;
    _minimizeToTray = prefs.getBool(_kMinimizeToTray) ?? false;
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await _initTray();
  }

  Future<void> _initTray() async {
    try {
      // Windows 用 .ico；Linux/macOS 用 .png（插件会按平台解析资源路径）
      final icon = Platform.isWindows
          ? 'assets/brand/tray_icon.ico'
          : 'assets/brand/tray_icon.png';
      await trayManager.setIcon(icon, iconSize: 20);
      await trayManager.setToolTip(_title);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '显示主界面'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出'),
          ],
        ),
      );
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('托盘初始化失败（忽略）：$e');
    }
  }

  /// 窗口标题跟随站点名（后台可改）
  Future<void> setTitle(String title) async {
    if (title == _title) {
      return;
    }
    _title = title;
    try {
      await windowManager.setTitle(title);
      await trayManager.setToolTip(title);
    } catch (_) {
      // 窗口/托盘尚未就绪时静默忽略
    }
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCloseToTray, value);
  }

  Future<void> setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMinimizeToTray, value);
  }

  /// 从托盘恢复并聚焦主窗口
  Future<void> showWindow() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      } else if (!await windowManager.isVisible()) {
        await windowManager.show();
      }
      await windowManager.focus();
    } catch (e) {
      debugPrint('恢复窗口失败：$e');
    }
  }

  /// 隐藏到托盘（frpc 继续运行）
  Future<void> hideToTray() async {
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('隐藏窗口失败：$e');
    }
  }

  /// 彻底退出：先停 frpc，再销毁托盘与窗口
  Future<void> quit() async {
    if (_quitting) {
      return;
    }
    _quitting = true;
    try {
      await frpcManager.stop();
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.destroy();
  }

  // ---- TrayListener

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'quit':
        quit();
    }
  }

  // ---- WindowListener

  @override
  void onWindowClose() {
    if (_quitting) {
      return;
    }
    if (_closeToTray) {
      hideToTray();
    } else {
      quit();
    }
  }

  @override
  void onWindowMinimize() {
    if (_minimizeToTray) {
      hideToTray();
    }
  }
}
