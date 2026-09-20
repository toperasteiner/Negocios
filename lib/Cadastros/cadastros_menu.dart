// lib/Cadastros/CadastrosMenuScreen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Atividades/atividades_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Financeiro/Financeiro_menu.dart';
import '../Pedidos/CadastroPedidoScreen.dart';
import '../Planos/PlanosScreen.dart';
import '../Planos/PlanService.dart';
import '../Preferencias/TextosPadroesScreen.dart';

import 'Cliente_screen.dart';
import 'ProdutoScreen.dart';
import 'ServicosCrudScreen.dart';
import 'ComprasCrudScreen.dart';
import 'CategoriasCrudScreen.dart';
import 'CategoriasPagamentoCrudScreen.dart';
import 'MetasHomeScreen.dart';
import 'UsuariosListScreen.dart';
import '../Home/home_screen.dart';

class CadastroColors {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color yellow = Color(0xFFFFB51F);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color teal = Color(0xFF00A896);
  static const Color pink = Color(0xFFD96AD8);
  static const Color background = Color(0xFFF7F7FA);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
}

class CadastrosMenuScreen extends StatefulWidget {
  const CadastrosMenuScreen({super.key});

  @override
  State<CadastrosMenuScreen> createState() => _CadastrosMenuScreenState();
}

class _CadastrosMenuScreenState extends State<CadastrosMenuScreen> {
  bool _loadingRole = true;
  bool _isAdmin = false;

  bool _canRegisterOrders = false;
  bool _canRegisterClientsSuppliers = false;
  bool _canManageProducts = false;
  bool _canManageServices = false;
  bool _canManagePaymentCategories = true;
  bool _canManageGoals = false;
  bool _canManagePurchases = false;
  bool _canManageCategories = false;

  String _currentPlan = 'free';

  int _monthlyOrdersCount = 0;
  bool _loadingOrdersLimit = true;
  int _monthlyOrdersLimit = -1;
  bool _canCreateOrderByPlan = true;
  String? _ordersPlanError;

  String? _companyId;

  bool get _isFreePlan => _currentPlan == 'free';
  bool get _isPremium => _currentPlan == 'premium';
  bool get _canAccessUsersModule => _isAdmin && !_isFreePlan;
  bool get _canAccessStandardTextsModule => !_isFreePlan;

  bool get _canAccessImagensPendentes {
    final email =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();

    return email == 'dani@dani.com';
  }

  bool get _isOrdersLimitReached =>
      !_loadingOrdersLimit &&
      _monthlyOrdersLimit != -1 &&
      _monthlyOrdersCount >= _monthlyOrdersLimit;

  bool get _shouldLockOrdersCard =>
      _isOrdersLimitReached || !_canRegisterOrders || !_canCreateOrderByPlan;

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
    await _resolveRole();
    await _refreshOrdersPlanRules();
  }

  VoidCallback? _guardTap(bool allowed, VoidCallback action) {
    return allowed ? action : null;
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

    if (directPlan != null) return _normalizePlan(directPlan);

    final subscription = data['subscription'];
    if (subscription is Map<String, dynamic>) {
      final nestedPlan =
          subscription['plan'] ??
          subscription['planId'] ??
          subscription['planKey'] ??
          subscription['currentPlan'];

      if (nestedPlan != null) return _normalizePlan(nestedPlan);
    }

    return 'free';
  }

  Future<Map<String, dynamic>?> _loadCurrentUserData() async {
    final auth = FirebaseAuth.instance;
    final fs = FirebaseFirestore.instance;
    final u = auth.currentUser;

    if (u == null) return null;

    Map<String, dynamic>? me;

    try {
      final byUid = await fs.collection('users').doc(u.uid).get();
      if (byUid.exists) me = byUid.data();
    } catch (_) {}

    if (me == null) {
      final emailKey = (u.email ?? '').trim().toLowerCase();

      if (emailKey.isNotEmpty) {
        try {
          final q =
              await fs
                  .collection('users')
                  .where('emailKey', isEqualTo: emailKey)
                  .limit(1)
                  .get();

          if (q.docs.isNotEmpty) me = q.docs.first.data();
        } catch (_) {}
      }
    }

    return me;
  }

  Future<void> _resolveRole() async {

    final me = await _loadCurrentUserData();

    final companyId = (me?['companyId'] ?? '').toString().trim();


    final role = (me?['role'] ?? 'funcionario').toString().toLowerCase();
    final isAdmin = role == 'admin';

    final permsDynamic = me?['permissions'];
    final Map<String, dynamic> perms =
        permsDynamic is Map<String, dynamic> ? permsDynamic : {};

    bool p(String k) => (perms[k] ?? false) == true;
    final userPlan = _extractPlanFromMap(me);
    final plan = userPlan;

    if (!mounted) return;

    setState(() {
      _companyId = companyId.isEmpty ? null : companyId;
      _isAdmin = isAdmin;
      _canRegisterOrders = p('canRegisterOrders');
      _canRegisterClientsSuppliers = p('canRegisterClientsSuppliers');
      _canManageProducts = p('canManageProducts');
      _canManageServices = p('canManageServices');
      _canManagePaymentCategories = isAdmin || p('canManagePaymentCategories');
      _canManageGoals = isAdmin || p('canManageGoals');
      _canManagePurchases = isAdmin || p('canManagePurchases');
      _canManageCategories = isAdmin || p('canManageCategories');
      _currentPlan =
          PlanService.instance.isLoaded ? PlanService.instance.planId : plan;
      _loadingRole = false;
    });
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
      });
    } catch (e) {
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
            'Você já atingiu o limite de pedidos do seu plano atual neste mês.\n\n'
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
                  _openPlansScreen();
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<void> _openCadastroPedidoGuarded() async {
    if (_loadingRole || _loadingOrdersLimit) return;

    if (!_canRegisterOrders) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para cadastrar pedidos.'),
        ),
      );
      return;
    }

    final ok = await _requireOrderSlot();

    if (!ok) return;

    if (!mounted) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CadastroPedidoScreen()));

    await _refreshOrdersPlanRules();
  }

  void _openPlansScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
  }

  Future<void> _shareComputerAccess() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';

      const link = 'https://projeto-pedidos-472813.web.app';

      final text = '''
Acesse o sistema no computador pelo link abaixo:

$link

${email.isNotEmpty ? 'Login sugerido: $email\n' : ''}Abra no navegador e entre com sua conta.
''';

      final params = ShareParams(text: text, subject: 'Acesso no computador');

      await SharePlus.instance.share(params);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao compartilhar: $e')));
    }
  }

  String get _pedidosSubtitle {
    if (_loadingOrdersLimit) return 'Verificando limite...';
    if (!_canRegisterOrders) return 'Sem permissão.';
    if (_monthlyOrdersLimit == -1) return 'Criar pedidos de venda.';

    if (_isOrdersLimitReached) {
      return 'Limite atingido: $_monthlyOrdersCount/$_monthlyOrdersLimit';
    }

    return '$_monthlyOrdersCount/$_monthlyOrdersLimit usados este mês.';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cadastros',
      useModernHeader: true,
      greetingName: 'Cadastros',
      subtitle: 'Gerencie clientes, produtos e configurações.',
      currentIndex: 1,
      onOpenMenu:
          () => AppMenuSheet.show(
            context,
            isAdmin: _isAdmin,
            isPremium: _isPremium,
            companyId: _companyId,
          ),
      onTabSelected: (i) {
        if (i == 0) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
          return;
        }

        if (i == 1) {
          // Já está na tela de Cadastros.
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
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FinanceiroMenuScreen()),
          );
        }
      },
      body: Container(
        color: CadastroColors.background,
        child: RefreshIndicator(
          onRefresh: () async {
            await _resolveRole();
            await _refreshOrdersPlanRules();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_ordersPlanError != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _WarningCard(message: _ordersPlanError!),
                  ),
                ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (ctx, c) {
                      final isWide = c.maxWidth >= 720;
                      final cols = isWide ? 3 : 2;

                      final cards = <Widget>[
                        _ModuleCard(
                          title: 'Cliente/Fornecedor',
                          subtitle:
                              _canRegisterClientsSuppliers
                                  ? 'Clientes e fornecedores.'
                                  : 'Sem permissão.',
                          icon: Icons.group_outlined,
                          color: CadastroColors.blue,
                          locked: !_canRegisterClientsSuppliers,
                          onTap: _guardTap(_canRegisterClientsSuppliers, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ClienteScreen(),
                              ),
                            );
                          }),
                        ),
                        _ModuleCard(
                          title: 'Produtos',
                          subtitle:
                              _canManageProducts
                                  ? 'Itens, preços e estoque.'
                                  : 'Sem permissão.',
                          icon: Icons.inventory_2_outlined,
                          color: CadastroColors.teal,
                          locked: !_canManageProducts,
                          onTap: () {
                            if (_loadingRole) return;

                            if (!_canManageProducts) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Você não tem permissão para cadastrar/gerenciar produtos.',
                                  ),
                                ),
                              );
                              return;
                            }

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ProdutoScreen(),
                              ),
                            );
                          },
                        ),
                        _ModuleCard(
                          title: 'Serviços',
                          subtitle:
                              _canManageServices
                                  ? 'Criação e edição.'
                                  : 'Sem permissão.',
                          icon: Icons.build_outlined,
                          color: CadastroColors.pink,
                          locked: !_canManageServices,
                          onTap: () {
                            if (_loadingRole) return;

                            if (!_canManageServices) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Você não tem permissão para cadastrar/gerenciar serviços.',
                                  ),
                                ),
                              );
                              return;
                            }

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ServicosCrudScreen(),
                              ),
                            );
                          },
                        ),
                        _ModuleCard(
                          title: 'Categorias Pagamento',
                          subtitle:
                              _canManagePaymentCategories
                                  ? 'Contas a pagar/receber.'
                                  : 'Sem permissão.',
                          icon: Icons.category_outlined,
                          color: CadastroColors.orange,
                          locked: !_canManagePaymentCategories,
                          onTap: _guardTap(_canManagePaymentCategories, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) =>
                                        const CategoriasPagamentoCrudScreen(),
                              ),
                            );
                          }),
                        ),
                        _ModuleCard(
                          title: 'Metas',
                          subtitle:
                              _canManageGoals
                                  ? 'Metas da empresa.'
                                  : 'Sem permissão.',
                          icon: Icons.flag_outlined,
                          color: CadastroColors.pink,
                          locked: !_canManageGoals,
                          onTap: _guardTap(_canManageGoals, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MetasHomeScreen(),
                              ),
                            );
                          }),
                        ),
                        _ModuleCard(
                          title: 'Pedidos',
                          subtitle: _pedidosSubtitle,
                          icon: Icons.assignment_outlined,
                          color: CadastroColors.purple,
                          locked: _shouldLockOrdersCard,
                          badge:
                              _isOrdersLimitReached
                                  ? 'Limite'
                                  : _monthlyOrdersLimit == -1
                                  ? null
                                  : '$_monthlyOrdersCount/$_monthlyOrdersLimit',
                          onTap: _openCadastroPedidoGuarded,
                        ),
                        _ModuleCard(
                          title: 'Compras',
                          subtitle:
                              _canManagePurchases
                                  ? 'Compras e contas.'
                                  : 'Sem permissão.',
                          icon: Icons.shopping_cart_outlined,
                          color: CadastroColors.green,
                          locked: !_canManagePurchases,
                          onTap: () {
                            if (_loadingRole) return;

                            if (!_canManagePurchases) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Você não tem permissão para acessar compras.',
                                  ),
                                ),
                              );
                              return;
                            }

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ComprasCrudScreen(),
                              ),
                            );
                          },
                        ),
                        _ModuleCard(
                          title: 'Categorias Produto',
                          subtitle:
                              _canManageCategories
                                  ? 'Produtos e serviços.'
                                  : 'Sem permissão.',
                          icon: Icons.account_tree_outlined,
                          color: CadastroColors.teal,
                          locked: !_canManageCategories,
                          onTap: () {
                            if (_loadingRole) return;

                            if (!_canManageCategories) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Você não tem permissão para acessar categorias.',
                                  ),
                                ),
                              );
                              return;
                            }

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CategoriasCrudScreen(),
                              ),
                            );
                          },
                        ),
                        _ModuleCard(
                          title: 'Computador',
                          subtitle:
                              _isPremium ? 'Compartilhar acesso.' : 'Premium.',
                          icon:
                              _isPremium
                                  ? Icons.computer_outlined
                                  : Icons.workspace_premium_outlined,
                          color: CadastroColors.blue,
                          locked: false,
                          badge: _isPremium ? null : 'Premium',
                          onTap: () async {
                            if (_isPremium) {
                              await _shareComputerAccess();
                              return;
                            }

                            _openPlansScreen();
                          },
                        ),
                        _ModuleCard(
                          title: 'Textos Padrões',
                          subtitle:
                              _canAccessStandardTextsModule
                                  ? 'Mensagens reutilizáveis.'
                                  : 'Starter/Premium.',
                          icon: Icons.sticky_note_2_outlined,
                          color: const Color(0xFF7D7A86),
                          locked: !_canAccessStandardTextsModule,
                          badge: _canAccessStandardTextsModule ? null : 'Plano',
                          onTap: () {
                            if (_canAccessStandardTextsModule) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TextosPadroesScreen(),
                                ),
                              );
                              return;
                            }

                            _openPlansScreen();
                          },
                        ),
                        if (_isAdmin || _isFreePlan)
                          _ModuleCard(
                            title: 'Usuários',
                            subtitle:
                                _isFreePlan
                                    ? 'Starter/Premium.'
                                    : 'Perfis e permissões.',
                            icon: Icons.manage_accounts_outlined,
                            color: Colors.redAccent,
                            locked: !_canAccessUsersModule,
                            badge: _canAccessUsersModule ? null : 'Plano',
                            onTap: () {
                              if (_canAccessUsersModule) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const UsuariosListScreen(),
                                  ),
                                );
                                return;
                              }

                              _openPlansScreen();
                            },
                          ),
                      ];

                      if (_loadingRole || _loadingOrdersLimit) {
                        cards.add(const _ModuleCard.skeleton());
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cards.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: isWide ? 156 : 168,
                        ),
                        itemBuilder: (_, i) => cards[i],
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

class _HeroCadastroCard extends StatelessWidget {
  final bool loading;
  final String plan;
  final bool isAdmin;

  const _HeroCadastroCard({
    required this.loading,
    required this.plan,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.white,
            CadastroColors.purple.withOpacity(0.06),
            CadastroColors.orange.withOpacity(0.05),
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
              color: CadastroColors.purple.withOpacity(0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: CadastroColors.purple,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Central de Cadastros',
                  style: TextStyle(
                    color: CadastroColors.textDark,
                    fontSize: 20,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  loading
                      ? 'Carregando permissões...'
                      : 'Clientes, produtos, serviços e configurações.',
                  style: const TextStyle(
                    color: CadastroColors.textMuted,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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

class _SmallBadge extends StatelessWidget {
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
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool locked;
  final Color color;
  final String? badge;

  const _ModuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.locked = false,
    this.badge,
  });

  const _ModuleCard.skeleton()
    : title = 'Carregando...',
      subtitle = 'Aguarde',
      icon = Icons.more_horiz,
      onTap = null,
      locked = true,
      color = const Color(0xFF7D7A86),
      badge = null;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = locked ? const Color(0xFF8A8791) : color;

    return MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Opacity(
            opacity: locked ? 0.62 : 1,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color:
                      locked
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
                              locked ? Icons.lock_outline_rounded : icon,
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
                              locked
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
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CadastroColors.textDark,
                          fontSize: 15,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CadastroColors.textMuted,
                          fontSize: 12,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (badge != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _SmallBadge(text: badge!, color: effectiveColor),
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
