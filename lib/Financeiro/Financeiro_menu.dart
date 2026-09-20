import '../Planos/PlanService.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Atividades/atividades_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Cadastros/cadastros_menu.dart';

import '../Financeiro/ContasReceberHomeScreen.dart';
import '../Financeiro/ContasPagarHomeScreen.dart';
import '../Financeiro/RecorrenciasFinanceirasCrudScreen.dart';
import '../Financeiro/CadastroRecorrenciaFinanceiraScreen.dart';

import '../Planos/PlanosScreen.dart';
import '../Home/home_screen.dart';

class FinanceiroColors {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color teal = Color(0xFF00A896);
  static const Color redOrange = Color(0xFFE85A12);
  static const Color background = Color(0xFFF7F7FA);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
}

class FinanceiroMenuScreen extends StatefulWidget {
  const FinanceiroMenuScreen({super.key});

  @override
  State<FinanceiroMenuScreen> createState() => _FinanceiroMenuScreenState();
}

class _FinanceiroMenuScreenState extends State<FinanceiroMenuScreen> {
  bool _loadingPerms = true;

  bool _canCR = false;
  bool _canCP = false;
  bool _canCashFlow = false;

  bool _isAdmin = false;
  String? _companyId;

  String _currentPlan = 'free';

  bool get _isPremium => _currentPlan == 'premium';

  bool get _canUseRecorrencias =>
      _currentPlan == 'premium' || _currentPlan == 'starter';

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    setState(() {
      _currentPlan = service.isLoaded ? service.planId : 'free';
    });
  }

  Future<void> _loadPlanState() async {
    if (!mounted) return;
    try {
      if (!PlanService.instance.isLoaded) await PlanService.instance.load();
      _onPlanChanged();
    } catch (e) {
      debugPrint('Plan refresh failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlanState());
    _loadPerms();
  }

  Future<void> _loadPerms() async {
    setState(() => _loadingPerms = true);

    try {
      final auth = FirebaseAuth.instance;
      final fs = FirebaseFirestore.instance;
      final u = auth.currentUser;

      if (u == null) {
        setState(() => _loadingPerms = false);
        return;
      }

      Map<String, dynamic>? me;

      try {
        final byUid = await fs.collection('users').doc(u.uid).get();
        if (byUid.exists) me = byUid.data();
      } catch (_) {}

      if (me == null) {
        final emailKey = (u.email ?? '').trim().toLowerCase();

        if (emailKey.isNotEmpty) {
          final q =
              await fs
                  .collection('users')
                  .where('emailKey', isEqualTo: emailKey)
                  .limit(1)
                  .get();

          if (q.docs.isNotEmpty) {
            me = q.docs.first.data();
          }
        }
      }

      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;

      final role = (me?['role'] ?? 'funcionario').toString().toLowerCase();
      final companyId = (me?['companyId'] ?? '').toString().trim();

      final rawPlan =
          (me?['planId'] ??
                  me?['plan'] ??
                  me?['planKey'] ??
                  me?['currentPlan'] ??
                  me?['plano'] ??
                  'free')
              .toString()
              .toLowerCase()
              .trim();

      final plan =
          rawPlan == 'premium'
              ? 'premium'
              : rawPlan == 'starter'
              ? 'starter'
              : 'free';

      if (!mounted) return;

      setState(() {
        _canCR = (perms['canAccountsReceivable'] ?? false) == true;
        _canCP = (perms['canAccountsPayable'] ?? false) == true;
        _canCashFlow = (perms['canDashboardCashFlow'] ?? false) == true;
        _isAdmin = role == 'admin';
        _companyId = companyId.isEmpty ? null : companyId;
        _currentPlan =
            PlanService.instance.isLoaded ? PlanService.instance.planId : plan;
        _loadingPerms = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingPerms = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar permissões: $e')),
      );
    }
  }

  void _openIfAllowed({
    required bool allowed,
    required String denyMsg,
    required BuildContext ctx,
    required Widget page,
  }) {
    if (_loadingPerms) return;

    if (!allowed) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(denyMsg)));
      return;
    }

    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openPlansScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
  }

  void _showRecorrenciaPlanDialog() {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Recorrências disponíveis no Starter e Premium'),
            content: const Text(
              'O cadastro de pagamentos e recebimentos recorrentes está disponível apenas nos planos Starter e Premium.\n\n'
              'Faça upgrade para automatizar suas contas mensais.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openPlansScreen();
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  void _openRecorrenciaIfAllowed({
    required bool allowedByPermission,
    required String denyMsg,
    required BuildContext ctx,
    required Widget page,
  }) {
    if (_loadingPerms) return;

    if (!allowedByPermission) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(denyMsg)));
      return;
    }

    if (!_canUseRecorrencias) {
      _showRecorrenciaPlanDialog();
      return;
    }

    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => page));
  }

  List<_FinanceItem> _items(BuildContext context) {
    return [
      _FinanceItem(
        title: 'Contas a Receber',
        subtitle:
            _canCR
                ? 'Faturas, boletos e recebimentos.'
                : 'Sem permissão de acesso.',
        icon:
            _canCR ? Icons.request_quote_outlined : Icons.lock_outline_rounded,
        color: FinanceiroColors.green,
        locked: !_canCR,
        onTap:
            () => _openIfAllowed(
              allowed: _canCR,
              denyMsg: 'Você não tem permissão para acessar Contas a Receber.',
              ctx: context,
              page: const ContasReceberHomeScreen(),
            ),
        onLongPress:
            _canCR
                ? () {
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Atalho: novo recebimento')),
                  );
                }
                : null,
      ),
      _FinanceItem(
        title: 'Contas a Pagar',
        subtitle: _canCP ? 'Despesas, vencimentos e saídas.' : 'Sem permissão.',
        icon: _canCP ? Icons.receipt_long_outlined : Icons.lock_outline_rounded,
        color: FinanceiroColors.orange,
        locked: !_canCP,
        onTap:
            () => _openIfAllowed(
              allowed: _canCP,
              denyMsg: 'Você não tem permissão para acessar Contas a Pagar.',
              ctx: context,
              page: const ContasPagarHomeScreen(),
            ),
        onLongPress:
            _canCP
                ? () {
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Atalho: novo pagamento')),
                  );
                }
                : null,
      ),
      _FinanceItem(
        title: 'Recebimentos Recorrentes',
        subtitle:
            !_canCR
                ? 'Sem permissão de acesso.'
                : !_canUseRecorrencias
                ? 'Disponível no Starter e Premium.'
                : 'Receitas fixas automáticas.',
        helperText:
            'Use para mensalidades, contratos e cobranças que se repetem.',
        icon:
            (!_canCR || !_canUseRecorrencias)
                ? Icons.lock_outline_rounded
                : Icons.repeat_outlined,
        color: FinanceiroColors.blue,
        locked: !_canCR || !_canUseRecorrencias,
        badge: !_canUseRecorrencias ? 'Plano' : null,
        onTap:
            () => _openRecorrenciaIfAllowed(
              allowedByPermission: _canCR,
              denyMsg:
                  'Você não tem permissão para cadastrar recebimentos recorrentes.',
              ctx: context,
              page: const RecorrenciasFinanceirasCrudScreen(
                tipo: TipoRecorrenciaFinanceira.receber,
              ),
            ),
      ),
      _FinanceItem(
        title: 'Pagamentos Recorrentes',
        subtitle:
            !_canCP
                ? 'Sem permissão de acesso.'
                : !_canUseRecorrencias
                ? 'Disponível no Starter e Premium.'
                : 'Despesas fixas automáticas.',
        helperText: 'Use para aluguel, internet, energia e contas mensais.',
        icon:
            (!_canCP || !_canUseRecorrencias)
                ? Icons.lock_outline_rounded
                : Icons.event_repeat_outlined,
        color: FinanceiroColors.purple,
        locked: !_canCP || !_canUseRecorrencias,
        badge: !_canUseRecorrencias ? 'Plano' : null,
        onTap:
            () => _openRecorrenciaIfAllowed(
              allowedByPermission: _canCP,
              denyMsg:
                  'Você não tem permissão para cadastrar pagamentos recorrentes.',
              ctx: context,
              page: const RecorrenciasFinanceirasCrudScreen(
                tipo: TipoRecorrenciaFinanceira.pagar,
              ),
            ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Financeiro',
      useModernHeader: true,
      greetingName: 'Financeiro',
      subtitle: 'Controle contas, recebimentos e recorrências.',
      onOpenMenu:
          () => AppMenuSheet.show(
            context,
            isAdmin: _isAdmin,
            isPremium: _isPremium,
            companyId: _companyId,
          ),
      currentIndex: 4,
      onTabSelected: (i) {
        if (i == 0) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
          return;
        }

        if (i == 1) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CadastrosMenuScreen()),
          );
          return;
        }

        if (i == 2) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AtividadesMenuScreen()),
          );
          return;
        }

        if (i == 3) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardsMenuScreen()),
          );
          return;
        }

        if (i == 4) {
          // Já está no Financeiro.
          return;
        }
      },
      body: Container(
        color: FinanceiroColors.background,
        child: RefreshIndicator(
          onRefresh: _loadPerms,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_loadingPerms)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  sliver: SliverToBoxAdapter(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        final cols = isWide ? 3 : 2;
                        final items = _items(context);

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: isWide ? 156 : 178,
                              ),
                          itemBuilder: (_, i) {
                            return FinanceActionCard(item: items[i]);
                          },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }
}

class _FinanceItem {
  final String title;
  final String subtitle;
  final String? helperText;
  final IconData icon;
  final Color color;
  final bool locked;
  final String? badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FinanceItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.helperText,
    this.locked = false,
    this.badge,
    this.onLongPress,
  });
}

class FinanceActionCard extends StatefulWidget {
  final _FinanceItem item;

  const FinanceActionCard({super.key, required this.item});

  @override
  State<FinanceActionCard> createState() => _FinanceActionCardState();
}

class _FinanceActionCardState extends State<FinanceActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final effectiveColor = item.locked ? const Color(0xFF8A8791) : item.color;

    return Semantics(
      button: true,
      label: item.title,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () {
                setState(() => _pressed = false);
                HapticFeedback.lightImpact();
                item.onTap();
              },
              onLongPress: item.onLongPress,
              child: Opacity(
                opacity: item.locked ? 0.62 : 1,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color:
                          item.locked
                              ? const Color(0xFFE2DFEA)
                              : effectiveColor.withOpacity(0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.045),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: effectiveColor.withOpacity(0.13),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  item.locked
                                      ? Icons.lock_outline_rounded
                                      : item.icon,
                                  color: effectiveColor,
                                  size: 27,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: effectiveColor.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  item.locked
                                      ? Icons.lock_outline_rounded
                                      : Icons.arrow_forward_rounded,
                                  color: effectiveColor,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: FinanceiroColors.textDark,
                              fontSize: 15,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: FinanceiroColors.textMuted,
                              fontSize: 12,
                              height: 1.18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.helperText != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              item.helperText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: FinanceiroColors.textMuted,
                                fontSize: 10.5,
                                height: 1.15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.badge != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _SmallBadge(
                            text: item.badge!,
                            color: effectiveColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _SmallBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
