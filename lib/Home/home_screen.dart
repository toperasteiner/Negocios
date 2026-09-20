// lib/Home/HomeScreen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../Atividades/atividades_menu.dart';
import '../Cadastros/cadastros_menu.dart';
import '../Catalogo/CatalogoMenuScreen.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Financeiro/ContasPagarHomeScreen.dart';
import '../Financeiro/ContasReceberHomeScreen.dart';
import '../Financeiro/Financeiro_menu.dart';
import '../Pedidos/CadastroPedidoScreen.dart';
//import '../Pedidos/PedidosHomeScreen.dart';
import '../Pedidos/PedidosHomeScreen.dart';
import '../Planos/PlanosScreen.dart';
import '../atividades/ConsultarAjustarEstoqueScreen.dart';
import '../ui/app_menu_sheet.dart';
import '../ui/app_scaffold.dart';
import '../Treinamento/TreinamentosHomeScreen.dart';

import 'HomeScreenDesktop.dart';
import 'home_controller.dart';
import 'home_widgets.dart';
import '../UI/SugestoesHomeWidget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;

  @override
  void initState() {
    super.initState();

    _controller = HomeController(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _contentMaxWidth(double width) {
    if (width >= 1400) return 1320;
    if (width >= 1100) return 1140;
    if (width >= 900) return 980;
    return width;
  }

  VoidCallback? _guardTap(bool allowed, VoidCallback action) {
    return allowed ? action : null;
  }

  void _openPlansScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
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
                  _openPlansScreen();
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  void _abrirCatalogoPublico() {
    if (!_controller.isPremium) {
      _showPremiumRequiredDialog(
        titulo: 'Catálogo Online disponível no Premium',
        mensagem:
            'O Catálogo Online é um recurso exclusivo do plano Premium.\n\n'
            'Faça upgrade para criar e compartilhar seu catálogo público com seus clientes.',
      );
      return;
    }

    if (_controller.companyId == null || _controller.companyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CatalogoMenuScreen()));
  }

  Future<void> _abrirAcessoComputador() async {
    if (!_controller.isPremium) {
      _showPremiumRequiredDialog(
        titulo: 'Acesso no computador disponível no Premium',
        mensagem:
            'O acesso pelo computador é um recurso exclusivo do plano Premium.\n\n'
            'Faça upgrade para utilizar o sistema também pelo navegador.',
      );
      return;
    }

    if (_controller.companyId == null || _controller.companyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A opção de acesso no computador será aberta pelo menu do aplicativo.',
        ),
      ),
    );
  }

  void _showOrderPlanLimitDialog({
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
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openPlansScreen();
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<void> _openNewOrderGuarded(BuildContext ctx) async {
    if (_controller.loadingScope || _controller.loadingOrdersLimit) return;

    if (!_controller.canRegisterOrders) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Sem acesso a Pedidos.')));
      return;
    }

    final result = await _controller.requireOrderSlot();

    if (!ctx.mounted) return;

    if (!result.allowed) {
      if (result.showLimitDialog) {
        _showOrderPlanLimitDialog(
          titulo: 'Limite de pedidos atingido',
          mensagem: result.message,
        );
      }

      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(result.shortMessage)));
      return;
    }

    await Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => const CadastroPedidoScreen()));

    await _controller.refreshOrdersPlanRules();
    await _controller.refreshHomeSummary();
  }

  void _onBottomTabSelected(int i) {
    if (i == 0) return;

    if (i == 1) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CadastrosMenuScreen()));
    } else if (i == 2) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AtividadesMenuScreen()));
    } else if (i == 3) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DashboardsMenuScreen()));
    } else if (i == 4) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FinanceiroMenuScreen()));
    }
  }

  void _openMenu() {
    AppMenuSheet.show(
      context,
      isAdmin: _controller.isAdmin,
      isPremium: _controller.isPremium,
      companyId: _controller.companyId,
    );
  }

  Future<List<QuickActionData>> _montarAcoesRapidasHome() {
    return SugestoesHomeWidget(
      scopeField: _controller.scopeField,
      scopeUserId: _controller.scopeUserId ?? '',
      companyId: _controller.companyId,
      isPremium: _controller.isPremium,
      onCatalogo: _abrirCatalogoPublico,
      onComputador: _abrirAcessoComputador,
    ).montarAcoesRapidas(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_controller.scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Início')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_controller.scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktopLayout = kIsWeb && width >= 900;

    if (isDesktopLayout) {
      return const HomeScreenDesktop();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxWidth = _contentMaxWidth(width);

        return AppScaffold(
          title: 'Início',
          useModernHeader: true,
          greetingName: _controller.headerUserName,
          subtitle: 'Aqui está o resumo do seu negócio.',
          notificationCount: _controller.notificationCount,
          onNotifications: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AtividadesMenuScreen()),
            );
          },
          currentIndex: 0,
          onTabSelected: _onBottomTabSelected,
          onOpenMenu: _openMenu,
          body: Container(
            color: HomeColors.background,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _controller.refreshOrdersPlanRules();
                    await _controller.refreshHomeSummary();
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        sliver: SliverGrid(
                          delegate: SliverChildListDelegate([
                            if (_controller.companyId != null)
                              PedidosHojeStat(
                                scopeUserId: _controller.scopeUserId ?? '',
                                scopeField: _controller.scopeField,
                                enabled: _controller.canRegisterOrders,
                                onTap: _guardTap(
                                  _controller.canRegisterOrders,
                                  () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const PedidosHomeScreen(),
                                    ),
                                  ),
                                ),
                              )
                            else
                              const HomeKpiCard(
                                title: 'Pedidos hoje',
                                value: '—',
                                subtitle: 'Empresa não identificada',
                                icon: Icons.info_outline_rounded,
                                iconColor: HomeColors.purple,
                                disabled: true,
                              ),
                            AReceberStat(
                              scopeUserId: _controller.scopeUserId ?? '',
                              scopeField: _controller.scopeField,
                              enabled:
                                  _controller.canAccountsReceivable &&
                                  _controller.scopeUserId != null,
                              onTap: _guardTap(
                                _controller.canAccountsReceivable,
                                () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => const ContasReceberHomeScreen(),
                                  ),
                                ),
                              ),
                            ),
                            ItensEmFaltaStat(
                              scopeUserId: _controller.scopeUserId ?? '',
                              scopeField: _controller.scopeField,
                              enabled:
                                  _controller.canAdjustStock &&
                                  _controller.scopeUserId != null,
                              onTap: _guardTap(
                                _controller.canAdjustStock,
                                () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) =>
                                            const ConsultarAjustarEstoqueScreen(),
                                  ),
                                ),
                              ),
                            ),
                            ContasAPagarStat(
                              scopeUserId: _controller.scopeUserId ?? '',
                              scopeField: _controller.scopeField,
                              enabled:
                                  _controller.canAccountsPayable &&
                                  _controller.scopeUserId != null,
                              onTap: _guardTap(
                                _controller.canAccountsPayable,
                                () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => const ContasPagarHomeScreen(),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.55,
                              ),
                        ),
                      ),

                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
                        sliver: SliverToBoxAdapter(
                          child: OrdersSpotlight(
                            loadingPlan: _controller.loadingOrdersLimit,
                            canRegisterOrders: _controller.canRegisterOrders,
                            isOrdersLimitReached:
                                _controller.isOrdersLimitReached,
                            monthlyOrdersCount: _controller.monthlyOrdersCount,
                            monthlyOrdersLimit: _controller.monthlyOrdersLimit,
                            onNewOrder: (ctx) => _openNewOrderGuarded(ctx),
                            onSeeOrders: (ctx) {
                              if (_controller.canRegisterOrders) {
                                Navigator.of(ctx).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PedidosHomeScreen(),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sem acesso a Pedidos.'),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),

                      if (_controller.ordersPlanError != null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          sliver: SliverToBoxAdapter(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red.shade100),
                              ),
                              child: Text(
                                _controller.ordersPlanError!,
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),

                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                        sliver: SliverToBoxAdapter(
                          child: FutureBuilder<List<QuickActionData>>(
                            future: _montarAcoesRapidasHome(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final actions = snapshot.data ?? [];

                              return QuickActionsSection(actions: actions);
                            },
                          ),
                        ),
                      ),

                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 120),
                        sliver: SliverToBoxAdapter(
                          child: MonthlySummaryCard(
                            faturamento: _controller.monthlyRevenue,
                            variacaoPercentual:
                                _controller.monthlyRevenueVariation,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const DashboardsMenuScreen(),
                                ),
                              );
                            },
                            onPeriodoTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Filtro de período será liberado em uma próxima versão.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
