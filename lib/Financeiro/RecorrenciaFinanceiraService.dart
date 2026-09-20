import 'package:cloud_firestore/cloud_firestore.dart';

class RecorrenciaFinanceiraService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  Future<void> gerarContasRecorrentesDoMes({
    required String companyId,
    required String userId,
  }) async {
    final hoje = DateTime.now();
    final competencia = '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}';

    await _gerarContasPagar(
      companyId: companyId,
      userId: userId,
      competencia: competencia,
      ano: hoje.year,
      mes: hoje.month,
    );

    await _gerarContasReceber(
      companyId: companyId,
      userId: userId,
      competencia: competencia,
      ano: hoje.year,
      mes: hoje.month,
    );
  }

  Future<void> _gerarContasPagar({
    required String companyId,
    required String userId,
    required String competencia,
    required int ano,
    required int mes,
  }) async {
    final snap =
        await _fs
            .collection('recorrencias_pagar')
            .where('companyId', isEqualTo: companyId)
            .where('ativo', isEqualTo: true)
            .get();

    for (final doc in snap.docs) {
      final r = doc.data();

      final jaGerou = r['ultimaGeracao'] == competencia;
      if (jaGerou) continue;

      final dia = _diaValido(
        (r['diaVencimento'] as num?)?.toInt() ?? 1,
        ano,
        mes,
      );
      final vencimento = DateTime(ano, mes, dia);

      final contaId = '${doc.id}_$competencia';

      final contaRef = _fs.collection('contas_pagar').doc(contaId);

      final contaExistente = await contaRef.get();
      if (contaExistente.exists) {
        await doc.reference.update({
          'ultimaGeracao': competencia,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        continue;
      }

      await contaRef.set({
        'companyId': companyId,
        'userId': userId,
        'createdByUid': r['createdByUid'] ?? userId,

        'descricao':
            '${r['descricao']} - ${mes.toString().padLeft(2, '0')}/$ano',

        'categoriaId': r['categoriaId'],
        'categoriaKey': r['categoriaKey'],
        'categoriaNome': r['categoriaNome'],

        'fornecedorId': r['fornecedorId'],
        'fornecedorNome': r['fornecedorNome'],

        'valor': (r['valor'] as num?)?.toDouble() ?? 0.0,
        'status': 'aberto',

        'origem': 'recorrencia',
        'recorrenciaId': doc.id,
        'competencia': competencia,

        'vencimento': Timestamp.fromDate(vencimento),

        'observacao': r['observacao'],

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await doc.reference.update({
        'ultimaGeracao': competencia,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _gerarContasReceber({
    required String companyId,
    required String userId,
    required String competencia,
    required int ano,
    required int mes,
  }) async {
    final snap =
        await _fs
            .collection('recorrencias_receber')
            .where('companyId', isEqualTo: companyId)
            .where('ativo', isEqualTo: true)
            .get();

    for (final doc in snap.docs) {
      final r = doc.data();

      final jaGerou = r['ultimaGeracao'] == competencia;
      if (jaGerou) continue;

      final dia = _diaValido(
        (r['diaVencimento'] as num?)?.toInt() ?? 1,
        ano,
        mes,
      );
      final vencimento = DateTime(ano, mes, dia);

      final contaId = '${doc.id}_$competencia';

      final contaRef = _fs.collection('contas_receber').doc(contaId);

      final contaExistente = await contaRef.get();
      if (contaExistente.exists) {
        await doc.reference.update({
          'ultimaGeracao': competencia,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        continue;
      }

      await contaRef.set({
        'companyId': companyId,
        'userId': userId,
        'createdByUid': r['createdByUid'] ?? userId,

        'descricao':
            '${r['descricao']} - ${mes.toString().padLeft(2, '0')}/$ano',

        'categoriaId': r['categoriaId'],
        'categoriaKey': r['categoriaKey'],
        'categoriaNome': r['categoriaNome'],

        'clienteId': r['clienteId'],
        'clienteNome': r['clienteNome'],

        'valor': (r['valor'] as num?)?.toDouble() ?? 0.0,
        'status': 'aberto',

        'origem': 'recorrencia',
        'recorrenciaId': doc.id,
        'competencia': competencia,

        'parcelaNumero': 1,
        'parcelasTotal': 1,

        'vencimento': Timestamp.fromDate(vencimento),

        'observacao': r['observacao'],

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await doc.reference.update({
        'ultimaGeracao': competencia,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  int _diaValido(int dia, int ano, int mes) {
    final ultimoDia = DateTime(ano, mes + 1, 0).day;

    if (dia < 1) return 1;
    if (dia > ultimoDia) return ultimoDia;

    return dia;
  }
}
