import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardGiroEstoqueScreen extends StatefulWidget {
  const DashboardGiroEstoqueScreen({super.key});

  @override
  State<DashboardGiroEstoqueScreen> createState() =>
      _DashboardGiroEstoqueScreenState();
}

class _DashboardGiroEstoqueScreenState
    extends State<DashboardGiroEstoqueScreen> {
  bool _loading = true;
  String? _scopeField;
  String? _scopeValue;

  int _periodoDias = 30;

  double _qtdVendidaTotal = 0;
  double _estoqueAtualTotal = 0;
  double _giroMedio = 0;
  double _diasMedioEstoque = 0;

  List<Map<String, dynamic>> _produtos = [];

  @override
  void initState() {
    super.initState();
    _carregarDashboard();
  }

  Future<void> _carregarDashboard() async {
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Usuário não autenticado.';

      final fs = FirebaseFirestore.instance;

      final userDoc = await fs.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final companyId = (userData?['companyId'] ?? '').toString().trim();

      if (companyId.isNotEmpty) {
        _scopeField = 'companyId';
        _scopeValue = companyId;
      } else {
        _scopeField = 'userId';
        _scopeValue = user.uid;
      }

      final dataInicio = DateTime.now().subtract(Duration(days: _periodoDias));

      final produtosSnap =
          await fs
              .collection('produtos')
              .where(_scopeField!, isEqualTo: _scopeValue)
              .get();

      final Map<String, Map<String, dynamic>> produtosMap = {};

      for (final doc in produtosSnap.docs) {
        final data = doc.data();

        final controlaEstoque = data['controlaEstoque'] == true;
        if (!controlaEstoque) continue;

        final estoque = _toDouble(data['estoque']);
        final custo = _toDouble(data['custo']);
        final precoMedio = _toDouble(data['precoMedio']);
        final custoBase = precoMedio > 0 ? precoMedio : custo;

        produtosMap[doc.id] = {
          'id': doc.id,
          'nome': (data['nome'] ?? 'Produto sem nome').toString(),
          'estoqueAtual': estoque,
          'custoBase': custoBase,
          'qtdVendida': 0.0,
          'valorVendidoCusto': 0.0,
        };
      }

      final pedidosSnap =
          await fs
              .collection('pedidos')
              .where(_scopeField!, isEqualTo: _scopeValue)
              .where(
                'data',
                isGreaterThanOrEqualTo: Timestamp.fromDate(dataInicio),
              )
              .get();

      for (final pedidoDoc in pedidosSnap.docs) {
        final pedido = pedidoDoc.data();

        final status = (pedido['status'] ?? '').toString().toLowerCase();

        if (status.contains('cancel')) continue;
        if (status == 'aguardando_aprovacao_web') continue;

        final itensProdutos = pedido['itensProdutos'];

        if (itensProdutos is! List) continue;

        for (final item in itensProdutos) {
          if (item is! Map) continue;

          final produtoId = _extractProdutoId(item);
          if (produtoId == null || produtoId.isEmpty) continue;

          final produto = produtosMap[produtoId];
          if (produto == null) continue;

          final quantidade = _extractQuantidade(item);
          if (quantidade <= 0) continue;

          produto['qtdVendida'] = _toDouble(produto['qtdVendida']) + quantidade;

          produto['valorVendidoCusto'] =
              _toDouble(produto['valorVendidoCusto']) +
              (quantidade * _toDouble(produto['custoBase']));
        }
      }

      final List<Map<String, dynamic>> lista = [];

      double qtdVendidaTotal = 0;
      double estoqueAtualTotal = 0;
      double somaGiro = 0;
      double somaDiasEstoque = 0;
      int produtosComVenda = 0;

      for (final produto in produtosMap.values) {
        final estoqueAtual = _toDouble(produto['estoqueAtual']);
        final qtdVendida = _toDouble(produto['qtdVendida']);
        final custoBase = _toDouble(produto['custoBase']);

        final estoqueInicialEstimado = estoqueAtual + qtdVendida;
        final estoqueMedio = (estoqueInicialEstimado + estoqueAtual) / 2;

        final giro = estoqueMedio > 0 ? qtdVendida / estoqueMedio : 0;
        final mediaVendaDia = qtdVendida / _periodoDias;
        final diasEstoque =
            mediaVendaDia > 0 ? estoqueAtual / mediaVendaDia : 0;

        qtdVendidaTotal += qtdVendida;
        estoqueAtualTotal += estoqueAtual;

        if (qtdVendida > 0) {
          somaGiro += giro;
          somaDiasEstoque += diasEstoque;
          produtosComVenda++;
        }

        lista.add({
          ...produto,
          'estoqueMedio': estoqueMedio,
          'giro': giro,
          'diasEstoque': diasEstoque,
          'valorEstoqueAtual': estoqueAtual * custoBase,
        });
      }

      lista.sort(
        (a, b) => _toDouble(b['giro']).compareTo(_toDouble(a['giro'])),
      );

      setState(() {
        _qtdVendidaTotal = qtdVendidaTotal;
        _estoqueAtualTotal = estoqueAtualTotal;
        _giroMedio = produtosComVenda > 0 ? somaGiro / produtosComVenda : 0;
        _diasMedioEstoque =
            produtosComVenda > 0 ? somaDiasEstoque / produtosComVenda : 0;
        _produtos = lista;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar giro de estoque: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String? _extractProdutoId(Map item) {
    final value =
        item['produtoId'] ??
        item['idProduto'] ??
        item['refId'] ?? // usado no seu pedido
        item['produtoRefId'] ??
        item['id'] ??
        item['docId'];

    return value?.toString();
  }

  double _extractQuantidade(Map item) {
    return _toDouble(
      item['quantidade'] ??
          item['qtd'] ??
          item['qtde'] ??
          item['quantidadeProduto'],
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value.toString().replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0;
  }

  String _formatNumber(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatMoney(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Color _giroColor(double giro) {
    if (giro >= 1) return Colors.green;
    if (giro >= 0.4) return Colors.orange;
    return Colors.red;
  }

  String _giroLabel(double giro) {
    if (giro >= 1) return 'Alto giro';
    if (giro >= 0.4) return 'Giro médio';
    return 'Baixo giro';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Giro de Estoque'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: _carregarDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _carregarDashboard,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 14),
                    _buildFiltroPeriodo(),
                    const SizedBox(height: 14),
                    _buildResumo(),
                    const SizedBox(height: 14),
                    _buildListaProdutos(),
                  ],
                ),
              ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance do estoque',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Veja quais produtos giram rápido, quais estão parados e quantos dias de estoque ainda existem.',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroPeriodo() {
    return Row(
      children:
          [30, 60, 90].map((dias) {
            final selected = _periodoDias == dias;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$dias dias'),
                selected: selected,
                onSelected: (_) {
                  setState(() => _periodoDias = dias);
                  _carregarDashboard();
                },
              ),
            );
          }).toList(),
    );
  }

  Widget _buildResumo() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                titulo: 'Qtd. vendida',
                valor: _formatNumber(_qtdVendidaTotal),
                icon: Icons.shopping_cart_outlined,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                titulo: 'Estoque atual',
                valor: _formatNumber(_estoqueAtualTotal),
                icon: Icons.inventory_2_outlined,
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                titulo: 'Giro médio',
                valor: _formatPercent(_giroMedio),
                icon: Icons.autorenew,
                color: _giroColor(_giroMedio),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                titulo: 'Dias médios estoque',
                valor: '${_formatNumber(_diasMedioEstoque)} dias',
                icon: Icons.calendar_month_outlined,
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String titulo,
    required String valor,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            valor,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildListaProdutos() {
    final produtosComMovimento =
        _produtos.where((p) => _toDouble(p['qtdVendida']) > 0).toList();

    final produtosParados =
        _produtos.where((p) => _toDouble(p['qtdVendida']) <= 0).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Produtos por giro',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),

          if (produtosComMovimento.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Nenhum produto vendido no período selecionado.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ...produtosComMovimento.map(_buildProdutoCard),

          if (produtosParados.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Produtos sem venda no período (${produtosParados.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 10),
            ...produtosParados.take(10).map(_buildProdutoCard),
          ],
        ],
      ),
    );
  }

  Widget _buildProdutoCard(Map<String, dynamic> produto) {
    final nome = produto['nome'].toString();
    final qtdVendida = _toDouble(produto['qtdVendida']);
    final estoqueAtual = _toDouble(produto['estoqueAtual']);
    final estoqueMedio = _toDouble(produto['estoqueMedio']);
    final giro = _toDouble(produto['giro']);
    final diasEstoque = _toDouble(produto['diasEstoque']);
    final valorEstoqueAtual = _toDouble(produto['valorEstoqueAtual']);

    final color = _giroColor(giro);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                child: Icon(Icons.inventory_outlined, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Chip(
                label: Text(_giroLabel(giro)),
                backgroundColor: color.withOpacity(0.12),
                labelStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _miniInfo('Vendido', _formatNumber(qtdVendida)),
              _miniInfo('Estoque atual', _formatNumber(estoqueAtual)),
              _miniInfo('Estoque médio', _formatNumber(estoqueMedio)),
              _miniInfo('Giro', _formatPercent(giro)),
              _miniInfo(
                'Dias estoque',
                diasEstoque > 0 ? '${_formatNumber(diasEstoque)} dias' : '-',
              ),
              _miniInfo('Valor estoque', _formatMoney(valorEstoqueAtual)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
