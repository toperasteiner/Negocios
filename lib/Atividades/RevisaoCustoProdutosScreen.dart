import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RevisaoCustoProdutosScreen extends StatefulWidget {
  const RevisaoCustoProdutosScreen({super.key});

  @override
  State<RevisaoCustoProdutosScreen> createState() =>
      _RevisaoCustoProdutosScreenState();
}

class _RevisaoCustoProdutosScreenState
    extends State<RevisaoCustoProdutosScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  String? _erro;
  String? _scopeField;
  String? _scopeValue;

  @override
  void initState() {
    super.initState();
    _initScope();
  }

  Future<void> _initScope() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        setState(() {
          _erro = 'Usuário não autenticado.';
          _loading = false;
        });
        return;
      }

      final userDoc = await _fs.collection('users').doc(user.uid).get();
      final data = userDoc.data() ?? {};
      final companyId = (data['companyId'] ?? '').toString().trim();

      setState(() {
        _scopeField = companyId.isNotEmpty ? 'companyId' : 'userId';
        _scopeValue = companyId.isNotEmpty ? companyId : user.uid;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar dados: $e';
        _loading = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _produtosStream() {
    return _fs
        .collection('produtos')
        .where(_scopeField!, isEqualTo: _scopeValue)
        .snapshots();
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();

    return double.tryParse(
          v
              .toString()
              .replaceAll('R\$', '')
              .replaceAll('.', '')
              .replaceAll(',', '.')
              .trim(),
        ) ??
        0.0;
  }

  bool _custoDiferente(Map<String, dynamic> data) {
    final custo = _toDouble(data['custo']);
    final precoMedio = _toDouble(data['precoMedio']);

    if (precoMedio <= 0) return false;

    return (custo - precoMedio).abs() >= 0.01;
  }

  String _fmtMoeda(double valor) {
    final sinal = valor < 0 ? '-' : '';
    final v = valor.abs();
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );

    return '${sinal}R\$ $inteiro,${p[1]}';
  }

  double _calcularValorVendaSugerido({
    required double custoAtual,
    required double custoSugerido,
    required double valorVendaAtual,
  }) {
    if (custoSugerido <= 0) return valorVendaAtual;

    if (custoAtual <= 0) {
      return valorVendaAtual > 0 ? valorVendaAtual : custoSugerido;
    }

    final margemAtual = (valorVendaAtual - custoAtual) / custoAtual;

    final valorSugerido = custoSugerido + (custoSugerido * margemAtual);

    if (valorSugerido <= 0) return valorVendaAtual;

    return valorSugerido;
  }

  Future<void> _usarValoresSugeridos({
    required String produtoId,
    required double custoSugerido,
    required double valorVendaSugerido,
  }) async {
    await _fs.collection('produtos').doc(produtoId).update({
      'custo': custoSugerido,
      'precoMedio': custoSugerido,
      'valorVenda': valorVendaSugerido,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Valores sugeridos aplicados com sucesso.')),
    );
  }

  Future<void> _manterValores({
    required String produtoId,
    required double custoAtual,
  }) async {
    await _fs.collection('produtos').doc(produtoId).update({
      'precoMedio': custoAtual,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Valores mantidos. Preço médio ajustado ao custo atual.'),
      ),
    );
  }

  Future<void> _informarNovosValores({
    required String produtoId,
    required double custoAtual,
    required double valorVendaAtual,
  }) async {
    final custoController = TextEditingController(
      text: custoAtual.toStringAsFixed(2).replaceAll('.', ','),
    );

    final vendaController = TextEditingController(
      text: valorVendaAtual.toStringAsFixed(2).replaceAll('.', ','),
    );

    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Informar novos valores'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: custoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Novo custo',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vendaController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Novo valor de venda',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                final novoCusto = _toDouble(custoController.text);
                final novaVenda = _toDouble(vendaController.text);

                if (novoCusto <= 0 || novaVenda <= 0) {
                  return;
                }

                Navigator.pop(dialogContext, {
                  'custo': novoCusto,
                  'venda': novaVenda,
                });
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    custoController.dispose();
    vendaController.dispose();

    if (result == null) return;

    final novoCusto = result['custo'] ?? 0.0;
    final novaVenda = result['venda'] ?? 0.0;

    await _fs.collection('produtos').doc(produtoId).update({
      'custo': novoCusto,
      'precoMedio': novoCusto,
      'valorVenda': novaVenda,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Valores atualizados com sucesso.')),
    );
  }

  Widget _metric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _produtoCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final cs = Theme.of(context).colorScheme;

    final nome = (data['nome'] ?? 'Produto sem nome').toString();
    final unidade = (data['unidade'] ?? '').toString();
    final estoque = _toDouble(data['estoque']);
    final custo = _toDouble(data['custo']);
    final precoMedio = _toDouble(data['precoMedio']);
    final valorVenda = _toDouble(data['valorVenda']);

    final custoSugerido = precoMedio;

    final valorVendaSugerido = _calcularValorVendaSugerido(
      custoAtual: custo,
      custoSugerido: custoSugerido,
      valorVendaAtual: valorVenda,
    );

    final diferenca = custoSugerido - custo;
    final aumento = diferenca > 0;

    final variacaoPercentual =
        custo <= 0 ? 0.0 : ((custoSugerido - custo) / custo) * 100;

    final corDiferenca = aumento ? Colors.orange : Colors.blue;

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: corDiferenca.withOpacity(0.13),
                    child: Icon(
                      aumento
                          ? Icons.trending_up_outlined
                          : Icons.trending_down_outlined,
                      color: corDiferenca,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Estoque: ${estoque.toStringAsFixed(2)} $unidade',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: corDiferenca.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${variacaoPercentual.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: corDiferenca,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metric(
                    icon: Icons.attach_money_outlined,
                    label: 'Custo atual',
                    value: _fmtMoeda(custo),
                    color: Colors.grey,
                  ),
                  _metric(
                    icon: Icons.auto_graph_outlined,
                    label: 'Custo sugerido',
                    value: _fmtMoeda(custoSugerido),
                    color: Colors.green,
                  ),
                  _metric(
                    icon: Icons.sell_outlined,
                    label: 'Valor de Venda atual',
                    value: _fmtMoeda(valorVenda),
                    color: Colors.blue,
                  ),
                  _metric(
                    icon: Icons.trending_up_outlined,
                    label: 'Valor de Venda sugerido',
                    value: _fmtMoeda(valorVendaSugerido),
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  aumento
                      ? 'O custo sugerido está maior que o custo atual. O valor de venda sugerido mantém a margem atual do produto.'
                      : 'O custo sugerido está menor que o custo atual. Avalie se deseja reduzir o custo e ajustar o valor de venda.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 520;

                  final manter = OutlinedButton.icon(
                    onPressed:
                        () => _manterValores(
                          produtoId: doc.id,
                          custoAtual: custo,
                        ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Manter'),
                  );

                  final novo = OutlinedButton.icon(
                    onPressed:
                        () => _informarNovosValores(
                          produtoId: doc.id,
                          custoAtual: custo,
                          valorVendaAtual: valorVenda,
                        ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Novo valor'),
                  );

                  final atualizar = FilledButton.icon(
                    onPressed:
                        () => _usarValoresSugeridos(
                          produtoId: doc.id,
                          custoSugerido: custoSugerido,
                          valorVendaSugerido: valorVendaSugerido,
                        ),
                    icon: const Icon(Icons.sync_alt_outlined),
                    label: const Text('Usar valores sugeridos'),
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        atualizar,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: manter),
                            const SizedBox(width: 8),
                            Expanded(child: novo),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: manter),
                      const SizedBox(width: 8),
                      Expanded(child: novo),
                      const SizedBox(width: 8),
                      Expanded(child: atualizar),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero({required int pendentes, required int totalProdutos}) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer,
            cs.secondaryContainer.withOpacity(0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.price_check_outlined, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisão de custos e venda',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  pendentes == 0
                      ? 'Todos os produtos estão alinhados com o custo sugerido.'
                      : '$pendentes de $totalProdutos produto(s) precisam de atenção.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Revisar custos')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar custos')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _produtosStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erro ao carregar produtos: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          final pendentes =
              docs.where((doc) => _custoDiferente(doc.data())).toList();

          pendentes.sort((a, b) {
            final da = a.data();
            final db = b.data();

            final diffA =
                (_toDouble(da['precoMedio']) - _toDouble(da['custo'])).abs();
            final diffB =
                (_toDouble(db['precoMedio']) - _toDouble(db['custo'])).abs();

            return diffB.compareTo(diffA);
          });

          if (pendentes.isEmpty) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _hero(pendentes: 0, totalProdutos: docs.length),
                ),
                const Expanded(child: _EmptyWrapper()),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _hero(pendentes: pendentes.length, totalProdutos: docs.length),
              const SizedBox(height: 12),
              ...pendentes.map(_produtoCard),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyWrapper extends StatelessWidget {
  const _EmptyWrapper();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 68,
              color: Colors.green.shade600,
            ),
            const SizedBox(height: 14),
            const Text(
              'Custos atualizados',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Nenhum produto está com custo diferente do preço médio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
