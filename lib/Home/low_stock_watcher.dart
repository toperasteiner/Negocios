// lib/home/low_stock_watcher.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LowStockWatcher {
  LowStockWatcher._();
  static final LowStockWatcher instance = LowStockWatcher._();

  final ValueNotifier<int> countListenable = ValueNotifier<int>(0);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<User?>? _authSub;
  bool _started = false;

  /// Inicia o monitoramento (idempotente)
  void start() {
    if (_started) return;
    _started = true;

    // Reage a login/logout
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _bind(user?.uid);
    });

    // Liga imediatamente para o usuário atual (se houver)
    _bind(FirebaseAuth.instance.currentUser?.uid);
  }

  /// Encerra streams (opcional)
  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _sub?.cancel();
    _sub = null;
    _started = false;
    countListenable.value = 0;
  }

  void _bind(String? uid) {
    _sub?.cancel();
    countListenable.value = 0;

    if (uid == null) return;

    final fs = FirebaseFirestore.instance;

    // Carrega somente produtos que controlam estoque do usuário
    _sub = fs
        .collection('produtos')
        .where('userId', isEqualTo: uid)
        .where('controlaEstoque', isEqualTo: true)
        .snapshots()
        .listen(
          (snap) {
            int low = 0;
            for (final doc in snap.docs) {
              final m = doc.data();
              final estoque = _asNum(m['estoque']);
              final alerta = _asNum(m['estoqueAlerta']);
              if (alerta > 0 && estoque < alerta) {
                low++;
              }
            }
            countListenable.value = low;
          },
          onError: (e, st) {
            debugPrint('LowStockWatcher error: $e');
          },
        );
  }

  double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }
}
