// lib/home/payables_overdue_watcher.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PayablesOverdueWatcher {
  PayablesOverdueWatcher._();
  static final PayablesOverdueWatcher instance = PayablesOverdueWatcher._();

  final ValueNotifier<int> overdueCount = ValueNotifier<int>(0);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<User?>? _authSub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _bind(u?.uid);
    });
    _bind(FirebaseAuth.instance.currentUser?.uid);
  }

  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _sub?.cancel();
    _sub = null;
    overdueCount.value = 0;
    _started = false;
  }

  void _bind(String? uid) {
    _sub?.cancel();
    overdueCount.value = 0;
    if (uid == null) return;

    final fs = FirebaseFirestore.instance;

    // Para evitar índices obrigatórios, fazemos o filtro principal no cliente.
    _sub = fs
        .collection('contas_pagar')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) {
            final today = DateTime.now();
            final today00 = DateTime(today.year, today.month, today.day);
            int count = 0;

            for (final doc in snap.docs) {
              final m = doc.data();
              final status = (m['status'] ?? '').toString().toLowerCase();
              if (status == 'pago') continue;

              final valor = _asNum(m['valor']);
              final valorPago = _asNum(m['valorPago']);
              final saldo = (valor - valorPago);
              if (saldo <= 0) continue;

              final ts = m['vencimento'] as Timestamp?;
              final dt = ts?.toDate();
              if (dt == null) continue;

              // vencido se data (à meia-noite) < hoje (à meia-noite)
              final d00 = DateTime(dt.year, dt.month, dt.day);
              if (d00.isBefore(today00)) count++;
            }

            overdueCount.value = count;
          },
          onError: (e, st) {
            debugPrint('PayablesOverdueWatcher error: $e');
          },
        );
  }

  double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }
}
