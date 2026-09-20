import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CalculadoraPrecoProdutoScreen extends StatefulWidget {
  const CalculadoraPrecoProdutoScreen({super.key});

  @override
  State<CalculadoraPrecoProdutoScreen> createState() =>
      _CalculadoraPrecoProdutoScreenState();
}

class _CalculadoraPrecoProdutoScreenState
    extends State<CalculadoraPrecoProdutoScreen> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  final _custoController = TextEditingController();
  final _embalagemController = TextEditingController();
  final _freteController = TextEditingController();
  final _impostoController = TextEditingController(text: '6');
  final _taxaCartaoController = TextEditingController(text: '4');
  final _custoFixoController = TextEditingController(text: '15');
  final _lucroController = TextEditingController(text: '20');

  bool _loading = true;
  String? _erro;

  double _gastoFixoMensal = 0;
  double _custoTotal = 0;
  double _percentualTotal = 0;
  double _precoVenda = 0;
  double _valorTaxasFixos = 0;
  double _lucroValor = 0;
  double _markup = 0;

  @override
  void initState() {
    super.initState();
    _carregarGastoFixoMensal();

    for (final c in [
      _custoController,
      _embalagemController,
      _freteController,
      _impostoController,
      _taxaCartaoController,
      _custoFixoController,
      _lucroController,
    ]) {
      c.addListener(_calcular);
    }
  }

  @override
  void dispose() {
    _custoController.dispose();
    _embalagemController.dispose();
    _freteController.dispose();
    _impostoController.dispose();
    _taxaCartaoController.dispose();
    _custoFixoController.dispose();
    _lucroController.dispose();
    super.dispose();
  }

  Future<void> _carregarGastoFixoMensal() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _erro = 'Usuário não autenticado.';
          _loading = false;
        });
        return;
      }

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final userData = userDoc.data() ?? {};
      final companyId = (userData['companyId'] ?? user.uid).toString();

      final query =
          await FirebaseFirestore.instance
              .collection('recorrencias_pagar')
              .where('companyId', isEqualTo: companyId)
              .where('tipo', isEqualTo: 'pagar')
              .where('ativo', isEqualTo: true)
              .get();

      double total = 0;

      for (final doc in query.docs) {
        final data = doc.data();
        total += _toDouble(data['valor']);
      }

      setState(() {
        _gastoFixoMensal = total;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar gasto fixo mensal: $e';
        _loading = false;
      });
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value
              .toString()
              .replaceAll('R\$', '')
              .replaceAll('.', '')
              .replaceAll(',', '.')
              .trim(),
        ) ??
        0;
  }

  void _calcular() {
    final custo = _toDouble(_custoController.text);
    final embalagem = _toDouble(_embalagemController.text);
    final frete = _toDouble(_freteController.text);

    final imposto = _toDouble(_impostoController.text) / 100;
    final taxaCartao = _toDouble(_taxaCartaoController.text) / 100;
    final custoFixo = _toDouble(_custoFixoController.text) / 100;
    final lucro = _toDouble(_lucroController.text) / 100;

    final custoTotal = custo + embalagem + frete;
    final percentualTotal = imposto + taxaCartao + custoFixo + lucro;

    double precoVenda = 0;
    double valorTaxasFixos = 0;
    double lucroValor = 0;
    double markup = 0;

    if (custoTotal > 0 && percentualTotal < 1) {
      precoVenda = custoTotal / (1 - percentualTotal);
      valorTaxasFixos = precoVenda * (imposto + taxaCartao + custoFixo);
      lucroValor = precoVenda * lucro;
      markup = precoVenda / custoTotal;
    }

    setState(() {
      _custoTotal = custoTotal;
      _percentualTotal = percentualTotal;
      _precoVenda = precoVenda;
      _valorTaxasFixos = valorTaxasFixos;
      _lucroValor = lucroValor;
      _markup = markup;
    });
  }

  bool get _percentualInvalido => _percentualTotal >= 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calculadora de Preço')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_erro != null) _cardErro(_erro!),

                      _cardGastoFixoEmpresa(),

                      const SizedBox(height: 16),

                      _cardOrientacao(),

                      const SizedBox(height: 16),

                      _sectionTitle('Custos do produto'),
                      _campoValor(
                        controller: _custoController,
                        label: 'Custo do produto',
                        prefix: 'R\$',
                      ),
                      _campoValor(
                        controller: _embalagemController,
                        label: 'Embalagem',
                        prefix: 'R\$',
                      ),
                      _campoValor(
                        controller: _freteController,
                        label: 'Frete',
                        prefix: 'R\$',
                      ),

                      const SizedBox(height: 16),

                      _sectionTitle('Percentuais'),
                      _campoValor(
                        controller: _impostoController,
                        label: 'Imposto %',
                        suffix: '%',
                      ),
                      _campoValor(
                        controller: _taxaCartaoController,
                        label: 'Taxa cartão %',
                        suffix: '%',
                      ),
                      _campoValor(
                        controller: _custoFixoController,
                        label: 'Custo fixo %',
                        suffix: '%',
                      ),
                      _campoValor(
                        controller: _lucroController,
                        label: 'Lucro desejado %',
                        suffix: '%',
                      ),

                      const SizedBox(height: 20),

                      if (_percentualInvalido)
                        _alertaPercentualInvalido()
                      else
                        _resultado(),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _limpar,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Limpar cálculo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _cardGastoFixoEmpresa() {
    return Card(
      elevation: 2,
      color: Colors.indigo.shade700,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gasto fixo mensal da empresa',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _money.format(_gastoFixoMensal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Baseado nas contas recorrentes ativas a pagar.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardOrientacao() {
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Informe os custos do produto e os percentuais. '
                'O campo custo fixo % representa quanto do preço de venda '
                'será reservado para cobrir os gastos fixos da empresa.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _campoValor({
    required TextEditingController controller,
    required String label,
    String? prefix,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix == null ? null : '$prefix ',
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _resultado() {
    return Column(
      children: [
        _resultadoPrincipal(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _cardResultado(
                titulo: 'Custo total',
                valor: _money.format(_custoTotal),
                icone: Icons.shopping_bag_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cardResultado(
                titulo: 'Taxas + fixos',
                valor: _money.format(_valorTaxasFixos),
                icone: Icons.percent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _cardResultado(
                titulo: 'Lucro estimado',
                valor: _money.format(_lucroValor),
                icone: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cardResultado(
                titulo: 'Markup',
                valor: _markup > 0 ? '${_markup.toStringAsFixed(2)}x' : '0x',
                icone: Icons.calculate_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultadoPrincipal() {
    return Card(
      elevation: 3,
      color: Colors.green.shade700,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Preço de venda sugerido',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _money.format(_precoVenda),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Percentual total aplicado: ${(_percentualTotal * 100).toStringAsFixed(2)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardResultado({
    required String titulo,
    required String valor,
    required IconData icone,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Icon(icone, size: 26),
            const SizedBox(height: 8),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              valor,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertaPercentualInvalido() {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 12),
            Expanded(
              child: Text('A soma dos percentuais precisa ser menor que 100%.'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardErro(String mensagem) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(mensagem, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  void _limpar() {
    _custoController.clear();
    _embalagemController.clear();
    _freteController.clear();
    _impostoController.text = '6';
    _taxaCartaoController.text = '4';
    _custoFixoController.text = '15';
    _lucroController.text = '20';
    _calcular();
  }
}
