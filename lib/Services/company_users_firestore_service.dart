// lib/services/company_users_firestore_service.dart
/*import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CompanyUsersFirestoreService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Remove espaços visíveis e invisíveis nas bordas e baixa caixa
  String _normalizeEmail(String email) {
    final trimmed =
        email
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '') // zero-width, BOM
            .trim();
    return trimmed.toLowerCase();
  }

  // Conjunto de variações para cobrir dados antigos
  List<String> _emailCandidates(String email) {
    final orig = email;
    final trimOnly =
        email.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
    final lowerOnly = email.toLowerCase();
    final norm = _normalizeEmail(email);
    final set = <String>{orig, trimOnly, lowerOnly, norm};
    set.removeWhere((e) => e.isEmpty);
    return set.toList();
  }

  /// Lógica: se JÁ existir qualquer doc em `users` com esse e-mail (qualquer
  /// variação), NÃO faz nada e retorna (created=false, docId=existente).
  /// Senão, cria um NOVO doc em `users` com role='admin' e retorna (created=true).
  Future<({String docId, bool created})> verificarOuCriarAdminPorEmail({
    required String email,
    required String nome,
    bool active = true,
    Map<String, dynamic> permissions = const {},
    String? companyId, // opcional: se quiser fixar a empresa do novo admin
  }) async {
    final current = _auth.currentUser;
    if (current == null) {
      throw Exception('Sem usuário logado.');
    }

    final normalizedEmail = _normalizeEmail(email);
    final displayName =
        nome.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
    if (normalizedEmail.isEmpty) throw Exception('E-mail inválido/vazio.');
    if (displayName.length < 2) throw Exception('Nome muito curto.');

    // 0) (Opcional) herdar companyId do solicitante se não vier por parâmetro
    String? requesterCompanyId = companyId;
    if (requesterCompanyId == null) {
      final me = await _fs.collection('users').doc(current.uid).get();
      requesterCompanyId = (me.data()?['companyId'] as String?)?.trim();
    }

    // 1) Pré-checagem por emailKey (se já existir nos docs antigos)
    QuerySnapshot<Map<String, dynamic>> q =
        await _fs
            .collection('users')
            .where('emailKey', isEqualTo: normalizedEmail)
            .limit(1)
            .get();

    // 2) Fallback: procurar por 'email' usando whereIn com variações
    if (q.docs.isEmpty) {
      final candidates = _emailCandidates(email);
      if (candidates.length == 1) {
        q =
            await _fs
                .collection('users')
                .where('email', isEqualTo: candidates.first)
                .limit(1)
                .get();
      } else {
        // whereIn aceita até 10 itens
        q =
            await _fs
                .collection('users')
                .where('email', whereIn: candidates.take(10).toList())
                .limit(1)
                .get();
      }
    }

    if (q.docs.isNotEmpty) {
      // Já existe => NÃO cria nada
      final existing = q.docs.first;
      return (docId: existing.id, created: false);
    }

    // 3) Transação com índice determinístico para unicidade real
    final indexRef = _fs.collection('_user_email_index').doc(normalizedEmail);
    return await _fs.runTransaction<({String docId, bool created})>((tx) async {
      final idx = await tx.get(indexRef);
      if (idx.exists) {
        final data = idx.data() as Map<String, dynamic>? ?? {};
        final existingUserId = (data['userId'] ?? '').toString();
        if (existingUserId.isNotEmpty) {
          // Outro processo já reservou esse e-mail
          return (docId: existingUserId, created: false);
        }
        // índice órfão: continua criação abaixo
      }

      final now = FieldValue.serverTimestamp();
      final newUserRef = _fs.collection('users').doc();
      tx.set(newUserRef, {
        'active': active,
        'companyId': requesterCompanyId, // se houver
        'createdAt': now,
        'updatedAt': now,
        'displayName': displayName,
        'email': normalizedEmail, // sempre salvo normalizado
        'emailKey': normalizedEmail, // chave canônica
        'permissions': permissions,
        'role1': 'adminnn', // <- requisito
        'createdBy': current.uid,
      });

      tx.set(indexRef, {
        'userId': newUserRef.id,
        'email': normalizedEmail,
        'companyId': requesterCompanyId,
        'createdAt': now,
      });

      return (docId: newUserRef.id, created: true);
    });
  }
}*/
