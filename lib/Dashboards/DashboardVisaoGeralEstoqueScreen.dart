import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardVisaoGeralEstoqueScreen extends StatefulWidget {
  const DashboardVisaoGeralEstoqueScreen({super.key});

  @override
  State<DashboardVisaoGeralEstoqueScreen> createState() =>
      _DashboardVisaoGeralEstoqueScreenState();
}

class _DashboardVisaoGeralEstoqueScreenState
    extends State<DashboardVisaoGeralEstoqueScreen> {
  bool _loading = true;

  String? _scopeField;
  String? _scopeValue;

  int totalProdutos = 0;
  int produtosComControleEstoque = 0;
  int produtosSemEstoque = 0;
  int produtosAbaixoAlerta = 0;

  double quantidadeTotalEstoque = 0;
  double valorTotalEstoque = 0;
  double custoMedioGeral = 0;

  List<Map<String, dynamic>> topProdutos = [];

  @override
  void initState() {
    super.initState();
    _carregarDashboard();
  }

  Future<void> _carregarDashboard() async {
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _showErro('Usuário não autenticado.');
        return;
      }

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final userData = userDoc.data();
      final companyId = userData?['companyId'];

      if (companyId != null && companyId.toString().trim().isNotEmpty) {
        _scopeField = 'companyId';
        _scopeValue = companyId.toString();
      } else {
        _scopeField = 'userId';
        _scopeValue = user.uid;
      }

      final produtosSnapshot =
          await FirebaseFirestore.instance
              .collection('produtos')
              .where(_scopeField!, isEqualTo: _scopeValue)
              .get();

      double somaValorEstoque = 0;
      double somaQuantidadeEstoque = 0;
      double somaCusto = 0;

      int qtdProdutos = 0;
      int qtdControleEstoque = 0;
      int qtdSemEstoque = 0;
      int qtdAbaixoAlerta = 0;
      int qtdComCusto = 0;

      final List<Map<String, dynamic>> produtosValorEstoque = [];

      for (final doc in produtosSnapshot.docs) {
        final data = doc.data();

        final nome = (data['nome'] ?? 'Produto sem nome').toString();

        final controlaEstoque = data['controlaEstoque'] == true;

        final estoque = _toDouble(data['estoque']);
        final estoqueAlerta = _toDouble(data['estoqueAlerta']);
        final custo = _toDouble(data['custo']);
        final precoMedio = _toDouble(data['precoMedio']);

        final custoBase = precoMedio > 0 ? precoMedio : custo;
        final valorEstoque = estoque * custoBase;

        qtdProdutos++;

        if (controlaEstoque) {
          qtdControleEstoque++;

          somaQuantidadeEstoque += estoque;
          somaValorEstoque += valorEstoque;

          if (estoque <= 0) {
            qtdSemEstoque++;
          }

          if (estoqueAlerta > 0 && estoque <= estoqueAlerta) {
            qtdAbaixoAlerta++;
          }

          if (custo > 0) {
            somaCusto += custo;
            qtdComCusto++;
          }

          produtosValorEstoque.add({
            'nome': nome,
            'estoque': estoque,
            'custoBase': custoBase,
            'valorEstoque': valorEstoque,
            'precoMedio': precoMedio,
            'custo': custo,
          });
        }
      }

      produtosValorEstoque.sort(
        (a, b) => (b['valorEstoque'] as double).compareTo(
          a['valorEstoque'] as double,
        ),
      );

      setState(() {
        totalProdutos = qtdProdutos;
        produtosComControleEstoque = qtdControleEstoque;
        produtosSemEstoque = qtdSemEstoque;
        produtosAbaixoAlerta = qtdAbaixoAlerta;

        quantidadeTotalEstoque = somaQuantidadeEstoque;
        valorTotalEstoque = somaValorEstoque;
        custoMedioGeral = qtdComCusto > 0 ? somaCusto / qtdComCusto : 0;

        topProdutos = produtosValorEstoque.take(10).toList();

        _loading = false;
      });
    } catch (e) {
      _showErro('Erro ao carregar dashboard: $e');
    }
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

  void _showErro(String mensagem) {
    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  String _formatMoney(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatNumber(double value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Visão Geral do Estoque'),
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
                    const SizedBox(height: 16),
                    _buildResumoPrincipal(),
                    const SizedBox(height: 16),
                    _buildIndicadoresSecundarios(),
                    const SizedBox(height: 16),
                    _buildTopProdutos(),
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
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo executivo do estoque',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Acompanhe o valor parado em estoque, quantidade disponível e produtos que exigem atenção.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoPrincipal() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                titulo: 'Valor em estoque',
                valor: _formatMoney(valorTotalEstoque),
                icone: Icons.attach_money,
                cor: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                titulo: 'Qtd. em estoque',
                valor: _formatNumber(quantidadeTotalEstoque),
                icone: Icons.inventory_2_outlined,
                cor: const Color(0xFF2563EB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                titulo: 'Produtos',
                valor: totalProdutos.toString(),
                icone: Icons.category_outlined,
                cor: const Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                titulo: 'Custo médio geral',
                valor: _formatMoney(custoMedioGeral),
                icone: Icons.trending_up,
                cor: const Color(0xFFF97316),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIndicadoresSecundarios() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Indicadores de atenção',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _buildLinhaIndicador(
            titulo: 'Produtos com controle de estoque',
            valor: produtosComControleEstoque.toString(),
            icon: Icons.check_circle_outline,
            color: Colors.green,
          ),
          _buildLinhaIndicador(
            titulo: 'Produtos sem estoque',
            valor: produtosSemEstoque.toString(),
            icon: Icons.remove_shopping_cart_outlined,
            color: Colors.red,
          ),
          _buildLinhaIndicador(
            titulo: 'Produtos abaixo do estoque alerta',
            valor: produtosAbaixoAlerta.toString(),
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildTopProdutos() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top 10 produtos por valor em estoque',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (topProdutos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Nenhum produto com estoque encontrado.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ...topProdutos.map((produto) {
              final nome = produto['nome'].toString();
              final estoque = produto['estoque'] as double;
              final custoBase = produto['custoBase'] as double;
              final valorEstoque = produto['valorEstoque'] as double;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.inventory_outlined,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Estoque: ${_formatNumber(estoque)} | Custo base: ${_formatMoney(custoBase)}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatMoney(valorEstoque),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String titulo,
    required String valor,
    required IconData icone,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: cor.withOpacity(0.12),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(height: 14),
          Text(
            valor,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaIndicador({
    required String titulo,
    required String valor,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(titulo, style: const TextStyle(fontSize: 14))),
          Text(
            valor,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
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
