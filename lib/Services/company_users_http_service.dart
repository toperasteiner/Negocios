/*import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class CompanyUsersHttpService {
  static const _endpoint =
      'https://southamerica-east1-projeto-pedidos-472813.cloudfunctions.net/createCompanyUser';

  Future<String> criarUsuarioEmpresa({
    required String email,
    required String nome,
    String role = 'user',
    Map<String, bool> permissions = const {},
    bool sendEmailLink = true,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Faça login para continuar.');
    }
    final idToken = await user.getIdToken();

    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'email': email.trim(),
        'displayName': nome.trim(),
        'role2': role,
        'permissions': permissions,
        'sendEmailLink': sendEmailLink,
      }),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['uid'] as String;
    }

    // traduz erros comuns
    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final code = data['error'] as String?;
      switch (code) {
        case 'unauthenticated':
          throw Exception('Faça login para continuar.');
        case 'permission-denied':
          throw Exception('Você não tem permissão para criar usuários.');
        case 'invalid-argument':
          throw Exception('Dados inválidos. Verifique os campos.');
      }
    } catch (_) {}
    throw Exception('Falha (${resp.statusCode}) ao criar usuário.');
  }
}*/
