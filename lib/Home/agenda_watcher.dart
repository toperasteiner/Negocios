// lib/home/agenda_watcher.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Monitora compromissos do usuário em `agenda`.
/// - overdueToday: compromissos de HOJE já atrasados (compromisso < agora)
/// - startingIn30: compromissos que começam nos PRÓXIMOS 30 minutos (agora..agora+30min)
class AgendaWatcher {
  AgendaWatcher._();
  static final AgendaWatcher instance = AgendaWatcher._();

  /// Atrasados HOJE
  final ValueNotifier<int> overdueToday = ValueNotifier<int>(0);

  /// Iniciam em até 30 minutos
  final ValueNotifier<int> startingIn30 = ValueNotifier<int>(0);

  /// total para badge (atrasados hoje + iniciando em 30min)
  late final ValueListenable<int> totalAlerts = _CombinedSum([
    overdueToday,
    startingIn30,
  ]);

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _started = false;

  /// Inicia o monitoramento (idempotente)
  void start() {
    if (_started) return;
    _started = true;

    _bind(FirebaseAuth.instance.currentUser?.uid);

    // reage a login/logout
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _bind(u?.uid);
    });
  }

  /// Encerra streams e zera contadores
  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _sub?.cancel();
    _sub = null;
    overdueToday.value = 0;
    startingIn30.value = 0;
    _started = false;
  }

  void _bind(String? uid) {
    _sub?.cancel();
    overdueToday.value = 0;
    startingIn30.value = 0;

    if (uid == null) return;

    final fs = FirebaseFirestore.instance;

    // Janela: apenas compromissos do DIA corrente
    final now = DateTime.now();
    final hoje00 = _at00(now);
    final amanha00 = hoje00.add(const Duration(days: 1));

    _sub = fs
        .collection('agenda')
        .where('userId', isEqualTo: uid)
        .where(
          'compromisso',
          isGreaterThanOrEqualTo: Timestamp.fromDate(hoje00),
        )
        .where('compromisso', isLessThan: Timestamp.fromDate(amanha00))
        .orderBy('compromisso') // range/order no mesmo campo
        .snapshots()
        .listen(
          (snap) {
            final now = DateTime.now();
            final in30 = now.add(const Duration(minutes: 30));

            int overdue = 0;
            int soon = 0;

            for (final doc in snap.docs) {
              final m = doc.data();

              // compromisso (Timestamp) -> DateTime
              final ts = m['compromisso'];
              DateTime? dt;
              if (ts is Timestamp) {
                dt = ts.toDate();
              } else if (ts is DateTime) {
                dt = ts;
              }
              if (dt == null) continue;

              // Contagem
              if (dt.isBefore(now)) {
                // começou e já está atrasado (considerando notificação de início)
                overdue++;
              } else if (!dt.isAfter(in30)) {
                // começa até 30min (dt ∈ (now, now+30])
                soon++;
              }
            }

            overdueToday.value = overdue;
            startingIn30.value = soon;
          },
          onError: (e, st) {
            debugPrint('AgendaWatcher error: $e');
          },
        );
  }

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Soma simples de vários ValueNotifier<int>
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
