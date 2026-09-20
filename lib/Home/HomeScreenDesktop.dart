// lib/Home/HomeScreen.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../ui/app_scaffold.dart';
import '../Cadastros/cadastros_menu.dart';
import '../Atividades/atividades_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Financeiro/Financeiro_menu.dart';
import '../Pedidos/PedidosHomeScreen.dart';
import '../Pedidos/CadastroPedidoScreen.dart';
import '../Planos/PlanosScreen.dart';
import '../Planos/PlanService.dart';
import '../Preferencias/PreferenciasScreen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../Insights/InsightsHomeCard.dart';
import '../Catalogo/CatalogoMenuScreen.dart';

// KPIs extras
import '../Financeiro/ContasReceberHomeScreen.dart';
import '../Financeiro/ContasPagarHomeScreen.dart';

// Firestore (KPIs/contadores)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/app_menu_sheet.dart';

// Ajuste o caminho se no seu projeto a pasta estiver com letra maiúscula/minúscula diferente
import '../atividades/ConsultarAjustarEstoqueScreen.dart';

import '../Cadastros/PerfilNegocioScreen.dart';
import '../Login/login_screnn.dart';

// Login providers
import 'package:google_sign_in/google_sign_in.dart';

// Abrir link de criação de índice do Firestore
import 'package:url_launcher/url_launcher_string.dart';

class HomeScreenDesktop extends StatefulWidget {
  const HomeScreenDesktop({super.key});

  @override
  State<HomeScreenDesktop> createState() => _HomeScreenDesktopState();
}

class _HomeScreenDesktopState extends State<HomeScreenDesktop> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

  StreamSubscription<User?>? _authSub;

  bool _initializingScope = false;
  bool _validatingSubscription = false;
  bool _desktopAccessDialogShown = false;

  // ===== ESCOPO MULTIEMPRESA =====
  String? _companyId;
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  bool _isAdmin = false;
  String _currentPlan = 'free';

  // Helpers de escopo para outras consultas (receber/pagar/estoque)
  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';
  bool get _isPremium => _currentPlan == 'premium';
  bool get _isDesktopEnvironment => kIsWeb;

  // 🔐 Permissões
  bool _canRegisterOrders = false;
  bool _canAccountsReceivable = false;
  bool _canAccountsPayable = false;
  bool _canAdjustStock = false;

  // ===== CONTROLE DE PLANO PARA PEDIDOS =====
  bool _loadingOrdersLimit = true;
  int _monthlyOrdersCount = 0;
  int _monthlyOrdersLimit = -1; // -1 = ilimitado
  bool _canCreateOrderByPlan = true;
  String? _ordersPlanError;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScope();
    });

    _authSub = _auth.authStateChanges().listen((_) {
      if (mounted) {
        _initScope();
      }
    });
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _authSub?.cancel();
    super.dispose();
  }

  double _contentMaxWidth(double width) {
    if (width >= 1400) return 1320;
    if (width >= 1100) return 1320;
    if (width >= 900) return 1180;
    return width;
  }

  double _horizontalPadding(double width) {
    if (width >= 1100) return 24;
    if (width >= 700) return 20;
    return 16;
  }

  int _statsColumns(double width) {
    if (width >= 1200) return 4;
    if (width >= 700) return 2;
    return 2;
  }

  double _statsAspectRatio(double width) {
    if (width >= 1200) return 2.25;
    if (width >= 900) return 2.0;
    if (width >= 700) return 1.85;
    if (width < 360) return 1.55;
    return 1.75;
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

  SliverToBoxAdapter _centeredSliver(Widget child, double maxWidth) {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }

  void _checkDesktopPremiumAccess() {
    if (!mounted) return;
    if (!_isDesktopEnvironment) return;
    if (_isPremium) return;
    if (_desktopAccessDialogShown) return;

    _desktopAccessDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Versão desktop disponível no Premium'),
              content: const Text(
                'Somente usuários com o plano Premium podem utilizar a versão desktop.\n\n'
                'Para liberar o acesso no computador, faça o upgrade do seu plano no celular.',
              ),
              actions: [
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _forceLogoutAfterDesktopBlock();
                  },
                  child: const Text('Entendi'),
                ),
              ],
            ),
      );
    });
  }

  Future<void> _forceLogoutAfterDesktopBlock() async {
    try {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}

      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível sair. Tente novamente.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    bool went = false;
    try {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      went = true;
    } catch (_) {}

    if (!went) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  void _resetScopeStateForLoggedOut() {
    if (!mounted) return;

    setState(() {
      _loadingScope = false;
      _scopeError = 'Usuário não autenticado.';
      _scopeUserId = null;
      _companyId = null;
      _canRegisterOrders = false;
      _canAccountsReceivable = false;
      _canAccountsPayable = false;
      _canAdjustStock = false;
      _isAdmin = false;
      _currentPlan = 'free';
      _loadingOrdersLimit = false;
      _monthlyOrdersCount = 0;
      _monthlyOrdersLimit = -1;
      _canCreateOrderByPlan = true;
      _ordersPlanError = null;
    });
  }

  Future<void> _refreshSubscriptionFromServer() async {
    final u = _auth.currentUser;
    if (u == null) return;
    if (_validatingSubscription) return;

    try {
      _validatingSubscription = true;

      final userDoc = await _fs.collection('users').doc(u.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};

      final purchaseToken =
          (userData['purchaseToken'] ??
                  userData['subscriptionPurchaseToken'] ??
                  userData['subscriptionToken'] ??
                  '')
              .toString()
              .trim();

      final productId =
          (userData['subscriptionProductId'] ?? userData['productId'] ?? '')
              .toString()
              .trim();

      if (purchaseToken.isEmpty || productId.isEmpty) {
        debugPrint(
          'HOME SUBSCRIPTION - sem purchaseToken/productId salvo, pulando revalidação.',
        );
        return;
      }

      debugPrint(
        'HOME SUBSCRIPTION - revalidando assinatura. uid=${u.uid}, productId=$productId',
      );

      final callable = _functions.httpsCallable('validateGoogleSubscription');

      final result = await callable.call({
        'uid': u.uid,
        'productId': productId,
        'purchaseToken': purchaseToken,
      });

      debugPrint('HOME SUBSCRIPTION - retorno function: ${result.data}');

      try {
        await PlanService.instance.load();
      } catch (e) {
        debugPrint('HOME SUBSCRIPTION - erro ao recarregar PlanService: $e');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'HOME SUBSCRIPTION - erro FirebaseFunctionsException: '
        'code=${e.code}, message=${e.message}, details=${e.details}',
      );
    } catch (e, st) {
      debugPrint('HOME SUBSCRIPTION - erro ao revalidar assinatura: $e');
      debugPrint('$st');
    } finally {
      _validatingSubscription = false;
    }
  }

  Future<void> _initScope() async {
    if (_initializingScope) return;

    _initializingScope = true;

    try {
      final u = _auth.currentUser;

      if (u == null) {
        _resetScopeStateForLoggedOut();
        return;
      }

      if (mounted) {
        setState(() {
          _loadingScope = true;
          _scopeError = null;
        });
      }

      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();

      final permsRaw = me?['permissions'];
      final perms =
          permsRaw is Map<String, dynamic> ? permsRaw : <String, dynamic>{};

      bool p(String k) => (perms[k] ?? false) == true;

      final role = (me?['role'] ?? 'funcionario').toString().toLowerCase();
      final isAdmin = role == 'admin';
      final initialPlan = _extractPlanFromMap(me);

      if (!mounted) return;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid;
        _canRegisterOrders = p('canRegisterOrders');
        _canAccountsReceivable = p('canAccountsReceivable');
        _canAccountsPayable = p('canAccountsPayable');
        _canAdjustStock = p('canAdjustStock');
        _loadingScope = false;
        _scopeError = null;
        _isAdmin = isAdmin;
        _currentPlan =
            PlanService.instance.isLoaded
                ? PlanService.instance.planId
                : initialPlan;
      });

      await _refreshSubscriptionFromServer();

      final refreshedMe = await _loadCurrentUserRecord();
      final refreshedCompanyId =
          (refreshedMe?['companyId'] ?? '').toString().trim();

      final refreshedPermsRaw = refreshedMe?['permissions'];
      final refreshedPerms =
          refreshedPermsRaw is Map<String, dynamic>
              ? refreshedPermsRaw
              : <String, dynamic>{};

      bool rp(String k) => (refreshedPerms[k] ?? false) == true;

      final refreshedRole =
          (refreshedMe?['role'] ?? 'funcionario').toString().toLowerCase();
      final refreshedIsAdmin = refreshedRole == 'admin';
      final refreshedPlan = _extractPlanFromMap(refreshedMe);

      if (!mounted) return;

      setState(() {
        _companyId = refreshedCompanyId.isEmpty ? null : refreshedCompanyId;
        _scopeUserId =
            refreshedCompanyId.isNotEmpty ? refreshedCompanyId : u.uid;
        _canRegisterOrders = rp('canRegisterOrders');
        _canAccountsReceivable = rp('canAccountsReceivable');
        _canAccountsPayable = rp('canAccountsPayable');
        _canAdjustStock = rp('canAdjustStock');
        _isAdmin = refreshedIsAdmin;
        _currentPlan =
            PlanService.instance.isLoaded
                ? PlanService.instance.planId
                : refreshedPlan;
      });

      await _refreshOrdersPlanRules();
      _checkDesktopPremiumAccess();
    } catch (e) {
      debugPrint('HOME - erro em _initScope: $e');

      if (!mounted) return;

      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar empresa/escopo: $e';
        _currentPlan = 'free';
        _loadingOrdersLimit = false;
        _monthlyOrdersCount = 0;
        _monthlyOrdersLimit = -1;
        _canCreateOrderByPlan = true;
        _ordersPlanError = 'Erro ao validar plano: $e';
      });

      _checkDesktopPremiumAccess();
    } finally {
      _initializingScope = false;
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) {
        final data = (byUid.data() ?? {}) as Map<String, dynamic>;
        data['__docId'] = byUid.id;
        return data;
      }
    } catch (e) {
      debugPrint('HOME - erro buscando user por uid: $e');
    }

    final email = (u.email ?? '').toLowerCase().trim();
    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();

        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          d['__docId'] = q.docs.first.id;
          return d;
        }
      } catch (e) {
        debugPrint('HOME - erro buscando user por emailKey: $e');
      }
    }

    return null;
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
                  Navigator.of(context).push(
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
    if (_loadingScope || _loadingOrdersLimit) return;

    if (!_canRegisterOrders) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Sem acesso a Pedidos.')));
      return;
    }

    final ok = await _requireOrderSlot();
    if (!ok) {
      if (!ctx.mounted) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            _monthlyOrdersLimit == -1
                ? 'Seu plano não permite criar pedidos.'
                : 'Você já atingiu o limite de $_monthlyOrdersLimit pedidos do seu plano neste mês.',
          ),
        ),
      );
      return;
    }

    if (!ctx.mounted) return;

    await Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => const CadastroPedidoScreen()));

    await _refreshOrdersPlanRules();
  }

  VoidCallback? _guardTap(bool allowed, VoidCallback action, String feature) {
    return allowed ? action : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Início')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxWidth = _contentMaxWidth(width);
        final hPad = _horizontalPadding(width);
        final statsColumns = _statsColumns(width);
        final statsAspectRatio = _statsAspectRatio(width);

        return AppScaffold(
          title: 'Início',
          body: CustomScrollView(
            slivers: [
              _centeredSliver(
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
                  child: _ResultadoMesCard(
                    scopeUserId: _scopeUserId ?? '',
                    scopeField: _scopeField,
                  ),
                ),
                maxWidth,
              ),

              _centeredSliver(
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
                  child: GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: statsColumns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: statsAspectRatio,
                    ),
                    children: [
                      if (_companyId != null)
                        _PedidosHojeStat(
                          companyId: _companyId!,
                          enabled: _canRegisterOrders,
                          onTap: _guardTap(
                            _canRegisterOrders,
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PedidosHomeScreen(),
                              ),
                            ),
                            'Pedidos',
                          ),
                        )
                      else
                        const _StatCard(
                          title: 'Pedidos hoje',
                          value: '—',
                          icon: Icons.info_outline,
                          disabled: true,
                        ),

                      _AReceberStat(
                        scopeUserId: _scopeUserId ?? '',
                        scopeField: _scopeField,
                        enabled: _canAccountsReceivable && _scopeUserId != null,
                        onTap: _guardTap(
                          _canAccountsReceivable,
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ContasReceberHomeScreen(),
                            ),
                          ),
                          'Contas a Receber',
                        ),
                      ),

                      _ItensEmFaltaStat(
                        scopeUserId: _scopeUserId ?? '',
                        scopeField: _scopeField,
                        enabled: _canAdjustStock && _scopeUserId != null,
                        onTap: _guardTap(
                          _canAdjustStock,
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => const ConsultarAjustarEstoqueScreen(),
                            ),
                          ),
                          'Ajuste de Estoque',
                        ),
                      ),

                      _ContasAPagarStat(
                        scopeUserId: _scopeUserId ?? '',
                        scopeField: _scopeField,
                        enabled: _canAccountsPayable && _scopeUserId != null,
                        onTap: _guardTap(
                          _canAccountsPayable,
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ContasPagarHomeScreen(),
                            ),
                          ),
                          'Contas a Pagar',
                        ),
                      ),
                    ],
                  ),
                ),
                maxWidth,
              ),

              _centeredSliver(
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
                  child: _OrdersSpotlight(
                    loadingPlan: _loadingOrdersLimit,
                    canRegisterOrders: _canRegisterOrders,
                    isOrdersLimitReached: _isOrdersLimitReached,
                    monthlyOrdersCount: _monthlyOrdersCount,
                    monthlyOrdersLimit: _monthlyOrdersLimit,
                    onNewOrder: (ctx) => _openNewOrderGuarded(ctx),
                    onSeeOrders: (ctx) {
                      if (_canRegisterOrders) {
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
                maxWidth,
              ),

              _centeredSliver(
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                  child: InsightsHomeCard(
                    scopeUserId: _scopeUserId ?? '',
                    scopeField: _scopeField,
                  ),
                ),
                maxWidth,
              ),

              if (_ordersPlanError != null)
                _centeredSliver(
                  Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _ordersPlanError!,
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  maxWidth,
                ),
            ],
          ),
          currentIndex: 0,
          onTabSelected: (i) {
            if (i == 0) return;

            if (i == 1) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CadastrosMenuScreen()),
              );
            } else if (i == 2) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AtividadesMenuScreen()),
              );
            } else if (i == 3) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardsMenuScreen()),
              );
            } else if (i == 4) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FinanceiroMenuScreen()),
              );
            }
          },
          onOpenMenu:
              () => AppMenuSheet.show(
                context,
                isAdmin: _isAdmin,
                isPremium: _isPremium,
                companyId: _companyId,
              ),
        );
      },
    );
  }
}

/* ========================== HEADER ========================== */

class _InsightItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _InsightItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}

class _InsightTile extends StatelessWidget {
  final _InsightItem item;

  const _InsightTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: item.color.withOpacity(0.14),
        child: Icon(item.icon, color: item.color),
      ),
      title: Text(
        item.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(item.subtitle),
    );
  }
}

class _ResultadoMesCard extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;

  const _ResultadoMesCard({
    required this.scopeUserId,
    required this.scopeField,
  });

  @override
  Widget build(BuildContext context) {
    if (scopeUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();

    final inicioMes = DateTime(now.year, now.month, 1);
    final inicioProximoMes =
        now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);

    final q = fs
        .collection('pedidos')
        .where(scopeField, isEqualTo: scopeUserId)
        .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
        .where('data', isLessThan: Timestamp.fromDate(inicioProximoMes));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        double faturamento = 0.0;
        double custo = 0.0;
        double lucro = 0.0;
        int pedidos = 0;

        String produtoDestaque = '';
        double produtoDestaqueLucro = 0.0;

        if (snap.hasData) {
          pedidos = snap.data!.docs.length;

          for (final doc in snap.data!.docs) {
            final m = doc.data();

            faturamento += _toDouble(m['subtotal']);
            custo += _toDouble(m['custoTotal']);
            lucro += _toDouble(m['lucroLiquido']);

            final itensProdutos = (m['itensProdutos'] ?? []) as List;

            for (final itemRaw in itensProdutos) {
              final item = Map<String, dynamic>.from(itemRaw as Map);

              final nome = (item['nome'] ?? '').toString();
              final lucroItem = _toDouble(item['lucroItem']);

              if (nome.isNotEmpty && lucroItem > produtoDestaqueLucro) {
                produtoDestaqueLucro = lucroItem;
                produtoDestaque = nome;
              }
            }
          }
        }

        final margem = faturamento <= 0 ? 0.0 : (lucro / faturamento) * 100.0;

        final diasPassados = now.day;
        final totalDiasMes = DateTime(now.year, now.month + 1, 0).day;

        final faturamentoPrevisto =
            diasPassados > 0
                ? (faturamento / diasPassados) * totalDiasMes
                : 0.0;

        final lucroPrevisto =
            diasPassados > 0 ? (lucro / diasPassados) * totalDiasMes : 0.0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.secondaryContainer,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resultado do mês',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Acompanhe faturamento, custo, lucro e previsões do seu negócio.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    title: 'Faturamento',
                    value: _fmtMoedaHome(faturamento),
                    icon: Icons.payments_outlined,
                    color: Colors.blue,
                  ),
                  _MetricCard(
                    title: 'Custo',
                    value: _fmtMoedaHome(custo),
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.orange,
                  ),
                  _MetricCard(
                    title: 'Lucro',
                    value: _fmtMoedaHome(lucro),
                    icon: Icons.trending_up_outlined,
                    color: lucro >= 0 ? Colors.green : Colors.red,
                  ),
                  _MetricCard(
                    title: 'Margem',
                    value: '${margem.toStringAsFixed(1).replaceAll('.', ',')}%',
                    icon: Icons.percent_outlined,
                    color: Colors.purple,
                  ),
                  _MetricCard(
                    title: 'Pedidos',
                    value: '$pedidos',
                    icon: Icons.receipt_long_outlined,
                    color: Colors.indigo,
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    title: 'Prev. faturamento',
                    value: _fmtMoedaHome(faturamentoPrevisto),
                    icon: Icons.insights_outlined,
                    color: Colors.blueAccent,
                  ),
                  _MetricCard(
                    title: 'Prev. lucro',
                    value: _fmtMoedaHome(lucroPrevisto),
                    icon: Icons.show_chart_outlined,
                    color: lucroPrevisto >= 0 ? Colors.green : Colors.red,
                  ),
                  if (produtoDestaque.isNotEmpty)
                    _MetricCard(
                      title: 'Produto destaque',
                      value: produtoDestaque,
                      icon: Icons.star_outline,
                      color: Colors.amber,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
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

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

String _fmtMoedaHome(num v) {
  final sinal = v < 0 ? '-' : '';
  final vv = v.abs();
  final s = vv.toStringAsFixed(2);
  final p = s.split('.');
  final inteiro = p[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '${sinal}R\$ $inteiro,${p[1]}';
}

class _TrainingsSpotlight extends StatefulWidget {
  final void Function(BuildContext) onOpen;

  const _TrainingsSpotlight({required this.onOpen});

  @override
  State<_TrainingsSpotlight> createState() => _TrainingsSpotlightState();
}

class _TrainingsSpotlightState extends State<_TrainingsSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) {
        final t = _ac.value;

        final g1 = Color.lerp(cs.tertiaryContainer, cs.primaryContainer, t)!;
        final g2 = Color.lerp(
          cs.secondaryContainer.withOpacity(0.85),
          cs.tertiary.withOpacity(0.85),
          t,
        )!.withOpacity(0.85);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [g1, g2],
              begin: const Alignment(-0.9, -1.0),
              end: const Alignment(0.8, 1.0),
            ),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surface.withOpacity(0.18),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.surface.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: const Icon(Icons.school_outlined, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final narrow = c.maxWidth < 360;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Treinamentos',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Aprenda vendas, estoque e financeiro com aulas rápidas e práticas.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            if (narrow)
                              FilledButton.icon(
                                onPressed: () => widget.onOpen(context),
                                icon: const Icon(Icons.play_circle_outline),
                                label: const Text(
                                  'Acessar treinamentos',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => widget.onOpen(context),
                                      icon: const Icon(
                                        Icons.play_circle_outline,
                                      ),
                                      label: const Text(
                                        'Acessar treinamentos',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Em breve: trilhas e certificados.',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.info_outline),
                                    label: const Text('Como funciona'),
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroHeaderSimple extends StatelessWidget {
  const _HeroHeaderSimple();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        8,
        isDesktop ? 24 : 16,
        8,
      ),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        isDesktop ? 24 : 18,
        isDesktop ? 24 : 16,
        isDesktop ? 24 : 18,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            cs.primary.withOpacity(0.10),
            cs.secondary.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bem-vindo 👋',
            style: (isDesktop
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Organize seus pedidos, finanças e estoque em um só lugar. V46 desktop',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/* ========================== KPIs (com Firestore + ESCOPO) ========================== */

class _PedidosHojeStat extends StatelessWidget {
  final String companyId;
  final bool enabled;
  final VoidCallback? onTap;

  const _PedidosHojeStat({
    required this.companyId,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final tomorrow = start.add(const Duration(days: 1));

    final q = fs
        .collection('pedidos')
        .where('companyId', isEqualTo: companyId)
        .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('data', isLessThan: Timestamp.fromDate(tomorrow));

    if (!enabled) {
      return const _StatCard(
        title: 'Pedidos hoje',
        value: '—',
        icon: Icons.lock_outline,
        disabled: true,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const _StatCard(
            title: 'Pedidos hoje',
            value: '…',
            icon: Icons.hourglass_empty,
          );
        }

        if (s.hasError) {
          String? indexUrl;
          const friendly =
              'Sua consulta requer um índice composto (companyId ==, data por intervalo).';

          final err = s.error;
          if (err is FirebaseException) {
            final msg = err.message ?? '';
            final m = RegExp(r'https?://[^\s)]+').firstMatch(msg);
            if (m != null) {
              indexUrl = m.group(0);
            }
          }

          return _IndexHintCard(
            title: 'Pedidos hoje',
            message: friendly,
            indexUrl: indexUrl,
          );
        }

        final total = (s.data?.docs.length ?? 0).toString();
        return _StatCard(
          title: 'Pedidos hoje',
          value: total,
          icon: Icons.today,
          onTap: onTap,
        );
      },
    );
  }
}

class _AReceberStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const _AReceberStat({
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final q = fs
        .collection('contas_receber')
        .where(scopeField, isEqualTo: scopeUserId);

    return StreamBuilder<QuerySnapshot>(
      stream: enabled ? q.snapshots() : const Stream.empty(),
      builder: (context, s) {
        double soma = 0.0;

        if (enabled && s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data() as Map<String, dynamic>;
            final status = (m['status'] ?? '').toString().toLowerCase();
            if (status == 'pago' || status == 'cancelado') continue;

            final valor = (m['valor'] as num?)?.toDouble() ?? 0.0;
            final valorPago = (m['valorPago'] as num?)?.toDouble() ?? 0.0;
            final saldo = valor - valorPago;
            if (saldo > 0) soma += saldo;
          }
        }

        return _StatCard(
          title: 'A receber',
          value: enabled ? _fmt(soma) : 'R\$ —',
          icon: enabled ? Icons.payments_outlined : Icons.lock_outline,
          onTap: onTap,
          disabled: !enabled,
        );
      },
    );
  }
}

class _ItensEmFaltaStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const _ItensEmFaltaStat({
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final q = fs
        .collection('produtos')
        .where(scopeField, isEqualTo: scopeUserId)
        .where('controlaEstoque', isEqualTo: true);

    return StreamBuilder<QuerySnapshot>(
      stream: enabled ? q.snapshots() : const Stream.empty(),
      builder: (context, s) {
        int faltando = 0;

        if (enabled && s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data() as Map<String, dynamic>;
            final estoque = (m['estoque'] as num?)?.toDouble() ?? 0.0;
            final min =
                (m['estoqueMin'] as num?)?.toDouble() ??
                (m['estoqueAlerta'] as num?)?.toDouble() ??
                0.0;

            if (min > 0 ? estoque < min : estoque <= 0) {
              faltando++;
            }
          }
        }

        return _StatCard(
          title: 'Itens em falta',
          value: enabled ? '$faltando' : '—',
          icon: enabled ? Icons.inventory_2_outlined : Icons.lock_outline,
          onTap: onTap,
          disabled: !enabled,
        );
      },
    );
  }
}

class _ContasAPagarStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const _ContasAPagarStat({
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final q = fs
        .collection('contas_pagar')
        .where(scopeField, isEqualTo: scopeUserId);

    if (!enabled) {
      return const _StatCard(
        title: 'Contas a pagar',
        value: 'R\$ —',
        icon: Icons.lock_outline,
        disabled: true,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, s) {
        double soma = 0.0;

        if (s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data();
            final status = (m['status'] ?? '').toString().toLowerCase();
            if (status == 'pago' || status == 'cancelado') continue;

            final valor = (m['valor'] as num?)?.toDouble() ?? 0.0;
            final valorPago = (m['valorPago'] as num?)?.toDouble() ?? 0.0;
            final saldo = valor - valorPago;
            if (saldo > 0) soma += saldo;
          }
        }

        return _StatCard(
          title: 'A pagar',
          value: _fmt(soma),
          icon: Icons.receipt_long_outlined,
          onTap: onTap,
        );
      },
    );
  }
}

/* ========================== SPOTLIGHT PEDIDOS ========================== */

class _OrdersSpotlight extends StatefulWidget {
  final void Function(BuildContext) onNewOrder;
  final void Function(BuildContext) onSeeOrders;
  final bool loadingPlan;
  final bool canRegisterOrders;
  final bool isOrdersLimitReached;
  final int monthlyOrdersCount;
  final int monthlyOrdersLimit;

  const _OrdersSpotlight({
    required this.onNewOrder,
    required this.onSeeOrders,
    required this.loadingPlan,
    required this.canRegisterOrders,
    required this.isOrdersLimitReached,
    required this.monthlyOrdersCount,
    required this.monthlyOrdersLimit,
  });

  @override
  State<_OrdersSpotlight> createState() => _OrdersSpotlightState();
}

class _OrdersSpotlightState extends State<_OrdersSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pedidoLocked =
        !widget.canRegisterOrders || widget.isOrdersLimitReached;

    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) {
        final t = _ac.value;
        final g1 = Color.lerp(cs.primaryContainer, cs.tertiaryContainer, t)!;
        final g2 = Color.lerp(
          cs.secondaryContainer.withOpacity(0.9),
          cs.primary,
          t,
        )!.withOpacity(0.82);

        final String subtitle;
        if (widget.loadingPlan) {
          subtitle = 'Verificando limite do plano...';
        } else if (!widget.canRegisterOrders) {
          subtitle = 'Sem acesso a Pedidos.';
        } else if (widget.isOrdersLimitReached &&
            widget.monthlyOrdersLimit != -1) {
          subtitle =
              '${widget.monthlyOrdersCount}/${widget.monthlyOrdersLimit} pedidos utilizados este mês.';
        } else {
          subtitle = 'Crie, edite e acompanhe o status em tempo real.';
        }

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [g1, g2],
              begin: const Alignment(-0.9, -1.0),
              end: const Alignment(0.8, 1.0),
            ),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surface.withOpacity(0.18),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.surface.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: Icon(
                      pedidoLocked
                          ? Icons.lock_outline
                          : Icons.assignment_turned_in_outlined,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final narrow = c.maxWidth < 360;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gerencie seus pedidos',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            if (narrow)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FilledButton.icon(
                                    onPressed:
                                        widget.loadingPlan
                                            ? null
                                            : () => widget.onNewOrder(context),
                                    icon: Icon(
                                      pedidoLocked
                                          ? Icons.lock_outline
                                          : Icons.add,
                                    ),
                                    label: Text(
                                      pedidoLocked
                                          ? 'Limite atingido'
                                          : 'Novo pedido',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        () => widget.onSeeOrders(context),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                    ),
                                    label: const Text('Ver pedidos'),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed:
                                          widget.loadingPlan
                                              ? null
                                              : () =>
                                                  widget.onNewOrder(context),
                                      icon: Icon(
                                        pedidoLocked
                                            ? Icons.lock_outline
                                            : Icons.add,
                                      ),
                                      label: Text(
                                        pedidoLocked
                                            ? 'Limite atingido'
                                            : 'Novo pedido',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          () => widget.onSeeOrders(context),
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                      ),
                                      label: const Text('Ver pedidos'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/* ========================== UI de Cards/elementos ========================== */

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabledText = cs.onSurface.withOpacity(0.5);
    final disabledBorder = cs.outlineVariant.withOpacity(0.6);

    final card = Semantics(
      button: true,
      enabled: !disabled,
      label: title,
      hint: disabled ? 'Sem permissão' : null,
      child: Opacity(
        opacity: disabled ? 0.55 : 1.0,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: disabled ? cs.surface.withOpacity(0.9) : cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: disabled ? disabledBorder : cs.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: disabled ? cs.surfaceVariant : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: disabled ? disabledText : cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: disabled ? disabledText : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: disabled ? disabledText : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (disabled)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Sem permissão',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(Icons.lock, size: 18, color: disabledText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: disabled ? null : onTap,
      enableFeedback: !disabled,
      child: card,
    );
  }
}

/* ========================== Card de índice ========================== */

class _IndexHintCard extends StatelessWidget {
  final String title;
  final String message;
  final String? indexUrl;

  const _IndexHintCard({
    required this.title,
    required this.message,
    this.indexUrl,
  });

  Future<void> _open(String url) async {
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatCard(
          title: title,
          value: '—',
          icon: Icons.error_outline,
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              if (indexUrl != null)
                FilledButton.icon(
                  onPressed: () => _open(indexUrl!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Criar índice no Firebase Console'),
                )
              else
                const Text(
                  'Abra o Log/Console do Firestore para obter o link automático do índice.',
                ),
            ],
          ),
        ),
      ],
    );
  }
}
