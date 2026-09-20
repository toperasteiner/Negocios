import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

class ReviewService {
  ReviewService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    InAppReview? inAppReview,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _fs = firestore ?? FirebaseFirestore.instance,
       _review = inAppReview ?? InAppReview.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _fs;
  final InAppReview _review;

  // ======= CONFIG =======
  static const int maxRequestsPerUser = 5;
  static const int minDaysBetweenRequests = 10;

  /// Exemplo de gatilho: pedir review só após X "eventos" positivos.
  static const int minPositiveEventsToAsk = 1;

  // Coleções / docs
  static const String _colUsers = 'users';
  static const String _subSettings = 'settings';
  static const String _docReview = 'review_prompt';

  static const String _colFeedback = 'review_feedback';

  DocumentReference<Map<String, dynamic>> _reviewDocRef(String uid) {
    return _fs
        .collection(_colUsers)
        .doc(uid)
        .collection(_subSettings)
        .doc(_docReview);
  }

  // ======= PUBLIC API =======

  /// Incrementa contador de eventos positivos (ex.: ação concluída com sucesso).
  /// Chame isso quando o usuário fizer algo que gere valor e satisfação.
  Future<void> registerPositiveEvent() async {
    final u = _auth.currentUser;
    if (u == null) return;

    final ref = _reviewDocRef(u.uid);
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final int count = (data['positiveEvents'] ?? 0) as int;
      tx.set(ref, {
        ...data,
        'positiveEvents': count + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Tenta mostrar o fluxo de review (com controle de frequência + filtro de satisfação).
  /// Retorna true se disparou algum fluxo (review ou feedback).
  Future<bool> maybeAskForReview(BuildContext context) async {
    final u = _auth.currentUser;
    if (u == null) return false;

    final ref = _reviewDocRef(u.uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};

    final int requestCount = (data['requestCount'] ?? 0) as int;
    final int positiveEvents = (data['positiveEvents'] ?? 0) as int;
    final Timestamp? lastReqTs = data['lastRequestAt'] as Timestamp?;
    final DateTime? lastReq = lastReqTs != null ? lastReqTs.toDate() : null;

    // 1) limite de solicitações por usuário
    if (requestCount >= maxRequestsPerUser) return false;

    // 2) precisa atingir o gatilho mínimo
    if (positiveEvents < minPositiveEventsToAsk) return false;

    // 3) intervalo mínimo entre solicitações
    if (lastReq != null) {
      final diffDays = DateTime.now().difference(lastReq).inDays;
      if (diffDays < minDaysBetweenRequests) return false;
    }

    // 4) checa se API está disponível
    final isAvailable = await _review.isAvailable();
    if (!isAvailable) {
      // fallback: abre Play Store (opcional)
      // Você pode retornar false aqui se não quiser fallback.
      return await _showSatisfactionGate(context, fallbackToStore: true);
    }

    // 5) Gate de satisfação
    return await _showSatisfactionGate(context, fallbackToStore: false);
  }

  // ======= INTERNALS =======

  Future<bool> _showSatisfactionGate(
    BuildContext context, {
    required bool fallbackToStore,
  }) async {
    final u = _auth.currentUser;
    if (u == null) return false;

    final bool? liked = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => AlertDialog(
            title: const Text('Você está gostando do app?'),
            content: const Text(
              'Seu feedback ajuda a melhorar. Leva poucos segundos 🙂',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Não muito'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sim!'),
              ),
            ],
          ),
    );

    if (liked == null) return false;

    if (liked == true) {
      // Usuario satisfeito -> pede review
      await _markRequestAttempt();
      final did = await _requestReviewOrFallback(
        fallbackToStore: fallbackToStore,
      );
      return did;
    } else {
      // Usuario insatisfeito -> coleta feedback interno
      await _openFeedbackDialog(context);
      await _markRequestAttempt(didOpenFeedback: true);
      return true;
    }
  }

  Future<void> _markRequestAttempt({bool didOpenFeedback = false}) async {
    final u = _auth.currentUser;
    if (u == null) return;

    final ref = _reviewDocRef(u.uid);

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final int requestCount = (data['requestCount'] ?? 0) as int;

      tx.set(ref, {
        ...data,
        'requestCount': requestCount + 1,
        'lastRequestAt': FieldValue.serverTimestamp(),
        'lastRequestType': didOpenFeedback ? 'feedback' : 'review',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<bool> _requestReviewOrFallback({required bool fallbackToStore}) async {
    try {
      // Observação: a API do Google decide se vai exibir ou não o popup.
      await _review.requestReview();
      return true;
    } catch (_) {
      if (!fallbackToStore) return false;
      return await _openStoreListing();
    }
  }

  Future<bool> _openStoreListing() async {
    // Troque pelo seu packageId:
    const packageId = 'com.seuapp.seupacote';
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageId',
    );
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  Future<void> _openFeedbackDialog(BuildContext context) async {
    final u = _auth.currentUser;
    if (u == null) return;

    final ctrl = TextEditingController();
    final bool? send = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => AlertDialog(
            title: const Text('Conte pra gente o que melhorar'),
            content: TextField(
              controller: ctrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Ex.: Está difícil encontrar tal função…',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
    );

    if (send != true) return;

    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    await _fs.collection(_colFeedback).add({
      'uid': u.uid,
      'message': text,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': Theme.of(context).platform.toString(),
    });
  }
}
