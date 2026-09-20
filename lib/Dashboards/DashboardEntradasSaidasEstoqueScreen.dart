import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardEntradasSaidasEstoqueScreen extends StatefulWidget {
  const DashboardEntradasSaidasEstoqueScreen({super.key});

  @override
  State<DashboardEntradasSaidasEstoqueScreen> createState() =>
      _DashboardEntradasSaidasEstoqueScreenState();
}

class _DashboardEntradasSaidasEstoqueScreenState
    extends State<DashboardEntradasSaidasEstoqueScreen> {
  bool _loading = true;

  String? _scopeField;
  String? _scopeValue;

  int _periodoDias = 30;

  double _totalEntradas = 0;
  double _totalSaidas = 0;
  double _saldoQuantidade = 0;

  double _valorEntradas = 0;
  double _valorSaidas = 0;
  double _saldoValor = 0;

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

        final custo = _toDouble(data['custo']);
        final precoMedio = _toDouble(data['precoMedio']);
        final custoBase = precoMedio > 0 ? precoMedio : custo;

        produtosMap[doc.id] = {
          'id': doc.id,
          'nome': (data['nome'] ?? 'Produto sem nome').toString(),
          'estoqueAtual': _toDouble(data['estoque']),
          'custoBase': custoBase,
          'entradaQtd': 0.0,
          'saidaQtd': 0.0,
          'entradaValor': 0.0,
          'saidaValor': 0.0,
        };
      }

      await _carregarEntradasCompras(
        fs: fs,
        dataInicio: dataInicio,
        produtosMap: produtosMap,
      );

      await _carregarSaidasPedidos(
        fs: fs,
        dataInicio: dataInicio,
        produtosMap: produtosMap,
      );

      double totalEntradas = 0;
      double totalSaidas = 0;
      double valorEntradas = 0;
      double valorSaidas = 0;

      final lista = <Map<String, dynamic>>[];

      for (final produto in produtosMap.values) {
        final entradaQtd = _toDouble(produto['entradaQtd']);
        final saidaQtd = _toDouble(produto['saidaQtd']);
        final entradaValor = _toDouble(produto['entradaValor']);
        final saidaValor = _toDouble(produto['saidaValor']);

        final saldoQtd = entradaQtd - saidaQtd;
        final saldoValor = entradaValor - saidaValor;

        totalEntradas += entradaQtd;
        totalSaidas += saidaQtd;
        valorEntradas += entradaValor;
        valorSaidas += saidaValor;

        if (entradaQtd > 0 || saidaQtd > 0) {
          lista.add({
            ...produto,
            'saldoQtd': saldoQtd,
            'saldoValor': saldoValor,
            'movimentoTotal': entradaQtd + saidaQtd,
          });
        }
      }

      lista.sort(
        (a, b) => _toDouble(
          b['movimentoTotal'],
        ).compareTo(_toDouble(a['movimentoTotal'])),
      );

      setState(() {
        _totalEntradas = totalEntradas;
        _totalSaidas = totalSaidas;
        _saldoQuantidade = totalEntradas - totalSaidas;

        _valorEntradas = valorEntradas;
        _valorSaidas = valorSaidas;
        _saldoValor = valorEntradas - valorSaidas;

        _produtos = lista;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar entradas e saídas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _carregarEntradasCompras({
    required FirebaseFirestore fs,
    required DateTime dataInicio,
    required Map<String, Map<String, dynamic>> produtosMap,
  }) async {
    final comprasSnap =
        await fs
            .collection('compras')
            .where(_scopeField!, isEqualTo: _scopeValue)
            .get();

    for (final compraDoc in comprasSnap.docs) {
      final compra = compraDoc.data();

      final dataCompra =
          compra['dataEntrega'] ??
          compra['dataRecebimento'] ??
          compra['data'] ??
          compra['createdAt'];

      if (dataCompra is Timestamp && dataCompra.toDate().isBefore(dataInicio)) {
        continue;
      }

      final status =
          (compra['status'] ?? compra['situacao'] ?? '')
              .toString()
              .toLowerCase();

      if (status != 'entregue' &&
          status != 'recebida' &&
          status != 'recebido') {
        continue;
      }

      final itens =
          compra['itensProdutos'] ??
          compra['produtos'] ??
          compra['itens'] ??
          [];

      if (itens is! List) continue;

      for (final item in itens) {
        if (item is! Map) continue;

        final produtoId = _extractProdutoId(item);
        if (produtoId == null || produtoId.isEmpty) continue;

        final produto = produtosMap[produtoId];
        if (produto == null) continue;

        final quantidade = _extractQuantidade(item);
        if (quantidade <= 0) continue;

        final valorUnitario = _extractValorCompra(item);
        final custoBase = _toDouble(produto['custoBase']);

        final valorMovimento =
            quantidade * (valorUnitario > 0 ? valorUnitario : custoBase);

        produto['entradaQtd'] = _toDouble(produto['entradaQtd']) + quantidade;

        produto['entradaValor'] =
            _toDouble(produto['entradaValor']) + valorMovimento;
      }
    }
  }

  Future<void> _carregarSaidasPedidos({
    required FirebaseFirestore fs,
    required DateTime dataInicio,
    required Map<String, Map<String, dynamic>> produtosMap,
  }) async {
    final pedidosSnap =
        await fs
            .collection('pedidos')
            .where(_scopeField!, isEqualTo: _scopeValue)
            .get();

    for (final pedidoDoc in pedidosSnap.docs) {
      final pedido = pedidoDoc.data();

      final dataPedido = pedido['data'] ?? pedido['createdAt'];

      if (dataPedido is Timestamp && dataPedido.toDate().isBefore(dataInicio)) {
        continue;
      }

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

        final custoUnitario = _toDouble(
          item['custoUnitario'] ??
              item['custo'] ??
              item['precoMedio'] ??
              produto['custoBase'],
        );

        final valorMovimento = quantidade * custoUnitario;

        produto['saidaQtd'] = _toDouble(produto['saidaQtd']) + quantidade;

        produto['saidaValor'] =
            _toDouble(produto['saidaValor']) + valorMovimento;
      }
    }
  }

  String? _extractProdutoId(Map item) {
    final value =
        item['produtoId'] ??
        item['idProduto'] ??
        item['refId'] ??
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

  double _extractValorCompra(Map item) {
    return _toDouble(
      item['valorUnitario'] ??
          item['custoUnitario'] ??
          item['valorCompra'] ??
          item['precoCompra'] ??
          item['custo'],
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

  Color _saldoColor(double value) {
    if (value > 0) return Colors.green;
    if (value < 0) return Colors.red;
    return Colors.grey;
  }

  String _saldoLabel(double value) {
    if (value > 0) return 'Saldo positivo';
    if (value < 0) return 'Mais saídas';
    return 'Equilibrado';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Entradas vs Saídas'),
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
                    _buildResumoQuantidade(),
                    const SizedBox(height: 14),
                    _buildResumoValor(),
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
          colors: [Color(0xFF1E40AF), Color(0xFF06B6D4)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fluxo do estoque',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Compare entradas por compras entregues com saídas por vendas realizadas.',
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

  Widget _buildResumoQuantidade() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumo por quantidade',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                titulo: 'Entradas',
                valor: _formatNumber(_totalEntradas),
                icon: Icons.call_received,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                titulo: 'Saídas',
                valor: _formatNumber(_totalSaidas),
                icon: Icons.call_made,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildKpiCard(
          titulo: 'Saldo de quantidade',
          valor: _formatNumber(_saldoQuantidade),
          icon: Icons.compare_arrows,
          color: _saldoColor(_saldoQuantidade),
        ),
      ],
    );
  }

  Widget _buildResumoValor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumo por custo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                titulo: 'Valor entradas',
                valor: _formatMoney(_valorEntradas),
                icon: Icons.south_west,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                titulo: 'Valor saídas',
                valor: _formatMoney(_valorSaidas),
                icon: Icons.north_east,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildKpiCard(
          titulo: 'Saldo em custo',
          valor: _formatMoney(_saldoValor),
          icon: Icons.account_balance_wallet_outlined,
          color: _saldoColor(_saldoValor),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Movimentação por produto',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (_produtos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Nenhuma movimentação encontrada no período.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ..._produtos.map(_buildProdutoCard),
        ],
      ),
    );
  }

  Widget _buildProdutoCard(Map<String, dynamic> produto) {
    final nome = produto['nome'].toString();

    final entradaQtd = _toDouble(produto['entradaQtd']);
    final saidaQtd = _toDouble(produto['saidaQtd']);
    final saldoQtd = _toDouble(produto['saldoQtd']);

    final entradaValor = _toDouble(produto['entradaValor']);
    final saidaValor = _toDouble(produto['saidaValor']);
    final saldoValor = _toDouble(produto['saldoValor']);

    final color = _saldoColor(saldoQtd);

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
                child: Icon(Icons.inventory_2_outlined, color: color),
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
                label: Text(_saldoLabel(saldoQtd)),
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
              _miniInfo('Entrada qtd.', _formatNumber(entradaQtd)),
              _miniInfo('Saída qtd.', _formatNumber(saidaQtd)),
              _miniInfo('Saldo qtd.', _formatNumber(saldoQtd)),
              _miniInfo('Valor entrada', _formatMoney(entradaValor)),
              _miniInfo('Valor saída', _formatMoney(saidaValor)),
              _miniInfo('Saldo custo', _formatMoney(saldoValor)),
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
