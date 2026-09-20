import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ValorOrcamentoFrete {
  final TextEditingController moedaController;
  final TextEditingController descricaoController;
  final TextEditingController valorController;

  ValorOrcamentoFrete({
    String moeda = 'USD',
    String descricao = '',
    String valor = '',
  }) : moedaController = TextEditingController(text: moeda),
       descricaoController = TextEditingController(text: descricao),
       valorController = TextEditingController(text: valor);

  Map<String, dynamic> toMap() {
    return {
      'moeda': moedaController.text.trim().toUpperCase(),
      'descricao': descricaoController.text.trim(),
      'valor':
          double.tryParse(
            valorController.text.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0,
    };
  }

  void dispose() {
    moedaController.dispose();
    descricaoController.dispose();
    valorController.dispose();
  }
}

class OrcamentoFreteInternacionalScreen extends StatefulWidget {
  final String cotacaoId;
  final String? orcamentoId;
  final String? referenciaCotacao;

  const OrcamentoFreteInternacionalScreen({
    super.key,
    required this.cotacaoId,
    this.orcamentoId,
    this.referenciaCotacao,
  });

  @override
  State<OrcamentoFreteInternacionalScreen> createState() =>
      _OrcamentoFreteInternacionalScreenState();
}

class _OrcamentoFreteInternacionalScreenState
    extends State<OrcamentoFreteInternacionalScreen> {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color background = Color(0xFFFBFAFF);

  final _formKey = GlobalKey<FormState>();

  final _referenciaController = TextEditingController();
  final _fornecedorController = TextEditingController();
  final _contatoController = TextEditingController();
  final _emailController = TextEditingController();

  final List<ValorOrcamentoFrete> _valores = [];

  final _transitTimeController = TextEditingController();
  final _freeTimeOrigemController = TextEditingController();
  final _freeTimeDestinoController = TextEditingController();
  final _validadePropostaController = TextEditingController();

  final _armadorController = TextEditingController();
  final _agenteOrigemController = TextEditingController();
  final _agenteDestinoController = TextEditingController();
  final _observacoesController = TextEditingController();

  final _ptaxController = TextEditingController();

  String _status = 'Recebido';
  String _condicaoPagamento = 'A combinar';

  bool _salvando = false;
  bool _carregando = false;

  DateTime? _dataValidade;

  final List<String> _statusList = [
    'Recebido',
    'Em análise',
    'Aprovado',
    'Reprovado',
    'Contratado',
    'Cancelado',
  ];

  final List<String> _condicoesPagamento = [
    'A combinar',
    'Antecipado',
    'À vista',
    '7 dias',
    '15 dias',
    '30 dias',
    '45 dias',
    '60 dias',
  ];

  bool get _isEdicao => widget.orcamentoId != null;

  @override
  void initState() {
    super.initState();

    if (_isEdicao) {
      _carregarOrcamento();
    } else {
      _gerarReferenciaInicial();
      _valores.add(
        ValorOrcamentoFrete(moeda: 'USD', descricao: 'Frete internacional'),
      );
    }
  }

  void _gerarReferenciaInicial() {
    final now = DateTime.now();
    _referenciaController.text =
        'ORC-FRETE-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(8)}';
  }

  Future<void> _carregarOrcamento() async {
    setState(() => _carregando = true);

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('cotacoes_frete_orcamentos')
              .doc(widget.orcamentoId)
              .get();

      if (!doc.exists) return;

      final data = doc.data()!;

      _referenciaController.text = data['referencia'] ?? '';
      _fornecedorController.text = data['fornecedorNome'] ?? '';
      _contatoController.text = data['fornecedorContato'] ?? '';
      _emailController.text = data['fornecedorEmail'] ?? '';

      _status = data['status'] ?? 'Recebido';
      _condicaoPagamento = data['condicaoPagamento'] ?? 'A combinar';

      final valores = data['valores'];
      _valores.clear();

      if (valores is List) {
        for (final item in valores) {
          if (item is Map) {
            _valores.add(
              ValorOrcamentoFrete(
                moeda: item['moeda'] ?? 'USD',
                descricao: item['descricao'] ?? '',
                valor: (item['valor'] ?? '').toString(),
              ),
            );
          }
        }
      }

      if (_valores.isEmpty) {
        _valores.add(
          ValorOrcamentoFrete(moeda: 'USD', descricao: 'Frete internacional'),
        );
      }

      _transitTimeController.text = data['transitTime'] ?? '';
      _freeTimeOrigemController.text = data['freeTimeOrigem'] ?? '';
      _freeTimeDestinoController.text = data['freeTimeDestino'] ?? '';
      _validadePropostaController.text = data['validadeProposta'] ?? '';

      _armadorController.text = data['armador'] ?? '';
      _agenteOrigemController.text = data['agenteOrigem'] ?? '';
      _agenteDestinoController.text = data['agenteDestino'] ?? '';
      _observacoesController.text = data['observacoes'] ?? '';

      if (data['dataValidade'] != null) {
        _dataValidade = (data['dataValidade'] as Timestamp).toDate();
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _mostrarMensagem('Usuário não autenticado.');
      return;
    }

    setState(() => _salvando = true);

    try {
      final valores = _valores.map((e) => e.toMap()).toList();
      final totaisPorMoeda = <String, double>{};

      for (final item in valores) {
        final moeda = item['moeda'] as String;
        final valor = item['valor'] as double;

        if (moeda.trim().isEmpty) continue;

        totaisPorMoeda[moeda] = (totaisPorMoeda[moeda] ?? 0) + valor;
      }

      final dados = {
        'companyId': user.uid,
        'createdByUid': user.uid,
        'cotacaoId': widget.cotacaoId,
        'referenciaCotacao': widget.referenciaCotacao ?? '',
        'referencia': _referenciaController.text.trim(),
        'fornecedorNome': _fornecedorController.text.trim(),
        'fornecedorContato': _contatoController.text.trim(),
        'fornecedorEmail': _emailController.text.trim(),
        'status': _status,
        'valores': valores,
        'totaisPorMoeda': totaisPorMoeda,
        'transitTime': _transitTimeController.text.trim(),
        'freeTimeOrigem': _freeTimeOrigemController.text.trim(),
        'freeTimeDestino': _freeTimeDestinoController.text.trim(),
        'validadeProposta': _validadePropostaController.text.trim(),
        'dataValidade':
            _dataValidade == null ? null : Timestamp.fromDate(_dataValidade!),
        'condicaoPagamento': _condicaoPagamento,
        'armador': _armadorController.text.trim(),
        'agenteOrigem': _agenteOrigemController.text.trim(),
        'agenteDestino': _agenteDestinoController.text.trim(),
        'observacoes': _observacoesController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdicao) {
        await FirebaseFirestore.instance
            .collection('cotacoes_frete_orcamentos')
            .doc(widget.orcamentoId)
            .update(dados);
      } else {
        await FirebaseFirestore.instance
            .collection('cotacoes_frete_orcamentos')
            .add({...dados, 'createdAt': FieldValue.serverTimestamp()});
      }

      if (!mounted) return;
      _mostrarMensagem('Orçamento salvo com sucesso.');
      Navigator.pop(context, true);
    } catch (e) {
      _mostrarMensagem('Erro ao salvar orçamento: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  double? _toDouble(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.replaceAll('.', '').replaceAll(',', '.'));
  }

  Future<void> _selecionarDataValidade() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataValidade ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (data != null) {
      setState(() => _dataValidade = data);
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'Selecionar data';
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  Map<String, double> get _totaisPorMoeda {
    final totais = <String, double>{};

    for (final item in _valores) {
      final moeda = item.moedaController.text.trim().toUpperCase();
      final valor = _toDouble(item.valorController.text) ?? 0;

      if (moeda.isEmpty) continue;

      totais[moeda] = (totais[moeda] ?? 0) + valor;
    }

    return totais;
  }

  String get _resumoTotais {
    final totais = _totaisPorMoeda;

    if (totais.isEmpty) return 'Sem valores informados';

    return totais.entries
        .map((e) => '${e.key} ${e.value.toStringAsFixed(2)}')
        .join(' • ');
  }

  @override
  void dispose() {
    _referenciaController.dispose();
    _fornecedorController.dispose();
    _contatoController.dispose();
    _emailController.dispose();

    for (final item in _valores) {
      item.dispose();
    }

    _transitTimeController.dispose();
    _freeTimeOrigemController.dispose();
    _freeTimeDestinoController.dispose();
    _validadePropostaController.dispose();
    _armadorController.dispose();
    _agenteOrigemController.dispose();
    _agenteDestinoController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: purple.withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: purple,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _salvando ? null : _salvar,
              icon:
                  _salvando
                      ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.save_rounded),
              label: Text(
                _salvando ? 'Salvando...' : 'Salvar Orçamento',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
      body:
          _carregando
              ? const Center(child: CircularProgressIndicator())
              : Form(
                key: _formKey,
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 185,
                      pinned: true,
                      elevation: 0,
                      backgroundColor: purple,
                      foregroundColor: Colors.white,
                      centerTitle: true,
                      title: Text(
                        _isEdicao ? 'Editar Orçamento' : 'Novo Orçamento',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      actions: [
                        IconButton(
                          onPressed: _salvando ? null : _salvar,
                          icon: const Icon(Icons.save_rounded),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [purple, deepPurple],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                70,
                                18,
                                18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.16),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.request_quote_outlined,
                                      color: Colors.white,
                                      size: 31,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Orçamento de Frete',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Registre cobranças, moedas, prazos e condições.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.82),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                        child: Column(
                          children: [
                            _resumoCard(),
                            _section(
                              icon: Icons.business_outlined,
                              titulo: 'Dados do Fornecedor',
                              subtitulo: 'Identifique quem enviou o orçamento.',
                              color: purple,
                              children: [
                                _responsive([
                                  _textField(
                                    controller: _referenciaController,
                                    label: 'Referência do orçamento',
                                    required: true,
                                    icon: Icons.tag_rounded,
                                  ),
                                  _dropdown(
                                    label: 'Status',
                                    value: _status,
                                    items: _statusList,
                                    icon: Icons.flag_outlined,
                                    onChanged:
                                        (v) => setState(() => _status = v!),
                                  ),
                                  _textField(
                                    controller: _fornecedorController,
                                    label: 'Fornecedor / Agente de carga',
                                    required: true,
                                    icon: Icons.business_center_outlined,
                                  ),
                                  _textField(
                                    controller: _contatoController,
                                    label: 'Contato',
                                    icon: Icons.person_outline,
                                  ),
                                  _textField(
                                    controller: _emailController,
                                    label: 'E-mail',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ]),
                              ],
                            ),
                            _section(
                              icon: Icons.payments_outlined,
                              titulo: 'Valores do Orçamento',
                              subtitulo:
                                  'Informe moeda, descrição da cobrança e valor.',
                              color: green,
                              children: [_valoresBox(), _totalPorMoedaBox()],
                            ),
                            _section(
                              icon: Icons.schedule_outlined,
                              titulo: 'Prazos e Condições',
                              subtitulo:
                                  'Informe validade, transit time e pagamento.',
                              color: blue,
                              children: [
                                _responsive([
                                  _textField(
                                    controller: _transitTimeController,
                                    label: 'Transit time',
                                    icon: Icons.timer_outlined,
                                  ),

                                  _textField(
                                    controller: _freeTimeDestinoController,
                                    label: 'Free time destino',
                                    icon: Icons.access_time_filled_outlined,
                                  ),
                                  _dateTile(
                                    label: 'Data de validade',
                                    value: _formatarData(_dataValidade),
                                    icon: Icons.event_available_outlined,
                                    onTap: _selecionarDataValidade,
                                  ),

                                  _dropdown(
                                    label: 'Condição de pagamento',
                                    value: _condicaoPagamento,
                                    items: _condicoesPagamento,
                                    icon: Icons.payment_outlined,
                                    onChanged:
                                        (v) => setState(
                                          () => _condicaoPagamento = v!,
                                        ),
                                  ),
                                ]),
                              ],
                            ),
                            _section(
                              icon: Icons.directions_boat_outlined,
                              titulo: 'Operação Logística',
                              subtitulo:
                                  'Informe armador, agentes e observações operacionais.',
                              color: orange,
                              children: [
                                _responsive([
                                  _textField(
                                    controller: _armadorController,
                                    label: 'Armador / Companhia aérea',
                                    icon: Icons.anchor_outlined,
                                  ),
                                  _textField(
                                    controller: _agenteOrigemController,
                                    label: 'Agente na origem',
                                    icon: Icons.location_on_outlined,
                                  ),
                                  _textField(
                                    controller: _agenteOrigemController,
                                    label: 'Telefone Agente na origem',
                                    icon: Icons.location_on_outlined,
                                  ),

                                  _textField(
                                    controller: _agenteOrigemController,
                                    label: 'Email Agente na origem',
                                    icon: Icons.location_on_outlined,
                                  ),

                                  _textField(
                                    controller: _agenteDestinoController,
                                    label: 'Agente no destino',
                                    icon: Icons.location_city_outlined,
                                  ),
                                ]),
                                _textField(
                                  controller: _observacoesController,
                                  label: 'Observações',
                                  icon: Icons.notes_outlined,
                                  maxLines: 4,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _resumoCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [purple.withOpacity(0.95), deepPurple.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: purple.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.request_quote_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fornecedorController.text.isEmpty
                      ? 'Novo orçamento'
                      : _fornecedorController.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_resumoTotais • $_status',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12,
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

  Widget _valoresBox() {
    return Column(
      children: [
        ...List.generate(_valores.length, (index) {
          final item = _valores[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: purple.withOpacity(0.10)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cobrança ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _valores.length == 1
                              ? null
                              : () {
                                setState(() {
                                  item.dispose();
                                  _valores.removeAt(index);
                                });
                              },
                      icon: Icon(
                        Icons.delete_outline,
                        color: _valores.length == 1 ? Colors.grey : Colors.red,
                      ),
                    ),
                  ],
                ),
                _responsive([
                  _textField(
                    controller: item.moedaController,
                    label: 'Moeda',
                    required: true,
                    icon: Icons.attach_money_rounded,
                    onChanged: (_) => setState(() {}),
                  ),
                  _textField(
                    controller: item.descricaoController,
                    label: 'Descrição da cobrança',
                    required: true,
                    icon: Icons.description_outlined,
                  ),
                  _textField(
                    controller: item.valorController,
                    label: 'Valor',
                    required: true,
                    icon: Icons.payments_outlined,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ]),
              ],
            ),
          );
        }),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _valores.add(ValorOrcamentoFrete(moeda: 'USD'));
              });
            },
            icon: const Icon(Icons.add),
            label: const Text(
              'Adicionar cobrança',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalPorMoedaBox() {
    final totais = _totaisPorMoeda;

    if (totais.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: green.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calculate_outlined, color: green),
              SizedBox(width: 10),
              Text(
                'Total por moeda',
                style: TextStyle(fontWeight: FontWeight.w900, color: textDark),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...totais.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textDark,
                      ),
                    ),
                  ),
                  Text(
                    e.value.toStringAsFixed(2),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: green,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              const Text(
                'PTAX',
                style: TextStyle(fontWeight: FontWeight.w800, color: textDark),
              ),

              const SizedBox(width: 12),

              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: _ptaxController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '0,00',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              const Text(
                '%',
                style: TextStyle(fontWeight: FontWeight.w800, color: textDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.95),
                        color.withOpacity(0.70),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _responsive(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;
        final itemWidth =
            isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 0,
          children:
              children
                  .map((child) => SizedBox(width: itemWidth, child: child))
                  .toList(),
        );
      },
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
        decoration: _inputDecoration(
          label: required ? '$label *' : label,
          icon: icon,
        ),
        validator:
            required
                ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe $label';
                  }
                  return null;
                }
                : null,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: _inputDecoration(label: label, icon: icon),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: textDark,
          fontSize: 15,
        ),
        items:
            items
                .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: InputDecorator(
          decoration: _inputDecoration(label: label, icon: icon),
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: textDark,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String label, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, color: purple),
      filled: true,
      fillColor: const Color(0xFFF8F6FF),
      labelStyle: const TextStyle(
        color: textMuted,
        fontWeight: FontWeight.w600,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: purple.withOpacity(0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: purple, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
    );
  }
}
