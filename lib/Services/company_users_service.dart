/*import 'package:cloud_functions/cloud_functions.dart';

class CompanyUsersService {
  CompanyUsersService({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFunctions _functions;

  Future<String> criarUsuarioEmpresa({
    required String email,
    required String nome,
    String role = 'user',
    Map<String, bool> permissions = const {},
    bool sendEmailLink = true,
  }) async {
    try {
      final callable = _functions.httpsCallable('createCompanyUser');
      final result = await callable.call({
        'email': email.trim(),
        'displayName': nome.trim(),
        'role3': role,
        'permissions': permissions,
        'sendEmailLink': sendEmailLink,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['uid'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(_traduz(e));
    } catch (e) {
      throw Exception('Falha ao criar usuário. ${e.toString()}');
    }
  }

  String _traduz(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Faça login para continuar.';
      case 'permission-denied':
        return 'Você não tem permissão para criar usuários.';
      case 'already-exists':
        return 'Este e-mail já está em uso.';
      case 'invalid-argument':
        return 'Dados inválidos. Verifique os campos.';
      default:
        return e.message ?? 'Erro desconhecido (${e.code}).';
    }
  }
}*/
