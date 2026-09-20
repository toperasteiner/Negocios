import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AprovarCotacoesFreteScreen extends StatefulWidget {
  final String cotacaoId;

  const AprovarCotacoesFreteScreen({super.key, required this.cotacaoId});

  @override
  State<AprovarCotacoesFreteScreen> createState() =>
      _AprovarCotacoesFreteScreenState();
}

class _AprovarCotacoesFreteScreenState
    extends State<AprovarCotacoesFreteScreen> {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color green = Color(0xFF08A64B);
  static const Color red = Color(0xFFE53935);
  static const Color orange = Color(0xFFFF6A21);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color background = Color(0xFFFBFAFF);

  bool _processando = false;

  Map<String, dynamic>? _dadosCotacao;

  @override
  void initState() {
    super.initState();
    _carregarCotacaoPrincipal();
  }

  Future<void> _carregarCotacaoPrincipal() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('cotacoes_frete_internacional')
            .doc(widget.cotacaoId)
            .get();

    if (doc.exists && mounted) {
      setState(() {
        _dadosCotacao = doc.data();
      });
    }
  }

  Future<void> _aprovarCotacao(
    String orcamentoId,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _mensagem('Usuário não autenticado.');
      return;
    }

    setState(() => _processando = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      final query =
          await FirebaseFirestore.instance
              .collection('cotacoes_frete_orcamentos')
              .where('companyId', isEqualTo: user.uid)
              .where('cotacaoId', isEqualTo: widget.cotacaoId)
              .get();

      for (final doc in query.docs) {
        if (doc.id == orcamentoId) {
          batch.update(doc.reference, {
            'status': 'Aprovado',
            'aprovado': true,
            'aprovadoAt': FieldValue.serverTimestamp(),
            'aprovadoByUid': user.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          batch.update(doc.reference, {
            'status': 'Reprovado',
            'aprovado': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      final cotacaoRef = FirebaseFirestore.instance
          .collection('cotacoes_frete_internacional')
          .doc(widget.cotacaoId);

      batch.update(cotacaoRef, {
        'status': 'Aprovada',
        'orcamentoVencedorId': orcamentoId,
        'fornecedorVencedor': data['fornecedorNome'] ?? '',
        'referenciaPropostaVencedora': data['referencia'] ?? '',
        'dataAprovacao': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      _mensagem('Cotação aprovada com sucesso.');
    } catch (e) {
      _mensagem('Erro ao aprovar cotação: $e');
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _reprovarCotacao(String orcamentoId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _mensagem('Usuário não autenticado.');
      return;
    }

    setState(() => _processando = true);

    try {
      await FirebaseFirestore.instance
          .collection('cotacoes_frete_orcamentos')
          .doc(orcamentoId)
          .update({
            'status': 'Reprovado',
            'aprovado': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _mensagem('Proposta reprovada.');
    } catch (e) {
      _mensagem('Erro ao reprovar proposta: $e');
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  void _confirmarAprovacao(
    String orcamentoId,
    String fornecedor,
    Map<String, dynamic> data,
  ) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Aprovar proposta'),
            content: Text(
              'Deseja aprovar a proposta de "$fornecedor"?\n\n'
              'As demais propostas desta cotação serão marcadas como reprovadas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _aprovarCotacao(orcamentoId, data);
                },
                child: const Text('Aprovar'),
              ),
            ],
          ),
    );
  }

  void _confirmarReprovacao(String orcamentoId, String fornecedor) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Reprovar proposta'),
            content: Text('Deseja reprovar a proposta de "$fornecedor"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _reprovarCotacao(orcamentoId);
                },
                child: const Text('Reprovar'),
              ),
            ],
          ),
    );
  }

  void _mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
    );
  }

  String _texto(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _formatarMoedaBR(dynamic value) {
    double valor = 0;

    if (value is num) {
      valor = value.toDouble();
    } else if (value is String) {
      valor =
          double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }

    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatarData(dynamic value) {
    if (value == null) return '-';

    DateTime? data;

    if (value is Timestamp) {
      data = value.toDate();
    } else if (value is DateTime) {
      data = value;
    }

    if (data == null) return '-';

    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  double _calcularCustoTotalBR(Map<String, dynamic> data) {
    final camposPossiveis = [
      data['custoTotalCotacaoBRL'],
      data['custoTotalBRL'],
      data['custoTotal'],
      data['valorTotalBRL'],
      data['valorTotal'],
    ];

    for (final campo in camposPossiveis) {
      if (campo is num) return campo.toDouble();
      if (campo is String) {
        final valor = double.tryParse(
          campo.replaceAll('.', '').replaceAll(',', '.'),
        );
        if (valor != null) return valor;
      }
    }

    final valores = data['valores'];

    if (valores is List) {
      double total = 0;

      for (final item in valores) {
        if (item is Map) {
          final moeda = _texto(item['moeda']).toUpperCase();
          final valor = item['valor'];

          if (moeda == 'BRL' || moeda == 'R\$' || moeda == 'REAL') {
            if (valor is num) {
              total += valor.toDouble();
            } else if (valor is String) {
              total +=
                  double.tryParse(
                    valor.replaceAll('.', '').replaceAll(',', '.'),
                  ) ??
                  0;
            }
          }
        }
      }

      return total;
    }

    return 0;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Aprovado':
        return green;
      case 'Reprovado':
      case 'Cancelado':
        return red;
      case 'Em análise':
        return orange;
      case 'Contratado':
        return purple;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Usuário não autenticado.')),
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Browser de Propostas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('cotacoes_frete_orcamentos')
                .where('companyId', isEqualTo: user.uid)
                .where('cotacaoId', isEqualTo: widget.cotacaoId)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma proposta encontrada para esta cotação.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final numeroCotacao = _texto(
                data['referenciaCotacao'] ??
                    _dadosCotacao?['referencia'] ??
                    widget.cotacaoId,
              );

              final referenciaProposta = _texto(data['referencia']);
              final fornecedor = _texto(data['fornecedorNome']);
              final localEmbarque = _texto(
                data['localEmbarque'] ??
                    _dadosCotacao?['localEmbarque'] ??
                    _dadosCotacao?['localOrigem'] ??
                    _dadosCotacao?['origem'],
              );
              final localDestino = _texto(
                data['localDestino'] ??
                    _dadosCotacao?['localDestino'] ??
                    _dadosCotacao?['destino'],
              );

              final custoTotalBR = _calcularCustoTotalBR(data);
              final condicaoPagamento = _texto(data['condicaoPagamento']);
              final transitTime = _texto(data['transitTime']);
              final freeTime = _texto(
                data['freeTimeDestino'] ??
                    data['freeTimeOrigem'] ??
                    data['freeTime'],
              );
              final validade =
                  data['dataValidade'] != null
                      ? _formatarData(data['dataValidade'])
                      : _texto(data['validadeProposta']);

              final status = _texto(data['status']);
              final statusColor = _statusColor(status);

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: statusColor.withOpacity(0.20)),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.12),
                          child: Icon(
                            Icons.request_quote_outlined,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            referenciaProposta,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    _linhaBrowser('Número da cotação', numeroCotacao),
                    _linhaBrowser('Referência da proposta', referenciaProposta),
                    _linhaBrowser('Fornecedor', fornecedor),
                    _linhaBrowser('Local de Embarque', localEmbarque),
                    _linhaBrowser('Local Destino', localDestino),
                    _linhaBrowser(
                      'Custo Total Cotação R\$',
                      _formatarMoedaBR(custoTotalBR),
                      destaque: true,
                    ),
                    _linhaBrowser('Condição de pagamento', condicaoPagamento),
                    _linhaBrowser('Transit time', transitTime),
                    _linhaBrowser('Free time', freeTime),
                    _linhaBrowser('Validade da cotação', validade),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _processando
                                    ? null
                                    : () => _confirmarReprovacao(
                                      doc.id,
                                      fornecedor,
                                    ),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Reprovar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: red,
                              side: const BorderSide(color: red),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _processando
                                    ? null
                                    : () => _confirmarAprovacao(
                                      doc.id,
                                      fornecedor,
                                      data,
                                    ),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Aprovar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _linhaBrowser(String label, String value, {bool destaque = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.12)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: destaque ? green : textDark,
                fontSize: destaque ? 15 : 13,
                fontWeight: destaque ? FontWeight.w900 : FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
