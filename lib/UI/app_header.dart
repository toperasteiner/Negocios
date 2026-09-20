import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onMenuPressed;
  final List<PopupMenuEntry>? menu;
  final PreferredSizeWidget? bottom;

  final bool useModernHeader;
  final String? greetingName;
  final String? subtitle;
  final int notificationCount;
  final VoidCallback? onNotifications;

  const AppHeader({
    super.key,
    required this.title,
    this.onMenuPressed,
    this.menu,
    this.bottom,
    this.useModernHeader = false,
    this.greetingName,
    this.subtitle,
    this.notificationCount = 0,
    this.onNotifications,
  });

  @override
  Size get preferredSize {
    if (useModernHeader) {
      final isCompactHeader =
          greetingName == 'Atividades' ||
          greetingName == 'Cadastros' ||
          greetingName == 'Dashboard' ||
          greetingName == 'Financeiro';

      return Size.fromHeight(
        (isCompactHeader ? 86 : 190) + (bottom?.preferredSize.height ?? 0),
      );
    }

    return Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (useModernHeader) {
      return _ModernHeader(
        name: greetingName ?? title,
        subtitle: subtitle ?? 'Aqui está o resumo do seu negócio.',
        notificationCount: notificationCount,
        onMenuPressed: onMenuPressed,
        onNotifications: onNotifications,
        bottom: bottom,
      );
    }

    return AppBar(
      title: Text(title),
      leading: IconButton(
        tooltip: 'Menu',
        icon: const Icon(Icons.menu),
        onPressed: onMenuPressed,
      ),
      actions: [
        if (menu != null)
          PopupMenuButton(tooltip: 'Mais', itemBuilder: (_) => menu!),
      ],
      bottom: bottom,
    );
  }
}

class _ModernHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final int notificationCount;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onNotifications;
  final PreferredSizeWidget? bottom;

  const _ModernHeader({
    required this.name,
    required this.subtitle,
    required this.notificationCount,
    this.onMenuPressed,
    this.onNotifications,
    this.bottom,
  });

  bool get _isCompactHeader =>
      name == 'Atividades' ||
      name == 'Cadastros' ||
      name == 'Dashboard' ||
      name == 'Financeiro';

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final headerHeight = _isCompactHeader ? 86.0 : 190.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: headerHeight + (bottom?.preferredSize.height ?? 0),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2F148C), Color(0xFF4A18B8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -55,
              top: -35,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: -70,
              bottom: -95,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                _isCompactHeader ? 20 : 24,
                top + (_isCompactHeader ? 4 : 8),
                20,
                0,
              ),
              child:
                  _isCompactHeader
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 42,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _HeaderIconButton(
                                    icon: Icons.menu_rounded,
                                    onTap: onMenuPressed,
                                    compact: true,
                                  ),
                                ),
                                Center(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (bottom != null) ...[const Spacer(), bottom!],
                        ],
                      )
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _HeaderIconButton(
                                icon: Icons.menu_rounded,
                                onTap: onMenuPressed,
                              ),
                              const Spacer(),
                              if (onNotifications != null ||
                                  notificationCount > 0)
                                _NotificationButton(
                                  count: notificationCount,
                                  onTap: onNotifications,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Olá, $name! 👋',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                          if (bottom != null) ...[const Spacer(), bottom!],
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  const _HeaderIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.10),
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        onTap: onTap,
        child: SizedBox(
          width: compact ? 42 : 48,
          height: compact ? 42 : 48,
          child: Icon(icon, color: Colors.white, size: compact ? 28 : 32),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _NotificationButton({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = count > 9 ? '9+' : '$count';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _HeaderIconButton(icon: Icons.notifications_none_rounded, onTap: onTap),
        if (count > 0)
          Positioned(
            right: 2,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5B2E),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
