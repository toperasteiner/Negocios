import 'package:flutter/material.dart';

import 'app_header.dart';
import 'app_footer.dart';
import 'package:pedido_crud/home/alerts_controller.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback? onOpenMenu;
  final List<PopupMenuEntry>? menu;
  final PreferredSizeWidget? headerBottom;
  final Widget? floatingActionButton;

  final bool useModernHeader;
  final String? greetingName;
  final String? subtitle;
  final int notificationCount;
  final VoidCallback? onNotifications;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.currentIndex,
    required this.onTabSelected,
    this.onOpenMenu,
    this.menu,
    this.headerBottom,
    this.floatingActionButton,
    this.useModernHeader = false,
    this.greetingName,
    this.subtitle,
    this.notificationCount = 0,
    this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppHeader(
        title: title,
        onMenuPressed: onOpenMenu,
        menu: menu,
        bottom: headerBottom,
        useModernHeader: useModernHeader,
        greetingName: greetingName,
        subtitle: subtitle,
        notificationCount: notificationCount,
        onNotifications: onNotifications,
      ),
      body: SafeArea(top: !useModernHeader, child: body),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: AlertsController.instance.totalAlerts,
        builder: (_, total, __) {
          return AppFooter(
            currentIndex: currentIndex,
            onTap: onTabSelected,
            atividadesBadgeCount: total,
          );
        },
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
