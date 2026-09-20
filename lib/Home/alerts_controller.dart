// lib/home/alerts_controller.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AlertsController {
  AlertsController._();
  static final AlertsController instance = AlertsController._();

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _prodSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pagarSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _receberSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _agendaSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _comprasSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _revisaoCustoSub;

  String? _uid;

  // ===== Escopo multiempresa =====
  // Se o usuário tiver users.companyId != null/empty, usamos companyId; senão, userId.
  String _scopeField = 'userId';
  String? _scopeValue;

  /// Notificadores públicos (estoque / financeiro)
  final ValueNotifier<int> lowStock = ValueNotifier<int>(0);
  final ValueNotifier<int> overduePayables = ValueNotifier<int>(0);
  final ValueNotifier<int> overdueReceivables = ValueNotifier<int>(0);
  final ValueNotifier<int> comprasAEntregar = ValueNotifier<int>(0);
  final ValueNotifier<int> revisarCustos = ValueNotifier<int>(0);

  // ----------------- COMPROMISSOS -----------------
  final ValueNotifier<int> apptOverdueToday = ValueNotifier<int>(
    0,
  ); // atrasados HOJE
  final ValueNotifier<int> apptStartingIn30 = ValueNotifier<int>(
    0,
  ); // começam ≤ 30min

  /// Compatibilidade com a sua tela atual
  final ValueNotifier<int> appointmentsToday = ValueNotifier<int>(0);
  final ValueNotifier<int> appointmentsOverdue = ValueNotifier<int>(0);

  /// total para badge dos compromissos (soma dos dois contadores acima)
  late final ValueListenable<int> appointmentsTotal = _CombinedSum([
    appointmentsToday,
    appointmentsOverdue,
  ]);
  late final ValueListenable<int> totalAlerts = _CombinedSum([
    lowStock,
    overduePayables,
    overdueReceivables,
    comprasAEntregar,
    revisarCustos,
  ]);

  bool _started = false;

  void ensureStarted() => start();

  void start() {
    if (_started) return;
    _started = true;

    _uid = _auth.currentUser?.uid;
    _attachListeners();

    _authSub = _auth.authStateChanges().listen((u) async {
      final newUid = u?.uid;
      if (newUid == _uid) return;
      _uid = newUid;
      _attachListeners();
    });
  }

  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _cancelStreamsAndReset();
    _started = false;
  }

  Future<void> _resolveScope() async {
    _scopeField = 'userId';
    _scopeValue = null;

    final uid = _uid;
    if (uid == null) return;

    // default fallback
    _scopeValue = uid;

    try {
      // tenta users/{uid}
      final uDoc = await _fs.collection('users').doc(uid).get();
      Map<String, dynamic>? me = uDoc.data();

      // fallback por emailKey, se necessário
      if (me == null || me.isEmpty) {
        final emailKey = (_auth.currentUser?.email ?? '').trim().toLowerCase();
        if (emailKey.isNotEmpty) {
          final q =
              await _fs
                  .collection('users')
                  .where('emailKey', isEqualTo: emailKey)
                  .limit(1)
                  .get();
          if (q.docs.isNotEmpty) me = q.docs.first.data();
        }
      }

      final companyId = (me?['companyId'] ?? '').toString().trim();
      if (companyId.isNotEmpty) {
        _scopeField = 'companyId';
        _scopeValue = companyId;
      } else {
        _scopeField = 'userId';
        _scopeValue = uid;
      }
    } catch (_) {
      // Em caso de erro, fica no fallback por uid
      _scopeField = 'userId';
      _scopeValue = uid;
    }
  }

  void _attachListeners() {
    _cancelStreamsAndReset(keepValues: true);

    if (_uid == null) {
      _resetValues();
      return;
    }

    // Resolve escopo e só então liga os listeners
    _resolveScope().then((_) {
      final scope = _scopeValue;
      if (scope == null) {
        _resetValues();
        return;
      }

      _comprasSub = _fs
          .collection('compras')
          .where(_scopeField, isEqualTo: scope)
          .where('status', whereIn: ['aberta', 'entrega_parcial'])
          .snapshots()
          .listen((snap) {
            comprasAEntregar.value = snap.docs.length;
          });

      _revisaoCustoSub = _fs
          .collection('produtos')
          .where(_scopeField, isEqualTo: scope)
          .snapshots()
          .listen((snap) {
            int c = 0;

            for (final d in snap.docs) {
              final m = d.data();

              final custo = _asNum(m['custo']);
              final precoMedio = _asNum(m['precoMedio']);

              if (precoMedio > 0 && (custo - precoMedio).abs() >= 0.01) {
                c++;
              }
            }

            revisarCustos.value = c;
          });

      // --------- Estoque baixo (produtos) ---------
      _prodSub = _fs
          .collection('produtos')
          .where(_scopeField, isEqualTo: scope)
          .where('controlaEstoque', isEqualTo: true)
          .snapshots()
          .listen((snap) {
            int c = 0;
            for (final d in snap.docs) {
              final m = d.data();
              final num estoque = (m['estoque'] ?? 0) as num;
              final num min = (m['estoqueAlerta'] ?? 0) as num;
              if (min > 0 && estoque < min) c++;
            }
            lowStock.value = c;
          });

      // --------- Contas a pagar vencidas ---------
      _pagarSub = _fs
          .collection('contas_pagar')
          .where(_scopeField, isEqualTo: scope)
          .where('status', isNotEqualTo: 'pago')
          .orderBy('status')
          .orderBy('vencimento')
          .snapshots()
          .listen((snap) {
            final hoje00 = _at00(DateTime.now());
            int c = 0;
            for (final d in snap.docs) {
              final m = d.data();
              final status = (m['status'] ?? '').toString().toLowerCase();
              if (status == 'pago' || status == 'cancelado') continue;
              final valor = _asNum(m['valor']);
              final pago = _asNum(m['valorPago']);
              final saldo = max(0.0, valor - pago);
              if (saldo <= 0) continue;
              final Timestamp? ts = m['vencimento'] as Timestamp?;
              final DateTime? venc = ts?.toDate();
              if (venc != null && _at00(venc).isBefore(hoje00)) c++;
            }
            overduePayables.value = c;
          });

      // --------- Contas a receber vencidas ---------
      _receberSub = _fs
          .collection('contas_receber')
          .where(_scopeField, isEqualTo: scope)
          .where('status', isNotEqualTo: 'pago')
          .orderBy('status')
          .orderBy('vencimento')
          .snapshots()
          .listen((snap) {
            final hoje00 = _at00(DateTime.now());
            int c = 0;
            for (final d in snap.docs) {
              final m = d.data();
              final status = (m['status'] ?? '').toString().toLowerCase();
              if (status == 'pago' || status == 'cancelado') continue;
              final valor = _asNum(m['valor']);
              final pago = _asNum(m['valorPago']);
              final saldo = max(0.0, valor - pago);
              if (saldo <= 0) continue;
              final Timestamp? ts = m['vencimento'] as Timestamp?;
              final DateTime? venc = ts?.toDate();
              if (venc != null && _at00(venc).isBefore(hoje00)) c++;
            }
            overdueReceivables.value = c;
          });

      // --------- Compromissos (AGENDA) ---------
      final agora = DateTime.now();
      final hoje00 = _at00(agora);
      final amanha00 = hoje00.add(const Duration(days: 1));

      _agendaSub = _fs
          .collection('agenda')
          .where(_scopeField, isEqualTo: scope)
          .where(
            'compromisso',
            isGreaterThanOrEqualTo: Timestamp.fromDate(hoje00),
          )
          .where('compromisso', isLessThan: Timestamp.fromDate(amanha00))
          .orderBy('compromisso')
          .snapshots()
          .listen((snap) {
            final now = DateTime.now();
            final in30 = now.add(const Duration(minutes: 30));

            int overdue = 0; // de hoje, já iniciaram
            int soon = 0; // começam nos próximos 30 minutos

            for (final d in snap.docs) {
              final m = d.data();
              final ts = m['compromisso'];
              DateTime? dt;
              if (ts is Timestamp) dt = ts.toDate();
              if (ts is DateTime) dt = ts;
              if (dt == null) continue;

              // Se existir um 'status' (concluido/cancelado), ignore conforme sua regra
              if (dt.isBefore(now)) {
                overdue++;
              } else if (!dt.isAfter(in30)) {
                // dt ∈ (now, now+30]
                soon++;
              }
            }

            // Nomes explícitos
            apptOverdueToday.value = overdue;
            apptStartingIn30.value = soon;

            // Compatibilidade com a tela atual
            appointmentsOverdue.value = overdue;
            appointmentsToday.value = soon;
          });
    });
  }

  void _cancelStreamsAndReset({bool keepValues = false}) {
    _prodSub?.cancel();
    _pagarSub?.cancel();
    _receberSub?.cancel();
    _agendaSub?.cancel();
    _comprasSub?.cancel();
    _revisaoCustoSub?.cancel();
    _prodSub = null;
    _pagarSub = null;
    _receberSub = null;
    _agendaSub = null;
    _comprasSub = null;
    _revisaoCustoSub = null;
    if (!keepValues) _resetValues();
  }

  void _resetValues() {
    comprasAEntregar.value = 0;
    lowStock.value = 0;
    overduePayables.value = 0;
    overdueReceivables.value = 0;
    apptOverdueToday.value = 0;
    apptStartingIn30.value = 0;
    appointmentsOverdue.value = 0;
    appointmentsToday.value = 0;
    revisarCustos.value = 0;
  }

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);

  static double _asNum(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
    _cancelStreamsAndReset();
    _started = false;
  }
}

/// Soma de vários ValueNotifier<int> em um único listenable
class _CombinedSum extends ValueNotifier<int> {
  final List<ValueNotifier<int>> sources;
  _CombinedSum(this.sources) : super(0) {
    for (final s in sources) {
      s.addListener(_recalc);
    }
    _recalc();
  }
  void _recalc() => value = sources.fold<int>(0, (sum, s) => sum + s.value);

  @override
  void dispose() {
    for (final s in sources) {
      s.removeListener(_recalc);
    }
    super.dispose();
  }
}
