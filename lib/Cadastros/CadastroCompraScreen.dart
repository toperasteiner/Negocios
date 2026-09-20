// lib/Compras/CadastroCompraScreen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../Seletores/SelecionarFornecedorSheet.dart';
import '../Seletores/SelecionarProdutosSheet.dart';
import '../Seletores/SelecionarServicosSheet.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

class CadastroCompraStyle {
  static const primary = Color(0xFF6A2BFF);
  static const primaryDark = Color(0xFF32106C);
  static const orange = Color(0xFFFF9800);
  static const background = Color(0xFFF7F7FB);
  static const text = Color(0xFF17152B);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE7E5EF);

  static const headerGradient = LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class CadastroCompraScreen extends StatefulWidget {
  final String? compraId;

  const CadastroCompraScreen({super.key, this.compraId});

  @override
  State<CadastroCompraScreen> createState() => _CadastroCompraScreenState();
}

class _CadastroCompraScreenState extends State<CadastroCompraScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();

  final _formKey = GlobalKey<FormState>();

  final _fornecedorCtrl = TextEditingController();
  final _observacaoCtrl = TextEditingController();
  final _parcelasCtrl = TextEditingController();
  final _diaVencimentoParcelasCtrl = TextEditingController();
  final _dataEntregaCtrl = TextEditingController();

  static const String _contasPagarCollection = 'contas_pagar';
  static const String _categoriaPagarId = 'MQNMsI1StGHthMzojZLX';
  static const String _categoriaPagarNome = 'Compras';

  String? _companyId;
  String? _scopeUserId;

  bool _loadingScope = true;
  bool _loadingCompra = false;
  bool _saving = false;
  String? _erro;

  String? _fornecedorId;
  String? _fornecedorNome;

  final List<_LinhaCompraItem> _itens = [];

  String _condicaoPagamento = 'À vista';
  DateTime? _dataEntrega;

  bool get _isEdicao => widget.compraId != null && widget.compraId!.isNotEmpty;

  final List<String> _condicoesPagamento = const [
    'À vista',
    '7 dias',
    '15 dias',
    '30 dias',
    'Parcelado',
  ];

  double get _valorTotalCompra =>
      _itens.fold(0.0, (total, item) => total + item.total);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _fornecedorCtrl.dispose();
    _observacaoCtrl.dispose();
    _parcelasCtrl.dispose();
    _diaVencimentoParcelasCtrl.dispose();
    _dataEntregaCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _initScope();

    if (_isEdicao) {
      await _carregarCompra();
    }
  }

  /*Future<void> _atualizarEstoqueECustoMedioProdutos({
    required Transaction tx,
  }) async {
    final produtos =
        _itens
            .where(
              (item) =>
                  item.tipo == 'produto' &&
                  item.refId != null &&
                  item.refId!.isNotEmpty,
            )
            .toList();

    final snaps = <_LinhaCompraItem, DocumentSnapshot<Map<String, dynamic>>>{};

    // Primeiro: faz TODAS as leituras
    for (final item in produtos) {
      final produtoRef = _fs.collection('produtos').doc(item.refId);
      final produtoSnap = await tx.get(produtoRef);
      snaps[item] = produtoSnap;
    }

    // Depois: faz TODAS as escritas
    for (final entry in snaps.entries) {
      final item = entry.key;
      final produtoSnap = entry.value;

      if (!produtoSnap.exists) continue;

      final produtoRef = _fs.collection('produtos').doc(item.refId);
      final produtoData = produtoSnap.data() ?? {};

      final estoqueAtual = _toDouble(produtoData['estoque']);

      double precoAntigo = _toDouble(
        produtoData['precoMedio'] ?? produtoData['preco-medio'],
      );

      if (precoAntigo == 0) {
        precoAntigo = item.valorUnitario;
      }

      final novaQtd = item.quantidade;
      final novoPreco = item.valorUnitario;
      final estoqueTotal = estoqueAtual + novaQtd;

      final precoMedio =
          estoqueTotal <= 0
              ? novoPreco
              : ((estoqueAtual * precoAntigo) + (novaQtd * novoPreco)) /
                  estoqueTotal;

      tx.update(produtoRef, {
        'precoMedio': precoMedio,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }*/

  Future<void> _logCreatePurchase({
    required double total,
    required int itemsCount,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'create_purchase',
        parameters: {
          'value': total,
          'currency': 'BRL',
          'items_count': itemsCount,
        },
      );

      debugPrint(
        '✅ Firebase Analytics: create_purchase '
        'value=$total items_count=$itemsCount',
      );
    } catch (e) {
      debugPrint('⚠️ Firebase create_purchase: $e');
    }

    try {
      await _facebookAppEvents.logEvent(
        name: 'create_purchase',
        parameters: {
          'value': total,
          'currency': 'BRL',
          'items_count': itemsCount,
        },
      );

      await _facebookAppEvents.flush();

      debugPrint(
        '✅ Meta: create_purchase '
        'value=$total items_count=$itemsCount',
      );
    } catch (e) {
      debugPrint('⚠️ Meta create_purchase: $e');
    }
  }

  Future<void> _initScope() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        setState(() {
          _loadingScope = false;
          _erro = 'Usuário não autenticado.';
        });
        return;
      }

      Map<String, dynamic>? data;

      final userDoc = await _fs.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        data = userDoc.data();
      } else {
        final email = (user.email ?? '').trim().toLowerCase();

        if (email.isNotEmpty) {
          final q =
              await _fs
                  .collection('users')
                  .where('emailKey', isEqualTo: email)
                  .limit(1)
                  .get();

          if (q.docs.isNotEmpty) {
            data = q.docs.first.data();
          }
        }
      }

      data ??= {};

      final companyId = (data['companyId'] ?? '').toString().trim();

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : user.uid;
        _loadingScope = false;
        _erro = null;
      });
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _erro = 'Erro ao carregar escopo: $e';
      });
    }
  }

  DateTime _somenteData(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  int _ultimoDiaMes(int ano, int mes) {
    return DateTime(ano, mes + 1, 0).day;
  }

  DateTime _vencimentoParcelado({
    required DateTime hoje,
    required int numeroParcela,
    required int diaVencimento,
  }) {
    final mesInicial = hoje.day > diaVencimento ? 1 : 0;

    final base = DateTime(
      hoje.year,
      hoje.month + mesInicial + numeroParcela - 1,
      1,
    );

    final ultimoDia = _ultimoDiaMes(base.year, base.month);
    final dia = diaVencimento > ultimoDia ? ultimoDia : diaVencimento;

    return DateTime(base.year, base.month, dia);
  }

  DateTime _vencimentoPorCondicao(String condicao) {
    final hoje = _somenteData(DateTime.now());

    switch (condicao) {
      case '7 dias':
        return hoje.add(const Duration(days: 7));
      case '15 dias':
        return hoje.add(const Duration(days: 15));
      case '30 dias':
        return hoje.add(const Duration(days: 30));
      case 'À vista':
      default:
        return hoje;
    }
  }

  Future<bool> _compraTemTituloPagoOuParcial(String compraId) async {
    final qs =
        await _fs
            .collection(_contasPagarCollection)
            .where('compraId', isEqualTo: compraId)
            .get();

    for (final doc in qs.docs) {
      final status = (doc.data()['status'] ?? '').toString().toLowerCase();

      if (status == 'pago' || status == 'parcial') {
        return true;
      }
    }

    return false;
  }

  Future<void> _excluirContasPagarAbertasDaCompra({
    required Transaction tx,
    required String compraId,
  }) async {
    final antigos =
        await _fs
            .collection(_contasPagarCollection)
            .where('compraId', isEqualTo: compraId)
            .where('status', isEqualTo: 'aberto')
            .get();

    for (final doc in antigos.docs) {
      tx.delete(doc.reference);
    }
  }

  void _criarContasPagarDaCompra({
    required Transaction tx,
    required String compraId,
    required String userId,
    required double valorTotal,
    required int? quantidadeParcelas,
    required int? diaVencimentoParcelas,
    required String numeroCompra,
    required String ownerId,
    required String companyId,
  }) {
    final hoje = _somenteData(DateTime.now());

    if (_condicaoPagamento == 'Parcelado') {
      final qtdParcelas = quantidadeParcelas ?? 1;
      final diaVencimento = diaVencimentoParcelas ?? hoje.day;

      final valorBase = double.parse(
        (valorTotal / qtdParcelas).toStringAsFixed(2),
      );

      double acumulado = 0;

      for (int i = 1; i <= qtdParcelas; i++) {
        final isUltima = i == qtdParcelas;

        final valorParcela =
            isUltima
                ? double.parse((valorTotal - acumulado).toStringAsFixed(2))
                : valorBase;

        acumulado += valorParcela;

        final vencimento = _vencimentoParcelado(
          hoje: hoje,
          numeroParcela: i,
          diaVencimento: diaVencimento,
        );

        final ref = _fs.collection(_contasPagarCollection).doc();

        tx.set(ref, {
          'compraId': compraId,
          'numeroCompra': numeroCompra,
          'numeroParcela': i,
          'totalParcelas': qtdParcelas,

          'categoriaId': _categoriaPagarId,
          'categoriaNome': _categoriaPagarNome,
          'categoriaTipo': 'pagar',

          'ownerId': ownerId,
          'companyId': companyId,
          'userId': userId,
          'createdByUid': userId,

          'fornecedorId': _fornecedorId,
          'fornecedorNome': _fornecedorNome ?? '',

          'descricao':
              'Compra '
              '$numeroCompra $i/$qtdParcelas',
          'observacao':
              'Compra: $numeroCompra | Fornecedor: ${_fornecedorNome ?? ''} | Parcela $i/$qtdParcelas',

          'origem': 'compra',
          'status': 'aberto',
          'valor': valorParcela,
          'vencimento': Timestamp.fromDate(vencimento),

          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return;
    }

    final vencimento = _vencimentoPorCondicao(_condicaoPagamento);
    final ref = _fs.collection(_contasPagarCollection).doc();

    tx.set(ref, {
      'compraId': compraId,
      'numeroCompra': numeroCompra,
      'numeroParcela': 1,
      'totalParcelas': 1,

      'categoriaId': _categoriaPagarId,
      'categoriaNome': _categoriaPagarNome,
      'categoriaTipo': 'pagar',

      'ownerId': ownerId,
      'companyId': companyId,
      'userId': userId,
      'createdByUid': userId,

      'fornecedorId': _fornecedorId,
      'fornecedorNome': _fornecedorNome ?? '',

      'descricao': 'Compra: ' + numeroCompra,
      'observacao':
          'Compra: $numeroCompra | Fornecedor: ${_fornecedorNome ?? ''} | Valor: ${_fmtMoeda(valorTotal)}',

      'origem': 'compra',
      'status': 'aberto',
      'valor': valorTotal,
      'vencimento': Timestamp.fromDate(vencimento),

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> _gerarNumeroCompra(Transaction tx) async {
    final now = DateTime.now();
    final ano = now.year;
    final scope = (_scopeUserId ?? _auth.currentUser?.uid ?? 'sem_usuario');

    final controleId = '${scope}_$ano';
    final ref = _fs.collection('compras_controle').doc(controleId);

    final snap = await tx.get(ref);

    int sequenciaAtual = 0;

    if (snap.exists) {
      final data = snap.data() ?? {};
      final seq = data['sequencia'];

      if (seq is num) {
        sequenciaAtual = seq.toInt();
      }
    }

    final novaSequencia = sequenciaAtual + 1;

    tx.set(ref, {
      'sequencia': novaSequencia,
      'ano': ano,
      'scopeUserId': scope,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final numeroFormatado = novaSequencia.toString().padLeft(4, '0');
    return '$numeroFormatado/$ano';
  }

  Future<(String?, String?)> _resolveOwnerAndCompany() async {
    final user = _auth.currentUser;
    if (user == null) return (null, null);

    Map<String, dynamic>? data;

    final byUid = await _fs.collection('users').doc(user.uid).get();

    if (byUid.exists) {
      data = byUid.data();
    } else {
      final email = (user.email ?? '').trim().toLowerCase();

      if (email.isNotEmpty) {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();

        if (q.docs.isNotEmpty) {
          data = q.docs.first.data();
        }
      }
    }

    if (data == null) return (null, null);

    final companyId = (data['companyId'] ?? '').toString().trim();

    if (companyId.isEmpty) return (null, null);

    return (companyId, companyId);
  }

  Future<void> _carregarCompra() async {
    try {
      setState(() => _loadingCompra = true);

      final doc = await _fs.collection('compras').doc(widget.compraId).get();

      if (!doc.exists) {
        setState(() {
          _loadingCompra = false;
          _erro = 'Compra não encontrada.';
        });
        return;
      }

      final data = doc.data() ?? {};

      final dataEntregaRaw = data['dataEntrega'];
      DateTime? dataEntrega;

      if (dataEntregaRaw is Timestamp) {
        dataEntrega = dataEntregaRaw.toDate();
      }

      final itensRaw = data['itens'] ?? data['itensProdutos'];
      final itens = <_LinhaCompraItem>[];

      if (itensRaw is List) {
        for (final raw in itensRaw) {
          if (raw is! Map) continue;

          final m = Map<String, dynamic>.from(raw);

          itens.add(
            _LinhaCompraItem(
              refId: (m['refId'] ?? m['itemId'] ?? '').toString(),
              nome: (m['nome'] ?? m['itemNome'] ?? '').toString(),
              unidade: (m['unidade'] ?? 'UN').toString(),
              quantidade: _toDouble(m['quantidade']),
              valorUnitario: _toDouble(m['valorUnitario']),
              tipo: (m['tipo'] ?? m['tipoItem'] ?? 'produto').toString(),
            ),
          );
        }
      } else {
        final itemId = (data['itemId'] ?? '').toString();
        final itemNome = (data['itemNome'] ?? '').toString();

        if (itemId.isNotEmpty || itemNome.isNotEmpty) {
          itens.add(
            _LinhaCompraItem(
              refId: itemId,
              nome: itemNome,
              unidade: (data['unidade'] ?? 'UN').toString(),
              quantidade: _toDouble(data['quantidade']),
              valorUnitario: _toDouble(data['valorUnitario']),
              tipo: (data['tipoItem'] ?? 'produto').toString(),
            ),
          );
        }
      }

      setState(() {
        _fornecedorId = (data['fornecedorId'] ?? '').toString();
        _fornecedorNome = (data['fornecedorNome'] ?? '').toString();
        _fornecedorCtrl.text = _fornecedorNome ?? '';

        _itens
          ..clear()
          ..addAll(itens);

        _condicaoPagamento =
            (data['condicaoPagamento'] ?? 'À vista').toString();

        if (!_condicoesPagamento.contains(_condicaoPagamento)) {
          _condicaoPagamento = 'À vista';
        }

        _dataEntrega = dataEntrega;
        _dataEntregaCtrl.text =
            dataEntrega == null ? '' : _fmtData(dataEntrega);
        _observacaoCtrl.text = (data['observacao'] ?? '').toString();
        _parcelasCtrl.text = (data['quantidadeParcelas'] ?? '').toString();
        _diaVencimentoParcelasCtrl.text =
            (data['diaVencimentoParcelas'] ?? '').toString();

        _loadingCompra = false;
      });
    } catch (e) {
      setState(() {
        _loadingCompra = false;
        _erro = 'Erro ao carregar compra: $e';
      });
    }
  }

  Future<void> _selecionarFornecedor() async {
    final escolhido = await showModalBottomSheet<FornecedorSelecionado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SelecionarFornecedorSheet(),
    );

    if (escolhido == null) return;

    setState(() {
      _fornecedorId = escolhido.id;
      _fornecedorNome = escolhido.nome;
      _fornecedorCtrl.text = escolhido.nome;
    });
  }

  Future<void> _selecionarServicos() async {
    final escolhidos = await showModalBottomSheet<List<LinhaItemServicoPedido>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) =>
              const SelecionarServicosSheet(tipoPreco: TipoPrecoServico.compra),
    );

    if (escolhidos == null || escolhidos.isEmpty) return;

    setState(() {
      for (final e in escolhidos) {
        _itens.add(
          _LinhaCompraItem(
            refId: e.refId,
            nome: e.nome,
            unidade: e.unidade,
            quantidade: e.quantidade,
            valorUnitario: e.valorUnitario,
            tipo: 'servico',
          ),
        );
      }
    });
  }

  Future<void> _selecionarProdutos() async {
    final escolhidos = await showModalBottomSheet<List<LinhaItemPedido>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) =>
              const SelecionarProdutosSheet(tipoPreco: TipoPrecoProduto.compra),
    );

    if (escolhidos == null || escolhidos.isEmpty) return;

    setState(() {
      for (final e in escolhidos) {
        _itens.add(
          _LinhaCompraItem(
            refId: e.refId,
            nome: e.nome,
            unidade: e.unidade,
            quantidade: e.quantidade,
            valorUnitario: e.valorUnitario,
            tipo: 'produto',
          ),
        );
      }
    });
  }

  Future<void> _editarItem(int index) async {
    final itemAtual = _itens[index];

    final novo = await showModalBottomSheet<_LinhaCompraItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EditarItemCompraSheet(item: itemAtual),
    );

    if (novo == null) return;

    setState(() {
      _itens[index] = novo;
    });
  }

  Future<void> _selecionarDataEntrega() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _dataEntrega ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Selecione a data de entrega',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );

    if (picked == null) return;

    setState(() {
      _dataEntrega = DateTime(picked.year, picked.month, picked.day);

      _dataEntregaCtrl.text = _fmtData(_dataEntrega);
    });
  }

  Future<void> _salvar() async {
    if (_saving) return;

    final user = _auth.currentUser;

    if (user == null || _scopeUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuário não autenticado.')));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_fornecedorId == null || _fornecedorId!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecione um fornecedor.')));
      return;
    }

    if (_itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um item comprado.')),
      );
      return;
    }

    for (final item in _itens) {
      if (item.quantidade <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quantidade inválida para ${item.nome}.')),
        );
        return;
      }

      if (item.valorUnitario <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Valor unitário inválido para ${item.nome}.')),
        );
        return;
      }
    }

    int? quantidadeParcelas;
    int? diaVencimentoParcelas;

    if (_condicaoPagamento == 'Parcelado') {
      quantidadeParcelas = int.tryParse(_parcelasCtrl.text.trim());
      diaVencimentoParcelas = int.tryParse(
        _diaVencimentoParcelasCtrl.text.trim(),
      );

      if (quantidadeParcelas == null || quantidadeParcelas <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe a quantidade de parcelas.')),
        );
        return;
      }

      if (diaVencimentoParcelas == null ||
          diaVencimentoParcelas < 1 ||
          diaVencimentoParcelas > 31) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O dia de vencimento deve ser entre 1 e 31.'),
          ),
        );
        return;
      }
    }

    if (_isEdicao) {
      final temTituloPagoOuParcial = await _compraTemTituloPagoOuParcial(
        widget.compraId!,
      );

      if (temTituloPagoOuParcial) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta compra já possui título pago. '
              'Não é possível alterar valor ou parcelamento.',
            ),
          ),
        );
        return;
      }
    }

    final (ownerId, companyId) = await _resolveOwnerAndCompany();

    if (ownerId == null || companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem empresa vinculada: configure o companyId no cadastro do usuário.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final primeiroItem = _itens.first;
      final total = _valorTotalCompra;

      final payload = <String, dynamic>{
        'fornecedorId': _fornecedorId,
        'fornecedorNome': _fornecedorNome ?? '',

        'itemId': primeiroItem.refId,
        'itemNome':
            _itens.length == 1
                ? primeiroItem.nome
                : '${_itens.length} itens comprados',
        'tipoItem': _itens.length == 1 ? primeiroItem.tipo : 'multiplo',
        'quantidade':
            _itens.length == 1
                ? primeiroItem.quantidade
                : _itens.fold(0.0, (t, i) => t + i.quantidade),
        'valorUnitario': _itens.length == 1 ? primeiroItem.valorUnitario : 0.0,
        'valorTotal': total,

        'itens': _itens.map((e) => e.toMap()).toList(),
        'subtotal': total,
        'total': total,

        'condicaoPagamento': _condicaoPagamento,
        if (_condicaoPagamento == 'Parcelado') ...{
          'quantidadeParcelas': quantidadeParcelas,
          'diaVencimentoParcelas': diaVencimentoParcelas,
        } else if (_isEdicao) ...{
          'quantidadeParcelas': FieldValue.delete(),
          'diaVencimentoParcelas': FieldValue.delete(),
        },

        'dataEntrega':
            _dataEntrega == null ? null : Timestamp.fromDate(_dataEntrega!),
        'observacao': _observacaoCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      //List<_LinhaCompraItem> itensAntesDaEdicao = [];
      await _fs.runTransaction((tx) async {
        final compraRef =
            _isEdicao
                ? _fs.collection('compras').doc(widget.compraId)
                : _fs.collection('compras').doc();

        DocumentSnapshot<Map<String, dynamic>>? compraAtualSnap;

        if (_isEdicao) {
          compraAtualSnap = await tx.get(compraRef);

          if (!compraAtualSnap.exists) {
            throw Exception('Compra não encontrada.');
          }

          /*itensAntesDaEdicao = _extrairItensDaCompra(
            compraAtualSnap.data() ?? {},
          );*/
        }

        final numeroCompraAtual =
            (compraAtualSnap?.data()?['numeroCompra'] ?? '').toString().trim();

        final numeroCompraFinal =
            numeroCompraAtual.isNotEmpty
                ? numeroCompraAtual
                : await _gerarNumeroCompra(tx);

        payload['numeroCompra'] = numeroCompraFinal;

        if (_isEdicao) {
          tx.update(compraRef, payload);

          await _excluirContasPagarAbertasDaCompra(
            tx: tx,
            compraId: compraRef.id,
          );
        } else {
          payload.addAll({
            'status': 'aberta',
            'ownerId': ownerId,
            'companyId': companyId,
            'userId': user.uid,
            'createdByUid': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'estoqueEstornado': false,
          });

          tx.set(compraRef, payload);
        }

        _criarContasPagarDaCompra(
          tx: tx,
          compraId: compraRef.id,
          userId: user.uid,
          valorTotal: total,
          quantidadeParcelas: quantidadeParcelas,
          diaVencimentoParcelas: diaVencimentoParcelas,
          numeroCompra: numeroCompraFinal,
          ownerId: ownerId,
          companyId: companyId,
        );
      });

      /*if (_isEdicao) {
        await _fs.runTransaction((tx) async {
          await _ajustarEstoqueAlteracaoCompra(
            tx: tx,
            itensAntigos: itensAntesDaEdicao,
            itensNovos: _itens,
          );
        });
      } else {
        await _fs.runTransaction((tx) async {
          await _atualizarEstoqueECustoMedioProdutos(tx: tx);
        });
      }*/

      // ============================================================
      // ANALYTICS - NOVA COMPRA CRIADA
      // Dispara somente na inclusão.
      // Alterações em compras existentes não geram novo evento.
      // ============================================================
      if (!_isEdicao) {
        await _logCreatePurchase(total: total, itemsCount: _itens.length);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdicao ? 'Compra alterada.' : 'Compra cadastrada.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar compra: $e')));
    }
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();

    final text = v
        .toString()
        .trim()
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(text) ?? 0.0;
  }

  /*List<_LinhaCompraItem> _extrairItensDaCompra(Map<String, dynamic> data) {
    final itensRaw = data['itens'] ?? data['itensProdutos'];
    final itens = <_LinhaCompraItem>[];

    if (itensRaw is List) {
      for (final raw in itensRaw) {
        if (raw is! Map) continue;

        final m = Map<String, dynamic>.from(raw);

        itens.add(
          _LinhaCompraItem(
            refId: (m['refId'] ?? m['itemId'] ?? '').toString(),
            nome: (m['nome'] ?? m['itemNome'] ?? '').toString(),
            unidade: (m['unidade'] ?? 'UN').toString(),
            quantidade: _toDouble(m['quantidade']),
            valorUnitario: _toDouble(m['valorUnitario']),
            tipo: (m['tipo'] ?? m['tipoItem'] ?? 'produto').toString(),
          ),
        );
      }
    }

    return itens;
  }*/

  /*Map<String, _LinhaCompraItem> _mapProdutosPorId(
    List<_LinhaCompraItem> itens,
  ) {
    final map = <String, _LinhaCompraItem>{};

    for (final item in itens) {
      if (item.tipo != 'produto') continue;

      final produtoId = item.refId?.trim() ?? '';
      if (produtoId.isEmpty) continue;

      final atual = map[produtoId];

      if (atual == null) {
        map[produtoId] = item;
      } else {
        map[produtoId] = atual.copyWith(
          quantidade: atual.quantidade + item.quantidade,
          valorUnitario: item.valorUnitario,
        );
      }
    }

    return map;
  }*/

  /*Future<void> _ajustarEstoqueAlteracaoCompra({
    required Transaction tx,
    required List<_LinhaCompraItem> itensAntigos,
    required List<_LinhaCompraItem> itensNovos,
  }) async {
    //final antigos = _mapProdutosPorId(itensAntigos);
    //final novos = _mapProdutosPorId(itensNovos);

    final produtoIds = <String>{...antigos.keys, ...novos.keys};

    final snaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};

    for (final produtoId in produtoIds) {
      final produtoRef = _fs.collection('produtos').doc(produtoId);
      snaps[produtoId] = await tx.get(produtoRef);
    }

    for (final produtoId in produtoIds) {
      final snap = snaps[produtoId];

      if (snap == null || !snap.exists) continue;

      final produtoRef = _fs.collection('produtos').doc(produtoId);
      final produtoData = snap.data() ?? {};

      final qtdAntiga = antigos[produtoId]?.quantidade ?? 0;
      final qtdNova = novos[produtoId]?.quantidade ?? 0;
      final diferenca = qtdNova - qtdAntiga;

      if (diferenca == 0) continue;

      final estoqueAtual = _toDouble(produtoData['estoque']);
      final novoEstoque = estoqueAtual + diferenca;

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (diferenca > 0 && novoEstoque > 0) {
        double precoAntigo = _toDouble(
          produtoData['precoMedio'] ?? produtoData['preco-medio'],
        );

        final novoPreco = novos[produtoId]?.valorUnitario ?? 0;

        if (precoAntigo == 0) {
          precoAntigo = novoPreco;
        }

        final precoMedio =
            novoEstoque <= 0
                ? novoPreco
                : ((estoqueAtual * precoAntigo) + (diferenca * novoPreco)) /
                    novoEstoque;

        updates['precoMedio'] = precoMedio;
      }

      tx.update(produtoRef, updates);
    }
  }*/

  String _fmtMoeda(num v) {
    final sinal = v < 0 ? '-' : '';
    final vv = v.abs();
    final s = vv.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return '${sinal}R\$ $inteiro,${p[1]}';
  }

  String _fmtData(DateTime? d) {
    if (d == null) return 'Selecionar data';

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope || _loadingCompra) {
      return const Scaffold(
        backgroundColor: CadastroCompraStyle.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_erro != null) {
      return Scaffold(
        backgroundColor: CadastroCompraStyle.background,
        appBar: AppBar(
          title: const Text('Compra'),
          backgroundColor: CadastroCompraStyle.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: CadastroCompraStyle.background,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: FilledButton.icon(
            onPressed: _saving ? null : _salvar,
            style: FilledButton.styleFrom(
              backgroundColor: CadastroCompraStyle.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon:
                _saving
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.save_outlined),
            label: Text(
              _saving ? 'Salvando...' : 'Salvar compra',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          children: [
            _cabecalho(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _bloco(
                          icon: Icons.local_shipping_outlined,
                          titulo: 'Fornecedor',
                          child: _campoFornecedor(),
                        ),
                        const SizedBox(height: 12),
                        _secaoItens(),
                        const SizedBox(height: 12),
                        _bloco(
                          icon: Icons.credit_card_outlined,
                          titulo: 'Pagamento',
                          child: Column(
                            children: [
                              _campoCondicaoPagamento(),
                              if (_condicaoPagamento == 'Parcelado') ...[
                                const SizedBox(height: 14),
                                _camposParcelamento(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _bloco(
                          icon: Icons.event_outlined,
                          titulo: 'Entrega',
                          child: _campoDataEntrega(),
                        ),
                        const SizedBox(height: 12),
                        _bloco(
                          icon: Icons.notes_outlined,
                          titulo: 'Observações',
                          child: _campoObservacao(),
                        ),
                        const SizedBox(height: 12),
                        _cardTotalCompra(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: CadastroCompraStyle.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          _botaoCabecalho(
            Icons.arrow_back_rounded,
            () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Text(
                  _isEdicao ? 'Alterar compra' : 'Nova compra',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fornecedor, itens e pagamento',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.82),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _botaoCabecalho(Icons.check_rounded, _saving ? () {} : _salvar),
        ],
      ),
    );
  }

  Widget _botaoCabecalho(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _bloco({
    required IconData icon,
    required String titulo,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: CadastroCompraStyle.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: CadastroCompraStyle.primary),
              ),
              const SizedBox(width: 12),
              Text(
                titulo,
                style: const TextStyle(
                  color: CadastroCompraStyle.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _campoFornecedor() {
    const cs = ColorScheme.light(primary: CadastroCompraStyle.primary);

    return TextFormField(
      controller: _fornecedorCtrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: 'Fornecedor',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        prefixIcon: const Icon(Icons.local_shipping_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_fornecedorCtrl.text.isNotEmpty)
              IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.close),
                onPressed:
                    () => setState(() {
                      _fornecedorId = null;
                      _fornecedorNome = null;
                      _fornecedorCtrl.clear();
                    }),
              ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: cs.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _selecionarFornecedor,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      onTap: _selecionarFornecedor,
      validator: (_) {
        if (_fornecedorId == null || _fornecedorId!.isEmpty) {
          return 'Selecione um fornecedor';
        }
        return null;
      },
    );
  }

  Widget _secaoItens() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rowAction(
              icon: Icons.inventory_2_outlined,
              label: 'Adicionar produtos',
              onAdd: _selecionarProdutos,
            ),
            const SizedBox(height: 8),
            _rowAction(
              icon: Icons.build_outlined,
              label: 'Adicionar serviços',
              onAdd: _selecionarServicos,
            ),
            const SizedBox(height: 10),
            if (_itens.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Adicione produtos ou serviços à compra.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _fmtMoeda(_valorTotalCompra),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _listaItens(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowAction({
    required IconData icon,
    required String label,
    required VoidCallback onAdd,
    Widget? trailing,
  }) {
    const cs = ColorScheme.light(primary: CadastroCompraStyle.primary);

    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[trailing, const SizedBox(width: 8)],
          Material(
            color: cs.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onAdd,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      onTap: onAdd,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _listaItens() {
    return Column(
      children: [
        for (int i = 0; i < _itens.length; i++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              title: Text(
                _itens[i].nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${_itens[i].quantidade} ${_itens[i].unidade} × ${_fmtMoeda(_itens[i].valorUnitario)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmtMoeda(_itens[i].total),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') {
                        _editarItem(i);
                      } else if (v == 'del') {
                        setState(() => _itens.removeAt(i));
                      }
                    },
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Editar'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'del',
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              title: Text('Excluir'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _campoCondicaoPagamento() {
    return DropdownButtonFormField<String>(
      value: _condicaoPagamento,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Condição de pagamento',
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        prefixIcon: const Icon(
          Icons.credit_card_outlined,
          color: CadastroCompraStyle.primary,
        ),
      ),
      items:
          _condicoesPagamento
              .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
              .toList(),
      onChanged: (v) {
        if (v == null) return;

        setState(() {
          _condicaoPagamento = v;

          if (_condicaoPagamento != 'Parcelado') {
            _parcelasCtrl.clear();
            _diaVencimentoParcelasCtrl.clear();
          }
        });
      },
    );
  }

  Widget _camposParcelamento() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parcelamento',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _parcelasCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Quantidade de parcelas',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.format_list_numbered),
                    ),
                    validator: (_) {
                      if (_condicaoPagamento != 'Parcelado') return null;

                      final qtd = int.tryParse(_parcelasCtrl.text.trim());

                      if (qtd == null || qtd <= 0) {
                        return 'Informe as parcelas';
                      }

                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _diaVencimentoParcelasCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Dia vencimento',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event_available_outlined),
                    ),
                    validator: (_) {
                      if (_condicaoPagamento != 'Parcelado') return null;

                      final dia = int.tryParse(
                        _diaVencimentoParcelasCtrl.text.trim(),
                      );

                      if (dia == null || dia < 1 || dia > 31) {
                        return 'Dia de 1 a 31';
                      }

                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Informe o dia fixo de vencimento das parcelas. Exemplo: todo dia 10.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoDataEntrega() {
    return TextFormField(
      controller: _dataEntregaCtrl,
      readOnly: true,
      onTap: _selecionarDataEntrega,
      decoration: InputDecoration(
        labelText: 'Data de entrega',
        hintText: 'Selecione a data',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        prefixIcon: const Icon(
          Icons.event_outlined,
          color: CadastroCompraStyle.primary,
        ),
        suffixIcon: IconButton(
          tooltip: 'Selecionar data',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: _selecionarDataEntrega,
        ),
      ),
    );
  }

  Widget _campoObservacao() {
    return TextFormField(
      controller: _observacaoCtrl,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: 'Observações',
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        prefixIcon: const Icon(
          Icons.notes_outlined,
          color: CadastroCompraStyle.primary,
        ),
      ),
    );
  }

  Widget _cardTotalCompra() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      decoration: BoxDecoration(
        gradient: CadastroCompraStyle.headerGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.payments_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total da compra',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            _fmtMoeda(_valorTotalCompra),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaCompraItem {
  final String? refId;
  final String nome;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final String tipo;

  double get total => quantidade * valorUnitario;

  _LinhaCompraItem({
    required this.refId,
    required this.nome,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.tipo,
  });

  Map<String, dynamic> toMap() => {
    'refId': refId,
    'nome': nome,
    'tipo': tipo,
    'unidade': unidade,
    'quantidade': quantidade,
    'valorUnitario': valorUnitario,
    'total': total,
  };

  _LinhaCompraItem copyWith({
    String? refId,
    String? nome,
    String? unidade,
    double? quantidade,
    double? valorUnitario,
    String? tipo,
  }) {
    return _LinhaCompraItem(
      refId: refId ?? this.refId,
      nome: nome ?? this.nome,
      unidade: unidade ?? this.unidade,
      quantidade: quantidade ?? this.quantidade,
      valorUnitario: valorUnitario ?? this.valorUnitario,
      tipo: tipo ?? this.tipo,
    );
  }
}

class _EditarItemCompraSheet extends StatefulWidget {
  final _LinhaCompraItem item;

  const _EditarItemCompraSheet({required this.item});

  @override
  State<_EditarItemCompraSheet> createState() => _EditarItemCompraSheetState();
}

class _EditarItemCompraSheetState extends State<_EditarItemCompraSheet> {
  late final TextEditingController _qtdCtrl;
  late final TextEditingController _valorCtrl;

  @override
  void initState() {
    super.initState();

    _qtdCtrl = TextEditingController(
      text: widget.item.quantidade.toString().replaceAll('.', ','),
    );

    _valorCtrl = TextEditingController(
      text: widget.item.valorUnitario.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _qtdCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  double _parseNumero(String value) {
    final text = value.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(text) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final padding =
        MediaQuery.of(context).viewInsets + const EdgeInsets.all(16);

    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            Text(
              widget.item.nome,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _qtdCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor unitário de compra',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final qtd = _parseNumero(_qtdCtrl.text);
                      final valor = _parseNumero(_valorCtrl.text);

                      if (qtd <= 0 || valor <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Informe quantidade e valor unitário válidos.',
                            ),
                          ),
                        );
                        return;
                      }

                      Navigator.pop(
                        context,
                        widget.item.copyWith(
                          quantidade: qtd,
                          valorUnitario: valor,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
