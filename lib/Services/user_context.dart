// lib/services/user_context.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Modelo imutável com a visão consolidada do usuário logado.
class AppUserContext {
  final String uid;
  final String role; // "admin", "funcionario", etc.
  final String? companyId;
  final Map<String, bool> permissions;

  const AppUserContext({
    required this.uid,
    required this.role,
    required this.companyId,
    required this.permissions,
  });

  /// Permissão bruta (com fallback para chave legada no topo do doc).
  bool has(String key) => permissions[key] == true;

  /// Regras de negócio (ajuste conforme seu app)
  bool get isAdmin => role == 'admin';
  bool get isFuncionario => role == 'funcionario';

  /// Dono lógico dos registros (igualamos a company quando houver).
  String? get effectiveOwnerId {
    if (isAdmin && (companyId == null || companyId!.isEmpty)) return uid;
    if (companyId != null && companyId!.isNotEmpty) return companyId;
    return null;
  }

  /// Empresa efetiva (se admin sem empresa, volta null).
  String? get effectiveCompanyId =>
      (companyId != null && companyId!.isNotEmpty) ? companyId : null;

  /// Campo legado/compatibilidade para consultas por dono.
  /// Use-o para salvar em coleções (clientes/produtos/etc).
  String? get userIdForWrites => effectiveCompanyId ?? effectiveOwnerId;

  // ======= Checks prontos usados nas telas =======

  /// Mesma regra usada no Cadastro de Cliente
  bool get canCreateClient {
    if (isAdmin) return true;
    if (isFuncionario) {
      final hasCompany = effectiveCompanyId != null;
      final canRegisterSales = has('canRegisterSales');
      final canSeeOthersClients = has('canSeeOthersClients');
      return hasCompany && (canRegisterSales || canSeeOthersClients);
    }
    return false;
  }

  /// Mesma regra usada no Cadastro de Produto
  bool get canCreateProduct {
    if (isAdmin) return true;
    if (isFuncionario) {
      final hasCompany = effectiveCompanyId != null;
      return hasCompany && has('canManageProducts');
    }
    return false;
  }

  /// Exemplo extra que pode te ajudar em outras telas
  bool get canManageStock {
    if (isAdmin) return true;
    if (isFuncionario)
      return effectiveCompanyId != null && has('canManageStock');
    return false;
  }

  bool get canManageFinance {
    if (isAdmin) return true;
    if (isFuncionario)
      return effectiveCompanyId != null && has('canManageFinance');
    return false;
  }

  AppUserContext copyWith({
    String? role,
    String? companyId,
    Map<String, bool>? permissions,
  }) {
    return AppUserContext(
      uid: uid,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      permissions: permissions ?? this.permissions,
    );
  }

  @override
  String toString() =>
      'AppUserContext(uid=$uid, role=$role, companyId=$companyId, permissions=$permissions)';
}

/// Serviço singleton que mantém e distribui o contexto do usuário.
class UserContext {
  UserContext._internal();
  static final UserContext instance = UserContext._internal();

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  AppUserContext? _cached;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  final _controller = StreamController<AppUserContext?>.broadcast();

  /// Começa a observar auth e o doc do usuário. Chame uma vez no app (ex.: main()).
  void initialize() {
    _authSub ??= _auth.authStateChanges().listen((user) async {
      // limpa estado quando troca de usuário
      await _attachToUserDoc(user?.uid);
    });
    // liga já com o usuário atual
    _attachToUserDoc(_auth.currentUser?.uid);
  }

  /// Stream do contexto (emite null quando deslogado).
  Stream<AppUserContext?> watch() => _controller.stream;

  /// Future com cache (carrega uma vez e reaproveita).
  Future<AppUserContext?> get() async {
    if (_cached != null) return _cached;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _fs.collection('users').doc(uid).get();
    _cached = _buildFromUserDoc(uid, snap.data() ?? {});
    return _cached;
  }

  /// Força recarregar do Firestore e atualizar ouvintes.
  Future<AppUserContext?> refresh() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _set(null);
      return null;
    }
    final snap = await _fs.collection('users').doc(uid).get();
    final ctx = _buildFromUserDoc(uid, snap.data() ?? {});
    _set(ctx);
    return ctx;
  }

  /// Libera recursos (opcional, ex.: ao fechar o app).
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _userDocSub?.cancel();
    await _controller.close();
  }

  // ----------------- Internos -----------------

  Future<void> _attachToUserDoc(String? uid) async {
    await _userDocSub?.cancel();
    if (uid == null) {
      _set(null);
      return;
    }
    _userDocSub = _fs
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snap) {
            final data = snap.data() ?? {};
            final ctx = _buildFromUserDoc(uid, data);
            _set(ctx);
          },
          onError: (_) {
            // Em caso de erro, não derruba stream; mantém último cache.
          },
        );
  }

  void _set(AppUserContext? ctx) {
    _cached = ctx;
    _controller.add(ctx);
  }

  AppUserContext _buildFromUserDoc(String uid, Map<String, dynamic> data) {
    final role = (data['role'] ?? '').toString().toLowerCase();
    final companyId =
        (data['companyId'] ?? '').toString().trim().isEmpty
            ? null
            : (data['companyId'] as String).trim();

    // Junta permissões do submap e chaves legadas do topo do doc
    final rawPerms = <String, bool>{};
    final mapPerms = (data['permissions'] ?? {}) as Map<String, dynamic>;
    for (final e in mapPerms.entries) {
      rawPerms[e.key] = (e.value == true);
    }
    // fallback para possíveis chaves legadas
    for (final k in [
      'canRegisterSales',
      'canSeeOthersClients',
      'canManageProducts',
      'canManageStock',
      'canManageFinance',
      'canEditOrder',
      'canDiscount',
      'canDirectSale',
      'canCrediario',
      'canEnableFiado',
      'canChangeOrderDate',
      'canSeeOthersOrders',
      'canSeeOthersCalendars',
      'canManageProducts', // repetido de propósito para garantir override
    ]) {
      if (data.containsKey(k)) {
        rawPerms[k] = (data[k] == true) || rawPerms[k] == true;
      }
    }

    return AppUserContext(
      uid: uid,
      role: role,
      companyId: companyId,
      permissions: rawPerms,
    );
  }
}
