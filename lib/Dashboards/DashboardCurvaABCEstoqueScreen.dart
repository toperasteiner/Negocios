import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardCurvaABCEstoqueScreen extends StatefulWidget {
  const DashboardCurvaABCEstoqueScreen({super.key});

  @override
  State<DashboardCurvaABCEstoqueScreen> createState() =>
      _DashboardCurvaABCEstoqueScreenState();
}

class _DashboardCurvaABCEstoqueScreenState
    extends State<DashboardCurvaABCEstoqueScreen> {
  bool _loading = true;

  String? _scopeField;
  String? _scopeValue;

  int _periodoDias = 30;

  double _valorTotalVendido = 0;
  int _totalProdutosVendidos = 0;

  int _totalClasseA = 0;
  int _totalClasseB = 0;
  int _totalClasseC = 0;

  double _valorClasseA = 0;
  double _valorClasseB = 0;
  double _valorClasseC = 0;

  String _filtroClasse = 'A';

  List<Map<String, dynamic>> _produtosABC = [];

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

      final Map<String, Map<String, dynamic>> produtosMap = {};

      final pedidosSnap =
          await fs
              .collection('pedidos')
              .where(_scopeField!, isEqualTo: _scopeValue)
              .get();

      for (final pedidoDoc in pedidosSnap.docs) {
        final pedido = pedidoDoc.data();

        final dataPedido = pedido['data'] ?? pedido['createdAt'];

        if (dataPedido is Timestamp &&
            dataPedido.toDate().isBefore(dataInicio)) {
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

          final nome = (item['nome'] ?? 'Produto sem nome').toString();
          final quantidade = _extractQuantidade(item);

          final valorTotalItem = _extractValorTotalItem(item);
          final valorUnitario = _extractValorUnitario(item);

          final valorVenda =
              valorTotalItem > 0 ? valorTotalItem : quantidade * valorUnitario;

          if (quantidade <= 0 || valorVenda <= 0) continue;

          produtosMap.putIfAbsent(produtoId, () {
            return {
              'produtoId': produtoId,
              'nome': nome,
              'quantidadeVendida': 0.0,
              'valorVendido': 0.0,
              'participacao': 0.0,
              'participacaoAcumulada': 0.0,
              'classe': 'C',
            };
          });

          produtosMap[produtoId]!['quantidadeVendida'] =
              _toDouble(produtosMap[produtoId]!['quantidadeVendida']) +
              quantidade;

          produtosMap[produtoId]!['valorVendido'] =
              _toDouble(produtosMap[produtoId]!['valorVendido']) + valorVenda;
        }
      }

      final lista = produtosMap.values.toList();

      lista.sort(
        (a, b) => _toDouble(
          b['valorVendido'],
        ).compareTo(_toDouble(a['valorVendido'])),
      );

      final valorTotal = lista.fold<double>(
        0,
        (sum, p) => sum + _toDouble(p['valorVendido']),
      );

      double acumulado = 0;

      int totalA = 0;
      int totalB = 0;
      int totalC = 0;

      double valorA = 0;
      double valorB = 0;
      double valorC = 0;

      for (final produto in lista) {
        final valorVendido = _toDouble(produto['valorVendido']);

        final participacao = valorTotal > 0 ? valorVendido / valorTotal : 0;

        String classe;

        if (lista.length <= 2) {
          classe = 'A';
          totalA++;
          valorA += valorVendido;
        } else if (acumulado <= 0.80) {
          classe = 'A';
          totalA++;
          valorA += valorVendido;
        } else if (acumulado <= 0.95) {
          classe = 'B';
          totalB++;
          valorB += valorVendido;
        } else {
          classe = 'C';
          totalC++;
          valorC += valorVendido;
        }

        acumulado += participacao;

        produto['participacao'] = participacao;
        produto['participacaoAcumulada'] = acumulado;
        produto['classe'] = classe;
      }

      setState(() {
        _valorTotalVendido = valorTotal;
        _totalProdutosVendidos = lista.length;

        _totalClasseA = totalA;
        _totalClasseB = totalB;
        _totalClasseC = totalC;

        _valorClasseA = valorA;
        _valorClasseB = valorB;
        _valorClasseC = valorC;

        _produtosABC = lista;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar Curva ABC: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

  double _extractValorTotalItem(Map item) {
    return _toDouble(
      item['subtotalVenda'] ??
          item['total'] ??
          item['valorTotal'] ??
          item['subtotal'],
    );
  }

  double _extractValorUnitario(Map item) {
    return _toDouble(
      item['valorUnitario'] ??
          item['precoVenda'] ??
          item['preco'] ??
          item['valor'],
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

  String _formatMoney(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatNumber(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Color _classeColor(String classe) {
    if (classe == 'A') return Colors.green;
    if (classe == 'B') return Colors.orange;
    return Colors.red;
  }

  String _classeDescricao(String classe) {
    if (classe == 'A') return 'Alta prioridade';
    if (classe == 'B') return 'Prioridade média';
    return 'Baixa prioridade';
  }

  List<Map<String, dynamic>> get _produtosFiltrados {
    return _produtosABC
        .where((p) => p['classe'].toString() == _filtroClasse)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Curva ABC'),
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
                    _buildResumoPrincipal(),
                    const SizedBox(height: 14),
                    _buildResumoABC(),
                    const SizedBox(height: 14),
                    _buildFiltroClasse(),
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
          colors: [Color(0xFF581C87), Color(0xFFA855F7)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Curva ABC de produtos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Identifique quais produtos concentram a maior parte das vendas e merecem mais atenção no estoque.',
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

  Widget _buildResumoPrincipal() {
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            titulo: 'Valor vendido',
            valor: _formatMoney(_valorTotalVendido),
            icon: Icons.attach_money,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            titulo: 'Produtos vendidos',
            valor: _totalProdutosVendidos.toString(),
            icon: Icons.inventory_2_outlined,
            color: Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildResumoABC() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo por classificação',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _buildClasseResumo(
            classe: 'A',
            descricao: 'Produtos mais importantes',
            quantidade: _totalClasseA,
            valor: _valorClasseA,
            percentual:
                _valorTotalVendido > 0 ? _valorClasseA / _valorTotalVendido : 0,
          ),
          _buildClasseResumo(
            classe: 'B',
            descricao: 'Produtos intermediários',
            quantidade: _totalClasseB,
            valor: _valorClasseB,
            percentual:
                _valorTotalVendido > 0 ? _valorClasseB / _valorTotalVendido : 0,
          ),
          _buildClasseResumo(
            classe: 'C',
            descricao: 'Produtos de menor impacto',
            quantidade: _totalClasseC,
            valor: _valorClasseC,
            percentual:
                _valorTotalVendido > 0 ? _valorClasseC / _valorTotalVendido : 0,
          ),
        ],
      ),
    );
  }

  Widget _buildClasseResumo({
    required String classe,
    required String descricao,
    required int quantidade,
    required double valor,
    required double percentual,
  }) {
    final color = _classeColor(classe);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.16),
            child: Text(
              classe,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descricao,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$quantidade produto(s) • ${_formatPercent(percentual)} das vendas',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            _formatMoney(valor),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroClasse() {
    final filtros = ['A', 'B', 'C'];

    return Row(
      children:
          filtros.map((classe) {
            final selected = _filtroClasse == classe;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('Classe $classe'),
                selected: selected,
                onSelected: (_) => setState(() => _filtroClasse = classe),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildListaProdutos() {
    final produtos = _produtosFiltrados;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Produtos classificados',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (produtos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Nenhuma venda encontrada no período.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ...produtos.map(_buildProdutoCard),
        ],
      ),
    );
  }

  Widget _buildProdutoCard(Map<String, dynamic> produto) {
    final nome = produto['nome'].toString();
    final classe = produto['classe'].toString();

    final quantidadeVendida = _toDouble(produto['quantidadeVendida']);
    final valorVendido = _toDouble(produto['valorVendido']);
    final participacao = _toDouble(produto['participacao']);
    final participacaoAcumulada = _toDouble(produto['participacaoAcumulada']);

    final color = _classeColor(classe);

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
                child: Text(
                  classe,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
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
                label: Text(_classeDescricao(classe)),
                backgroundColor: color.withOpacity(0.12),
                labelStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: participacao.clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _miniInfo('Qtd. vendida', _formatNumber(quantidadeVendida)),
              _miniInfo('Valor vendido', _formatMoney(valorVendido)),
              _miniInfo('Participação', _formatPercent(participacao)),
              _miniInfo('Acumulado', _formatPercent(participacaoAcumulada)),
            ],
          ),
        ],
      ),
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
