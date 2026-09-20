import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

import '../Planos/PlanService.dart';
import '../Planos/UsersPlansScreen.dart';

class PlanosScreen extends StatefulWidget {
  const PlanosScreen({super.key});

  @override
  State<PlanosScreen> createState() => _PlanosScreenState();
}

class _PlanosScreenState extends State<PlanosScreen> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  StreamSubscription<User?>? _authSub;

  bool _storeAvailable = false;
  bool _loading = true;
  bool _purchaseInProgress = false;
  bool _authReady = false;
  bool _desktopPurchaseAlertShown = false;

  double _getProductPrice(String productId) {
    for (final p in _products) {
      if (p.id == productId) {
        final price = p.rawPrice;
        return price;
      }
    }
    return 0.0;
  }

  User? _currentUser;

  List<ProductDetails> _products = <ProductDetails>[];
  List<Map<String, dynamic>> _plans = <Map<String, dynamic>>[];

  final Set<String> _processingPurchases = <String>{};

  String _billingDebugMessage = '';
  String _storeStatusMessage = '';

  @override
  void initState() {
    super.initState();
    debugPrint('PLANOS initState - iniciou');
    _listenAuth();
    _initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showDesktopPurchaseAlertIfNeeded();
    });
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isDesktopEnvironment => kIsWeb;

  void _showDesktopPurchaseAlertIfNeeded() {
    if (!mounted) return;
    if (!_isDesktopEnvironment) return;
    if (_desktopPurchaseAlertShown) return;

    _desktopPurchaseAlertShown = true;

    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Compras pelo celular'),
            content: const Text(
              'As compras de planos devem ser feitas pelo aplicativo no celular.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendi'),
              ),
            ],
          ),
    );
  }

  void _listenAuth() {
    _currentUser = _auth.currentUser;
    _authReady = true;

    debugPrint(
      'PLANOS AUTH INIT - currentUser inicial: ${_currentUser?.uid ?? "null"}',
    );

    _authSub = _auth.authStateChanges().listen((user) {
      debugPrint(
        'PLANOS AUTH CHANGE - stream user: ${user?.uid ?? "null"} / email: ${user?.email ?? "-"}',
      );
      debugPrint(
        'PLANOS AUTH CHANGE - auth.currentUser: ${_auth.currentUser?.uid ?? "null"} / email: ${_auth.currentUser?.email ?? "-"}',
      );

      if (!mounted) {
        _currentUser = user;
        _authReady = true;
        return;
      }

      setState(() {
        _currentUser = user;
        _authReady = true;
      });
    });
  }

  Future<void> _refreshPlanBeforeExit() async {
    debugPrint('PLANOS SAIDA - iniciando atualização');

    try {
      await PlanService.instance.reload();

      debugPrint(
        'PLANOS SAIDA - '
        'planId=${PlanService.instance.planId} / '
        'status=${PlanService.instance.planStatus} / '
        'premium=${PlanService.instance.isPremiumActive}',
      );
    } catch (e, st) {
      debugPrint('PLANOS SAIDA - erro: $e');
      debugPrint('$st');
    }
  }

  Future<void> _logSubscriptionPurchase({
    required PurchaseDetails purchase,
  }) async {
    final price = _getProductPrice(purchase.productID);

    // Firebase Analytics
    try {
      await _analytics.logEvent(
        name: 'subscribe_plan',
        parameters: {
          'product_id': purchase.productID,
          'value': price,
          'currency': 'BRL',
          'billing_cycle': 'monthly',
        },
      );

      debugPrint(
        '✅ Firebase: subscribe enviado '
        'product=${purchase.productID} value=$price',
      );
    } catch (e) {
      debugPrint('⚠️ Firebase subscribe: $e');
    }

    // Meta
    try {
      await _facebookAppEvents.logEvent(
        name: 'subscribe_plan',
        parameters: {
          'product_id': purchase.productID,
          'value': price,
          'currency': 'BRL',
          'billing_cycle': 'monthly',
        },
      );

      await _facebookAppEvents.flush();

      debugPrint(
        '✅ Meta: subscribe enviado '
        'product=${purchase.productID} value=$price',
      );
    } catch (e) {
      debugPrint('⚠️ Meta subscribe: $e');
    }
  }

  Future<User?> _waitForAuthenticatedUser({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    User? user = _currentUser ?? _auth.currentUser;
    if (user != null) {
      debugPrint('PLANOS AUTH WAIT - usuário já disponível: ${user.uid}');
      return user;
    }

    debugPrint('PLANOS AUTH WAIT - aguardando usuário autenticado...');

    final completer = Completer<User?>();

    late final StreamSubscription<User?> sub;
    sub = _auth.authStateChanges().listen((u) {
      if (!completer.isCompleted && u != null) {
        _currentUser = u;
        completer.complete(u);
      }
    });

    try {
      user = await completer.future.timeout(
        timeout,
        onTimeout: () => _currentUser ?? _auth.currentUser,
      );
    } catch (_) {
      user = _currentUser ?? _auth.currentUser;
    } finally {
      await sub.cancel();
    }

    debugPrint(
      'PLANOS AUTH WAIT - resultado: ${user?.uid ?? "null"} / email: ${user?.email ?? "-"}',
    );

    return user;
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _billingDebugMessage = '';
        _storeStatusMessage = '';
      });
    }

    try {
      debugPrint('PLANOS_UI PASSO 0 - aguardando auth');
      final user = await _waitForAuthenticatedUser();

      if (user == null) {
        debugPrint('PLANOS_UI PASSO 0 - usuário não autenticado');
        if (mounted) {
          setState(() {
            _billingDebugMessage =
                'Nenhum usuário autenticado encontrado. Faça login novamente.';
          });
        }
      } else {
        debugPrint('PLANOS_UI PASSO 0 - usuário autenticado: ${user.uid}');
      }

      debugPrint('PLANOS_UI PASSO 1 - refreshPlanState');
      await _refreshPlanState();

      debugPrint('PLANOS_UI PASSO 2 - loadPlansFromFirestore');
      await _loadPlansFromFirestore();

      debugPrint('PLANOS_UI PASSO 3 - initInAppPurchase');
      await _initInAppPurchase();

      if (mounted) {
        setState(() {
          if (_storeAvailable && _products.isNotEmpty) {
            _storeStatusMessage = 'Loja conectada e produtos carregados.';
          } else if (_storeAvailable && _products.isEmpty) {
            _storeStatusMessage =
                'Loja conectada, mas nenhum produto da Play foi retornado.';
          } /*else {
            _storeStatusMessage =
                'Compras no app indisponíveis neste dispositivo.';
          }*/
        });
      }
    } catch (e, st) {
      debugPrint('PLANOS_UI ERRO _initialize: $e');
      debugPrint('$st');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshPlanState() async {
    debugPrint('PLANOS PASSO 2 - refreshPlanState');
    await PlanService.instance.reload();

    debugPrint('PLANOS PASSO 2 - planId: ${PlanService.instance.planId}');
    debugPrint(
      'PLANOS PASSO 2 - planStatus: ${PlanService.instance.planStatus}',
    );
    debugPrint(
      'PLANOS PASSO 2 - billingCycle: ${PlanService.instance.billingCycle}',
    );
    debugPrint('PLANOS PASSO 2 - companyId: ${PlanService.instance.companyId}');
    debugPrint('PLANOS PASSO 2 - userData: ${PlanService.instance.userData}');
    debugPrint(
      'PLANOS PASSO 2 - subscriptionData: ${PlanService.instance.subscriptionData}',
    );

    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;

    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, val) {
        result[key.toString()] = val;
      });
      return result;
    }

    return <String, dynamic>{};
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    return int.tryParse(text);
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return text;
  }

  Future<Map<String, dynamic>> _validatePurchase(
    PurchaseDetails purchase,
  ) async {
    User? user = await _waitForAuthenticatedUser();
    user ??= _currentUser ?? _auth.currentUser;

    if (user == null) {
      debugPrint('PLANOS VALIDAR - usuário nulo ao validar compra');
      throw Exception(
        'Usuário não autenticado para validar a compra. Faça login novamente e tente outra vez.',
      );
    }

    try {
      await user.reload();
    } catch (e) {
      debugPrint('PLANOS VALIDAR - erro no reload do usuário: $e');
    }

    final refreshedUser = _auth.currentUser ?? _currentUser ?? user;

    if (refreshedUser == null) {
      throw Exception(
        'Usuário não autenticado para validar a compra. Faça login novamente e tente outra vez.',
      );
    }

    String? refreshedToken;
    try {
      refreshedToken = await refreshedUser.getIdToken(true);
    } catch (e) {
      debugPrint('PLANOS VALIDAR - erro ao gerar idToken: $e');
    }

    final purchaseToken =
        purchase.verificationData.serverVerificationData.trim();

    debugPrint('PLANOS VALIDAR - uid: ${refreshedUser.uid}');
    debugPrint('PLANOS VALIDAR - email: ${refreshedUser.email}');
    debugPrint(
      'PLANOS VALIDAR - idToken carregado?: ${(refreshedToken ?? '').isEmpty ? "nao" : "sim"}',
    );
    debugPrint('PLANOS VALIDAR - productId: ${purchase.productID}');
    debugPrint('PLANOS VALIDAR - purchaseID: ${purchase.purchaseID}');
    debugPrint(
      'PLANOS VALIDAR - token vazio?: ${purchaseToken.isEmpty ? "sim" : "nao"}',
    );

    if (purchaseToken.isEmpty) {
      throw Exception('Purchase token inválido.');
    }

    final callable = _functions.httpsCallable('validateGoogleSubscription');

    final result = await callable.call({
      'uid': refreshedUser.uid,
      'productId': purchase.productID,
      'purchaseToken': purchaseToken,
    });

    debugPrint('PLANOS VALIDAR - retorno function: ${result.data}');

    final data = result.data;
    if (data is! Map) {
      throw Exception('Retorno inválido da validação da compra.');
    }

    final map = Map<String, dynamic>.from(data);
    if (map['active'] != true) {
      throw Exception('Compra não foi validada corretamente.');
    }
    return map;
  }

  Future<void> _restorePurchases() async {
    debugPrint('PLANOS RESTORE - inicio');
    debugPrint('PLANOS RESTORE - storeAvailable: $_storeAvailable');

    final user = await _waitForAuthenticatedUser();
    if (user == null) {
      _showSnack('Faça login novamente para restaurar suas compras.');
      return;
    }

    if (!_storeAvailable) {
      _showSnack('Compras no app não estão disponíveis neste dispositivo.');
      return;
    }

    try {
      if (mounted) {
        setState(() => _purchaseInProgress = true);
      }

      await user.getIdToken(true);
      await _inAppPurchase.restorePurchases();
      debugPrint('PLANOS RESTORE - restorePurchases executado');

      Future.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;

        if (_processingPurchases.isEmpty) {
          debugPrint('PLANOS RESTORE - sem compras em processamento');
          await _refreshPlanState();
          if (mounted) {
            setState(() => _purchaseInProgress = false);
          }
        } else {
          debugPrint(
            'PLANOS RESTORE - aguardando processamento: $_processingPurchases',
          );
        }
      });
    } catch (e, st) {
      debugPrint('PLANOS RESTORE - erro: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() => _purchaseInProgress = false);
      _showSnack('Erro ao restaurar compras: $e');
    }
  }

  Future<void> _loadPlansFromFirestore() async {
    debugPrint('PLANOS PASSO 3 - loadPlansFromFirestore');

    final snap =
        await _fs.collection('plans').where('active', isEqualTo: true).get();

    debugPrint('PLANOS PASSO 3 - documentos encontrados: ${snap.docs.length}');

    final plans = <Map<String, dynamic>>[];

    for (final d in snap.docs) {
      final raw = Map<String, dynamic>.from(d.data());

      final plan = <String, dynamic>{
        'docId': d.id,
        'id': _asString(raw['id']) ?? d.id,
        'name': _asString(raw['name']) ?? '',
        'description': _asString(raw['description']) ?? '',
        'limits': _asMap(raw['limits']),
        'features': _asMap(raw['features']),
        'labels': _asMap(raw['labels']),
        'prices': _asMap(raw['prices']),
        'productIds': _asMap(raw['productIds']),
        'active': raw['active'] == true,
      };

      plans.add(plan);
    }

    _plans = plans;
  }

  Future<void> _initInAppPurchase() async {
    try {
      if (_isDesktopEnvironment) {
        if (mounted) {
          setState(() => _storeAvailable = false);
        }
        return;
      }

      final available = await _inAppPurchase.isAvailable();
      debugPrint('PLANOS_UI PASSO 3.1 - store available: $available');

      if (mounted) {
        setState(() => _storeAvailable = available);
      }

      if (!available) {
        debugPrint('PLANOS_UI PASSO 3.2 - loja indisponível');
        return;
      }

      await _purchaseSub?.cancel();

      _purchaseSub = _inAppPurchase.purchaseStream.listen(
        (purchases) {
          debugPrint(
            'PLANOS_UI PASSO 3.3 - purchaseStream recebeu ${purchases.length} evento(s)',
          );
          _onPurchaseUpdated(purchases);
        },
        onDone: () {
          _purchaseSub?.cancel();
        },
        onError: (error) {
          debugPrint('PLANOS_UI ERRO purchaseStream: $error');
          if (!mounted) return;
          setState(() {
            _purchaseInProgress = false;
          });
        },
      );

      await _loadStoreProducts();
    } catch (e, st) {
      debugPrint('PLANOS_UI ERRO _initInAppPurchase: $e');
      debugPrint('$st');
    }
  }

  Future<void> _loadStoreProducts() async {
    final ids = _plans.map(_productIdFromPlan).whereType<String>().toSet();

    debugPrint('PLANOS_UI PASSO 4 - ids consultados: $ids');

    if (ids.isEmpty) {
      _products = <ProductDetails>[];
      return;
    }

    final response = await _inAppPurchase.queryProductDetails(ids);

    _products = response.productDetails;

    if (mounted) {
      setState(() {});
    }

    if (response.error != null) {
      debugPrint('PLANOS_UI queryProductDetails error: ${response.error}');
    }

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint(
        'PLANOS_UI produtos não encontrados: ${response.notFoundIDs.join(", ")}',
      );
    }

    if (response.productDetails.isEmpty) {
      debugPrint('PLANOS_UI nenhum produto retornado pela Play');
    }
  }

  void _onPurchaseUpdated(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      debugPrint(
        'PLANOS PURCHASE UPDATE - productId=${purchase.productID} status=${purchase.status} pendingCompletePurchase=${purchase.pendingCompletePurchase}',
      );

      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (mounted) {
            setState(() => _purchaseInProgress = true);
          }
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _verifyAndCompletePurchase(purchase);
          break;

        case PurchaseStatus.error:
          if (mounted) {
            setState(() {
              _purchaseInProgress = false;
              _billingDebugMessage =
                  purchase.error?.message ?? 'Falha ao processar compra.';
            });
            _showSnack(purchase.error?.message ?? 'Falha ao processar compra.');
          }

          if (purchase.pendingCompletePurchase) {
            unawaited(_inAppPurchase.completePurchase(purchase));
          }
          break;

        case PurchaseStatus.canceled:
          if (mounted) {
            setState(() => _purchaseInProgress = false);
            _showSnack('Compra cancelada.');
          }

          if (purchase.pendingCompletePurchase) {
            unawaited(_inAppPurchase.completePurchase(purchase));
          }
          break;
      }
    }
  }

  String _purchaseKey(PurchaseDetails purchase) {
    final purchaseId = (purchase.purchaseID ?? '').trim();
    if (purchaseId.isNotEmpty) {
      return '${purchase.productID}::$purchaseId';
    }

    final token = purchase.verificationData.serverVerificationData.trim();
    if (token.isNotEmpty) {
      return '${purchase.productID}::$token';
    }

    return '${purchase.productID}::fallback';
  }

  Future<void> _verifyAndCompletePurchase(PurchaseDetails purchase) async {
    final key = _purchaseKey(purchase);

    if (_processingPurchases.contains(key)) {
      debugPrint('PLANOS VERIFY - compra já em processamento: $key');
      return;
    }

    _processingPurchases.add(key);

    try {
      if (mounted) {
        setState(() => _purchaseInProgress = true);
      }

      debugPrint('PLANOS VERIFY - iniciando validação: $key');

      final validated = await _validatePurchase(purchase);
      Object? refreshError;
      Object? completionError;
      try {
        await PlanService.instance.reload(forceServer: true);
        final expectedPlan =
            (validated['planId'] ?? validated['plan'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        if (!PlanService.instance.isLoaded ||
            PlanService.instance.planId != expectedPlan ||
            PlanService.instance.companyId != validated['companyId'] ||
            _auth.currentUser?.uid != validated['uid']) {
          throw StateError('O plano validado ainda não foi carregado.');
        }
      } catch (e, st) {
        refreshError = e;
        debugPrint('PLANOS VERIFY - refresh: $e\n$st');
      }
      // Store completion must still be attempted if the UI refresh failed.
      if (purchase.pendingCompletePurchase) {
        try {
          await _inAppPurchase.completePurchase(purchase);
        } catch (e, st) {
          completionError = e;
          debugPrint('PLANOS VERIFY - completion: $e\n$st');
        }
      }
      // Analytics never delays publication of the validated entitlement.
      if (purchase.status == PurchaseStatus.purchased) {
        unawaited(_logSubscriptionPurchase(purchase: purchase));
      }
      if (refreshError != null) throw refreshError;
      if (!mounted) return;
      setState(() => _purchaseInProgress = false);
      _showSnack(
        completionError == null
            ? 'Plano atualizado com sucesso.'
            : 'Plano atualizado. A conclusão na loja ficou pendente.',
      );
    } catch (e, st) {
      debugPrint('PLANOS VERIFY - erro: $e');
      debugPrint('$st');

      String friendlyMessage = 'Erro ao validar/atualizar compra.';

      if (e is FirebaseFunctionsException) {
        switch (e.code.toLowerCase()) {
          case 'unauthenticated':
            friendlyMessage = 'Usuário não autenticado. Faça login novamente.';
            break;
          case 'permission-denied':
            friendlyMessage = 'Permissão negada. Verifique o usuário.';
            break;
          case 'failed-precondition':
            friendlyMessage = 'Erro ao validar compra na Google Play.';
            break;
          default:
            friendlyMessage = e.message ?? friendlyMessage;
        }
      } else {
        friendlyMessage = e.toString();
      }

      if (!mounted) return;

      setState(() {
        _purchaseInProgress = false;
      });

      _showSnack(friendlyMessage);
    } finally {
      _processingPurchases.remove(key);
    }
  }

  String _planIdFromDoc(Map<String, dynamic> plan) {
    final id = (plan['id'] ?? plan['docId'] ?? '').toString().trim();
    return id.toLowerCase();
  }

  String? _productIdFromPlan(Map<String, dynamic> plan) {
    final productIds = _asMap(plan['productIds']);

    final monthly = _asString(productIds['monthly']);
    if (monthly != null) return monthly;

    switch (_planIdFromDoc(plan)) {
      case 'starter':
        return 'starter_mensal';
      case 'premium':
        return 'premium_mensal';
      default:
        return null;
    }
  }

  ProductDetails? _findProductByPlan(Map<String, dynamic> plan) {
    final productId = _productIdFromPlan(plan);
    if (productId == null) return null;

    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Future<GooglePlayPurchaseDetails?> _findOldSubscriptionPurchase() async {
    if (!_isAndroid) {
      debugPrint('PLANOS BUY - não é Android, sem busca de assinatura antiga');
      return null;
    }

    try {
      final addition =
          _inAppPurchase
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();

      final QueryPurchaseDetailsResponse response =
          await addition.queryPastPurchases();

      final currentSub = _asMap(PlanService.instance.subscriptionData);
      final currentProductId = _asString(currentSub['productId']);

      if (currentProductId != null && currentProductId.isNotEmpty) {
        for (final purchase in response.pastPurchases) {
          if (purchase is GooglePlayPurchaseDetails &&
              purchase.productID == currentProductId) {
            return purchase;
          }
        }
      }

      for (final purchase in response.pastPurchases) {
        if (purchase is GooglePlayPurchaseDetails &&
            (purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored)) {
          return purchase;
        }
      }
    } catch (e, st) {
      debugPrint('PLANOS BUY - erro ao consultar compras anteriores: $e');
      debugPrint('$st');
    }

    return null;
  }

  String _planName(Map<String, dynamic> plan) {
    final value = (plan['name'] ?? '').toString().trim();
    if (value.isNotEmpty) return value;

    final planId = _planIdFromDoc(plan);
    switch (planId) {
      case 'free':
        return 'Free';
      case 'starter':
        return 'Starter';
      case 'premium':
        return 'Premium';
      default:
        return planId.toUpperCase();
    }
  }

  String _planDescription(Map<String, dynamic> plan) {
    return (plan['description'] ?? '').toString().trim();
  }

  String? _planBadge(Map<String, dynamic> plan) {
    final labels = _asMap(plan['labels']);
    return _asString(labels['badge']);
  }

  String _planCta(Map<String, dynamic> plan) {
    final labels = _asMap(plan['labels']);
    final cta = _asString(labels['cta']);
    if (cta != null) return cta;

    final planId = _planIdFromDoc(plan);
    if (planId == 'free') return 'Ativar Free';
    return 'Assinar';
  }

  String _priceLabel(Map<String, dynamic> plan, ProductDetails? product) {
    final planId = _planIdFromDoc(plan);
    if (planId == 'free') return 'Grátis';

    if (product != null) return product.price;

    final prices = _asMap(plan['prices']);

    final monthlyAsInt = _asInt(prices['monthly']);
    if (monthlyAsInt != null) {
      return 'R\$ $monthlyAsInt/mês';
    }

    final monthlyAsString = _asString(prices['monthly']);
    if (monthlyAsString != null) {
      return 'R\$ $monthlyAsString/mês';
    }

    return 'Preço indisponível';
  }

  List<String> _highlights(Map<String, dynamic> plan) {
    final limits = _asMap(plan['limits']);
    final features = _asMap(plan['features']);
    final planId = _planIdFromDoc(plan);

    final items = <String>[];

    if (planId == 'premium') {
      items.add('Cursos ilimitados');
    } else {
      items.add('Cursos limitados');
    }

    final maxClients = _asInt(limits['maxClients']);
    if (maxClients != null) {
      items.add(
        maxClients == -1 ? 'Clientes ilimitados' : 'Até $maxClients clientes',
      );
    }

    final maxProducts = _asInt(limits['maxProducts']);
    if (maxProducts != null) {
      items.add(
        maxProducts == -1 ? 'Produtos ilimitados' : 'Até $maxProducts produtos',
      );
    }

    final maxServices = _asInt(limits['maxServices']);
    if (maxServices != null) {
      items.add(
        maxServices == -1 ? 'Serviços ilimitados' : 'Até $maxServices serviços',
      );
    }

    final maxOrders = _asInt(limits['maxOrdersPerMonth']);
    if (maxOrders != null) {
      items.add(
        maxOrders == -1
            ? 'Pedidos ilimitados por mês'
            : 'Até $maxOrders pedidos por mês',
      );
    }

    final maxCompras = _asInt(limits['maxCompras']);
    if (maxCompras != null) {
      items.add(
        maxOrders == -1
            ? 'Compras ilimitados por mês'
            : 'Até $maxCompras compras por mês',
      );
    }

    if (features['canUseStock'] == true) {
      items.add('Controle de estoque');

      // 👇 NOVA REGRA
      if (planId == 'premium') {
        items.add('Acesso no computador');
      }
      if (planId == 'premium') {
        items.add('Catálogo de Produtos Online');
      }
      if (planId == 'premium') {
        items.add('Funcionalidades Exclusivas');
      }
      if (planId == 'premium') {
        items.add('Controle de preço medido dos produtos');
      }
    }

    if (features['canUseFinanceDashboard'] == true) {
      items.add('Dashboards Completo');
    }
    if (features['canUseFinanceDashboard'] == false) {
      items.add('Dashboard Limitado');
    }
    if (features['canUseAccountsPayable'] == true) {
      items.add('Contas a Pagar Ilimitado');
    }
    if (features['canUseAccountsReceivable'] == true) {
      items.add('Contas a Receber Ilimitado');
    }

    if (features['canUseRecurringFinance'] != true) {
      items.add('Cadastro de Contas Fixas');
    }

    if (features['canUseRecurringFinance'] == true) {
      items.add('Automatização de contas mensais');
    }

    if (features['canUseAccountsPayable'] == false) {
      items.add('Contas a Pagar Limitado');
    }
    if (features['canUseAccountsReceivable'] == false) {
      items.add('Contas a Receber Limitado');
    }

    return items.take(20).toList();
  }

  Future<void> _buyPlan(Map<String, dynamic> plan) async {
    if (_isDesktopEnvironment) {
      _showSnack('As compras devem ser feitas pelo aplicativo no celular.');
      return;
    }

    final user = await _waitForAuthenticatedUser();

    if (user == null) {
      _showSnack('Faça login novamente antes de assinar um plano.');
      return;
    }

    final planId = _planIdFromDoc(plan);
    final product = _findProductByPlan(plan);
    await user.getIdToken(true);

    debugPrint('PLANOS BUY - plano: $planId');

    if (product == null) {
      _showSnack('Produto não encontrado para este plano.');
      return;
    }

    if (!_storeAvailable) {
      _showSnack('Compras no app não estão disponíveis neste dispositivo.');
      return;
    }

    if (mounted) {
      setState(() {
        _purchaseInProgress = true;
        _billingDebugMessage = '';
      });
    }

    try {
      PurchaseParam purchaseParam;

      if (_isAndroid) {
        final oldSubscription = await _findOldSubscriptionPurchase();

        if (oldSubscription != null &&
            oldSubscription.productID != product.id) {
          purchaseParam = GooglePlayPurchaseParam(
            productDetails: product,
            changeSubscriptionParam: ChangeSubscriptionParam(
              oldPurchaseDetails: oldSubscription,
              replacementMode: ReplacementMode.withTimeProration,
            ),
          );
        } else {
          purchaseParam = GooglePlayPurchaseParam(productDetails: product);
        }
      } else {
        purchaseParam = PurchaseParam(productDetails: product);
      }

      final started = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!started) {
        throw Exception(
          'A Google Play não iniciou a compra. Verifique se o produto está ativo e disponível para esta conta.',
        );
      }
    } catch (e, st) {
      debugPrint('PLANOS BUY - erro ao iniciar compra: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _purchaseInProgress = false;
        _billingDebugMessage = 'Erro ao iniciar compra: $e';
      });

      _showSnack('Erro ao iniciar compra: $e');
    }
  }

  Future<void> _activateFreePlan() async {
    final user = await _waitForAuthenticatedUser();

    if (user == null) {
      _showSnack('Faça login novamente para ativar o plano Free.');
      return;
    }

    if (mounted) {
      setState(() => _purchaseInProgress = true);
    }

    try {
      await PlanService.instance.setFreePlan();

      if (!mounted) return;

      setState(() => _purchaseInProgress = false);
      await _refreshPlanState();
      _showSnack('Plano Free ativado com sucesso.');
    } catch (e, st) {
      debugPrint('PLANOS FREE - erro: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() => _purchaseInProgress = false);
      _showSnack('Erro ao ativar plano Free: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  bool _isCurrentPlan(Map<String, dynamic> plan) {
    return PlanService.instance.planId == _planIdFromDoc(plan);
  }

  bool _isRecommendedPlan(Map<String, dynamic> plan) {
    return _planIdFromDoc(plan) == 'premium';
  }

  String _footerNote() {
    return 'As assinaturas são renovadas automaticamente até cancelamento na Google Play.';
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Planos',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Escolha o plano ideal para o seu negócio e desbloqueie mais recursos para crescer.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (_isDesktopEnvironment) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withValues(
                  alpha: 0.8,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'As compras de planos devem ser feitas pelo aplicativo no celular.',
                style: TextStyle(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanBadge({
    required String text,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final theme = Theme.of(context);
    final planId = _planIdFromDoc(plan);
    final product = _findProductByPlan(plan);
    final highlights = _highlights(plan);
    final isFree = planId == 'free';
    final isCurrent = _isCurrentPlan(plan);
    final isRecommended = _isRecommendedPlan(plan);
    final canBuyPaid =
        !isFree && _storeAvailable && product != null && !_isDesktopEnvironment;

    final Color borderColor =
        isRecommended
            ? theme.colorScheme.primary
            : isCurrent
            ? theme.colorScheme.secondary
            : theme.colorScheme.outlineVariant;

    final Color backgroundColor =
        isRecommended
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: isRecommended ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isRecommended)
                  _buildPlanBadge(
                    text: 'Mais escolhido',
                    background: theme.colorScheme.primary,
                    foreground: theme.colorScheme.onPrimary,
                  ),
                if (isCurrent)
                  _buildPlanBadge(
                    text: 'Plano atual',
                    background: theme.colorScheme.secondaryContainer,
                    foreground: theme.colorScheme.onSecondaryContainer,
                  ),
                if (!isRecommended && !isCurrent && _planBadge(plan) != null)
                  _buildPlanBadge(
                    text: _planBadge(plan)!,
                    background: theme.colorScheme.surfaceContainerHighest,
                    foreground: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _planName(plan),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _planDescription(plan),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _priceLabel(plan, product),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color:
                    isRecommended
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 18),
            ...highlights.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color:
                          isRecommended
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
            if (_isDesktopEnvironment && !isFree)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Para assinar este plano, utilize o aplicativo no celular.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            /*if (!isFree && !_storeAvailable)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Compras no app indisponíveis neste dispositivo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),*/
            if (!isFree && _storeAvailable && product == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Produto da loja não encontrado para este plano.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _purchaseInProgress
                        ? null
                        : isCurrent
                        ? null
                        : isFree
                        ? _activateFreePlan
                        : canBuyPaid
                        ? () => _buyPlan(plan)
                        : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  isCurrent ? 'Plano atual' : _planCta(plan),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          Text(
            _footerNote(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed:
                _purchaseInProgress || !_storeAvailable || _isDesktopEnvironment
                    ? null
                    : _restorePurchases,
            child: const Text('Restaurar compras'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = [..._plans]..sort((a, b) {
      const order = {'free': 0, 'starter': 2, 'premium': 1};
      final aOrder = order[_planIdFromDoc(a)] ?? 99;
      final bOrder = order[_planIdFromDoc(b)] ?? 99;
      return aOrder.compareTo(bOrder);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        await _refreshPlanBeforeExit();

        if (!context.mounted) return;

        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Planos'),
          centerTitle: true,
          actions: [
            if (_currentUser?.email == 'dani@dani.com')
              IconButton(
                icon: const Icon(Icons.people_alt_outlined),
                tooltip: 'Usuários',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UsersPlansScreen()),
                  );
                },
              ),
          ],
        ),
        body: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child:
                          plans.isEmpty
                              ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Nenhum plano ativo encontrado.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                              : ListView(
                                padding: const EdgeInsets.only(bottom: 8),
                                children: [
                                  ...plans.map(_buildPlanCard),
                                  _buildFooter(),
                                ],
                              ),
                    ),
                  ],
                ),
              ),
            if (_purchaseInProgress)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
