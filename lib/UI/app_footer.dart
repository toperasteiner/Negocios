// ui/app_footer.dart
import 'package:flutter/material.dart';

class AppFooter extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int atividadesBadgeCount;

  final Key? kTabHome;
  final Key? kTabCadastros;
  final Key? kTabAtividades;
  final Key? kTabDashboards;
  final Key? kTabFinanceiro;

  const AppFooter({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.atividadesBadgeCount = 0,
    this.kTabHome,
    this.kTabCadastros,
    this.kTabAtividades,
    this.kTabDashboards,
    this.kTabFinanceiro,
  });

  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottom > 0 ? bottom : 8),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        elevation: 0,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFBFAFF),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5DFF2), width: 1),
            boxShadow: [
              BoxShadow(
                color: deepPurple.withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _FooterItem(
                key: kTabHome,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Início',
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _FooterItem(
                key: kTabCadastros,
                icon: Icons.badge_outlined,
                selectedIcon: Icons.badge_rounded,
                label: 'Cadastro',
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _FooterItem(
                key: kTabAtividades,
                icon: Icons.task_alt_outlined,
                selectedIcon: Icons.task_alt_rounded,
                label: 'Atividade',
                selected: currentIndex == 2,
                badge: atividadesBadgeCount,
                onTap: () => onTap(2),
              ),
              _FooterItem(
                key: kTabDashboards,
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights_rounded,
                label: 'Dashboard',
                selected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _FooterItem(
                key: kTabFinanceiro,
                icon: Icons.account_balance_wallet_outlined,
                selectedIcon: Icons.account_balance_wallet_rounded,
                label: 'Financeiro',
                selected: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _FooterItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppFooter.purple : AppFooter.textMuted;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: selected ? 54 : 42,
                    height: 30,
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? AppFooter.purple.withOpacity(0.13)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(
                      selected ? selectedIcon : icon,
                      color: color,
                      size: selected ? 24 : 22,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -2,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
