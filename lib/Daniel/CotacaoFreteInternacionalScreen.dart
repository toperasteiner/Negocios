import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CotacaoFreteInternacionalScreen extends StatefulWidget {
  final String? cotacaoId;

  const CotacaoFreteInternacionalScreen({super.key, this.cotacaoId});

  @override
  State<CotacaoFreteInternacionalScreen> createState() =>
      _CotacaoFreteInternacionalScreenState();
}

class _CotacaoFreteInternacionalScreenState
    extends State<CotacaoFreteInternacionalScreen> {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color blue = Color(0xFF2F80ED);
  static const Color green = Color(0xFF08A64B);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color background = Color(0xFFFBFAFF);

  final _formKey = GlobalKey<FormState>();

  final _referenciaController = TextEditingController();
  final _localEmbarqueController = TextEditingController();
  final _localDestinoController = TextEditingController();
  final _terminalDestinoController = TextEditingController();
  final _ncmController = TextEditingController();
  final _codigoImoController = TextEditingController();
  final _condicaoPagamentoController = TextEditingController();
  final _observacoesController = TextEditingController();

  final _paisColetaController = TextEditingController();
  final _cidadeColetaController = TextEditingController();
  final _enderecoColetaController = TextEditingController();
  final _contatoColetaController = TextEditingController();
  final _telefoneColetaController = TextEditingController();

  final _quantidadeContainersController = TextEditingController();
  final _pesoBrutoController = TextEditingController();
  final _cubagemController = TextEditingController();
  final _volumesController = TextEditingController();
  final _dimensoesController = TextEditingController();

  final _referenciaCotacaoController = TextEditingController();
  final _instrucoesEstufagemController = TextEditingController();

  final _exportadorNomeController = TextEditingController();
  final _exportadorEnderecoController = TextEditingController();
  final _exportadorContatoController = TextEditingController();

  final _importadorNomeController = TextEditingController();
  final _importadorCnpjController = TextEditingController();
  final _importadorEnderecoController = TextEditingController();
  final _importadorContatoController = TextEditingController();

  final _tipoAcondicionamentoController = TextEditingController();

  String _status = 'Rascunho';
  String _modal = 'Marítimo';
  String _incoterm = 'EXW';
  String _tipoCarga = 'FCL';
  String _tipoContainer = '40 HC';

  bool _cargaPerigosa = false;
  bool _salvando = false;
  bool _carregando = false;

  DateTime? _dataProntidaoCarga;
  DateTime? _dataDesejadaChegada;

  final _statusList = [
    'Rascunho',
    'Solicitada',
    'Cotando',
    'Recebida',
    'Em análise',
    'Aprovada',
    'Contratada',
    'Cancelada',
  ];

  final _modais = [
    'Marítimo',
    'Aéreo',
    'Rodoviário',
    'Ferroviário',
    'Multimodal',
  ];

  final _incoterms = [
    'EXW',
    'FCA',
    'FAS',
    'FOB',
    'CFR',
    'CIF',
    'CPT',
    'CIP',
    'DAP',
    'DPU',
    'DDP',
  ];

  final _tiposCarga = ['FCL', 'LCL', 'Carga Solta', 'break bulk', 'a granel'];

  final _tiposContainer = [
    '20 DC',
    '40 DC',
    '40 HC',
    '45 HC',
    'Reefer 20',
    'Reefer 40',
    'Open Top',
    'Flat Rack',
  ];

  bool get _isEdicao => widget.cotacaoId != null;
  bool get _isExw => _incoterm == 'EXW';
  bool get _isFcl => _tipoCarga == 'FCL';

  @override
  void initState() {
    super.initState();
    if (_isEdicao) {
      _carregarCotacao();
    } else {
      _gerarReferenciaInicial();
    }
  }

  void _gerarReferenciaInicial() {
    final now = DateTime.now();
    _referenciaController.text =
        'COT-FRETE-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(8)}';
  }

  Future<void> _carregarCotacao() async {
    setState(() => _carregando = true);

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('cotacoes_frete_internacional')
              .doc(widget.cotacaoId)
              .get();

      if (!doc.exists) return;

      final data = doc.data()!;

      _referenciaController.text = data['referencia'] ?? '';
      _status = data['status'] ?? 'Rascunho';
      _modal = data['modal'] ?? 'Marítimo';
      _incoterm = data['incoterm'] ?? 'EXW';
      _tipoCarga = data['tipoCarga'] ?? 'FCL';
      _tipoContainer = data['tipoContainer'] ?? '40 HC';

      _localEmbarqueController.text = data['localEmbarque'] ?? '';
      _localDestinoController.text = data['localDestino'] ?? '';
      _terminalDestinoController.text = data['terminalDestino'] ?? '';
      _ncmController.text = data['ncm'] ?? '';
      _codigoImoController.text = data['codigoImo'] ?? '';
      _condicaoPagamentoController.text = data['condicaoPagamento'] ?? '';
      _observacoesController.text = data['observacoes'] ?? '';
      _cargaPerigosa = data['cargaPerigosa'] ?? false;

      _quantidadeContainersController.text =
          (data['quantidadeContainers'] ?? '').toString();
      _pesoBrutoController.text = (data['pesoBruto'] ?? '').toString();
      _cubagemController.text = (data['cubagem'] ?? '').toString();
      _volumesController.text = (data['volumes'] ?? '').toString();
      _dimensoesController.text = data['dimensoes'] ?? '';
      _tipoAcondicionamentoController.text = data['tipoAcondicionamento'] ?? '';

      final enderecoColeta = data['enderecoColeta'] ?? {};
      _paisColetaController.text = enderecoColeta['pais'] ?? '';
      _cidadeColetaController.text = enderecoColeta['cidade'] ?? '';
      _enderecoColetaController.text = enderecoColeta['endereco'] ?? '';
      _contatoColetaController.text = enderecoColeta['contato'] ?? '';
      _telefoneColetaController.text = enderecoColeta['telefone'] ?? '';

      final contratacao = data['contratacao'] ?? {};
      _referenciaCotacaoController.text =
          contratacao['referenciaCotacao'] ?? '';
      _instrucoesEstufagemController.text =
          contratacao['instrucoesEstufagem'] ?? '';

      _exportadorNomeController.text = contratacao['exportadorNome'] ?? '';
      _exportadorEnderecoController.text =
          contratacao['exportadorEndereco'] ?? '';
      _exportadorContatoController.text =
          contratacao['exportadorContato'] ?? '';

      _importadorNomeController.text = contratacao['importadorNome'] ?? '';
      _importadorCnpjController.text = contratacao['importadorCnpj'] ?? '';
      _importadorEnderecoController.text =
          contratacao['importadorEndereco'] ?? '';
      _importadorContatoController.text =
          contratacao['importadorContato'] ?? '';

      if (data['dataProntidaoCarga'] != null) {
        _dataProntidaoCarga =
            (data['dataProntidaoCarga'] as Timestamp).toDate();
      }

      if (data['dataDesejadaChegada'] != null) {
        _dataDesejadaChegada =
            (data['dataDesejadaChegada'] as Timestamp).toDate();
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
      final dados = {
        'companyId': user.uid,
        'createdByUid': user.uid,
        'referencia': _referenciaController.text.trim(),
        'status': _status,
        'modal': _modal,
        'incoterm': _incoterm,
        'tipoCarga': _tipoCarga,
        'tipoContainer': _isFcl ? _tipoContainer : null,
        'quantidadeContainers': _toInt(_quantidadeContainersController.text),
        'localEmbarque': _isExw ? null : _localEmbarqueController.text.trim(),
        'localDestino': _localDestinoController.text.trim(),
        'terminalDestino': _terminalDestinoController.text.trim(),
        'pesoBruto': _toDouble(_pesoBrutoController.text),
        'cubagem': _toDouble(_cubagemController.text),
        'volumes': _toInt(_volumesController.text),
        'dimensoes': _dimensoesController.text.trim(),
        'tipoAcondicionamento':
            !_isFcl ? _tipoAcondicionamentoController.text.trim() : null,
        'ncm': _ncmController.text.trim(),
        'codigoImo': _codigoImoController.text.trim(),
        'cargaPerigosa': _cargaPerigosa,
        'dataProntidaoCarga':
            _dataProntidaoCarga == null
                ? null
                : Timestamp.fromDate(_dataProntidaoCarga!),
        'dataDesejadaChegada':
            _dataDesejadaChegada == null
                ? null
                : Timestamp.fromDate(_dataDesejadaChegada!),
        'condicaoPagamento': _condicaoPagamentoController.text.trim(),
        'observacoes': _observacoesController.text.trim(),
        'enderecoColeta': {
          'pais': _paisColetaController.text.trim(),
          'cidade': _cidadeColetaController.text.trim(),
          'endereco': _enderecoColetaController.text.trim(),
          'contato': _contatoColetaController.text.trim(),
          'telefone': _telefoneColetaController.text.trim(),
        },
        'contratacao': {
          'referenciaCotacao': _referenciaCotacaoController.text.trim(),
          'instrucoesEstufagem': _instrucoesEstufagemController.text.trim(),
          'exportadorNome': _exportadorNomeController.text.trim(),
          'exportadorEndereco': _exportadorEnderecoController.text.trim(),
          'exportadorContato': _exportadorContatoController.text.trim(),
          'importadorNome': _importadorNomeController.text.trim(),
          'importadorCnpj': _importadorCnpjController.text.trim(),
          'importadorEndereco': _importadorEnderecoController.text.trim(),
          'importadorContato': _importadorContatoController.text.trim(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdicao) {
        await FirebaseFirestore.instance
            .collection('cotacoes_frete_internacional')
            .doc(widget.cotacaoId)
            .update(dados);
      } else {
        await FirebaseFirestore.instance
            .collection('cotacoes_frete_internacional')
            .add({...dados, 'createdAt': FieldValue.serverTimestamp()});
      }

      if (!mounted) return;
      _mostrarMensagem('Cotação salva com sucesso.');
      Navigator.pop(context, true);
    } catch (e) {
      _mostrarMensagem('Erro ao salvar cotação: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  double? _toDouble(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  int? _toInt(String value) {
    if (value.trim().isEmpty) return null;
    return int.tryParse(value);
  }

  Future<void> _selecionarData({
    required DateTime? dataAtual,
    required Function(DateTime) onSelecionado,
  }) async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataAtual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (data != null) {
      onSelecionado(data);
      setState(() {});
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

  @override
  void dispose() {
    _referenciaController.dispose();
    _localEmbarqueController.dispose();
    _localDestinoController.dispose();
    _terminalDestinoController.dispose();
    _ncmController.dispose();
    _codigoImoController.dispose();
    _condicaoPagamentoController.dispose();
    _observacoesController.dispose();
    _paisColetaController.dispose();
    _cidadeColetaController.dispose();
    _enderecoColetaController.dispose();
    _contatoColetaController.dispose();
    _telefoneColetaController.dispose();
    _quantidadeContainersController.dispose();
    _pesoBrutoController.dispose();
    _cubagemController.dispose();
    _volumesController.dispose();
    _dimensoesController.dispose();
    _referenciaCotacaoController.dispose();
    _instrucoesEstufagemController.dispose();
    _exportadorNomeController.dispose();
    _exportadorEnderecoController.dispose();
    _exportadorContatoController.dispose();
    _importadorNomeController.dispose();
    _importadorCnpjController.dispose();
    _importadorEnderecoController.dispose();
    _importadorContatoController.dispose();
    _pesoBrutoController.dispose();
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
                _salvando ? 'Salvando...' : 'Salvar Cotação',
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
                      expandedHeight: 190,
                      pinned: true,
                      elevation: 0,
                      backgroundColor: purple,
                      foregroundColor: Colors.white,
                      centerTitle: true,
                      title: Text(
                        _isEdicao ? 'Editar Cotação' : 'Nova Cotação',
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
                                      Icons.local_shipping_outlined,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Solicitacao de cotacao de frete internacionalll',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Solicitação, dados da carga e instrução de embarque.',
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
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                        child: Column(
                          children: [
                            _statusResumoCard(),
                            _section(
                              icon: Icons.description_outlined,
                              titulo: 'Dados da Cotação',
                              subtitulo:
                                  'Informe os dados principais da solicitação.',
                              color: purple,
                              children: [
                                _responsive([
                                  _textField(
                                    controller: _referenciaController,
                                    label: 'Referência',
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
                                  _dropdown(
                                    label: 'Modal',
                                    value: _modal,
                                    items: _modais,
                                    icon: Icons.public_rounded,
                                    onChanged:
                                        (v) => setState(() => _modal = v!),
                                  ),
                                  _dropdown(
                                    label: 'Incoterm',
                                    value: _incoterm,
                                    items: _incoterms,
                                    icon: Icons.handshake_outlined,
                                    onChanged:
                                        (v) => setState(() => _incoterm = v!),
                                  ),
                                  _dropdown(
                                    label: 'Tipo de Carga',
                                    value: _tipoCarga,
                                    items: _tiposCarga,
                                    icon: Icons.inventory_2_outlined,
                                    onChanged:
                                        (v) => setState(() => _tipoCarga = v!),
                                  ),
                                ]),
                              ],
                            ),
                            if (_isExw)
                              _section(
                                icon: Icons.location_on_outlined,
                                titulo: 'Endereço de Coleta - EXW',
                                subtitulo:
                                    'Para EXW, o endereço completo de coleta é obrigatório.',
                                color: orange,
                                children: [
                                  _alertBox(
                                    icon: Icons.info_outline_rounded,
                                    text:
                                        'No Incoterm EXW, o fornecedor disponibiliza a carga na origem. Por isso, informe o endereço completo para cotação da coleta.',
                                    color: orange,
                                  ),
                                  _responsive([
                                    _textField(
                                      controller: _paisColetaController,
                                      label: 'País',
                                      required: true,
                                      icon: Icons.flag_outlined,
                                    ),
                                    _textField(
                                      controller: _cidadeColetaController,
                                      label: 'Cidade',
                                      required: true,
                                      icon: Icons.location_city_outlined,
                                    ),
                                    _textField(
                                      controller: _enderecoColetaController,
                                      label: 'Endereço completo',
                                      required: true,
                                      icon: Icons.home_work_outlined,
                                    ),
                                    _textField(
                                      controller: _enderecoColetaController,
                                      label: 'ZIP Code',
                                      required: true,
                                      icon: Icons.home_work_outlined,
                                    ),
                                    _textField(
                                      controller: _contatoColetaController,
                                      label: 'Contato',
                                      icon: Icons.person_outline,
                                    ),
                                    _textField(
                                      controller: _telefoneColetaController,
                                      label: 'Telefone',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                    ),
                                  ]),
                                ],
                              ),
                            _section(
                              icon: Icons.route_outlined,
                              titulo: 'Origem e Destino',
                              subtitulo:
                                  'Informe o local de embarque e destino da operação.',
                              color: blue,
                              children: [
                                _responsive([
                                  if (!_isExw)
                                    _textField(
                                      controller: _localEmbarqueController,
                                      label: 'Local / Porto de embarque',
                                      required: true,
                                      icon: Icons.flight_takeoff_rounded,
                                    ),
                                  _textField(
                                    controller: _localDestinoController,
                                    label: 'Local / Porto de destino',
                                    required: true,
                                    icon: Icons.flight_land_rounded,
                                  ),
                                  _textField(
                                    controller: _terminalDestinoController,
                                    label:
                                        'Terminal alfandegado / destino final',
                                    icon: Icons.warehouse_outlined,
                                  ),
                                ]),
                              ],
                            ),
                            _section(
                              icon: Icons.inventory_2_outlined,
                              titulo: 'Dados da Carga',
                              subtitulo:
                                  'As informações mudam conforme o tipo de carga selecionado.',
                              color: green,
                              children: [
                                _tipoCargaInfo(),
                                const SizedBox(height: 12),
                                if (_isFcl)
                                  _responsive([
                                    _dropdown(
                                      label: 'Tipo de Container',
                                      value: _tipoContainer,
                                      items: _tiposContainer,
                                      icon: Icons.view_in_ar_outlined,
                                      onChanged:
                                          (v) => setState(
                                            () => _tipoContainer = v!,
                                          ),
                                    ),
                                    _textField(
                                      controller:
                                          _quantidadeContainersController,
                                      label: 'Quantidade de Containers',
                                      keyboardType: TextInputType.number,
                                      required: true,
                                      icon: Icons.numbers_rounded,
                                    ),
                                  ])
                                else
                                  _responsive([
                                    _textField(
                                      controller:
                                          _tipoAcondicionamentoController,
                                      label: 'Tipo de acondicionamento',
                                      required: true,
                                      icon: Icons.inventory_outlined,
                                    ),
                                    _textField(
                                      controller: _pesoBrutoController,
                                      label: 'Peso Bruto',
                                      keyboardType: TextInputType.number,
                                      required: true,
                                      icon: Icons.scale_outlined,
                                    ),
                                    _textField(
                                      controller: _cubagemController,
                                      label: 'Cubagem',
                                      keyboardType: TextInputType.number,
                                      required: true,
                                      icon: Icons.square_foot_outlined,
                                    ),
                                    _textField(
                                      controller: _volumesController,
                                      label: 'Quantidade de Volumes',
                                      keyboardType: TextInputType.number,
                                      icon: Icons.all_inbox_outlined,
                                    ),
                                    _textField(
                                      controller: _dimensoesController,
                                      label: 'Dimensões',
                                      icon: Icons.straighten_outlined,
                                    ),
                                  ]),
                                _responsive([
                                  _textField(
                                    controller: _ncmController,
                                    label: 'NCM da Mercadoria',
                                    icon: Icons.qr_code_2_rounded,
                                  ),
                                ]),
                                _switchCard(),
                                if (_cargaPerigosa)
                                  _textField(
                                    controller: _codigoImoController,
                                    label: 'Código IMO',
                                    required: true,
                                    icon: Icons.warning_amber_rounded,
                                  ),
                              ],
                            ),
                            _section(
                              icon: Icons.event_available_outlined,
                              titulo: 'Datas e Condições',
                              subtitulo:
                                  'Informe previsão de prontidão e condições desejadas.',
                              color: orange,
                              children: [
                                _responsive([
                                  _dateTile(
                                    label: 'Previsão de prontidão da carga',
                                    value: _formatarData(_dataProntidaoCarga),
                                    icon: Icons.event_outlined,
                                    onTap:
                                        () => _selecionarData(
                                          dataAtual: _dataProntidaoCarga,
                                          onSelecionado:
                                              (d) => _dataProntidaoCarga = d,
                                        ),
                                  ),
                                  _dateTile(
                                    label: 'Data desejada de chegada',
                                    value: _formatarData(_dataDesejadaChegada),
                                    icon: Icons.event_available_outlined,
                                    onTap:
                                        () => _selecionarData(
                                          dataAtual: _dataDesejadaChegada,
                                          onSelecionado:
                                              (d) => _dataDesejadaChegada = d,
                                        ),
                                  ),
                                  _textField(
                                    controller: _condicaoPagamentoController,
                                    label: 'Condição de pagamento desejada',
                                    icon: Icons.payments_outlined,
                                  ),
                                ]),
                                _textField(
                                  controller: _observacoesController,
                                  label: 'Observações',
                                  maxLines: 3,
                                  icon: Icons.notes_outlined,
                                ),
                              ],
                            ),
                            _section(
                              icon: Icons.assignment_turned_in_outlined,
                              titulo: 'Contratação',
                              subtitulo:
                                  'Preencha quando a cotação for aprovada e contratada.',
                              color: purple,
                              children: [
                                /*_subTitle('Exportador'),
                                _responsive([
                                  _textField(
                                    controller: _exportadorNomeController,
                                    label: 'Nome do exportador',
                                    icon: Icons.business_outlined,
                                  ),
                                  _textField(
                                    controller: _exportadorEnderecoController,
                                    label: 'Endereço do exportador',
                                    icon: Icons.location_on_outlined,
                                  ),
                                  _textField(
                                    controller: _exportadorContatoController,
                                    label: 'Contato do exportador',
                                    icon: Icons.person_outline,
                                  ),
                                ]),*/
                                _subTitle('Importador'),
                                _responsive([
                                  _textField(
                                    controller: _importadorNomeController,
                                    label: 'Nome do importador',
                                    icon: Icons.business_center_outlined,
                                  ),
                                  _textField(
                                    controller: _importadorCnpjController,
                                    label: 'CNPJ do importador',
                                    icon: Icons.badge_outlined,
                                  ),
                                  _textField(
                                    controller: _importadorEnderecoController,
                                    label: 'Endereço do importador',
                                    icon: Icons.location_on_outlined,
                                  ),
                                  _textField(
                                    controller: _importadorContatoController,
                                    label: 'Telefone do importador',
                                    icon: Icons.person_outline,
                                  ),
                                  _textField(
                                    controller: _importadorContatoController,
                                    label: 'Email do importador',
                                    icon: Icons.person_outline,
                                  ),
                                ]),
                              ],
                            ),
                            const SizedBox(height: 74),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _statusResumoCard() {
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
              Icons.anchor_outlined,
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
                  _referenciaController.text.isEmpty
                      ? 'Nova cotação'
                      : _referenciaController.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_modal • $_incoterm • $_tipoCarga • $_status',
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
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

  Widget _switchCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:
            _cargaPerigosa ? orange.withOpacity(0.08) : const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              _cargaPerigosa
                  ? orange.withOpacity(0.22)
                  : purple.withOpacity(0.10),
        ),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Carga perigosa',
          style: TextStyle(fontWeight: FontWeight.w800, color: textDark),
        ),
        subtitle: const Text(
          'Quando marcado, o código IMO será obrigatório.',
          style: TextStyle(fontWeight: FontWeight.w600, color: textMuted),
        ),
        value: _cargaPerigosa,
        activeColor: orange,
        onChanged: (v) => setState(() => _cargaPerigosa = v),
      ),
    );
  }

  Widget _tipoCargaInfo() {
    final texto =
        _isFcl
            ? 'FCL: container exclusivo. Informe tipo e quantidade de containers.'
            : 'LCL/Carga Solta: informe peso bruto, cubagem, volumes e dimensões.';

    return _alertBox(
      icon: _isFcl ? Icons.view_in_ar_outlined : Icons.inventory_outlined,
      text: texto,
      color: green,
    );
  }

  Widget _alertBox({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: textDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 20,
            decoration: BoxDecoration(
              color: purple,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: textDark,
            ),
          ),
        ],
      ),
    );
  }
}
