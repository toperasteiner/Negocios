import '../Planos/PlanService.dart';
// lib/Dashboards/dashboards_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Cadastros/cadastros_menu.dart';
import '../Atividades/atividades_menu.dart';
import '../Financeiro/Financeiro_menu.dart';

import 'ContasReceberDashboardScreen.dart';
import 'ContasPagarDashboardScreen.dart';
import 'PedidosDashboardScreen.dart';
import 'TopProdutosDashboardScreen.dart';
import 'FinanceiroDashboardScreen.dart';
import 'TopServicosDashboardScreen.dart';
import 'DashboardResultadosFinanceirosScreen.dart';
import 'DashboardFluxoCaixaScreen.dart';
import 'MetasDashboardScreen.dart';
import 'DashboardVisaoGeralEstoqueScreen.dart';
import 'DashboardGiroEstoqueScreen.dart';
import 'DashboardCurvaABCEstoqueScreen.dart';
import '../Home/home_screen.dart';
import '../Agenda/Dashboard/agenda_dashboard_screen.dart';

class DashboardColors {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color yellow = Color(0xFFFFB51F);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color teal = Color(0xFF00A896);
  static const Color pink = Color(0xFFD96AD8);
  static const Color redOrange = Color(0xFFE85A12);
  static const Color background = Color(0xFFF7F7FA);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
}

class DashboardsMenuScreen extends StatefulWidget {
  const DashboardsMenuScreen({super.key});

  @override
  State<DashboardsMenuScreen> createState() => _DashboardsMenuScreenState();
}

class _DashboardsMenuScreenState extends State<DashboardsMenuScreen> {
  String _activeFilter = 'Todos';

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _perms = const {};
  bool _isAdmin = false;
  String _currentPlan = 'free';
  String? _companyId;

  bool get _canCR => _perms['canDashboardReceivables'] == true;
  bool get _canCP => _perms['canDashboardPayables'] == true;
  bool get _canOrdersByPeriod => _perms['canDashboardOrdersByPeriod'] == true;
  bool get _canTopProducts => _perms['canDashboardTopProducts'] == true;
  bool get _canTopServices => _perms['canDashboardTopServices'] == true;
  bool get _canFinance => _perms['canDashboardFinance'] == true;
  bool get _canCashFlow => _perms['canDashboardCashFlow'] == true;
  bool get _isPremium => _currentPlan == 'premium';

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
    _loadPermissions();
  }

  String _normalizePlan(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'premium') return 'premium';
    if (value == 'starter') return 'starter';
    return 'free';
  }

  String _extractPlanFromMap(Map<String, dynamic>? data) {
    if (data == null) return 'free';

    final directPlan =
        data['plan'] ??
        data['planId'] ??
        data['planKey'] ??
        data['currentPlan'];

    if (directPlan != null) {
      return _normalizePlan(directPlan);
    }

    final subscription = data['subscription'];
    if (subscription is Map<String, dynamic>) {
      final nestedPlan =
          subscription['plan'] ??
          subscription['planId'] ??
          subscription['planKey'] ??
          subscription['currentPlan'];

      if (nestedPlan != null) {
        return _normalizePlan(nestedPlan);
      }
    }

    return 'free';
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Usuário não autenticado.';

      final fs = FirebaseFirestore.instance;

      DocumentSnapshot<Map<String, dynamic>>? snap;
      Map<String, dynamic>? userData;

      try {
        final byUid = await fs.collection('users').doc(user.uid).get();
        if (byUid.exists) {
          snap = byUid;
          userData = byUid.data();
        }
      } catch (_) {}

      if (snap == null) {
        final emailKey = (user.email ?? '').trim().toLowerCase();

        if (emailKey.isEmpty) {
          throw 'E-mail do usuário não encontrado.';
        }

        final q =
            await fs
                .collection('users')
                .where('emailKey', isEqualTo: emailKey)
                .limit(1)
                .get();

        if (q.docs.isEmpty) {
          throw 'Registro do usuário não encontrado em "users".';
        }

        snap = q.docs.first;
        userData = q.docs.first.data();
      }

      final data = userData ?? {};
      final role = (data['role'] ?? 'funcionario').toString().toLowerCase();
      final isAdmin = role == 'admin';
      final perms = (data['permissions'] ?? {}) as Map<String, dynamic>;

      final companyId = (data['companyId'] ?? '').toString().trim();
      final userPlan = _extractPlanFromMap(data);
      final plan = userPlan;

      if (!mounted) return;

      setState(() {
        _perms = perms;
        _isAdmin = isAdmin;
        _currentPlan =
            PlanService.instance.isLoaded ? PlanService.instance.planId : plan;
        _companyId = companyId.isEmpty ? null : companyId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateIfAllowed(BuildContext context, bool allowed, WidgetBuilder b) {
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você não tem permissão para acessar este dashboard. Solicite permissão ao administrador.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: b));
  }

  void _onTabSelected(int i) {
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
      // Já está na tela de Dashboards.
      return;
    }

    if (i == 4) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FinanceiroMenuScreen()),
      );
    }
  }

  List<_DashboardItem> _items() {
    return [
      _DashboardItem(
        id: 'contas_receber',
        title: 'Contas a Receber',
        subtitle: 'A receber, pagos e atrasos.',
        icon: Icons.request_quote_outlined,
        category: 'Financeiro',
        allowed: _canCR,
        builder: (_) => const ContasReceberDashboardScreen(),
        color: DashboardColors.green,
      ),
      _DashboardItem(
        id: 'contas_pagar',
        title: 'Contas a Pagar',
        subtitle: 'Obrigações e vencidos.',
        icon: Icons.receipt_long_outlined,
        category: 'Financeiro',
        allowed: _canCP,
        builder: (_) => const ContasPagarDashboardScreen(),
        color: DashboardColors.orange,
      ),
      _DashboardItem(
        id: 'pedidos',
        title: 'Pedidos por Período',
        subtitle: 'Evolução de pedidos.',
        icon: Icons.stacked_line_chart,
        category: 'Operação',
        allowed: _canOrdersByPeriod,
        builder: (_) => const PedidosDashboardScreen(),
        color: DashboardColors.blue,
      ),
      _DashboardItem(
        id: 'metas',
        title: 'Metas',
        subtitle: 'Acompanhe metas e progresso.',
        icon: Icons.flag_outlined,
        category: 'Vendas',
        allowed: true,
        builder: (_) => const DashboardMetasProdutosScreen(),
        color: DashboardColors.purple,
      ),
      _DashboardItem(
        id: 'top_produtos',
        title: 'TOP Produtos',
        subtitle: 'Itens mais vendidos.',
        icon: Icons.star_outline,
        category: 'Vendas',
        allowed: _canTopProducts,
        builder: (_) => const TopProdutosDashboardScreen(),
        color: DashboardColors.pink,
      ),
      _DashboardItem(
        id: 'top_servicos',
        title: 'TOP Serviços',
        subtitle: 'Serviços mais vendidos.',
        icon: Icons.handyman_outlined,
        category: 'Vendas',
        allowed: _canTopServices,
        builder: (_) => const TopServicosDashboardScreen(),
        color: DashboardColors.teal,
      ),

      _DashboardItem(
        id: 'financeiro',
        title: 'Financeiro',
        subtitle: 'Visão geral de caixa.',
        icon: Icons.account_balance_wallet_outlined,
        category: 'Financeiro',
        allowed: _canFinance,
        builder: (_) => const FinanceiroDashboardScreen(),
        color: DashboardColors.purple,
      ),
      _DashboardItem(
        id: 'fluxo_caixa',
        title: 'Fluxo de Caixa',
        subtitle: 'Entradas, saídas e saldo.',
        icon: Icons.bar_chart_outlined,
        category: 'Financeiro',
        allowed: _canCashFlow,
        builder: (_) => const DashboardFluxoCaixaScreen(),
        color: DashboardColors.blue,
      ),
      _DashboardItem(
        id: 'custo_lucro',
        title: 'Custo/Lucro',
        subtitle: 'Custos e lucros.',
        icon: Icons.trending_up_outlined,
        category: 'Financeiro',
        allowed: _canCashFlow,
        builder: (_) => const DashboardResultadosFinanceirosScreen(),
        color: DashboardColors.green,
      ),
      _DashboardItem(
        id: 'estoque_visao_geral',
        title: 'Estoque Geral',
        subtitle: 'Valor, quantidade e alertas.',
        icon: Icons.inventory_2_outlined,
        category: 'Estoque',
        allowed: true,
        builder: (_) => const DashboardVisaoGeralEstoqueScreen(),
        color: DashboardColors.orange,
      ),
      _DashboardItem(
        id: 'giro_estoque',
        title: 'Giro de Estoque',
        subtitle: 'Performance e estoque parado.',
        icon: Icons.autorenew,
        category: 'Estoque',
        allowed: true,
        builder: (_) => const DashboardGiroEstoqueScreen(),
        color: DashboardColors.teal,
      ),
      _DashboardItem(
        id: 'curva_abc_estoque',
        title: 'Curva ABC',
        subtitle: 'Prioridade dos produtos vendidos.',
        icon: Icons.filter_alt_outlined,
        category: 'Estoque',
        allowed: true,
        builder: (_) => const DashboardCurvaABCEstoqueScreen(),
        color: DashboardColors.deepPurple,
      ),

      _DashboardItem(
        id: 'agenda_online',
        title: 'Agenda',
        subtitle: 'Resultados dos agendamentos.',
        icon: Icons.calendar_month_outlined,
        category: 'Operação',
        allowed: true,
        builder: (_) => const AgendaDashboardScreen(),
        color: DashboardColors.purple,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppScaffold(
        title: 'Dashboards',
        useModernHeader: true,
        greetingName: 'Dashboard',
        subtitle: 'Acompanhe seus indicadores.',
        body: const Center(child: CircularProgressIndicator()),
        currentIndex: 3,
        onTabSelected: _onTabSelected,
        onOpenMenu:
            () => AppMenuSheet.show(
              context,
              isAdmin: _isAdmin,
              isPremium: _isPremium,
              companyId: _companyId,
            ),
      );
    }

    if (_error != null) {
      return AppScaffold(
        title: 'Dashboards',
        useModernHeader: true,
        greetingName: 'Dashboard',
        subtitle: 'Acompanhe seus indicadores.',
        body: _ErrorState(error: _error!, onRetry: _loadPermissions),
        currentIndex: 3,
        onTabSelected: _onTabSelected,
        onOpenMenu:
            () => AppMenuSheet.show(
              context,
              isAdmin: _isAdmin,
              isPremium: _isPremium,
              companyId: _companyId,
            ),
      );
    }

    final items = _items();

    final categories = [
      'Todos',
      ...{for (final it in items) it.category}.toList()..sort(),
    ];

    if (!categories.contains(_activeFilter)) {
      _activeFilter = 'Todos';
    }

    final filtered =
        items
            .where(
              (it) => _activeFilter == 'Todos' || it.category == _activeFilter,
            )
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));

    return AppScaffold(
      title: 'Dashboards',
      useModernHeader: true,
      greetingName: 'Dashboard',
      subtitle: 'Acompanhe seus indicadores.',
      body: Container(
        color: DashboardColors.background,
        child: RefreshIndicator(
          onRefresh: _loadPermissions,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _FilterChips(
                    categories: categories,
                    activeFilter: _activeFilter,
                    onSelected: (value) {
                      setState(() => _activeFilter = value);
                    },
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final cross =
                          w >= 1000
                              ? 4
                              : w >= 720
                              ? 3
                              : 2;

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cross,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: cross >= 3 ? 156 : 168,
                        ),
                        itemBuilder: (_, i) {
                          final it = filtered[i];

                          return _DashboardCard(
                            item: it,
                            enabled: it.allowed,
                            onTap:
                                () => _navigateIfAllowed(
                                  context,
                                  it.allowed,
                                  it.builder,
                                ),
                          );
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
      currentIndex: 3,
      onTabSelected: _onTabSelected,
      onOpenMenu:
          () => AppMenuSheet.show(
            context,
            isAdmin: _isAdmin,
            isPremium: _isPremium,
            companyId: _companyId,
          ),
    );
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }
}

class _DashboardItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String category;
  final bool allowed;
  final WidgetBuilder builder;
  final Color color;

  _DashboardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
    required this.allowed,
    required this.builder,
    required this.color,
  });
}

class _FilterChips extends StatelessWidget {
  final List<String> categories;
  final String activeFilter;
  final ValueChanged<String> onSelected;

  const _FilterChips({
    required this.categories,
    required this.activeFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = categories[index];
          final selected = item == activeFilter;

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? DashboardColors.purple : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color:
                      selected
                          ? DashboardColors.purple
                          : const Color(0xFFE5DFF2),
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: DashboardColors.purple.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                ],
              ),
              child: Text(
                item,
                style: TextStyle(
                  color: selected ? Colors.white : DashboardColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final _DashboardItem item;
  final bool enabled;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? item.color : const Color(0xFF8A8791);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.62,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color:
                      enabled
                          ? effectiveColor.withOpacity(0.18)
                          : const Color(0xFFE2DFEA),
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
                              enabled ? item.icon : Icons.lock_outline_rounded,
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
                              enabled
                                  ? Icons.arrow_forward_rounded
                                  : Icons.lock_outline_rounded,
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
                          color: DashboardColors.textDark,
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
                          color: DashboardColors.textMuted,
                          fontSize: 12,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CategoryBadge(
                        label: item.category,
                        color: effectiveColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CategoryBadge({required this.label, required this.color});

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
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DashboardColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFEAE7F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.045),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 42,
                  color: DashboardColors.redOrange,
                ),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar permissões:\n$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DashboardColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
