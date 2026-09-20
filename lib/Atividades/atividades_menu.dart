// lib/Atividades/atividades_menu.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Cadastros/cadastros_menu.dart';
import '../Cadastros/ComprasCrudScreen.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Financeiro/Financeiro_menu.dart';
import '../Pedidos/CadastroPedidoScreen.dart';
import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';
import '../home/alerts_controller.dart';

import 'ConsultarAjustarEstoqueScreen.dart';
import 'ContasPagarAVencerScreen.dart';
import 'CompromissosListaScreen.dart';
import 'ContasReceberAVencerScreen.dart';
import 'CompromissosCalendarScreen.dart';
import '../Atividades/PedidosCatalogoAprovacaoScreen.dart';
import '../Atividades/comprasAprovacaoScreen.dart';
import '../atividades/RevisaoCustoProdutosScreen.dart';
import '../Home/home_screen.dart';
import '../Agenda/AgendaScreen.dart';
//import '../Atividades/CalculadoraPrecoProdutoScreen.dart';

class AtividadeColors {
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

class AtividadesMenuScreen extends StatefulWidget {
  const AtividadesMenuScreen({super.key});

  @override
  State<AtividadesMenuScreen> createState() => _AtividadesMenuScreenState();
}

class _AtividadesMenuScreenState extends State<AtividadesMenuScreen> {
  bool _loadingPerms = true;
  bool _canRegisterOrders = false;
  bool _canAccountsPayable = false;
  bool _canAccountsReceivable = false;
  bool _canAdjustStock = false;
  bool _isAdmin = false;
  bool _canManagePurchases = false;

  String? _companyId;
  bool _loadingOrdersLimit = true;
  int _monthlyOrdersCount = 0;
  int _monthlyOrdersLimit = -1;
  bool _canCreateOrderByPlan = true;
  String? _ordersPlanError;

  String _currentPlan = 'free';
  bool get _isPremium => _currentPlan == 'premium';

  bool get _isOrdersLimitReached =>
      !_loadingOrdersLimit &&
      _monthlyOrdersLimit != -1 &&
      _monthlyOrdersCount >= _monthlyOrdersLimit;

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    setState(() {
      _currentPlan = service.isLoaded ? service.planId : 'free';
      if (service.isLoaded) {
        _monthlyOrdersLimit = service.getLimit('maxOrdersPerMonth');
        if (!_loadingOrdersLimit && _ordersPlanError == null) {
          _canCreateOrderByPlan =
              _monthlyOrdersLimit == -1 ||
              _monthlyOrdersCount < _monthlyOrdersLimit;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _initData();
  }

  Future<void> _initData() async {
    await _loadPerms();
    await _refreshOrdersPlanRules();
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

  void _showPremiumRequiredDialog({
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<void> _loadPerms() async {
    setState(() => _loadingPerms = true);

    try {
      final auth = FirebaseAuth.instance;
      final fs = FirebaseFirestore.instance;
      final u = auth.currentUser;

      if (u == null) {
        setState(() {
          _loadingPerms = false;
          _companyId = null;
          _currentPlan = 'free';
        });
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

          if (q.docs.isNotEmpty) me = q.docs.first.data();
        }
      }

      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      final role = (me?['role'] ?? 'funcionario').toString().toLowerCase();
      final isAdmin = role == 'admin';
      final companyId = (me?['companyId'] ?? '').toString().trim();
      final userPlan = _extractPlanFromMap(me);
      final plan = userPlan;

      if (!mounted) return;

      setState(() {
        _isAdmin = isAdmin;
        _companyId = companyId.isEmpty ? null : companyId;
        _canRegisterOrders = (perms['canRegisterOrders'] ?? false) == true;
        _canAccountsPayable = (perms['canAccountsPayable'] ?? false) == true;
        _canAccountsReceivable =
            (perms['canAccountsReceivable'] ?? false) == true;
        _canAdjustStock = (perms['canAdjustStock'] ?? false) == true;
        _canManagePurchases = (perms['canManagePurchases'] ?? false) == true;
        _currentPlan =
            PlanService.instance.isLoaded ? PlanService.instance.planId : plan;
        _loadingPerms = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadingPerms = false;
        _companyId = null;
        _currentPlan = 'free';
      });
    }
  }

  Future<int> _loadMonthlyOrdersCount() async {
    return PlanService.instance.getCurrentOrdersMonthCount();
  }

  Future<void> _refreshOrdersPlanRules() async {
    try {
      if (mounted) {
        setState(() {
          _loadingOrdersLimit = true;
          _ordersPlanError = null;
        });
      }

      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await _loadMonthlyOrdersCount();
      final limite = PlanService.instance.getLimit('maxOrdersPerMonth');
      final canCreate = limite == -1 ? true : usados < limite;

      if (!mounted) return;

      setState(() {
        _monthlyOrdersCount = usados;
        _monthlyOrdersLimit = limite;
        _canCreateOrderByPlan = canCreate;
        _loadingOrdersLimit = false;
        _ordersPlanError = null;
      });
    } catch (e) {
      debugPrint('Erro ao validar plano de pedidos: $e');

      if (!mounted) return;

      setState(() {
        _monthlyOrdersCount = 0;
        _monthlyOrdersLimit = -1;
        _canCreateOrderByPlan = true;
        _loadingOrdersLimit = false;
        _ordersPlanError = 'Erro ao validar plano: $e';
      });
    }
  }

  void _showOrderPlanLimitDialog({
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<bool> _requireOrderSlot() async {
    try {
      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await _loadMonthlyOrdersCount();
      final limite = PlanService.instance.getLimit('maxOrdersPerMonth');
      final canCreate = limite == -1 ? true : usados < limite;

      if (!mounted) return false;

      setState(() {
        _monthlyOrdersCount = usados;
        _monthlyOrdersLimit = limite;
        _canCreateOrderByPlan = canCreate;
      });

      if (canCreate) return true;

      _showOrderPlanLimitDialog(
        titulo: 'Limite de pedidos atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de pedidos do seu plano atual neste mês.\n\n'
                    'Pedidos usados: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando pedidos.',
      );

      return false;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao validar plano de pedidos: $e')),
      );

      return false;
    }
  }

  Future<void> _openNewOrderGuarded(BuildContext ctx) async {
    if (_loadingPerms || _loadingOrdersLimit) return;

    if (!_canRegisterOrders) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para cadastrar pedidos.'),
        ),
      );
      return;
    }

    final ok = await _requireOrderSlot();
    if (!ok) return;

    if (!ctx.mounted) return;

    await Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => const CadastroPedidoScreen()));

    await _refreshOrdersPlanRules();
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

  String _pedidoSubtitle() {
    if (_loadingOrdersLimit) return 'Verificando limite...';
    if (!_canRegisterOrders) return 'Sem permissão.';
    if (_canRegisterOrders && !_isOrdersLimitReached)
      return 'Criar pedido de venda.';
    if (_monthlyOrdersLimit == -1) return 'Criar pedido de venda.';

    return '$_monthlyOrdersCount/$_monthlyOrdersLimit usados este mês.';
  }

  @override
  Widget build(BuildContext context) {
    AlertsController.instance.ensureStarted();

    final bool pedidoLocked =
        !_canRegisterOrders ||
        (_isOrdersLimitReached && !_canCreateOrderByPlan);

    return ValueListenableBuilder<int>(
      valueListenable: AlertsController.instance.lowStock,
      builder: (context, lowCount, _) {
        return ValueListenableBuilder<int>(
          valueListenable: AlertsController.instance.overduePayables,
          builder: (context, pagarCount, __) {
            return ValueListenableBuilder<int>(
              valueListenable: AlertsController.instance.overdueReceivables,
              builder: (context, receberCount, ___) {
                return ValueListenableBuilder<int>(
                  valueListenable: AlertsController.instance.appointmentsTotal,
                  builder: (context, compromissosTotal, ____) {
                    return ValueListenableBuilder<int>(
                      valueListenable:
                          AlertsController.instance.appointmentsOverdue,
                      builder: (context, compromissosAtrasados, _____) {
                        return ValueListenableBuilder<int>(
                          valueListenable:
                              AlertsController.instance.appointmentsToday,
                          builder: (context, compromissosHoje, ______) {
                            return ValueListenableBuilder<int>(
                              valueListenable:
                                  AlertsController.instance.comprasAEntregar,
                              builder: (context, comprasAEntregar, _______) {
                                return ValueListenableBuilder<int>(
                                  valueListenable:
                                      AlertsController.instance.revisarCustos,
                                  builder: (
                                    context,
                                    revisarCustosCount,
                                    ________,
                                  ) {
                                    final items = <_ActivityItem>[
                                      _ActivityItem(
                                        id: 'novo_pedido',
                                        title: 'Novo Pedido',
                                        subtitle: _pedidoSubtitle(),
                                        icon:
                                            pedidoLocked
                                                ? Icons.lock_outline_rounded
                                                : Icons
                                                    .add_shopping_cart_outlined,
                                        color: AtividadeColors.purple,
                                        locked: pedidoLocked,
                                        onTap:
                                            (ctx) => _openNewOrderGuarded(ctx),
                                      ),
                                      _ActivityItem(
                                        id: 'compras',
                                        title: 'Compras',
                                        subtitle:
                                            _canManagePurchases
                                                ? 'Cadastro e controle.'
                                                : 'Sem permissão.',
                                        icon:
                                            _canManagePurchases
                                                ? Icons.shopping_cart_outlined
                                                : Icons.lock_outline_rounded,
                                        color: AtividadeColors.green,
                                        locked: !_canManagePurchases,
                                        onTap:
                                            (ctx) => _openIfAllowed(
                                              allowed: _canManagePurchases,
                                              denyMsg:
                                                  'Você não tem permissão para acessar Compras.',
                                              ctx: ctx,
                                              page: const ComprasCrudScreen(),
                                            ),
                                      ),
                                      _ActivityItem(
                                        id: 'aprovCompras',
                                        title: 'Aprovar Compras',
                                        subtitle: 'Compras aguardando entrega.',
                                        icon: Icons.fact_check_outlined,
                                        color: AtividadeColors.blue,
                                        onTap: (ctx) {
                                          Navigator.of(ctx).push(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const ComprasAprovacaoScreen(),
                                            ),
                                          );
                                        },
                                        badge: comprasAEntregar,
                                      ),
                                      _ActivityItem(
                                        id: 'pagar',
                                        title: 'Contas a Pagar',
                                        subtitle:
                                            _canAccountsPayable
                                                ? 'A vencer e vencidas.'
                                                : 'Sem permissão.',
                                        icon:
                                            _canAccountsPayable
                                                ? Icons.receipt_long_outlined
                                                : Icons.lock_outline_rounded,
                                        color: AtividadeColors.orange,
                                        locked: !_canAccountsPayable,
                                        onTap:
                                            (ctx) => _openIfAllowed(
                                              allowed: _canAccountsPayable,
                                              denyMsg:
                                                  'Você não tem permissão para acessar Contas a Pagar.',
                                              ctx: ctx,
                                              page:
                                                  const ContasPagarAVencerScreen(),
                                            ),
                                        badge: pagarCount,
                                      ),
                                      _ActivityItem(
                                        id: 'receber',
                                        title: 'Contas a Receber',
                                        subtitle:
                                            _canAccountsReceivable
                                                ? 'A vencer e vencidas.'
                                                : 'Sem permissão.',
                                        icon:
                                            _canAccountsReceivable
                                                ? Icons.request_quote_outlined
                                                : Icons.lock_outline_rounded,
                                        color: AtividadeColors.green,
                                        locked: !_canAccountsReceivable,
                                        onTap:
                                            (ctx) => _openIfAllowed(
                                              allowed: _canAccountsReceivable,
                                              denyMsg:
                                                  'Você não tem permissão para acessar Contas a Receber.',
                                              ctx: ctx,
                                              page:
                                                  const ContasReceberAVencerScreen(),
                                            ),
                                        badge: receberCount,
                                      ),
                                      _ActivityItem(
                                        id: 'revisao_custo',
                                        title: 'Revisar Custos',
                                        subtitle:
                                            revisarCustosCount > 0
                                                ? '$revisarCustosCount produto(s) para revisar.'
                                                : 'Custos alinhados.',
                                        icon:
                                            revisarCustosCount > 0
                                                ? Icons.warning_amber_rounded
                                                : Icons.sync_alt_outlined,
                                        color:
                                            revisarCustosCount > 0
                                                ? AtividadeColors.yellow
                                                : AtividadeColors.purple,
                                        onTap: (ctx) {
                                          Navigator.of(ctx).push(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const RevisaoCustoProdutosScreen(),
                                            ),
                                          );
                                        },
                                        badge: revisarCustosCount,
                                      ),
                                      _ActivityItem(
                                        id: 'estoque',
                                        title: 'Atualizar Estoque',
                                        subtitle:
                                            _canAdjustStock
                                                ? 'Entradas e saídas.'
                                                : 'Sem permissão.',
                                        icon:
                                            _canAdjustStock
                                                ? Icons.inventory_2_outlined
                                                : Icons.lock_outline_rounded,
                                        color: AtividadeColors.teal,
                                        locked: !_canAdjustStock,
                                        onTap:
                                            (ctx) => _openIfAllowed(
                                              allowed: _canAdjustStock,
                                              denyMsg:
                                                  'Você não tem permissão para ajustar estoque.',
                                              ctx: ctx,
                                              page:
                                                  const ConsultarAjustarEstoqueScreen(),
                                            ),
                                        badge: lowCount,
                                      ),
                                      _ActivityItem(
                                        id: 'aprovar_catalogo',
                                        title: 'Pedidos Catálogo',
                                        subtitle:
                                            _isPremium
                                                ? 'Pedidos recebidos online.'
                                                : 'Disponível no Premium.',
                                        icon:
                                            _isPremium
                                                ? Icons.storefront_outlined
                                                : Icons
                                                    .workspace_premium_outlined,
                                        color: AtividadeColors.orange,
                                        onTap: (ctx) {
                                          if (_isPremium) {
                                            Navigator.of(ctx).push(
                                              MaterialPageRoute(
                                                builder:
                                                    (_) =>
                                                        const PedidosCatalogoAprovacaoScreen(),
                                              ),
                                            );
                                            return;
                                          }

                                          _showPremiumRequiredDialog(
                                            titulo:
                                                'Pedidos do catálogo disponíveis no Premium',
                                            mensagem:
                                                'A aprovação de pedidos do catálogo é um recurso exclusivo do plano Premium.\n\n'
                                                'Faça upgrade para gerenciar e aprovar pedidos feitos pelos seus clientes.',
                                          );
                                        },
                                      ),
                                      _ActivityItem(
                                        id: 'reservas_online',
                                        title: 'Reservas Online',
                                        subtitle:
                                            _isPremium
                                                ? 'Agendamentos recebidos pelo site.'
                                                : 'Disponível no Premium.',
                                        icon:
                                            _isPremium
                                                ? Icons.calendar_month_outlined
                                                : Icons
                                                    .workspace_premium_outlined,
                                        color: AtividadeColors.purple,
                                        locked: !_isPremium,
                                        onTap: (ctx) {
                                          if (_isPremium) {
                                            Navigator.of(ctx).push(
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => const AgendaScreen(),
                                              ),
                                            );
                                            return;
                                          }

                                          _showPremiumRequiredDialog(
                                            titulo:
                                                'Reservas Online disponíveis no Premium',
                                            mensagem:
                                                'As reservas recebidas pela Agenda Online são um recurso '
                                                'exclusivo do plano Premium.\n\n'
                                                'Faça upgrade para visualizar e gerenciar os agendamentos '
                                                'feitos pelos seus clientes.',
                                          );
                                        },
                                      ),
                                      _ActivityItem(
                                        id: 'compromisso',
                                        title: 'Compromissos',
                                        subtitle: 'Hoje e atrasados.',
                                        icon: Icons.event_note_outlined,
                                        color: AtividadeColors.blue,
                                        onTap: (ctx) {
                                          Navigator.of(ctx).push(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const CompromissosCalendarScreen(),
                                            ),
                                          );
                                        },
                                        badge: compromissosTotal,
                                      ),
                                      /*_ActivityItem(
                                        id: 'calculadora',
                                        title: 'Calculadora',
                                        subtitle: 'Preço de produtos.',
                                        icon: Icons.calculate_outlined,
                                        color: AtividadeColors.pink,
                                        onTap: (ctx) {
                                          Navigator.of(ctx).push(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const CalculadoraPrecoProdutoScreen(),
                                            ),
                                          );
                                        },
                                      ),*/
                                    ];

                                    return AppScaffold(
                                      title: 'Atividades',
                                      useModernHeader: true,
                                      greetingName: 'Atividades',
                                      subtitle:
                                          'Acesse rapidamente as rotinas do seu dia.',
                                      currentIndex: 2,
                                      onOpenMenu:
                                          () => AppMenuSheet.show(
                                            context,
                                            isAdmin: _isAdmin,
                                            isPremium: _isPremium,
                                            companyId: _companyId,
                                          ),
                                      onTabSelected: (i) {
                                        if (i == 0) {
                                          Navigator.of(
                                            context,
                                          ).pushAndRemoveUntil(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) => const HomeScreen(),
                                            ),
                                            (route) => false,
                                          );
                                          return;
                                        }

                                        if (i == 1) {
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const CadastrosMenuScreen(),
                                            ),
                                          );
                                          return;
                                        }

                                        if (i == 2) {
                                          // Já está na tela de Atividades.
                                          return;
                                        }

                                        if (i == 3) {
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const DashboardsMenuScreen(),
                                            ),
                                          );
                                          return;
                                        }

                                        if (i == 4) {
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const FinanceiroMenuScreen(),
                                            ),
                                          );
                                        }
                                      },
                                      body: Container(
                                        color: AtividadeColors.background,
                                        child: RefreshIndicator(
                                          onRefresh: () async {
                                            await _loadPerms();
                                            await _refreshOrdersPlanRules();
                                          },
                                          child: CustomScrollView(
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            slivers: [
                                              SliverPadding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      16,
                                                      16,
                                                      16,
                                                      10,
                                                    ),
                                                sliver: SliverToBoxAdapter(),
                                              ),

                                              if (_ordersPlanError != null)
                                                SliverPadding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        16,
                                                        4,
                                                        16,
                                                        8,
                                                      ),
                                                  sliver: SliverToBoxAdapter(
                                                    child: _WarningCard(
                                                      message:
                                                          _ordersPlanError!,
                                                    ),
                                                  ),
                                                ),

                                              SliverPadding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      16,
                                                      2,
                                                      16,
                                                      8,
                                                    ),
                                                sliver: SliverToBoxAdapter(
                                                  child: Column(
                                                    children: [
                                                      if (comprasAEntregar > 0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .blue,
                                                          icon:
                                                              Icons
                                                                  .inventory_2_outlined,
                                                          text:
                                                              comprasAEntregar ==
                                                                      1
                                                                  ? '1 compra aguardando entrega'
                                                                  : '$comprasAEntregar compras aguardando entrega',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const ComprasAprovacaoScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel: 'VER',
                                                        ),
                                                      if (compromissosAtrasados >
                                                          0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .redOrange,
                                                          icon:
                                                              Icons
                                                                  .warning_amber_rounded,
                                                          text:
                                                              compromissosAtrasados ==
                                                                      1
                                                                  ? '1 compromisso atrasado'
                                                                  : '$compromissosAtrasados compromissos atrasados',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const CompromissosListaScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel: 'VER',
                                                        ),
                                                      if (compromissosHoje > 0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .yellow,
                                                          icon:
                                                              Icons
                                                                  .event_available_outlined,
                                                          text:
                                                              compromissosHoje ==
                                                                      1
                                                                  ? 'Hoje você tem 1 compromisso'
                                                                  : 'Hoje você tem $compromissosHoje compromissos',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const CompromissosListaScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel: 'VER',
                                                        ),
                                                      if (pagarCount > 0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .redOrange,
                                                          icon:
                                                              Icons
                                                                  .warning_amber_rounded,
                                                          text:
                                                              pagarCount == 1
                                                                  ? '1 título em pagar está vencido'
                                                                  : '$pagarCount títulos em pagar estão vencidos',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const ContasPagarAVencerScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel: 'VER',
                                                        ),
                                                      if (receberCount > 0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .orange,
                                                          icon:
                                                              Icons
                                                                  .warning_amber_rounded,
                                                          text:
                                                              receberCount == 1
                                                                  ? '1 título em receber está vencido'
                                                                  : '$receberCount títulos em receber estão vencidos',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const ContasReceberAVencerScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel: 'VER',
                                                        ),
                                                      if (revisarCustosCount >
                                                          0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .yellow,
                                                          icon:
                                                              Icons
                                                                  .price_change_outlined,
                                                          text:
                                                              revisarCustosCount ==
                                                                      1
                                                                  ? '1 produto precisa de revisão de custo'
                                                                  : '$revisarCustosCount produtos precisam de revisão de custo',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const RevisaoCustoProdutosScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel:
                                                              'REVISAR',
                                                        ),
                                                      if (lowCount > 0)
                                                        _BannerWarn(
                                                          color:
                                                              AtividadeColors
                                                                  .redOrange,
                                                          icon:
                                                              Icons
                                                                  .inventory_2_outlined,
                                                          text:
                                                              lowCount == 1
                                                                  ? '1 produto com estoque abaixo do mínimo'
                                                                  : '$lowCount produtos com estoque abaixo do mínimo',
                                                          action: () {
                                                            Navigator.of(
                                                              context,
                                                            ).push(
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (_) =>
                                                                        const ConsultarAjustarEstoqueScreen(),
                                                              ),
                                                            );
                                                          },
                                                          actionLabel:
                                                              'AJUSTAR',
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),

                                              SliverPadding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      16,
                                                      8,
                                                      16,
                                                      120,
                                                    ),
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
                                                        physics:
                                                            const NeverScrollableScrollPhysics(),
                                                        itemCount: items.length,
                                                        gridDelegate:
                                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                              crossAxisCount:
                                                                  cross,
                                                              crossAxisSpacing:
                                                                  12,
                                                              mainAxisSpacing:
                                                                  12,
                                                              mainAxisExtent:
                                                                  cross >= 3
                                                                      ? 156
                                                                      : 168,
                                                            ),
                                                        itemBuilder: (_, i) {
                                                          return _ActivityCard(
                                                            item: items[i],
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
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }
}

class _ActivityItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final void Function(BuildContext ctx) onTap;
  final int badge;
  final bool locked;

  _ActivityItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge = 0,
    this.locked = false,
  });
}

class _ActivityCard extends StatelessWidget {
  final _ActivityItem item;

  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = item.locked ? const Color(0xFF8A8791) : item.color;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => item.onTap(context),
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
                        Stack(
                          clipBehavior: Clip.none,
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
                            if (item.badge > 0)
                              Positioned(
                                right: -7,
                                top: -7,
                                child: _CounterBadge(count: item.badge),
                              ),
                          ],
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
                        color: AtividadeColors.textDark,
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
                        color: AtividadeColors.textMuted,
                        fontSize: 12,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterBadge extends StatelessWidget {
  final int count;

  const _CounterBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final s =
        count > 99
            ? '99+'
            : count > 9
            ? '9+'
            : '$count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
        s,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _BannerWarn extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final VoidCallback action;
  final String actionLabel;

  const _BannerWarn({
    required this.color,
    required this.icon,
    required this.text,
    required this.action,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AtividadeColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: action,
            child: Text(
              actionLabel,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String message;

  const _WarningCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.red.shade800,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/*class _HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool loading;
  final String plan;
  final int totalAlerts;

  const _HeroHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.loading,
    required this.plan,
    required this.totalAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final planLabel =
        plan == 'premium'
            ? 'Premium'
            : plan == 'starter'
            ? 'Starter'
            : 'Free';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.white,
            AtividadeColors.purple.withOpacity(0.06),
            AtividadeColors.orange.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFEAE7F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AtividadeColors.purple.withOpacity(0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: AtividadeColors.purple, size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AtividadeColors.textDark,
                    fontSize: 20,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  loading ? 'Carregando permissões...' : subtitle,
                  style: const TextStyle(
                    color: AtividadeColors.textMuted,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SmallBadge(
                      text: 'Plano $planLabel',
                      color: AtividadeColors.purple,
                    ),
                    if (totalAlerts > 0)
                      _SmallBadge(
                        text: '$totalAlerts alerta(s)',
                        color: AtividadeColors.redOrange,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}*/

/*class _SmallBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _SmallBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}*/
