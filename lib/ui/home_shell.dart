import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'connect_page.dart';
import 'membership_page.dart';
import 'messages_page.dart';
import 'settings_page.dart';

/// 主框架：宽屏用侧边导航（PC），窄屏用底部导航（手机）
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  Timer? _unreadTimer;

  @override
  void initState() {
    super.initState();
    unawaited(appState.ensurePlansLoaded());
    _unreadTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (appState.loggedIn) {
        appState.loadUnread();
      }
    });
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 780;
        return ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final unread = appState.unreadCount;
            // 后台关闭会员功能时（非测试人员）整个会员模块不展示
            final nav = <({IconData icon, IconData selected, String label, Widget page})>[
              (icon: Icons.bolt_outlined, selected: Icons.bolt, label: '连接', page: const ConnectPage()),
              if (appState.canBuy)
                (icon: Icons.workspace_premium_outlined, selected: Icons.workspace_premium, label: '会员', page: const MembershipPage()),
              (icon: Icons.notifications_outlined, selected: Icons.notifications, label: '消息', page: const MessagesPage()),
              (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置', page: const SettingsPage()),
            ];
            final index = _index >= nav.length ? nav.length - 1 : _index;

            if (wide) {
              return Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in nav)
                          NavigationRailDestination(
                            icon: _maybeBadge(Icon(d.icon), d.label, unread),
                            selectedIcon: _maybeBadge(Icon(d.selected), d.label, unread),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: IndexedStack(
                        index: index,
                        children: [for (final d in nav) d.page],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Scaffold(
              body: IndexedStack(
                index: index,
                children: [for (final d in nav) d.page],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final d in nav)
                    NavigationDestination(
                      icon: _maybeBadge(Icon(d.icon), d.label, unread),
                      selectedIcon: _maybeBadge(Icon(d.selected), d.label, unread),
                      label: d.label,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _maybeBadge(Widget icon, String label, int unread) {
    if (label != '消息' || unread <= 0) {
      return icon;
    }
    return Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
  }
}
