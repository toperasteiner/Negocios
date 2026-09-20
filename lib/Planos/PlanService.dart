// lib/Planos/PlanService.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PlanService extends ChangeNotifier {
  PlanService._()
    : this._withDependencies(FirebaseAuth.instance, FirebaseFirestore.instance);

  @visibleForTesting
  PlanService.forTesting({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : this._withDependencies(auth, firestore);

  PlanService._withDependencies(this._auth, this._fs) {
    _sessionUid = _auth.currentUser?.uid;
    _authSub = _auth.authStateChanges().listen((user) {
      if (_sessionUid == user?.uid) return;
      _sessionUid = user?.uid;
      _loadGeneration++;
      _loadFuture = null;
      _reset();
      notifyListeners();
    });
  }

  static final PlanService instance = PlanService._();

  final FirebaseAuth _auth;
  final FirebaseFirestore _fs;
  late final StreamSubscription<User?> _authSub;

  @override
  void dispose() {
    _loadGeneration++;
    _authSub.cancel();
    super.dispose();
  }

  Map<String, dynamic> _userData = {};
  Map<String, dynamic> _subscriptionData = {};
  Map<String, dynamic> _planData = {};
  Map<String, dynamic> _limits = {};
  Map<String, dynamic> _features = {};

  String _planId = 'free';
  String _planStatus = 'active';
  String _billingCycle = '';
  String? _companyId;

  bool _loaded = false;
  String? _sessionUid;
  Future<void>? _loadFuture;
  int _loadGeneration = 0;

  static const String usersCollection = 'users';
  static const String plansCollection = 'plans';
  static const String subscriptionsCollection = 'subscriptions';

  static const String clientsCollection = 'clientes';
  static const String suppliersCollection = 'clientes';
  static const String productsCollection = 'produtos';
  static const String servicesCollection = 'servicos';
  static const String goalsCollection = 'goals';
  static const String ordersCollection = 'pedidos';

  static const String companyIdField = 'companyId';
  static const String createdAtField = 'createdAt';

  bool get isLoaded => _loaded;
  String get planId => _planId;
  String get planStatus => _planStatus;
  String get billingCycle => _billingCycle;
  String? get companyId => _companyId;

  Map<String, dynamic> get userData => Map<String, dynamic>.from(_userData);
  Map<String, dynamic> get subscriptionData =>
      Map<String, dynamic>.from(_subscriptionData);
  Map<String, dynamic> get planData => Map<String, dynamic>.from(_planData);
  Map<String, dynamic> get limits => Map<String, dynamic>.from(_limits);
  Map<String, dynamic> get features => Map<String, dynamic>.from(_features);

  bool get isFree => _planId == 'free';
  bool get isStarter => _planId == 'starter';
  bool get isPremium => _planId == 'premium';

  void notifyPlanChanged() {
    _log(
      'notifyPlanChanged() - '
      'planId=$_planId / '
      'status=$_planStatus',
    );

    notifyListeners();
  }

  bool get isPremiumActive {
    if (_planId != 'premium') return false;

    final normalized = _normalizeStatus(_planStatus);

    return normalized == 'active' ||
        normalized == 'in_grace_period' ||
        normalized == 'trialing';
  }

  void _log(String message) {
    debugPrint('PLAN_SERVICE: $message');
  }

  Future<void> load({bool forceServer = false}) {
    final uid = _auth.currentUser?.uid;
    if (_sessionUid != uid) {
      _sessionUid = uid;
      _loadGeneration++;
      _loadFuture = null;
      _reset();
      notifyListeners();
    }
    if (!forceServer && _loadFuture != null) return _loadFuture!;
    final generation = ++_loadGeneration;
    final future = _loadState(uid, generation, forceServer: forceServer);
    final tracked = future.whenComplete(() {
      if (generation == _loadGeneration) _loadFuture = null;
    });
    _loadFuture = tracked;
    return tracked;
  }

  Future<void> _loadState(
    String? uid,
    int generation, {
    required bool forceServer,
  }) async {
    bool isCurrent() =>
        generation == _loadGeneration && _auth.currentUser?.uid == uid;
    if (uid == null) {
      _reset();
      notifyListeners();
      return;
    }
    try {
      final options = GetOptions(
        source: forceServer ? Source.server : Source.serverAndCache,
      );
      final userSnap = await _fs
          .collection(usersCollection)
          .doc(uid)
          .get(options);
      if (!isCurrent()) return;
      Map<String, dynamic>? resolvedUser = userSnap.data();
      if (!userSnap.exists) {
        final email = (_auth.currentUser?.email ?? '').trim().toLowerCase();
        if (email.isNotEmpty) {
          final matches = await _fs.collection(usersCollection)
              .where('emailKey', isEqualTo: email).limit(1).get(options);
          if (!isCurrent()) return;
          if (matches.docs.isNotEmpty) resolvedUser = matches.docs.first.data();
        }
      }
      if (resolvedUser == null) {
        _reset();
        notifyListeners();
        throw StateError('Cadastro do usuário não encontrado para validar o plano');
      }
      final userData = _safeMap(resolvedUser);
      final company = _safeString(userData['companyId']);
      final companyId = company.isEmpty ? uid : company;
      final subRef = _fs.collection(subscriptionsCollection).doc(companyId);
      final subSnap = await subRef.get(options);
      if (!isCurrent()) return;
      final storedSubscription = _safeMap(subSnap.data());
      final subscriptionOwner = _safeString(storedSubscription['userId']);
      // Company membership does not grant the owner's personal subscription.
      final ownsSubscription = subscriptionOwner == uid ||
          (subscriptionOwner.isEmpty && companyId == uid);
      final previous = ownsSubscription
          ? storedSubscription
          : <String, dynamic>{};
      final normalized = _buildNormalizedSubscription(
        userUid: uid,
        userData: userData,
        subscriptionData: previous,
        companyId: companyId,
      );
      // Existing subscription rights are never rewritten by a read.
      if (!subSnap.exists && !forceServer) {
        await _syncSubscriptionDocument(
          ref: subRef,
          previous: previous,
          normalized: normalized,
        );
      }
      final planId = _safeString(normalized['planId']).toLowerCase();
      final planData = await _loadPlanDocument(planId, options);
      if (!isCurrent()) return;
      // Publish only a complete snapshot. A failed refresh keeps the old one.
      _userData = userData;
      _subscriptionData = normalized;
      _companyId = companyId;
      _planId = planId;
      _planStatus = _safeString(normalized['status']).toLowerCase();
      _billingCycle = _safeString(normalized['billingCycle']).toLowerCase();
      _planData = planData;
      _limits = _safeMap(planData['limits']);
      _features = _safeMap(planData['features']);
      _loaded = true;
      notifyListeners();
    } catch (e, st) {
      if (!isCurrent()) return;
      _log('load() failed: $e');
      _log(st.toString());
      rethrow;
    }
  }

  Future<void> reload({bool forceServer = false}) =>
      load(forceServer: forceServer);

  Map<String, dynamic> _buildNormalizedSubscription({
    required String userUid,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> subscriptionData,
    required String companyId,
  }) {
    final subPlanId = _safeString(subscriptionData['planId']).toLowerCase();
    final userPlan =
        _pickFirstNonEmptyString([
          userData['planId'],
          userData['plan'],
        ]).toLowerCase();

    final productId = _pickFirstNonEmptyString([
      subscriptionData['productId'],
      userData['productId'],
    ]);

    final purchaseToken = _pickFirstNonEmptyString([
      subscriptionData['purchaseToken'],
      userData['purchaseToken'],
    ]);

    final orderId = _pickFirstNonEmptyString([subscriptionData['orderId']]);

    final purchaseSource = _pickFirstNonEmptyString([
      subscriptionData['purchaseSource'],
      productId.isNotEmpty ? 'google_play' : null,
    ]);

    final billingCycle = _pickFirstNonEmptyString([
      subscriptionData['billingCycle'],
      _inferBillingCycle(productId),
      userPlan == 'free' || subPlanId == 'free' ? '' : 'monthly',
    ]);

    final status = _normalizeStatus(
      _pickFirstNonEmptyString([
        subscriptionData['status'],
        userData['subscriptionStatus'],
        userData['subscriptionActive'] == true ? 'active' : '',
        'active',
      ]),
    );

    final expiresAt = _toTimestamp(
      subscriptionData['expiresAt'] ?? userData['expiryTime'],
    );

    final purchaseDate = _toTimestamp(subscriptionData['purchaseDate']);
    final startedAt = _toTimestamp(subscriptionData['startedAt']);

    final autoRenewing = _pickFirstBool([
      subscriptionData['autoRenewing'],
    ], defaultValue: false);

    final trial = _pickFirstBool([
      subscriptionData['trial'],
    ], defaultValue: false);

    String planId = subPlanId;
    if (planId.isEmpty) {
      if (userPlan.isNotEmpty) {
        planId = userPlan;
      } else if (productId.isNotEmpty) {
        planId = _mapProductToPlan(productId);
      } else {
        planId = 'free';
      }
    }

    if (!_isSupportedPlan(planId)) {
      _log('Plano não suportado encontrado: $planId. Aplicando free.');
      planId = 'free';
    }

    if (planId == 'free') {
      return {
        'companyId': companyId,
        'userId': userUid,
        'planId': 'free',
        'status': 'active',
        'billingCycle': '',
        'productId': null,
        'purchaseToken': null,
        'orderId': null,
        'purchaseSource': null,
        'autoRenewing': false,
        'trial': false,
        'purchaseDate': null,
        'startedAt': startedAt ?? Timestamp.now(),
        'expiresAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }

    return {
      'companyId': companyId,
      'userId': userUid,
      'planId': planId,
      'status': status,
      'billingCycle': billingCycle.isEmpty ? 'monthly' : billingCycle,
      'productId': productId.isEmpty ? null : productId,
      'purchaseToken': purchaseToken.isEmpty ? null : purchaseToken,
      'orderId': orderId.isEmpty ? null : orderId,
      'purchaseSource': purchaseSource.isEmpty ? null : purchaseSource,
      'autoRenewing': autoRenewing,
      'trial': trial,
      'purchaseDate': purchaseDate,
      'startedAt': startedAt,
      'expiresAt': expiresAt,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _syncSubscriptionDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> previous,
    required Map<String, dynamic> normalized,
  }) async {
    if (!_needsSync(previous, normalized)) {
      _log('PASSO 4.1 - subscriptions já está sincronizada');
      return;
    }

    _log('PASSO 4.2 - sincronizando subscriptions');
    await _fs.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      if (current.exists) return;
      transaction.set(ref, normalized, SetOptions(merge: true));
    });
    _log('PASSO 4.3 - subscriptions sincronizada');
  }

  bool _needsSync(
    Map<String, dynamic> previous,
    Map<String, dynamic> normalized,
  ) {
    const keys = <String>[
      'companyId',
      'userId',
      'planId',
      'status',
      'billingCycle',
      'productId',
      'purchaseToken',
      'orderId',
      'purchaseSource',
      'autoRenewing',
      'trial',
      'purchaseDate',
      'startedAt',
      'expiresAt',
    ];

    for (final key in keys) {
      final oldValue = previous[key];
      final newValue = normalized[key];

      if (!_sameValue(oldValue, newValue)) {
        return true;
      }
    }

    return false;
  }

  bool _sameValue(dynamic a, dynamic b) {
    if (a is Timestamp && b is Timestamp) {
      return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
    }

    if (a == null && b == null) return true;
    return a == b;
  }

  Future<Map<String, dynamic>> _loadPlanDocument(
    String planId,
    GetOptions options,
  ) async {
    final snap = await _fs.collection(plansCollection).doc(planId).get(options);
    if (!snap.exists) return <String, dynamic>{};
    final raw = _safeMap(snap.data());
    return <String, dynamic>{
      'id': _safeString(raw['id']),
      'name': _safeString(raw['name']),
      'description': _safeString(raw['description']),
      'limits': _safeMap(raw['limits']),
      'features': _safeMap(raw['features']),
      'labels': _safeMap(raw['labels']),
      'prices': _safeMap(raw['prices']),
      'productIds': _safeMap(raw['productIds']),
      'active': raw['active'] == true,
    };
  }

  void _reset() {
    _log('_reset() chamado');
    _userData = {};
    _subscriptionData = {};
    _planData = {};
    _limits = {};
    _features = {};
    _planId = 'free';
    _planStatus = 'active';
    _billingCycle = '';
    _companyId = null;
    _loaded = false;
  }

  Future<String?> _resolveCompanyId() async {
    try {
      final user = _auth.currentUser;
      _log('_resolveCompanyId() - uid: ${user?.uid}');

      if (user == null) return null;

      if ((_companyId ?? '').isNotEmpty) {
        _log('_resolveCompanyId() - usando companyId em memória: $_companyId');
        return _companyId;
      }

      final userSnap =
          await _fs.collection(usersCollection).doc(user.uid).get();
      final userData = _safeMap(userSnap.data());

      String company = _safeString(userData['companyId']);
      if (company.isEmpty) {
        company = user.uid;
      }

      _companyId = company;
      _log('_resolveCompanyId() - companyId resolvido: $_companyId');
      return company;
    } catch (e, st) {
      _log('ERRO em _resolveCompanyId(): $e');
      _log(st.toString());
      rethrow;
    }
  }

  int getLimit(String key, {int defaultValue = -1}) {
    final value = _limits[key];
    final converted = _safeInt(value);
    return converted ?? defaultValue;
  }

  bool hasFeature(String key, {bool defaultValue = false}) {
    final value = _features[key];
    if (value is bool) return value;
    return defaultValue;
  }

  bool isUnlimited(String key) => getLimit(key) == -1;

  Future<int> _countDocuments({
    required String collection,
    required String fieldName,
    required String fieldValue,
  }) async {
    final query =
        await _fs
            .collection(collection)
            .where(fieldName, isEqualTo: fieldValue)
            .count()
            .get();

    return query.count ?? 0;
  }

  Future<int> _countOrdersCurrentMonth() async {
    if (!_loaded || _sessionUid != _auth.currentUser?.uid) await load();
    final pending = _loadFuture;
    if (!_loaded && pending != null) await pending;
    final uid = _auth.currentUser?.uid;
    final company = _companyId;
    if (uid == null || company == null || company.isEmpty) {
      throw StateError('User plan must be loaded before counting orders');
    }
    final now = DateTime.now();
    final snapshot = await _fs.collection(ordersCollection)
        .where(companyIdField, isEqualTo: company)
        .where('data', isGreaterThanOrEqualTo:
            Timestamp.fromDate(DateTime(now.year, now.month, 1)))
        .where('data', isLessThan:
            Timestamp.fromDate(DateTime(now.year, now.month + 1, 1)))
        .get();
    return snapshot.docs.where((doc) {
      final data = doc.data();
      final creator = _safeString(data['createdByUid']);
      return (creator.isNotEmpty ? creator : _safeString(data['userId'])) == uid;
    }).length;
  }

  Future<bool> _canCreateByLimit({
    required int limit,
    required Future<int> Function() counter,
  }) async {
    if (limit == -1) return true;
    final current = await counter();
    return current < limit;
  }

  Future<bool> canCreateClient() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return false;

    final limit = getLimit('maxClients', defaultValue: -1);

    return _canCreateByLimit(
      limit: limit,
      counter:
          () => _countDocuments(
            collection: clientsCollection,
            fieldName: companyIdField,
            fieldValue: company,
          ),
    );
  }

  Future<bool> canCreateSupplier() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return false;

    final limit = getLimit('maxSuppliers', defaultValue: -1);

    return _canCreateByLimit(
      limit: limit,
      counter:
          () => _countDocuments(
            collection: suppliersCollection,
            fieldName: companyIdField,
            fieldValue: company,
          ),
    );
  }

  Future<bool> canCreateProduct() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return false;

    final limit = getLimit('maxProducts', defaultValue: -1);

    return _canCreateByLimit(
      limit: limit,
      counter:
          () => _countDocuments(
            collection: productsCollection,
            fieldName: companyIdField,
            fieldValue: company,
          ),
    );
  }

  Future<bool> canCreateService() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return false;

    final limit = getLimit('maxServices', defaultValue: -1);

    return _canCreateByLimit(
      limit: limit,
      counter:
          () => _countDocuments(
            collection: servicesCollection,
            fieldName: companyIdField,
            fieldValue: company,
          ),
    );
  }

  Future<bool> canCreateGoal() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return false;

    final limit = getLimit('maxGoals', defaultValue: -1);

    return _canCreateByLimit(
      limit: limit,
      counter:
          () => _countDocuments(
            collection: goalsCollection,
            fieldName: companyIdField,
            fieldValue: company,
          ),
    );
  }

  Future<bool> canCreateOrder() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return false;

    final limit = getLimit('maxOrdersPerMonth', defaultValue: -1);

    return _canCreateByLimit(limit: limit, counter: _countOrdersCurrentMonth);
  }

  Future<int> getCurrentClientsCount() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return 0;

    return _countDocuments(
      collection: clientsCollection,
      fieldName: companyIdField,
      fieldValue: company,
    );
  }

  Future<int> getCurrentSuppliersCount() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return 0;

    return _countDocuments(
      collection: suppliersCollection,
      fieldName: companyIdField,
      fieldValue: company,
    );
  }

  Future<int> getCurrentProductsCount() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return 0;

    return _countDocuments(
      collection: productsCollection,
      fieldName: companyIdField,
      fieldValue: company,
    );
  }

  Future<int> getCurrentServicesCount() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return 0;

    return _countDocuments(
      collection: servicesCollection,
      fieldName: companyIdField,
      fieldValue: company,
    );
  }

  Future<int> getCurrentGoalsCount() async {
    final company = _companyId;
    if (company == null || company.isEmpty) return 0;

    return _countDocuments(
      collection: goalsCollection,
      fieldName: companyIdField,
      fieldValue: company,
    );
  }

  Future<int> getCurrentOrdersMonthCount() async {
    return _countOrdersCurrentMonth();
  }

  Future<void> updatePlan({
    required String planId,
    String status = 'active',
    String? billingCycle,
    String? productId,
    String? purchaseToken,
    String? orderId,
    String? purchaseSource,
    bool? autoRenewing,
    DateTime? purchaseDate,
    DateTime? startedAt,
    DateTime? expiresAt,
    bool? trial,
  }) async {
    try {
      _log('updatePlan() iniciado');
      _log('updatePlan() planId recebido: $planId');
      _log('updatePlan() billingCycle recebido: $billingCycle');
      _log('updatePlan() productId recebido: $productId');

      final user = _auth.currentUser;
      if (user == null) {
        _log('updatePlan() abortado - usuário nulo');
        return;
      }

      final company = await _resolveCompanyId();
      if (company == null || company.isEmpty) {
        _log('updatePlan() abortado - companyId nulo/vazio');
        return;
      }

      final normalizedPlanId =
          planId.trim().toLowerCase().isEmpty
              ? 'free'
              : planId.trim().toLowerCase();

      final normalizedStatus = _normalizeStatus(status);
      final normalizedBilling =
          normalizedPlanId == 'free'
              ? ''
              : (billingCycle ?? '').trim().toLowerCase();

      final expiresAtTimestamp =
          expiresAt != null ? Timestamp.fromDate(expiresAt) : null;

      final subscriptionUpdates = <String, dynamic>{
        'companyId': company,
        'userId': user.uid,
        'planId': normalizedPlanId,
        'status': normalizedPlanId == 'free' ? 'active' : normalizedStatus,
        'billingCycle': normalizedBilling,
        'productId': normalizedPlanId == 'free' ? null : productId,
        'purchaseToken': normalizedPlanId == 'free' ? null : purchaseToken,
        'orderId': normalizedPlanId == 'free' ? null : orderId,
        'purchaseSource': normalizedPlanId == 'free' ? null : purchaseSource,
        'autoRenewing':
            normalizedPlanId == 'free' ? false : (autoRenewing ?? false),
        'purchaseDate':
            purchaseDate != null ? Timestamp.fromDate(purchaseDate) : null,
        'startedAt': startedAt != null ? Timestamp.fromDate(startedAt) : null,
        'expiresAt': expiresAtTimestamp,
        'trial': trial ?? false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      _log('updatePlan() subscriptions payload: $subscriptionUpdates');

      await _fs
          .collection(subscriptionsCollection)
          .doc(company)
          .set(subscriptionUpdates, SetOptions(merge: true));

      final userUpdates = <String, dynamic>{
        'plan': normalizedPlanId,
        'subscriptionStatus':
            normalizedPlanId == 'free' ? 'active' : normalizedStatus,
        'subscriptionActive':
            normalizedPlanId == 'free'
                ? false
                : _isActiveStatus(normalizedStatus),
        'productId': normalizedPlanId == 'free' ? null : productId,
        'purchaseToken': normalizedPlanId == 'free' ? null : purchaseToken,
        'expiryTime': expiresAtTimestamp,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      _log('updatePlan() users payload: $userUpdates');

      await _fs
          .collection(usersCollection)
          .doc(user.uid)
          .set(userUpdates, SetOptions(merge: true));

      await reload();
      _log('updatePlan() concluído com sucesso');
    } catch (e, st) {
      _log('ERRO em updatePlan(): $e');
      _log(st.toString());
      rethrow;
    }
  }

  Future<void> upgradePlan({
    required String planId,
    required String billingCycle,
    required DateTime startAt,
    required DateTime endAt,
    String? productId,
    String? purchaseToken,
    String? orderId,
    String? purchaseSource,
    bool? autoRenewing,
    DateTime? purchaseDate,
    String status = 'active',
  }) async {
    await updatePlan(
      planId: planId,
      status: status,
      billingCycle: billingCycle,
      productId: productId,
      purchaseToken: purchaseToken,
      orderId: orderId,
      purchaseSource: purchaseSource,
      autoRenewing: autoRenewing,
      purchaseDate: purchaseDate,
      startedAt: startAt,
      expiresAt: endAt,
      trial: false,
    );
  }

  Future<void> downgradeToFree({String status = 'expired'}) async {
    await updatePlan(
      planId: 'free',
      status: status,
      billingCycle: null,
      productId: null,
      purchaseToken: null,
      orderId: null,
      purchaseSource: null,
      autoRenewing: false,
      purchaseDate: null,
      startedAt: DateTime.now(),
      expiresAt: null,
      trial: false,
    );
  }

  Future<void> setFreePlan() async {
    await updatePlan(
      planId: 'free',
      status: 'active',
      billingCycle: null,
      productId: null,
      purchaseToken: null,
      orderId: null,
      purchaseSource: null,
      autoRenewing: false,
      purchaseDate: null,
      startedAt: DateTime.now(),
      expiresAt: null,
      trial: false,
    );
  }

  Future<void> setStarterMonthly({String? purchaseToken}) async {
    await updatePlan(
      planId: 'starter',
      status: 'active',
      billingCycle: 'monthly',
      productId: 'starter_mensal',
      purchaseToken: purchaseToken,
      orderId: null,
      purchaseSource: purchaseToken != null ? 'google_play' : null,
      autoRenewing: purchaseToken != null,
      purchaseDate: purchaseToken != null ? DateTime.now() : null,
      startedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      trial: false,
    );
  }

  Future<void> setPremiumMonthly({String? purchaseToken}) async {
    await updatePlan(
      planId: 'premium',
      status: 'active',
      billingCycle: 'monthly',
      productId: 'premium_mensal',
      purchaseToken: purchaseToken,
      orderId: null,
      purchaseSource: purchaseToken != null ? 'google_play' : null,
      autoRenewing: purchaseToken != null,
      purchaseDate: purchaseToken != null ? DateTime.now() : null,
      startedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      trial: false,
    );
  }

  bool _isSupportedPlan(String value) {
    return value == 'free' || value == 'starter' || value == 'premium';
  }

  String _mapProductToPlan(String productId) {
    final value = productId.trim().toLowerCase();

    if (value.startsWith('starter')) return 'starter';
    if (value.startsWith('premium')) return 'premium';
    return 'free';
  }

  String _inferBillingCycle(String productId) {
    final value = productId.trim().toLowerCase();
    if (value.isEmpty) return '';

    if (value.contains('anual') || value.contains('annual')) {
      return 'annual';
    }
    if (value.contains('semestral') || value.contains('semiannual')) {
      return 'semiannual';
    }
    if (value.contains('mensal') || value.contains('monthly')) {
      return 'monthly';
    }

    return 'monthly';
  }

  String _normalizeStatus(String value) {
    final normalized = value.trim().toLowerCase();

    switch (normalized) {
      case 'subscription_state_active':
      case 'active':
        return 'active';

      case 'subscription_state_in_grace_period':
      case 'in_grace_period':
      case 'grace_period':
        return 'in_grace_period';

      case 'subscription_state_on_hold':
      case 'on_hold':
        return 'on_hold';

      case 'subscription_state_canceled':
      case 'canceled':
      case 'cancelled':
        return 'canceled';

      case 'subscription_state_expired':
      case 'expired':
        return 'expired';

      case 'subscription_state_revoked':
      case 'revoked':
        return 'revoked';

      case 'trialing':
        return 'trialing';

      default:
        return normalized.isEmpty ? 'active' : normalized;
    }
  }

  bool _isActiveStatus(String status) {
    final normalized = _normalizeStatus(status);
    return normalized == 'active' ||
        normalized == 'in_grace_period' ||
        normalized == 'trialing';
  }

  String _pickFirstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = _safeString(value);
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  bool _pickFirstBool(List<dynamic> values, {required bool defaultValue}) {
    for (final value in values) {
      if (value is bool) return value;
    }
    return defaultValue;
  }

  Timestamp? _toTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;

    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }

    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return Timestamp.fromDate(parsed);
      }
    }

    return null;
  }

  Map<String, dynamic> _safeMap(dynamic value) {
    if (value == null) return <String, dynamic>{};

    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, val) {
        result[key.toString()] = val;
      });
      return result;
    }

    return <String, dynamic>{};
  }

  String _safeString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final parsedInt = int.tryParse(text);
    if (parsedInt != null) return parsedInt;

    final parsedDouble = double.tryParse(text);
    if (parsedDouble != null) return parsedDouble.toInt();

    return null;
  }
}
