// lib/Home/home_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Financeiro/RecorrenciaFinanceiraService.dart';
import '../Planos/PlanService.dart';

class OrderSlotResult {
  final bool allowed;
  final bool showLimitDialog;
  final String message;
  final String shortMessage;

  const OrderSlotResult({
    required this.allowed,
    required this.showLimitDialog,
    required this.message,
    required this.shortMessage,
  });
}

class HomeController {
  HomeController({required this.onChanged});

  final VoidCallback onChanged;

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

  StreamSubscription<User?>? _authSub;

  bool _initializingScope = false;
  bool _validatingSubscription = false;
  bool _checkingDailyPlanMessage = false;

  String? companyId;
  String? scopeUserId;
  bool loadingScope = true;
  String? scopeError;

  bool isAdmin = false;
  String currentPlan = 'free';

  String displayName = '';
  String userEmail = '';

  bool canRegisterOrders = false;
  bool canAccountsReceivable = false;
  bool canAccountsPayable = false;
  bool canAdjustStock = false;

  bool loadingOrdersLimit = true;
  int monthlyOrdersCount = 0;
  int monthlyOrdersLimit = -1;
  bool canCreateOrderByPlan = true;
  String? ordersPlanError;

  bool loadingHomeSummary = true;
  double monthlyRevenue = 0.0;
  double previousMonthRevenue = 0.0;
  double monthlyRevenueVariation = 0.0;
  int notificationCount = 0;

  bool get isCompanyScope => companyId != null && companyId!.isNotEmpty;

  String get scopeField => isCompanyScope ? 'companyId' : 'userId';

  bool get isPremium => currentPlan == 'premium';

  bool get isOrdersLimitReached =>
      !loadingOrdersLimit &&
      monthlyOrdersLimit != -1 &&
      monthlyOrdersCount >= monthlyOrdersLimit;

  String get headerUserName {
    final name = displayName.trim();

    if (name.isNotEmpty) {
      return name.split(' ').first;
    }

    final email = userEmail.trim();

    if (email.contains('@')) {
      return email.split('@').first;
    }

    return 'Usuário';
  }

  void init() {
    PlanService.instance.addListener(_onPlanChanged);
    Future.microtask(initScope);

    _authSub = _auth.authStateChanges().listen((_) {
      initScope();
    });
  }

  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _authSub?.cancel();
  }

  void _onPlanChanged() {
    final service = PlanService.instance;
    currentPlan = service.isLoaded ? service.planId : 'free';
    if (service.isLoaded) {
      monthlyOrdersLimit = service.getLimit('maxOrdersPerMonth');
      if (!loadingOrdersLimit && ordersPlanError == null) {
        canCreateOrderByPlan =
            monthlyOrdersLimit == -1 || monthlyOrdersCount < monthlyOrdersLimit;
      }
    }
    _notify();
  }

  void _notify() {
    onChanged();
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

  void _resetScopeStateForLoggedOut() {
    loadingScope = false;
    scopeError = 'Usuário não autenticado.';
    scopeUserId = null;
    companyId = null;

    displayName = '';
    userEmail = '';

    canRegisterOrders = false;
    canAccountsReceivable = false;
    canAccountsPayable = false;
    canAdjustStock = false;

    isAdmin = false;
    currentPlan = 'free';

    loadingOrdersLimit = false;
    monthlyOrdersCount = 0;
    monthlyOrdersLimit = -1;
    canCreateOrderByPlan = true;
    ordersPlanError = null;

    loadingHomeSummary = false;
    monthlyRevenue = 0.0;
    previousMonthRevenue = 0.0;
    monthlyRevenueVariation = 0.0;
    notificationCount = 0;

    _notify();
  }

  Future<void> initScope() async {
    if (_initializingScope) return;

    _initializingScope = true;

    try {
      final u = _auth.currentUser;

      if (u == null) {
        _resetScopeStateForLoggedOut();
        return;
      }

      loadingScope = true;
      loadingHomeSummary = true;
      scopeError = null;
      _notify();

      final me = await loadCurrentUserRecord();

      _applyUserData(u, me);

      loadingScope = false;
      scopeError = null;
      _notify();

      await refreshSubscriptionFromServer();

      final refreshedMe = await loadCurrentUserRecord();

      _applyUserData(u, refreshedMe);

      _notify();

      await refreshOrdersPlanRules();
      await refreshHomeSummary();
      await maybeShowDailyFreePlanMessage();

      if (companyId != null && scopeUserId != null) {
        await RecorrenciaFinanceiraService().gerarContasRecorrentesDoMes(
          companyId: companyId!,
          userId: scopeUserId!,
        );
      }
    } catch (e) {
      debugPrint('HOME - erro em initScope: $e');

      loadingScope = false;
      scopeError = 'Erro ao carregar empresa/escopo: $e';
      currentPlan = 'free';

      loadingOrdersLimit = false;
      monthlyOrdersCount = 0;
      monthlyOrdersLimit = -1;
      canCreateOrderByPlan = true;
      ordersPlanError = 'Erro ao validar plano: $e';

      loadingHomeSummary = false;
      monthlyRevenue = 0.0;
      previousMonthRevenue = 0.0;
      monthlyRevenueVariation = 0.0;
      notificationCount = 0;

      _notify();
    } finally {
      _initializingScope = false;
    }
  }

  void _applyUserData(User u, Map<String, dynamic>? me) {
    final loadedCompanyId = (me?['companyId'] ?? '').toString().trim();

    final permsRaw = me?['permissions'];
    final perms =
        permsRaw is Map<String, dynamic> ? permsRaw : <String, dynamic>{};

    bool p(String k) => (perms[k] ?? false) == true;

    final role = (me?['role'] ?? 'funcionario').toString().toLowerCase();

    displayName =
        (me?['displayName'] ??
                me?['nome'] ??
                me?['name'] ??
                u.displayName ??
                '')
            .toString()
            .trim();

    userEmail =
        (me?['email'] ?? me?['emailKey'] ?? u.email ?? '').toString().trim();

    companyId = loadedCompanyId.isEmpty ? null : loadedCompanyId;
    scopeUserId = loadedCompanyId.isNotEmpty ? loadedCompanyId : u.uid;

    canRegisterOrders = p('canRegisterOrders');
    canAccountsReceivable = p('canAccountsReceivable');
    canAccountsPayable = p('canAccountsPayable');
    canAdjustStock = p('canAdjustStock');

    isAdmin = role == 'admin';
    currentPlan =
        PlanService.instance.isLoaded
            ? PlanService.instance.planId
            : _extractPlanFromMap(me);
  }

  Future<Map<String, dynamic>?> loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();

      if (byUid.exists) {
        final data = byUid.data() ?? <String, dynamic>{};
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
          final data = q.docs.first.data();
          data['__docId'] = q.docs.first.id;
          return data;
        }
      } catch (e) {
        debugPrint('HOME - erro buscando user por emailKey: $e');
      }
    }

    return null;
  }

  Future<void> refreshSubscriptionFromServer() async {
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

  Future<int> loadMonthlyOrdersCount() async {
    return PlanService.instance.getCurrentOrdersMonthCount();
  }

  Future<void> refreshOrdersPlanRules() async {
    try {
      loadingOrdersLimit = true;
      ordersPlanError = null;
      _notify();

      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await loadMonthlyOrdersCount();
      final limite = PlanService.instance.getLimit('maxOrdersPerMonth');
      final canCreate = limite == -1 ? true : usados < limite;

      monthlyOrdersCount = usados;
      monthlyOrdersLimit = limite;
      canCreateOrderByPlan = canCreate;
      loadingOrdersLimit = false;
      ordersPlanError = null;

      _notify();
    } catch (e) {
      debugPrint('Erro ao validar plano de pedidos: $e');

      monthlyOrdersCount = 0;
      monthlyOrdersLimit = -1;
      canCreateOrderByPlan = false;
      loadingOrdersLimit = false;
      ordersPlanError = 'Erro ao validar plano: $e';

      _notify();
    }
  }

  Future<OrderSlotResult> requireOrderSlot() async {
    try {
      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await loadMonthlyOrdersCount();
      final limite = PlanService.instance.getLimit('maxOrdersPerMonth');
      final canCreate = limite == -1 ? true : usados < limite;

      monthlyOrdersCount = usados;
      monthlyOrdersLimit = limite;
      canCreateOrderByPlan = canCreate;

      _notify();

      if (canCreate) {
        return const OrderSlotResult(
          allowed: true,
          showLimitDialog: false,
          message: '',
          shortMessage: '',
        );
      }

      final message =
          limite == -1
              ? 'Seu plano não permite esta ação.'
              : 'Você já atingiu o limite de pedidos do seu plano atual neste mês.\n\n'
                  'Pedidos usados: $usados\n'
                  'Limite do plano: $limite\n\n'
                  'Faça upgrade para continuar cadastrando pedidos.';

      final shortMessage =
          limite == -1
              ? 'Seu plano não permite criar pedidos.'
              : 'Você já atingiu o limite de $limite pedidos do seu plano neste mês.';

      return OrderSlotResult(
        allowed: false,
        showLimitDialog: true,
        message: message,
        shortMessage: shortMessage,
      );
    } catch (e) {
      return OrderSlotResult(
        allowed: false,
        showLimitDialog: false,
        message: 'Erro ao validar plano de pedidos: $e',
        shortMessage: 'Erro ao validar plano de pedidos: $e',
      );
    }
  }

  Future<void> refreshHomeSummary() async {
    try {
      loadingHomeSummary = true;
      _notify();

      final now = DateTime.now();

      final startOfMonth = DateTime(now.year, now.month, 1);
      final startOfNextMonth =
          now.month == 12
              ? DateTime(now.year + 1, 1, 1)
              : DateTime(now.year, now.month + 1, 1);

      final startOfPreviousMonth =
          now.month == 1
              ? DateTime(now.year - 1, 12, 1)
              : DateTime(now.year, now.month - 1, 1);

      final revenueThisMonth = await _loadRevenueBetween(
        start: startOfMonth,
        end: startOfNextMonth,
      );

      final revenuePreviousMonth = await _loadRevenueBetween(
        start: startOfPreviousMonth,
        end: startOfMonth,
      );

      monthlyRevenue = revenueThisMonth;
      previousMonthRevenue = revenuePreviousMonth;

      if (revenuePreviousMonth <= 0 && revenueThisMonth > 0) {
        monthlyRevenueVariation = 100;
      } else if (revenuePreviousMonth <= 0) {
        monthlyRevenueVariation = 0;
      } else {
        monthlyRevenueVariation =
            ((revenueThisMonth - revenuePreviousMonth) / revenuePreviousMonth) *
            100;
      }

      notificationCount = await _loadNotificationCount();

      loadingHomeSummary = false;
      _notify();
    } catch (e) {
      debugPrint('Erro ao carregar resumo da home: $e');

      loadingHomeSummary = false;
      monthlyRevenue = 0.0;
      previousMonthRevenue = 0.0;
      monthlyRevenueVariation = 0.0;
      notificationCount = 0;

      _notify();
    }
  }

  Future<double> _loadRevenueBetween({
    required DateTime start,
    required DateTime end,
  }) async {
    final u = _auth.currentUser;
    if (u == null) return 0.0;

    try {
      Query<Map<String, dynamic>> query = _fs
          .collection('pedidos')
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data', isLessThan: Timestamp.fromDate(end));

      if ((companyId ?? '').isNotEmpty) {
        query = query.where('companyId', isEqualTo: companyId);
      } else {
        query = query.where('userId', isEqualTo: u.uid);
      }

      final snap = await query.get();

      double total = 0.0;

      for (final doc in snap.docs) {
        final data = doc.data();

        final status = (data['status'] ?? '').toString().toLowerCase();

        if (status == 'cancelado' || status == 'cancelada') {
          continue;
        }

        total += _extractOrderRevenue(data);
      }

      return total;
    } catch (e) {
      debugPrint('Erro ao carregar faturamento: $e');
      return 0.0;
    }
  }

  double _extractOrderRevenue(Map<String, dynamic> data) {
    final possibleFields = [
      'valorTotal',
      'totalPedido',
      'valorPedido',
      'totalGeral',
      'total',
      'valorLiquido',
      'totalLiquido',
    ];

    for (final field in possibleFields) {
      final value = data[field];

      if (value is num) {
        return value.toDouble();
      }

      if (value is String) {
        final parsed = _parseMoney(value);

        if (parsed > 0) return parsed;
      }
    }

    final produtos = data['itensProdutos'];
    final servicos = data['itensServicos'];

    double total = 0.0;

    if (produtos is List) {
      for (final item in produtos) {
        if (item is Map) {
          total += _extractItemTotal(item);
        }
      }
    }

    if (servicos is List) {
      for (final item in servicos) {
        if (item is Map) {
          total += _extractItemTotal(item);
        }
      }
    }

    return total;
  }

  double _extractItemTotal(Map item) {
    final total =
        item['total'] ??
        item['valorTotal'] ??
        item['subtotal'] ??
        item['valorSubtotal'];

    if (total is num) return total.toDouble();

    final quantidade =
        (item['quantidade'] as num?)?.toDouble() ??
        (item['qtd'] as num?)?.toDouble() ??
        1.0;

    final valorUnitario =
        (item['valorUnitario'] as num?)?.toDouble() ??
        (item['preco'] as num?)?.toDouble() ??
        (item['valor'] as num?)?.toDouble() ??
        0.0;

    return quantidade * valorUnitario;
  }

  double _parseMoney(String raw) {
    final cleaned =
        raw
            .replaceAll('R\$', '')
            .replaceAll(' ', '')
            .replaceAll('.', '')
            .replaceAll(',', '.')
            .trim();

    return double.tryParse(cleaned) ?? 0.0;
  }

  Future<int> _loadNotificationCount() async {
    int count = 0;

    count += await _countOverdueAccountsPayable();
    count += await _countOverdueAccountsReceivable();
    count += await _countLowStockProducts();

    if (count > 99) return 99;

    return count;
  }

  Future<int> _countOverdueAccountsPayable() async {
    if (!canAccountsPayable || scopeUserId == null) return 0;

    try {
      final today = DateTime.now();
      final endOfToday = DateTime(today.year, today.month, today.day + 1);

      final q =
          await _fs
              .collection('contas_pagar')
              .where(scopeField, isEqualTo: scopeUserId)
              .where(
                'dataVencimento',
                isLessThan: Timestamp.fromDate(endOfToday),
              )
              .get();

      int count = 0;

      for (final d in q.docs) {
        final m = d.data();

        final status = (m['status'] ?? '').toString().toLowerCase();

        if (status == 'pago' || status == 'cancelado') continue;

        count++;
      }

      return count;
    } catch (e) {
      debugPrint('Erro ao contar contas a pagar vencidas: $e');
      return 0;
    }
  }

  Future<int> _countOverdueAccountsReceivable() async {
    if (!canAccountsReceivable || scopeUserId == null) return 0;

    try {
      final today = DateTime.now();
      final endOfToday = DateTime(today.year, today.month, today.day + 1);

      final q =
          await _fs
              .collection('contas_receber')
              .where(scopeField, isEqualTo: scopeUserId)
              .where(
                'dataVencimento',
                isLessThan: Timestamp.fromDate(endOfToday),
              )
              .get();

      int count = 0;

      for (final d in q.docs) {
        final m = d.data();

        final status = (m['status'] ?? '').toString().toLowerCase();

        if (status == 'pago' || status == 'cancelado') continue;

        count++;
      }

      return count;
    } catch (e) {
      debugPrint('Erro ao contar contas a receber vencidas: $e');
      return 0;
    }
  }

  Future<int> _countLowStockProducts() async {
    if (!canAdjustStock || scopeUserId == null) return 0;

    try {
      final q =
          await _fs
              .collection('produtos')
              .where(scopeField, isEqualTo: scopeUserId)
              .where('controlaEstoque', isEqualTo: true)
              .get();

      int count = 0;

      for (final d in q.docs) {
        final m = d.data();

        final estoque = (m['estoque'] as num?)?.toDouble() ?? 0.0;

        final min =
            (m['estoqueMin'] as num?)?.toDouble() ??
            (m['estoqueAlerta'] as num?)?.toDouble() ??
            0.0;

        if (min > 0 ? estoque < min : estoque <= 0) {
          count++;
        }
      }

      return count;
    } catch (e) {
      debugPrint('Erro ao contar itens em falta: $e');
      return 0;
    }
  }

  Future<void> maybeShowDailyFreePlanMessage() async {
    if (_checkingDailyPlanMessage) return;

    final user = _auth.currentUser;
    if (user == null) return;

    if (currentPlan != 'free') return;

    _checkingDailyPlanMessage = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final firstAccessKey = 'home_first_access_${user.uid}';
      final lastShowKey = 'home_last_free_plan_message_${user.uid}';

      final firstAccessDate = prefs.getString(firstAccessKey);
      final lastShowDate = prefs.getString(lastShowKey);

      if (firstAccessDate == null || firstAccessDate.isEmpty) {
        await prefs.setString(firstAccessKey, todayKey);
        return;
      }

      if (lastShowDate == todayKey) {
        return;
      }

      await prefs.setString(lastShowKey, todayKey);
    } finally {
      _checkingDailyPlanMessage = false;
    }
  }

  Future<void> shareComputerAccess(BuildContext context) async {
    try {
      final user = _auth.currentUser;
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
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao compartilhar: $e')));
    }
  }
}
