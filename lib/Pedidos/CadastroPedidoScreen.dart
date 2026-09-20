// lib/Pedidos/CadastroPedidoScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../Seletores/SelecionarServicosSheet.dart';
import '../Seletores/SelecionarProdutosSheet.dart';
import '../Seletores/SelecionarClienteSheet.dart';
import '../Pedidos/ConfigurarPagamentoScreen.dart';
import '../Pedidos/GarantiaScreen.dart';
import '../Pedidos/MeiosPagamentoScreen.dart';
import '../Seletores/SelecionarStatusPedidoScreen.dart';
import '../Financeiro/ContasReceberPreviewScreen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../services/review_service.dart';
import '../Pedidos/ConfigurarEntregaPedidoScreen.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

// Desconto pode ser valor absoluto (R$) ou percentual (% sobre o subtotal)
enum DescontoTipo { valor, percentual }

class CadastroPedidoScreen extends StatefulWidget {
  final String? pedidoId; // edição
  final Map<String, dynamic>? initialData; // dados pré-preenchidos (duplicar)
  final bool isDuplicate; // flag de duplicação

  const CadastroPedidoScreen({
    super.key,
    this.pedidoId,
    this.initialData,
    this.isDuplicate = false,
  });

  @override
  State<CadastroPedidoScreen> createState() => _CadastroPedidoScreenState();
}

class _Excedente {
  final String nome;
  final double quantidadeSolicitada;
  final double estoqueAtual;
  _Excedente(this.nome, this.quantidadeSolicitada, this.estoqueAtual);
}

class _CadastroPedidoScreenState extends State<CadastroPedidoScreen> {
  // ===== ESCOPO POR EMPRESA/USUÁRIO =====
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();
  final ReviewService _reviewService = ReviewService();

  String? get _uid => _auth.currentUser?.uid;

  String? _companyId; // users.companyId do usuário logado (se houver)
  String? _scopeUserId; // companyId ?? uid  -> usado em queries/escritas
  bool _loadingScope = true; // tela de loading até resolver escopo
  String? _scopeError;
  String? get _scopeId =>
      (_companyId != null && _companyId!.isNotEmpty) ? _companyId : _uid;

  // ==== Helpers de escopo para numeração/consulta ====
  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeValue => _isCompanyScope ? _companyId! : (_uid ?? '_');

  Query<Map<String, dynamic>> _pedidosPorEscopoEAno(int ano) {
    final col = _fs.collection('pedidos').where('ano', isEqualTo: ano);
    return _isCompanyScope
        ? col.where('companyId', isEqualTo: _companyId)
        : col.where('userId', isEqualTo: _uid);
  }

  // ===== DETALHES =====
  bool _expDetalhes = true;
  int _parcelas = 0;
  GarantiaConfig? _garantiaCfg; // null = ainda não definida

  // Mapa produtoId -> quantidade original no pedido (antes de salvar)
  Map<String, double> _produtosOriginais = {};

  Map<String, double> _mapearQuantidadesPorProduto(List<_LinhaItem> itens) {
    final map = <String, double>{};
    for (final it in itens) {
      final id = it.refId;
      if (id == null || id.isEmpty) continue;
      map[id] = (map[id] ?? 0) + it.quantidade;
    }
    return map;
  }

  final _meiosPagCtrl = TextEditingController();
  final _garantiaCtrl = TextEditingController();
  final _clausulasCtrl = TextEditingController();
  final _infoAdicCtrl = TextEditingController();
  final _anotacoesCtrl = TextEditingController();
  final _relatorioCtrl = TextEditingController();

  String? _clienteId; // guarda o id do cliente escolhido
  bool _carregando = false; // loading geral quando for editar
  bool _inicializado = false;

  bool get _isEdicao => widget.pedidoId != null;

  // ---- estado principal ----
  int _numero = 1;
  int _ano = DateTime.now().year;
  DateTime _data = DateTime.now();

  final _clienteCtrl = TextEditingController(); // pode receber ID ou nome
  final _refCtrl = TextEditingController();

  // compromissos (opcional)
  DateTime? _compromisso;
  final _compromissoTextoCtrl = TextEditingController();

  // Itens
  final List<_LinhaItem> _servicos = [];
  final List<_LinhaItem> _produtos = [];

  List<MetodoPagamento> _meiosPermitidosEmpresa = [];

  List<ItemPedidoEntregaBase> _itensParaEntrega() {
    return [
      ..._produtos.map(
        (p) => ItemPedidoEntregaBase(
          refId: p.refId,
          tipo: 'produto',
          nome: p.nome,
          unidade: p.unidade,
          quantidade: p.quantidade,
        ),
      ),
      ..._servicos.map(
        (s) => ItemPedidoEntregaBase(
          refId: s.refId,
          tipo: 'servico',
          nome: s.nome,
          unidade: s.unidade,
          quantidade: s.quantidade,
        ),
      ),
    ];
  }

  // Taxas/ajustes
  DescontoTipo _descontoTipo = DescontoTipo.valor;
  double _descontoValor = 0.0; // em R$
  double _descontoPercent = 0.0; // em %

  double _taxaEntrega = 0.0;
  double _outrasTaxas = 0.0;

  bool _salvando = false;
  bool _expandedCompromissos = false;
  bool _mostrarAnaliseInterna = false;

  List<MetodoPagamento> _meiosSelecionados = []; // vazio até o usuário escolher

  String _resumoMeiosPagamento() {
    if (_meiosSelecionados.isEmpty) return 'toque para selecionar';
    final r = MeiosPagamentoResult(_meiosSelecionados).resumo();
    return r;
  }

  // ====== RESOLUÇÃO DE ESCOPO ======
  @override
  void initState() {
    super.initState();
    _initScope();
  }

  Future<void> _carregarMeiosPagamentoEmpresa() async {
    final scope = _scopeUserId;
    if (scope == null) return;

    try {
      final q =
          await _fs
              .collection('company_payment_settings')
              .where('companyId', isEqualTo: scope)
              .limit(1)
              .get();

      if (q.docs.isEmpty) {
        setState(() {
          _meiosPermitidosEmpresa = [];
        });
        return;
      }

      final data = q.docs.first.data();
      final methods = Map<String, dynamic>.from(data['methods'] ?? {});

      final permitidos = <MetodoPagamento>[];

      void addSeAtivo(String key, MetodoPagamento metodo) {
        if (methods[key] == true) {
          permitidos.add(metodo);
        }
      }

      addSeAtivo('dinheiro', MetodoPagamento.dinheiro);
      addSeAtivo('pix', MetodoPagamento.pix);
      addSeAtivo('boleto', MetodoPagamento.boleto);
      addSeAtivo('cheque', MetodoPagamento.cheque);
      addSeAtivo('transferencia', MetodoPagamento.transferencia);
      addSeAtivo('cartaoCredito', MetodoPagamento.cartaoCredito);
      addSeAtivo('cartaoDebito', MetodoPagamento.cartaoDebito);

      if (!mounted) return;

      setState(() {
        _meiosPermitidosEmpresa = permitidos;

        if (!_isEdicao && _meiosSelecionados.isEmpty) {
          _meiosSelecionados = List<MetodoPagamento>.from(permitidos);
        }

        _meiosPagCtrl.text = _resumoMeiosPagamento();
      });
    } catch (e) {
      debugPrint('Erro ao carregar meios de pagamento da empresa: $e');
    }
  }

  Future<void> _logCreateOrder({
    required String pedidoId,
    required double total,
    required int itensCount,
    required bool isEdicao,
    required bool isDuplicate,
  }) async {
    // ============================================================
    // FIREBASE ANALYTICS
    // ============================================================
    try {
      await _analytics.logEvent(
        name: 'create_order',
        parameters: {
          'pedido_id': pedidoId,
          'value': total,
          'currency': 'BRL',
          'items_count': itensCount,
          'is_edit': isEdicao ? 1 : 0,
          'is_duplicate': isDuplicate ? 1 : 0,
          'scope': _isCompanyScope ? 'company' : 'user',
        },
      );

      debugPrint('✅ Firebase: create_order enviado');
    } catch (e) {
      debugPrint('⚠️ Firebase: erro ao enviar create_order: $e');
    }

    // ============================================================
    // META / FACEBOOK APP EVENTS
    // ============================================================
    try {
      await _facebookAppEvents.logEvent(
        name: 'create_order',
        parameters: {
          'pedido_id': pedidoId,
          'value': total,
          'currency': 'BRL',
          'items_count': itensCount,
          'is_duplicate': isDuplicate ? 1 : 0,
        },
      );

      await _facebookAppEvents.flush();

      debugPrint(
        '✅ Meta: create_order enviado '
        'pedido=$pedidoId total=$total itens=$itensCount',
      );
    } catch (e) {
      debugPrint('⚠️ Meta: erro ao enviar create_order: $e');
    }
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
      });
      return;
    }
    try {
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();
      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isEmpty ? u.uid : companyId;
        _loadingScope = false;
        _scopeError = null;
      });

      await _carregarMeiosPagamentoEmpresa();

      // Com escopo resolvido, segue o fluxo normal
      if (widget.pedidoId == null) {
        _preencherTextosPadroes();

        if (widget.initialData != null && widget.isDuplicate) {
          // aplica dados do original
          _aplicarMapaNosControles(widget.initialData!);
          // força sugerir novo número válido ao duplicar
          await _initNumeroAuto();
        } else {
          await _initNumeroAuto(); // inclusão “normal”
        }
      } else {
        _carregarPedido(); // edição
      }
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar empresa/escopo: $e';
      });
    }
  }

  Future<void> _carregarCompromissoAgenda(String pedidoId) async {
    try {
      final scope = _scopeUserId ?? _auth.currentUser?.uid;
      final uid = _auth.currentUser?.uid;

      // Vamos guardar o primeiro documento encontrado aqui
      QueryDocumentSnapshot<Map<String, dynamic>>? snap;

      // 1) Novo modelo (escopo = companyId ou uid)
      if (scope != null) {
        final q1 =
            await _fs
                .collection('agenda')
                .where('userId', isEqualTo: scope)
                .where('pedidoId', isEqualTo: pedidoId)
                .limit(1)
                .get();
        if (q1.docs.isNotEmpty) snap = q1.docs.first;
      }

      // 2) Fallback legado (userId == uid)
      if (snap == null && uid != null && uid != scope) {
        final q2 =
            await _fs
                .collection('agenda')
                .where('userId', isEqualTo: uid)
                .where('pedidoId', isEqualTo: pedidoId)
                .limit(1)
                .get();
        if (q2.docs.isNotEmpty) snap = q2.docs.first;
      }

      // 3) Fallback final: só por pedidoId
      if (snap == null) {
        final q3 =
            await _fs
                .collection('agenda')
                .where('pedidoId', isEqualTo: pedidoId)
                .limit(1)
                .get();
        if (q3.docs.isNotEmpty) snap = q3.docs.first;
      }

      if (!mounted) return;

      if (snap == null) {
        setState(() {
          _compromisso = null;
          _compromissoTextoCtrl.clear();
          _expandedCompromissos = false;
        });
        return;
      }

      final m = snap.data();
      final ts = m['compromisso'];
      final dt = ts is Timestamp ? ts.toDate() : null;
      final txt = (m['compromissoTexto'] as String?)?.trim() ?? '';

      setState(() {
        _compromisso = dt;
        _compromissoTextoCtrl.text = txt;
        _expandedCompromissos =
            dt != null || txt.isNotEmpty; // expande se houver dados
      });
    } catch (_) {
      // silencioso
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    // 1) por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) {
        final data = (byUid.data() ?? {}) as Map<String, dynamic>;
        data['__docId'] = byUid.id;
        return data;
      }
    } catch (_) {}

    // 2) por emailKey (fallback)
    final email = (u.email ?? '').toLowerCase().trim();
    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          d['__docId'] = q.docs.first.id;
          return d;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Retorna (ownerId, companyId) ao criar um pedido
  Future<(String?, String?)> _resolveOwnerAndCompany() async {
    final me = await _loadCurrentUserRecord();
    if (me == null) return (null, null);

    final role = (me['role'] ?? '').toString().toLowerCase().trim();
    final companyId = (me['companyId'] ?? '').toString().trim();
    final uid = _auth.currentUser?.uid;

    if (role == 'admin') {
      // admin pode operar no próprio uid (sem company) ou em companyId se existir
      return (
        companyId.isNotEmpty ? companyId : uid,
        companyId.isNotEmpty ? companyId : null,
      );
    }
    if (role == 'funcionario') {
      // funcionários devem pertencer a uma empresa
      if (companyId.isEmpty) return (null, null);
      return (companyId, companyId);
    }
    // default: sem permissão clara
    return (null, null);
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _refCtrl.dispose();

    _meiosPagCtrl.dispose();
    _garantiaCtrl.dispose();
    _clausulasCtrl.dispose();
    _infoAdicCtrl.dispose();
    _anotacoesCtrl.dispose();
    _relatorioCtrl.dispose();
    _compromissoTextoCtrl.dispose();

    super.dispose();
  }

  void _aplicarMapaNosControles(Map<String, dynamic> m) {
    // Campos simples
    _ano = (m['ano'] as num?)?.toInt() ?? _ano;
    final tsData = m['data'];
    _data =
        tsData is Timestamp
            ? DateTime(
              tsData.toDate().year,
              tsData.toDate().month,
              tsData.toDate().day,
            )
            : _data;

    _clienteId = (m['clienteId'] as String?);
    _clienteCtrl.text =
        (m['clienteNome'] as String?) ??
        (m['cliente'] as String? ?? _clienteCtrl.text);
    _refCtrl.text = (m['referencia'] as String?) ?? _refCtrl.text;

    // Itens
    _servicos
      ..clear()
      ..addAll(
        ((m['itensServicos'] as List?) ?? []).map((e) {
          final x = Map<String, dynamic>.from(e as Map);
          return _LinhaItem(
            refId: x['refId'] as String?,
            nome: (x['nome'] ?? '').toString(),
            unidade: (x['unidade'] ?? 'UN').toString(),
            quantidade:
                (x['quantidade'] is num)
                    ? (x['quantidade'] as num).toDouble()
                    : double.tryParse('${x['quantidade']}') ?? 0.0,
            valorUnitario:
                (x['valorUnitario'] is num)
                    ? (x['valorUnitario'] as num).toDouble()
                    : double.tryParse('${x['valorUnitario']}') ?? 0.0,
            custoUnitario:
                (x['custoUnitario'] is num)
                    ? (x['custoUnitario'] as num).toDouble()
                    : double.tryParse('${x['custoUnitario']}') ?? 0.0,
          );
        }),
      );

    _produtos
      ..clear()
      ..addAll(
        ((m['itensProdutos'] as List?) ?? []).map((e) {
          final x = Map<String, dynamic>.from(e as Map);
          return _LinhaItem(
            refId: x['refId'] as String?,
            nome: (x['nome'] ?? '').toString(),
            unidade: (x['unidade'] ?? 'UN').toString(),
            quantidade:
                (x['quantidade'] is num)
                    ? (x['quantidade'] as num).toDouble()
                    : double.tryParse('${x['quantidade']}') ?? 0.0,
            valorUnitario:
                (x['valorUnitario'] is num)
                    ? (x['valorUnitario'] as num).toDouble()
                    : double.tryParse('${x['valorUnitario']}') ?? 0.0,
            custoUnitario:
                (x['custoUnitario'] is num)
                    ? (x['custoUnitario'] as num).toDouble()
                    : double.tryParse('${x['custoUnitario']}') ?? 0.0,
          );
        }),
      );

    // Descontos/Taxas
    final tipo = (m['descontoTipo'] as String?) ?? 'valor';
    _descontoTipo =
        (tipo == 'percentual') ? DescontoTipo.percentual : DescontoTipo.valor;
    _descontoValor =
        (m['descontoValor'] is num)
            ? (m['descontoValor'] as num).toDouble()
            : _descontoValor;
    _descontoPercent =
        (m['descontoPercent'] is num)
            ? (m['descontoPercent'] as num).toDouble()
            : _descontoPercent;

    _taxaEntrega =
        (m['taxaEntrega'] is num)
            ? (m['taxaEntrega'] as num).toDouble()
            : _taxaEntrega;
    _outrasTaxas =
        (m['outrasTaxas'] is num)
            ? (m['outrasTaxas'] as num).toDouble()
            : _outrasTaxas;

    // Garantia
    _garantiaCtrl.text = (m['garantiaTexto'] as String?) ?? _garantiaCtrl.text;
    final gu = (m['garantiaUnidade'] as String?);
    final gp =
        (m['garantiaPeriodo'] is num)
            ? (m['garantiaPeriodo'] as num).toInt()
            : null;
    if (gu != null && gp != null) {
      GarantiaUnidade unidade = GarantiaUnidade.dias;
      if (gu == 'meses') unidade = GarantiaUnidade.meses;
      if (gu == 'anos') unidade = GarantiaUnidade.anos;
      _garantiaCfg = GarantiaConfig(
        unidade: unidade,
        periodo: gp,
        condicoesTexto: _garantiaCtrl.text,
      );
    }

    // Meios de pagamento
    final lst = (m['meiosPagamento'] as List?)?.cast<String>() ?? const [];
    _meiosSelecionados = [
      for (final s in lst) ...MetodoPagamento.values.where((e) => e.name == s),
    ];

    _meiosPagCtrl.text = _resumoMeiosPagamento();

    // Textos
    final infoAdic =
        (m['infoAdicionais'] as String?) ?? (m['info_adicional'] as String?);
    if (infoAdic != null && infoAdic.trim().isNotEmpty) {
      _infoAdicCtrl.text = infoAdic;
    }
    final claus =
        (m['clausulasContratuais'] as String?) ??
        (m['clausula_contratual'] as String?);
    if (claus != null && claus.trim().isNotEmpty) _clausulasCtrl.text = claus;
  }

  PagamentoConfig? _pagamentoCfg; // null = não configurado ainda
  EntregaPedidoConfig? _entregaCfg;

  String _resumoPagamento() {
    if (_pagamentoCfg == null) return 'não configurado';
    final d = _pagamentoCfg!;
    String data =
        '${d.dataPrimeiroPgto.day.toString().padLeft(2, '0')}/${d.dataPrimeiroPgto.month.toString().padLeft(2, '0')}/${d.dataPrimeiroPgto.year}';
    if (!d.parcelado) return 'à vista em $data';
    return '${d.numeroParcelas} parcelas • 1º venc.: $data';
  }

  // ------------ helpers de número/pt-BR ------------
  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  // ------------ totais ------------
  double get _subtotalServicos => _servicos.fold(0.0, (a, b) => a + b.total);
  double get _subtotalProdutos => _produtos.fold(0.0, (a, b) => a + b.total);
  double get _subtotal => _subtotalServicos + _subtotalProdutos;
  double get _custoTotalServicos =>
      _servicos.fold(0.0, (a, b) => a + b.subtotalCusto);

  double get _custoTotalProdutos =>
      _produtos.fold(0.0, (a, b) => a + b.subtotalCusto);

  double get _custoTotal => _custoTotalServicos + _custoTotalProdutos;

  double get _lucroBruto => _subtotal - _custoTotal;

  double get _lucroLiquido =>
      (_lucroBruto - _descontoAplicado - _taxaEntrega - _outrasTaxas);

  double get _margemLucro =>
      _subtotal <= 0 ? 0.0 : (_lucroLiquido / _subtotal) * 100.0;

  double get _descontoAplicado {
    if (_subtotal <= 0) return 0.0;
    if (_descontoTipo == DescontoTipo.valor) {
      return _descontoValor.clamp(0.0, _subtotal);
    } else {
      final perc =
          (_descontoPercent.isNaN || _descontoPercent.isInfinite)
              ? 0.0
              : _descontoPercent;
      return (_subtotal * (perc / 100.0)).clamp(0.0, _subtotal);
    }
  }

  double get _total =>
      (_subtotal - _descontoAplicado + _taxaEntrega + _outrasTaxas).clamp(
        0.0,
        double.infinity,
      );

  // ===== checagem de estoque antes de salvar =====
  Future<bool> _checarEstoqueProdutosAntesDeSalvar() async {
    // Se não houver produtos no pedido, tudo ok
    if (_produtos.isEmpty) return true;

    final List<_Excedente> excedentes = [];

    // Busca dos docs de produto em paralelo para acelerar
    final futures = <Future<void>>[];
    for (final item in _produtos) {
      futures.add(() async {
        final String? produtoId = item.refId; // id do doc em 'produtos'
        if (produtoId == null || produtoId.isEmpty)
          return; // não há como checar

        try {
          final snap = await _fs.collection('produtos').doc(produtoId).get();
          if (!snap.exists) return;

          final m = snap.data() as Map<String, dynamic>;
          final bool controla = m['controlaEstoque'] == true;
          if (!controla) return;

          // Ajuste o nome do campo de estoque conforme seu schema
          final double estoqueAtual =
              (m['estoque'] is num) ? (m['estoque'] as num).toDouble() : 0.0;

          final double qtdSolic = item.quantidade;

          if (qtdSolic > estoqueAtual) {
            final nome =
                (item.nome.isNotEmpty)
                    ? item.nome
                    : (m['nome'] ?? 'Produto').toString();
            excedentes.add(_Excedente(nome, qtdSolic, estoqueAtual));
          }
        } catch (_) {
          // silencioso
        }
      }());
    }

    await Future.wait(futures);

    if (excedentes.isEmpty) return true; // ✅ ninguém excedeu

    if (!mounted) return false;
    final continuar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final unico = excedentes.length == 1;
        final titulo =
            unico
                ? 'Quantidade maior que o estoque'
                : 'Itens com quantidade maior que o estoque';
        final msgTopo =
            unico
                ? 'Quantidade solicitada do produto ${excedentes.first.nome} maior que o estoque atual, deseja continuar?'
                : 'Os itens abaixo estão com quantidade solicitada maior que o estoque atual. Deseja continuar?';

        return AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msgTopo),
                const SizedBox(height: 12),
                if (!unico)
                  ...excedentes.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${e.nome}: solicitada ${_fmtNum(e.quantidadeSolicitada)} × estoque ${_fmtNum(e.estoqueAtual)}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar e corrigir'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );

    return continuar == true;
  }

  String _fmtNum(num v) {
    final s = v.toStringAsFixed((v % 1 == 0) ? 0 : 2);
    return s.replaceAll('.', ',');
  }

  Future<void> _syncAgenda(String pedidoId) async {
    // use SEMPRE o mesmo userId para consultar e salvar (escopo)
    final scope = _scopeUserId ?? _auth.currentUser?.uid;
    if (scope == null) return;

    // 1) procura agenda existente para este pedido dentro do escopo
    final q =
        await _fs
            .collection('agenda')
            .where('userId', isEqualTo: scope)
            .where('pedidoId', isEqualTo: pedidoId)
            .limit(1)
            .get();

    // 2) se não há compromisso no formulário, apaga (se existir)
    if (_compromisso == null) {
      if (q.docs.isNotEmpty) {
        await _fs.collection('agenda').doc(q.docs.first.id).delete();
      }
      return;
    }

    // 3) monta payload da agenda
    final payload = <String, dynamic>{
      'userId': scope,
      'pedidoId': pedidoId,
      'clienteId': _clienteId,
      'clienteNome': _clienteCtrl.text.trim(),
      'numero': _numero,
      'ano': _ano,
      'compromisso': Timestamp.fromDate(_compromisso!),
      'compromissoTexto':
          _compromissoTextoCtrl.text.trim().isEmpty
              ? null
              : _compromissoTextoCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 4) cria ou atualiza
    if (q.docs.isEmpty) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await _fs.collection('agenda').add(payload);
    } else {
      await _fs.collection('agenda').doc(q.docs.first.id).update(payload);
    }
  }

  Future<void> _carregarPedido() async {
    setState(() => _carregando = true);

    try {
      final doc = await _fs.collection('pedidos').doc(widget.pedidoId).get();
      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pedido não encontrado.')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final m = doc.data() as Map<String, dynamic>;

      // Campos simples
      _numero = (m['numero'] as num?)?.toInt() ?? _numero;
      _ano = (m['ano'] as num?)?.toInt() ?? _ano;

      final tsData = m['data'];
      if (tsData is Timestamp) {
        _data = DateTime(
          tsData.toDate().year,
          tsData.toDate().month,
          tsData.toDate().day,
        );
      }

      _clienteId = (m['clienteId'] as String?);
      _clienteCtrl.text =
          (m['clienteNome'] as String?) ?? (m['cliente'] as String? ?? '');
      _refCtrl.text = (m['referencia'] as String?) ?? '';

      // Itens
      _servicos
        ..clear()
        ..addAll(
          ((m['itensServicos'] as List?) ?? []).map((e) {
            final x = Map<String, dynamic>.from(e as Map);
            return _LinhaItem(
              refId: x['refId'] as String?,
              nome: (x['nome'] ?? '').toString(),
              unidade: (x['unidade'] ?? 'UN').toString(),
              quantidade:
                  (x['quantidade'] is num)
                      ? (x['quantidade'] as num).toDouble()
                      : double.tryParse('${x['quantidade']}') ?? 0.0,
              valorUnitario:
                  (x['valorUnitario'] is num)
                      ? (x['valorUnitario'] as num).toDouble()
                      : double.tryParse('${x['valorUnitario']}') ?? 0.0,

              custoUnitario:
                  (x['custoUnitario'] is num)
                      ? (x['custoUnitario'] as num).toDouble()
                      : double.tryParse('${x['custoUnitario']}') ?? 0.0,
            );
          }),
        );

      _produtos
        ..clear()
        ..addAll(
          ((m['itensProdutos'] as List?) ?? []).map((e) {
            final x = Map<String, dynamic>.from(e as Map);
            return _LinhaItem(
              refId: x['refId'] as String?,
              nome: (x['nome'] ?? '').toString(),
              unidade: (x['unidade'] ?? 'UN').toString(),
              quantidade:
                  (x['quantidade'] is num)
                      ? (x['quantidade'] as num).toDouble()
                      : double.tryParse('${x['quantidade']}') ?? 0.0,
              valorUnitario:
                  (x['valorUnitario'] is num)
                      ? (x['valorUnitario'] as num).toDouble()
                      : double.tryParse('${x['valorUnitario']}') ?? 0.0,

              custoUnitario:
                  (x['custoUnitario'] is num)
                      ? (x['custoUnitario'] as num).toDouble()
                      : double.tryParse('${x['custoUnitario']}') ?? 0.0,
            );
          }),
        );

      // Descontos/Taxas
      final tipo = (m['descontoTipo'] as String?) ?? 'valor';
      _descontoTipo =
          (tipo == 'percentual') ? DescontoTipo.percentual : DescontoTipo.valor;
      _descontoValor =
          (m['descontoValor'] is num)
              ? (m['descontoValor'] as num).toDouble()
              : 0.0;
      _descontoPercent =
          (m['descontoPercent'] is num)
              ? (m['descontoPercent'] as num).toDouble()
              : 0.0;

      _taxaEntrega =
          (m['taxaEntrega'] is num)
              ? (m['taxaEntrega'] as num).toDouble()
              : 0.0;
      _outrasTaxas =
          (m['outrasTaxas'] is num)
              ? (m['outrasTaxas'] as num).toDouble()
              : 0.0;

      // Garantia
      _garantiaCtrl.text = (m['garantiaTexto'] as String?) ?? '';

      _infoAdicCtrl.text =
          (m['infoAdicionais'] as String?) ??
          (m['info_adicional'] as String?) ??
          '';

      _clausulasCtrl.text =
          (m['clausulasContratuais'] as String?) ??
          (m['clausula_contratual'] as String?) ??
          '';

      _anotacoesCtrl.text = (m['anotacoes'] as String?) ?? '';
      _relatorioCtrl.text = (m['relatorio'] as String?) ?? '';

      final gu = (m['garantiaUnidade'] as String?);
      final gp =
          (m['garantiaPeriodo'] is num)
              ? (m['garantiaPeriodo'] as num).toInt()
              : null;
      if (gu != null && gp != null) {
        GarantiaUnidade unidade = GarantiaUnidade.dias;
        if (gu == 'meses') unidade = GarantiaUnidade.meses;
        if (gu == 'anos') unidade = GarantiaUnidade.anos;
        _garantiaCfg = GarantiaConfig(
          unidade: unidade,
          periodo: gp,
          condicoesTexto: _garantiaCtrl.text,
        );
      }

      // Meios de pagamento
      final lst = (m['meiosPagamento'] as List?)?.cast<String>() ?? const [];
      _meiosSelecionados = [
        for (final s in lst)
          ...MetodoPagamento.values.where((e) => e.name == s),
      ];

      _meiosPagCtrl.text = _resumoMeiosPagamento();

      // carregar configuração de pagamento vinculada (por ESCOPO)
      await _carregarPagamentoDoc(widget.pedidoId!);
      await _carregarPedidoEntrega(widget.pedidoId!);
      await _carregarCompromissoAgenda(widget.pedidoId!);

      _inicializado = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
    _produtosOriginais = _mapearQuantidadesPorProduto(_produtos);
  }

  Future<void> _aplicarMovimentoEstoqueAposSalvar(String pedidoId) async {
    final atuais = _mapearQuantidadesPorProduto(_produtos);

    // diferença = atuais - originais
    final deltas = <String, double>{}..addAll(atuais);
    for (final e in _produtosOriginais.entries) {
      deltas[e.key] = (deltas[e.key] ?? 0) - e.value;
    }
    if (deltas.values.every((v) => v == 0)) return;

    final ids = deltas.keys.where((k) => k.isNotEmpty).toList();
    if (ids.isEmpty) return;

    final snaps = await Future.wait(
      ids.map((id) => _fs.collection('produtos').doc(id).get()),
    );

    final batch = _fs.batch();

    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final delta = deltas[id] ?? 0;
      if (delta == 0) continue;

      final snap = snaps[i];
      if (!snap.exists) continue;

      final m = snap.data() as Map<String, dynamic>;
      final controla = m['controlaEstoque'] == true;
      if (!controla) continue;

      // campo "estoque"
      final ref = _fs.collection('produtos').doc(id);
      // delta > 0  => baixar (saída)
      // delta < 0  => devolver (entrada)
      batch.update(ref, {'estoque': FieldValue.increment(-delta)});

      // (opcional) log do movimento
      final movRef = _fs.collection('movimento_estoque').doc();
      batch.set(movRef, {
        'userId': _uid, // grava escopo do autor
        'companyId': _scopeUserId,
        'pedidoId': pedidoId,
        'produtoId': id,
        'quantidade': -delta, // negativo=saída; positivo=entrada
        'tipo': 'ajuste_pedido',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // atualiza snapshot para próximas edições
    _produtosOriginais = atuais;
  }

  Future<void> _preencherTextosPadroes() async {
    final scope = _scopeUserId;
    if (scope == null) return;

    try {
      Map<String, dynamic>? data;

      // tenta doc com id = scope (company ou uid)
      final byId = await _fs.collection('textos_padroes').doc(scope).get();
      if (byId.exists) {
        data = byId.data() as Map<String, dynamic>?;
      } else {
        // fallback por userId == scope
        final q =
            await _fs
                .collection('textos_padroes')
                .where('userId', isEqualTo: scope)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) {
          data = q.docs.first.data() as Map<String, dynamic>;
        }
      }

      if (data == null) return;

      final infoAdic = (data['info_adicional'] ?? '').toString();
      final clausulas = (data['clausula_contratual'] ?? '').toString();

      if (mounted) {
        if (_infoAdicCtrl.text.trim().isEmpty && infoAdic.isNotEmpty) {
          setState(() => _infoAdicCtrl.text = infoAdic);
        }
        if (_clausulasCtrl.text.trim().isEmpty && clausulas.isNotEmpty) {
          setState(() => _clausulasCtrl.text = clausulas);
        }
      }
    } catch (e) {
      debugPrint('Não foi possível carregar textos_padroes: $e');
    }
  }

  Future<void> _carregarPedidoEntrega(String pedidoId) async {
    try {
      if (_scopeUserId == null) return;

      final isCompany = _companyId != null && _companyId!.isNotEmpty;
      final scope = _scopeUserId!;
      final docId = '${isCompany ? 'C' : 'U'}:$scope::P:$pedidoId';

      final snap = await _fs.collection('pedido_entrega').doc(docId).get();

      if (!snap.exists) return;

      final m = snap.data() ?? {};

      TipoEntregaPedido tipo = TipoEntregaPedido.semEntrega;
      final tipoEntrega = (m['tipoEntrega'] ?? '').toString();

      if (tipoEntrega == 'data_unica') {
        tipo = TipoEntregaPedido.dataUnica;
      } else if (tipoEntrega == 'programada') {
        tipo = TipoEntregaPedido.programada;
      }

      final dataUnicaTs = m['dataUnica'];

      final entregasMap = (m['entregas'] as List?) ?? [];

      final entregas =
          entregasMap.map((e) {
            final entrega = Map<String, dynamic>.from(e as Map);

            final dataEntregaTs = entrega['dataEntrega'];

            final itensMap = (entrega['itens'] as List?) ?? [];

            final itens =
                itensMap.map((i) {
                  final item = Map<String, dynamic>.from(i as Map);

                  return EntregaPedidoItem(
                    refId: item['refId']?.toString(),
                    tipo: item['tipo']?.toString() ?? 'produto',
                    nome: item['nome']?.toString() ?? '',
                    unidade: item['unidade']?.toString() ?? 'UN',
                    quantidadePedido:
                        (item['quantidadePedido'] as num?)?.toDouble() ?? 0,
                    quantidadeEntrega:
                        (item['quantidadeEntrega'] as num?)?.toDouble() ?? 0,
                  );
                }).toList();

            return EntregaProgramada(
              dataEntrega:
                  dataEntregaTs is Timestamp
                      ? dataEntregaTs.toDate()
                      : DateTime.now(),
              observacao: entrega['observacao']?.toString(),
              itens: itens,
            );
          }).toList();

      setState(() {
        _entregaCfg = EntregaPedidoConfig(
          tipoEntrega: tipo,
          dataUnica: dataUnicaTs is Timestamp ? dataUnicaTs.toDate() : null,
          observacao: m['observacao']?.toString(),
          entregas: entregas,
        );
      });
    } catch (e) {
      debugPrint('Erro ao carregar entrega do pedido: $e');
    }
  }

  Future<void> _carregarPagamentoDoc(String pedidoId) async {
    try {
      // 1) primeiro tenta pelo ESCOPO correto (companyId == _scopeUserId)
      var q =
          await _fs
              .collection('pedido_pagamento')
              .where('companyId', isEqualTo: _scopeUserId) // <<< ESCOP0 CORRETO
              .where('pedidoId', isEqualTo: pedidoId)
              .limit(1)
              .get();

      // 2) fallback opcional para registros antigos (se houver)
      if (q.docs.isEmpty) {
        q =
            await _fs
                .collection('pedido_pagamento')
                .where('userId', isEqualTo: _uid) // autor como legado
                .where('pedidoId', isEqualTo: pedidoId)
                .limit(1)
                .get();
      }

      if (q.docs.isEmpty) return;

      final m = q.docs.first.data();
      final bool parcelado = (m['tipo'] == 'parcelado');
      final int nParcelas =
          (m['numeroParcelas'] as num?)?.toInt() ?? (parcelado ? 2 : 1);
      final ts = m['dataPrimeiroPagamento'];
      final dt1 = ts is Timestamp ? ts.toDate() : DateTime.now();

      setState(() {
        _pagamentoCfg = PagamentoConfig(
          parcelado: parcelado,
          numeroParcelas: parcelado ? nParcelas : 1,
          dataPrimeiroPgto: dt1,
        );
        _parcelas = parcelado ? nParcelas : 1;
      });
    } catch (_) {
      /* silencioso */
    }
  }

  // =========== NUMERAÇÃO ÚNICA (numero + ano por ESCOPO) ===========
  Future<void> _initNumeroAuto() async {
    if (widget.pedidoId != null) return; // em edição, mantém o existente
    try {
      final q =
          await _pedidosPorEscopoEAno(
            _ano,
          ).orderBy('numero', descending: true).limit(1).get();

      final proximo =
          q.docs.isEmpty
              ? 1
              : ((q.docs.first.data()['numero'] as num?)?.toInt() ?? 0) + 1;

      if (mounted) setState(() => _numero = proximo);
    } catch (e) {
      debugPrint('⚠️ Falha ao sugerir próximo número: $e');
    }
  }

  Future<bool> _numeroExiste(int numero, int ano, {String? ignoreId}) async {
    final q =
        await _pedidosPorEscopoEAno(
          ano,
        ).where('numero', isEqualTo: numero).limit(1).get();

    if (q.docs.isEmpty) return false;
    if (ignoreId != null && q.docs.first.id == ignoreId) return false;
    return true;
  }

  Future<int> _proximoNumeroLivre(int ano) async {
    final q =
        await _pedidosPorEscopoEAno(
          ano,
        ).orderBy('numero', descending: true).limit(1).get();

    final maxNum =
        q.docs.isEmpty
            ? 0
            : ((q.docs.first.data()['numero'] as num?)?.toInt() ?? 0);
    final sugestao = maxNum + 1;

    if (!await _numeroExiste(_numero, ano, ignoreId: widget.pedidoId)) {
      return _numero;
    }
    return sugestao;
  }

  // ===== índice para lock atômico =====
  String _pedidoIndexKey({
    required String scope,
    required int ano,
    required int numero,
  }) {
    // Escopo fica explícito no id para ser único por empresa/usuário
    final n6 = numero.toString().padLeft(6, '0');
    final s = _isCompanyScope ? 'C:$scope' : 'U:$scope';
    return '$s::$ano::$n6';
  }

  Future<void> _configurarEntregaPedido() async {
    if (_produtos.isEmpty && _servicos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adicione produtos ou serviços antes de configurar a entrega.',
          ),
        ),
      );
      return;
    }

    final cfg = await Navigator.push<EntregaPedidoConfig>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ConfigurarEntregaPedidoScreen(
              initial: _entregaCfg,
              itensPedido: _itensParaEntrega(),
            ),
        fullscreenDialog: true,
      ),
    );

    if (cfg != null) {
      setState(() {
        _entregaCfg = cfg;
      });
    }
  }

  Future<void> _configurarPagamento() async {
    final cfg = await Navigator.push<PagamentoConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => ConfigurarPagamentoScreen(initial: _pagamentoCfg),
        fullscreenDialog: true,
      ),
    );

    if (cfg != null) {
      setState(() {
        _pagamentoCfg = cfg;
        _parcelas = cfg.parcelado ? cfg.numeroParcelas : 1;
      });
    }
  }

  Future<void> _validarNumeroEAlertar() async {
    if (!await _numeroExiste(_numero, _ano, ignoreId: widget.pedidoId)) {
      return; // está livre
    }
    final sugestao = await _proximoNumeroLivre(_ano);
    if (!mounted) return;

    final usar = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Número já utilizado'),
            content: Text(
              'O número ${_numero.toString().padLeft(3, '0')} para o ano $_ano já existe.\n\n'
              'Sugerido: ${sugestao.toString().padLeft(3, '0')}-${_ano}. Deseja usar a sugestão?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Usar sugestão'),
              ),
            ],
          ),
    );

    if (usar == true) {
      setState(() => _numero = sugestao);
    }
  }

  // ------------ salvar ------------

  Future<void> _upsertPedidoEntrega(String pedidoId) async {
    if (_scopeUserId == null) return;

    final isCompany = _companyId != null && _companyId!.isNotEmpty;
    final scope = _scopeUserId!;
    final docId = '${isCompany ? 'C' : 'U'}:$scope::P:$pedidoId';

    final ref = _fs.collection('pedido_entrega').doc(docId);
    final now = FieldValue.serverTimestamp();

    if (_entregaCfg == null) {
      await ref.set({
        'userId': _uid,
        'createdByUid': _uid,
        'companyId': _scopeUserId,
        'pedidoId': pedidoId,
        'tipoEntrega': 'sem_entrega',
        'tipoEntregaLabel': 'Sem entrega configurada',
        'dataUnica': null,
        'observacao': null,
        'entregas': [],
        'updatedAt': now,
      }, SetOptions(merge: true));
      return;
    }

    final cfg = _entregaCfg!;

    final payload = <String, dynamic>{
      'userId': _uid,
      'createdByUid': _uid,
      'companyId': _scopeUserId,
      'pedidoId': pedidoId,
      'tipoEntrega': tipoEntregaKey(cfg.tipoEntrega),
      'tipoEntregaLabel': tipoEntregaLabel(cfg.tipoEntrega),
      'dataUnica':
          cfg.dataUnica == null
              ? null
              : Timestamp.fromDate(
                DateTime(
                  cfg.dataUnica!.year,
                  cfg.dataUnica!.month,
                  cfg.dataUnica!.day,
                ),
              ),
      'observacao': cfg.observacao,
      'entregas':
          cfg.entregas.map((entrega) {
            return {
              'dataEntrega': Timestamp.fromDate(
                DateTime(
                  entrega.dataEntrega.year,
                  entrega.dataEntrega.month,
                  entrega.dataEntrega.day,
                ),
              ),
              'observacao': entrega.observacao,
              'itens':
                  entrega.itens.map((item) {
                    return {
                      'refId': item.refId,
                      'tipo': item.tipo,
                      'nome': item.nome,
                      'unidade': item.unidade,
                      'quantidadePedido': item.quantidadePedido,
                      'quantidadeEntrega': item.quantidadeEntrega,
                    };
                  }).toList(),
            };
          }).toList(),
      'updatedAt': now,
    };

    final snap = await ref.get();

    if (snap.exists) {
      await ref.set(payload, SetOptions(merge: true));
    } else {
      await ref.set({...payload, 'createdAt': now});
    }
  }

  Future<void> _upsertPedidoPagamento(String pedidoId) async {
    if (_scopeUserId == null || _pagamentoCfg == null) return;

    final cfg = _pagamentoCfg!;
    final isCompany = _companyId != null && _companyId!.isNotEmpty;
    final scope = _scopeUserId!; // companyId ou uid
    final docId = '${isCompany ? 'C' : 'U'}:$scope::P:$pedidoId';

    final ref = _fs.collection('pedido_pagamento').doc(docId);

    final now = FieldValue.serverTimestamp();
    final base = <String, dynamic>{
      'userId': _uid,
      'createdByUid': _uid,
      'companyId': _scopeUserId,
      'pedidoId': pedidoId,
      'tipo': cfg.parcelado ? 'parcelado' : 'avista',
      'numeroParcelas': cfg.parcelado ? cfg.numeroParcelas : 1,
      'dataPrimeiroPagamento': Timestamp.fromDate(
        DateTime(
          cfg.dataPrimeiroPgto.year,
          cfg.dataPrimeiroPgto.month,
          cfg.dataPrimeiroPgto.day,
        ),
      ),
      'totalPedido': _total,
      'updatedAt': now,
    };

    final snap = await ref.get();
    if (snap.exists) {
      await ref.set(base, SetOptions(merge: true)); // update/merge
    } else {
      await ref.set({...base, 'createdAt': now});
    }
  }

  String _humanizeError(Object e) {
    if (e is FirebaseException) {
      final code = e.code.isNotEmpty ? ' (${e.code})' : '';
      return (e.message ?? 'Falha Firebase') + code;
    }
    if (e is PlatformException) {
      final code = e.code.isNotEmpty ? ' (${e.code})' : '';
      return (e.message ?? 'Falha de plataforma') + code;
    }
    if (e is StateError && e.message == 'DUP_NUM') {
      return 'Número do pedido já está em uso.';
    }
    return e.toString();
  }

  void _logSalvarError(String tag, Object error, StackTrace stack) {
    debugPrint('[$tag] erro: $error');
    debugPrint('[$tag] stack:\n$stack');
  }

  /// Alguns plugins empacotam o erro em um objeto com .error e .stack.
  /// Este helper tenta desempacotar para recuperar a causa real.
  (Object, StackTrace?) _unwrapConvertedFutureError(Object e) {
    try {
      final d = e as dynamic;
      final inner = d.error;
      final st = d.stack;
      if (inner != null) {
        final stack = st is StackTrace ? st : StackTrace.fromString('$st');
        return (inner as Object, stack);
      }
    } catch (_) {}
    return (e, null);
  }

  Future<void> _salvar() async {
    if (_scopeUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível determinar o escopo (empresa/usuário).',
          ),
        ),
      );
      return;
    }
    if (_clienteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe o cliente.')));
      return;
    }
    if (_pagamentoCfg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Defina a condição de pagamento do pedido.'),
        ),
      );
      return;
    }
    if (_servicos.isEmpty && _produtos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um produto ou serviço ao pedido.'),
        ),
      );
      return;
    }

    // checar estoque
    final estoqueOk = await _checarEstoqueProdutosAntesDeSalvar();
    if (!estoqueOk) return;

    // validação otimista
    final existe = await _numeroExiste(
      _numero,
      _ano,
      ignoreId: widget.pedidoId,
    );
    if (existe) {
      final sugestao = await _proximoNumeroLivre(_ano);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Número ${_numero.toString().padLeft(3, '0')}-$_ano já existe. '
            'Sugerido: ${sugestao.toString().padLeft(3, '0')}-$_ano.',
          ),
          action: SnackBarAction(
            label: 'Usar sugestão',
            onPressed: () => setState(() => _numero = sugestao),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() => _salvando = true);

    try {
      final nowServer = FieldValue.serverTimestamp();

      final base = <String, dynamic>{
        'userId': _uid,
        'numero': _numero,
        'ano': _ano,
        'data': Timestamp.fromDate(
          DateTime(_data.year, _data.month, _data.day),
        ),
        'clausulasContratuais':
            _clausulasCtrl.text.trim().isEmpty
                ? null
                : _clausulasCtrl.text.trim(),
        'cliente': _clienteCtrl.text.trim(),
        'referencia':
            _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'infoAdicionais':
            _infoAdicCtrl.text.trim().isEmpty
                ? null
                : _infoAdicCtrl.text.trim(),
        'anotacoes':
            _anotacoesCtrl.text.trim().isEmpty
                ? null
                : _anotacoesCtrl.text.trim(),
        'relatorio':
            _relatorioCtrl.text.trim().isEmpty
                ? null
                : _relatorioCtrl.text.trim(),
        'itensServicos': _servicos.map((e) => e.toMap()).toList(),
        'itensProdutos': _produtos.map((e) => e.toMap()).toList(),
        'descontoTipo':
            _descontoTipo == DescontoTipo.valor ? 'valor' : 'percentual',
        'descontoValor': _descontoValor,
        'descontoPercent': _descontoPercent,
        'descontoAplicado': _descontoAplicado,
        'taxaEntrega': _taxaEntrega,
        'outrasTaxas': _outrasTaxas,
        'subtotalServicos': _subtotalServicos,
        'subtotalProdutos': _subtotalProdutos,
        'subtotal': _subtotal,
        'custoTotalServicos': _custoTotalServicos,
        'custoTotalProdutos': _custoTotalProdutos,
        'custoTotal': _custoTotal,
        'lucroBruto': _lucroBruto,
        'lucroLiquido': _lucroLiquido,
        'margemLucro': _margemLucro,
        'total': _total,
        'clienteId': _clienteId,
        'clienteNome': _clienteCtrl.text,
        'garantiaUnidade':
            _garantiaCfg == null
                ? null
                : (_garantiaCfg!.unidade == GarantiaUnidade.dias
                    ? 'dias'
                    : _garantiaCfg!.unidade == GarantiaUnidade.meses
                    ? 'meses'
                    : 'anos'),
        'garantiaPeriodo': _garantiaCfg?.periodo,
        'garantiaTexto':
            _garantiaCtrl.text.trim().isEmpty
                ? null
                : _garantiaCtrl.text.trim(),
        'meiosPagamento': _meiosSelecionados.map((m) => m.name).toList(),
        'meiosPagamentoRotulo':
            _meiosSelecionados.isEmpty
                ? null
                : _meiosSelecionados.map((m) => m.label ?? m.name).join(', '),
        'updatedAt': nowServer,
      };

      late String savedPedidoId;

      if (widget.pedidoId == null) {
        // criação
        final (ownerId, companyId) = await _resolveOwnerAndCompany();
        if (ownerId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sem permissão para cadastrar: verifique seu perfil/empresa.',
                ),
              ),
            );
          }
          setState(() => _salvando = false);
          return;
        }

        final scope = _scopeValue; // companyId ou uid
        final idxId = _pedidoIndexKey(scope: scope, ano: _ano, numero: _numero);
        final idxRef = _fs.collection('pedidos_index').doc(idxId);

        bool dupNum = false;

        await _fs.runTransaction((tx) async {
          // 1) índice único
          final idxSnap = await tx.get(idxRef);
          if (idxSnap.exists) {
            // NÃO lance exceção aqui — apenas marque e finalize a transação sem writes
            dupNum = true;
            return;
          }

          // 2) cria o pedido
          final pedidoRef = _fs.collection('pedidos').doc();

          // 3) grava o índice
          tx.set(idxRef, {
            'pedidoId': pedidoRef.id,
            'scope': scope,
            'ano': _ano,
            'numero': _numero,
            'createdAt': nowServer,
          });

          // 4) grava o pedido
          final payload = {
            ...base,
            'ownerId': ownerId,
            'companyId': companyId,
            'createdByUid': _uid,
            'createdAt': nowServer,
            'status': 'Pendente',
            'statusLabel': 'Pendente',
          };

          tx.set(pedidoRef, payload);
          savedPedidoId = pedidoRef.id;
        });

        if (dupNum) {
          final sugestao = await _proximoNumeroLivre(_ano);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Número ${_numero.toString().padLeft(3, '0')}-$_ano já está em uso. '
                'Sugerido: ${sugestao.toString().padLeft(3, '0')}-$_ano.',
              ),
              action: SnackBarAction(
                label: 'Usar sugestão',
                onPressed: () => setState(() => _numero = sugestao),
              ),
            ),
          );
          setState(() => _salvando = false);
          return;
        }
      } else {
        // edição
        final dup = await _numeroExiste(
          _numero,
          _ano,
          ignoreId: widget.pedidoId,
        );
        if (dup) {
          final sugestao = await _proximoNumeroLivre(_ano);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Número ${_numero.toString().padLeft(3, '0')}-$_ano já existe. '
                  'Sugerido: ${sugestao.toString().padLeft(3, '0')}-$_ano.',
                ),
                action: SnackBarAction(
                  label: 'Usar sugestão',
                  onPressed: () => setState(() => _numero = sugestao),
                ),
              ),
            );
          }
          setState(() => _salvando = false);
          return;
        }

        await _fs.collection('pedidos').doc(widget.pedidoId!).update(base);
        savedPedidoId = widget.pedidoId!;
      }

      // Dispara conversão somente em CRIAÇÃO (inclui duplicação, pois cria novo pedido)
      if (widget.pedidoId == null) {
        final itensCount = _servicos.length + _produtos.length;

        await _logCreateOrder(
          pedidoId: savedPedidoId,
          total: _total,
          itensCount: itensCount,
          isEdicao: false,
          isDuplicate: widget.isDuplicate,
        );
      }

      // pós-salvar
      await _aplicarMovimentoEstoqueAposSalvar(savedPedidoId);
      await _upsertPedidoPagamento(savedPedidoId);
      await _upsertPedidoEntrega(savedPedidoId);
      await _syncAgenda(savedPedidoId);

      // 1) status
      final savedStatus = await Navigator.push<PedidoStatus>(
        context,
        MaterialPageRoute(
          builder:
              (_) => SelecionarStatusPedidoScreen(
                pedidoId: savedPedidoId,
                initial: PedidoStatus.pendente,
              ),
          fullscreenDialog: true,
        ),
      );

      // 2) recebíveis
      if (!mounted) return;
      final gerou = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder:
              (_) => ContasReceberPreviewScreen(
                pedidoId: savedPedidoId,
                totalPedido: _total,
                pagamento: _pagamentoCfg!, // já validado
                clienteNome: _clienteCtrl.text,
                numero: _numero,
                ano: _ano,
              ),
          fullscreenDialog: true,
        ),
      );

      // 3) feedback
      // 3) após finalizar todas as etapas do cadastro (status + recebíveis),
      // registra um evento positivo e tenta pedir review (com frequência controlada)
      if (mounted) {
        // Você pode escolher pedir SOMENTE se gerou recebíveis:
        // if (gerou == true) { ... }
        // Eu recomendo pedir quando o usuário completou o fluxo inteiro,
        // independentemente de ter gerado recebíveis.
        await _reviewService.registerPositiveEvent();
        await _reviewService.maybeAskForReview(context);

        final label =
            savedStatus == null ? 'sem alteração' : statusLabel(savedStatus);
        final msg =
            gerou == true
                ? 'Pedido salvo • Status: $label • Recebíveis gerados'
                : 'Pedido salvo • Status: $label';

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, true);
      }
    } on FirebaseException catch (e, st) {
      _logSalvarError('_salvar/FirebaseException', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar (Firebase): ${e.message ?? e.code}'),
          ),
        );
      }
    } catch (e, st) {
      // Desempacota "converted Future"
      final (inner, innerSt) = _unwrapConvertedFutureError(e);
      final useSt = innerSt ?? st;

      _logSalvarError('_salvar/Exception', inner, useSt);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $inner')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ------------ UI ------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Text(_isEdicao ? 'Editar pedido' : 'Novo pedido'),
        actions: [
          IconButton(
            tooltip: 'Editar número',
            icon: const Icon(Icons.edit_outlined),
            onPressed: (_salvando || _carregando) ? null : _editarNumero,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: (_salvando || _carregando) ? null : _salvar,
            child:
                _salvando
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(_isEdicao ? 'atualizar pedido' : 'salvar pedido'),
          ),
        ),
      ),
      body:
          _carregando
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(
                absorbing: _salvando,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    _cabecalho(cs),
                    const SizedBox(height: 16),
                    _campoCliente(cs),
                    const SizedBox(height: 12),
                    _campoReferencia(cs),
                    const SizedBox(height: 20),
                    _secaoCompromissos(cs),
                    const SizedBox(height: 16),
                    _secaoPedido(cs),
                    const SizedBox(height: 20),
                    _resumoTotais(cs),
                    const SizedBox(height: 20),
                    _secaoDetalhes(cs),
                  ],
                ),
              ),
    );
  }

  // ----- widgets -----
  Widget _cabecalho(ColorScheme cs) {
    final dataStr =
        '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedido n. ${_numero.toString().padLeft(3, '0')}-$_ano',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          dataStr,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _campoCliente(ColorScheme cs) {
    return TextFormField(
      controller: _clienteCtrl,
      readOnly: true, // usuário escolhe via sheet
      decoration: InputDecoration(
        labelText: 'cliente',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_clienteCtrl.text.isNotEmpty)
              IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.close),
                onPressed:
                    () => setState(() {
                      _clienteId = null;
                      _clienteCtrl.clear();
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
                  onTap: _selecionarCliente,
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
      onTap: _selecionarCliente,
    );
  }

  Widget _campoReferencia(ColorScheme cs) {
    return TextFormField(
      controller: _refCtrl,
      maxLength: 100,
      decoration: InputDecoration(
        labelText: 'Referência',
        counterText: '${_refCtrl.text.length}/100',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _secaoCompromissos(ColorScheme cs) {
    final obsResumo = _compromissoTextoCtrl.text.trim();

    return _Section(
      title: 'Compromissos',
      trailing: IconButton(
        onPressed:
            () =>
                setState(() => _expandedCompromissos = !_expandedCompromissos),
        icon: Icon(
          _expandedCompromissos ? Icons.expand_less : Icons.expand_more,
        ),
      ),
      child: AnimatedCrossFade(
        crossFadeState:
            _expandedCompromissos
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
        duration: const Duration(milliseconds: 200),
        firstChild: Column(
          children: [
            // Data/hora
            _rowAction(
              icon: Icons.event_available_outlined,
              label:
                  _compromisso == null
                      ? 'Marcar compromisso'
                      : 'Compromisso: ${_compromissoFmt(_compromisso!)}',
              onAdd: _marcarCompromisso,
              trailing:
                  _compromisso == null
                      ? null
                      : IconButton(
                        tooltip: 'Limpar',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _compromisso = null),
                      ),
            ),
            const SizedBox(height: 8),
            // Observação do compromisso
            ListTile(
              leading: Icon(Icons.notes_outlined, color: cs.primary),
              title: const Text(
                'Observação do compromisso',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle:
                  obsResumo.isEmpty
                      ? const Text('toque para adicionar')
                      : Text(
                        obsResumo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (obsResumo.isNotEmpty)
                    IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close),
                      onPressed:
                          () => setState(() => _compromissoTextoCtrl.clear()),
                    ),
                  const SizedBox(width: 4),
                  _botaoAdd(
                    () => _editarTexto(
                      'Observação do compromisso',
                      _compromissoTextoCtrl,
                      maxLines: 5,
                      hint: 'Ex.: Local, instruções, o que levar…',
                    ),
                  ),
                ],
              ),
              onTap:
                  () => _editarTexto(
                    'Observação do compromisso',
                    _compromissoTextoCtrl,
                    maxLines: 5,
                    hint: 'Ex.: Local, instruções, o que levar…',
                  ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        secondChild: const SizedBox.shrink(),
      ),
    );
  }

  Widget _secaoPedido(ColorScheme cs) {
    final descontoLabel =
        _descontoTipo == DescontoTipo.valor
            ? '- ${_fmtMoeda(_descontoAplicado)}'
            : '${_descontoPercent.toStringAsFixed(0)}%  (- ${_fmtMoeda(_descontoAplicado)})';

    return _Section(
      title: 'Pedido',
      child: Column(
        children: [
          _rowAction(
            icon: Icons.fact_check_outlined,
            label: 'Serviços',
            onAdd: _addServico,
            trailing:
                _servicos.isEmpty ? null : Text(_fmtMoeda(_subtotalServicos)),
          ),
          if (_servicos.isNotEmpty) _listaItens(_servicos, true),
          const SizedBox(height: 8),
          _rowAction(
            icon: Icons.shopping_bag_outlined,
            label: 'Produtos',
            onAdd: _addProduto,
            trailing:
                _produtos.isEmpty ? null : Text(_fmtMoeda(_subtotalProdutos)),
          ),
          if (_produtos.isNotEmpty) _listaItens(_produtos, false),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.percent_outlined),
            title: const Text('Desconto'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(descontoLabel),
                const SizedBox(width: 8),
                _botaoAdd(_editarDesconto),
              ],
            ),
            onTap: _editarDesconto,
            contentPadding: EdgeInsets.zero,
          ),
          _rowValor(
            icon: Icons.local_shipping_outlined,
            label: 'Taxa de entrega',
            onTap: _editarTaxaEntrega,
            valor: _taxaEntrega,
          ),
          _rowValor(
            icon: Icons.attach_money_outlined,
            label: 'Outras taxas',
            onTap: _editarOutrasTaxas,
            valor: _outrasTaxas,
          ),
        ],
      ),
    );
  }

  Widget _secaoDetalhes(ColorScheme cs) {
    final clausResumo = _clausulasCtrl.text.trim();
    final infoResumo = _infoAdicCtrl.text.trim();
    final anotResumo = _anotacoesCtrl.text.trim();
    final relResumo = _relatorioCtrl.text.trim();

    Widget _tile({
      required IconData icon,
      required String titulo,
      String? subtitulo,
      VoidCallback? onTap,
      VoidCallback? onAdd,
    }) {
      return ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle:
            (subtitulo == null || subtitulo.isEmpty)
                ? null
                : Text(subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onTap != null) Icon(Icons.chevron_right, color: cs.primary),
            const SizedBox(width: 8),
            _botaoAdd(onAdd ?? onTap ?? () {}),
          ],
        ),
        onTap: onTap,
        contentPadding: EdgeInsets.zero,
      );
    }

    return _Section(
      title: 'Detalhes',
      trailing: IconButton(
        onPressed: () => setState(() => _expDetalhes = !_expDetalhes),
        icon: Icon(_expDetalhes ? Icons.expand_less : Icons.expand_more),
      ),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 200),
        crossFadeState:
            _expDetalhes ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        firstChild: Column(
          children: [
            // Parcelas
            ListTile(
              leading: Icon(Icons.credit_card_outlined, color: cs.primary),
              title: const Text(
                'Condição de Pagamento',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _pagamentoCfg == null
                    ? 'toque para configurar'
                    : '${_parcelas} parcela(s) • ${_resumoPagamento()}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _configurarPagamento,
                  ),
                  _botaoAdd(_configurarPagamento),
                ],
              ),
              onTap: _configurarPagamento,
              contentPadding: EdgeInsets.zero,
            ),

            _tile(
              icon: Icons.local_shipping_outlined,
              titulo: 'Entrega do pedido',
              subtitulo:
                  _entregaCfg == null
                      ? 'toque para configurar'
                      : _entregaCfg!.resumo(),
              onTap: _configurarEntregaPedido,
              onAdd: _configurarEntregaPedido,
            ),

            _tile(
              icon: Icons.payments_outlined,
              titulo: 'Meios de pagamento',
              subtitulo: _resumoMeiosPagamento(),
              onTap: () async {
                final res = await Navigator.push<MeiosPagamentoResult>(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) =>
                            MeiosPagamentoScreen(initial: _meiosSelecionados),
                    fullscreenDialog: true,
                  ),
                );
                if (res != null) {
                  setState(() {
                    _meiosSelecionados = res.selecionados;
                    _meiosPagCtrl.text = res.toStringList().join(', ');
                  });
                }
              },
              onAdd: () async {
                final res = await Navigator.push<MeiosPagamentoResult>(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) =>
                            MeiosPagamentoScreen(initial: _meiosSelecionados),
                    fullscreenDialog: true,
                  ),
                );
                if (res != null) {
                  setState(() {
                    _meiosSelecionados = res.selecionados;
                    _meiosPagCtrl.text = res.toStringList().join(', ');
                  });
                }
              },
            ),

            _tile(
              icon: Icons.verified_outlined,
              titulo: 'Garantia',
              subtitulo:
                  _garantiaCfg == null
                      ? 'toque para configurar'
                      : _garantiaCfg!.resumo(),
              onTap: () async {
                final cfg = await Navigator.push<GarantiaConfig>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GarantiaScreen(initial: _garantiaCfg),
                    fullscreenDialog: true,
                  ),
                );
                if (cfg != null) {
                  setState(() {
                    _garantiaCfg = cfg;
                    _garantiaCtrl.text = cfg.condicoesTexto;
                  });
                }
              },
              onAdd: () async {
                final cfg = await Navigator.push<GarantiaConfig>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GarantiaScreen(initial: _garantiaCfg),
                    fullscreenDialog: true,
                  ),
                );
                if (cfg != null) {
                  setState(() {
                    _garantiaCfg = cfg;
                    _garantiaCtrl.text = cfg.condicoesTexto;
                  });
                }
              },
            ),
            _tile(
              icon: Icons.description_outlined,
              titulo: 'Cláusulas contratuais',
              subtitulo: clausResumo,
              onTap:
                  () => _editarTexto(
                    'Cláusulas contratuais',
                    _clausulasCtrl,
                    maxLines: 8,
                  ),
            ),
            _tile(
              icon: Icons.info_outline,
              titulo: 'Informações adicionais',
              subtitulo: infoResumo,
              onTap:
                  () => _editarTexto(
                    'Informações adicionais',
                    _infoAdicCtrl,
                    maxLines: 6,
                  ),
            ),
            _tile(
              icon: Icons.note_alt_outlined,
              titulo: 'Anotações',
              subtitulo: anotResumo,
              onTap:
                  () => _editarTexto('Anotações', _anotacoesCtrl, maxLines: 6),
            ),
            _tile(
              icon: Icons.assignment_outlined,
              titulo: 'Relatório',
              subtitulo: relResumo,
              onTap:
                  () => _editarTexto('Relatório', _relatorioCtrl, maxLines: 8),
            ),
          ],
        ),
        secondChild: const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _editarParcelas() async {
    final ctrl = TextEditingController(text: _parcelas.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Parcelas'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade de parcelas',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ok'),
              ),
            ],
          ),
    );
    if (ok == true) {
      final n = int.tryParse(ctrl.text) ?? _parcelas;
      setState(() => _parcelas = n.clamp(1, 120));
    }
  }

  Future<void> _editarTexto(
    String titulo,
    TextEditingController controller, {
    int maxLines = 4,
    String? hint,
  }) async {
    final temp = TextEditingController(text: controller.text);
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(titulo),
            content: TextField(
              controller: temp,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
    );
    if (ok == true) setState(() => controller.text = temp.text);
  }

  Widget _resumoTotais(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Resumo do pedido',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _mostrarAnaliseInterna = !_mostrarAnaliseInterna;
                    });
                  },
                  icon: Icon(
                    _mostrarAnaliseInterna
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _mostrarAnaliseInterna
                        ? 'Ocultar análise'
                        : 'Mostrar análise',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            _kv('Subtotal', _fmtMoeda(_subtotal)),
            _kv('Desconto', '- ${_fmtMoeda(_descontoAplicado)}'),
            _kv('Taxa de entrega', _fmtMoeda(_taxaEntrega)),
            _kv('Outras taxas', _fmtMoeda(_outrasTaxas)),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState:
                  _mostrarAnaliseInterna
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
              firstChild: Column(
                children: [
                  const Divider(height: 22),
                  _kv('Custo total', _fmtMoeda(_custoTotal)),
                  _kv('Lucro bruto', _fmtMoeda(_lucroBruto)),
                  _kv('Lucro líquido', _fmtMoeda(_lucroLiquido)),
                  _kv(
                    'Margem',
                    '${_margemLucro.toStringAsFixed(2).replaceAll('.', ',')}%',
                  ),
                ],
              ),
              secondChild: const SizedBox.shrink(),
            ),

            const Divider(),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _fmtMoeda(_total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---- linhas de ação ----
  Widget _rowAction({
    required IconData icon,
    required String label,
    required VoidCallback onAdd,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[trailing, const SizedBox(width: 8)],
          _botaoAdd(onAdd),
        ],
      ),
      onTap: onAdd,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _botaoAdd(VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.add, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _rowValor({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required double valor,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_fmtMoeda(valor)),
          const SizedBox(width: 8),
          _botaoAdd(onTap),
        ],
      ),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _listaItens(List<_LinhaItem> itens, bool isServico) {
    return Column(
      children: [
        for (int i = 0; i < itens.length; i++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(
                itens[i].nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${itens[i].quantidade} ${itens[i].unidade} × ${_fmtMoeda(itens[i].valorUnitario)}\n'
                'Custo: ${_fmtMoeda(itens[i].subtotalCusto)} • Lucro: ${_fmtMoeda(itens[i].lucroItem)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmtMoeda(itens[i].total),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        final novo = await _abrirEditorItem(
                          initial: itens[i],
                          isServico: isServico,
                        );
                        if (novo != null) setState(() => itens[i] = novo);
                      } else if (v == 'del') {
                        setState(() => itens.removeAt(i));
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

  // ---- ações específicas ----
  Future<void> _editarNumero() async {
    final numCtrl = TextEditingController(text: _numero.toString());
    final anoCtrl = TextEditingController(text: _ano.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Editar número do pedido'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numCtrl,
                  decoration: const InputDecoration(labelText: 'Número'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: anoCtrl,
                  decoration: const InputDecoration(labelText: 'Ano'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ok'),
              ),
            ],
          ),
    );
    if (ok == true) {
      setState(() {
        _numero = int.tryParse(numCtrl.text) ?? _numero;
        final novoAno = int.tryParse(anoCtrl.text) ?? _ano;
        final anoMudou = novoAno != _ano;
        _ano = novoAno;
        if (anoMudou && widget.pedidoId == null) {
          // Se alterou o ano em modo inclusão, sugerimos novo número
          _initNumeroAuto();
        }
      });
      // Valida e, se necessário, sugere correção
      await _validarNumeroEAlertar();
    }
  }

  Future<void> _selecionarCliente() async {
    final escolhido = await showModalBottomSheet<ClienteSelecionado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SelecionarClienteSheet(),
    );

    if (escolhido == null) return;

    setState(() {
      _clienteId = escolhido.id;
      _clienteCtrl.text = escolhido.nome;
    });
  }

  Future<void> _marcarCompromisso() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: hoje.subtract(const Duration(days: 1)),
      lastDate: hoje.add(const Duration(days: 365 * 2)),
      initialDate: _compromisso ?? hoje,
      helpText: 'Escolha a data',
    );
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null) return;
    setState(() {
      _compromisso = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      _expandedCompromissos = true;
    });
  }

  String _compromissoFmt(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} $hh:$mi';
  }

  Future<void> _addServico() async {
    final escolhidos = await showModalBottomSheet<List<LinhaItemServicoPedido>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SelecionarServicosSheet(),
    );

    if (escolhidos == null || escolhidos.isEmpty) return;

    setState(() {
      // converte para o tipo interno
      for (final e in escolhidos) {
        _servicos.add(
          _LinhaItem(
            refId: e.refId,
            nome: e.nome,
            unidade: e.unidade,
            quantidade: e.quantidade,
            valorUnitario: e.valorUnitario,
            custoUnitario:
                (e.custoExecucao is num)
                    ? (e.custoExecucao as num).toDouble()
                    : double.tryParse('${e.custoExecucao}') ?? 0.0,
          ),
        );
      }
    });
  }

  Future<void> _addProduto() async {
    final escolhidos = await showModalBottomSheet<List<LinhaItemPedido>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SelecionarProdutosSheet(),
    );

    if (escolhidos == null || escolhidos.isEmpty) return;

    setState(() {
      for (final e in escolhidos) {
        _produtos.add(
          _LinhaItem(
            refId: e.refId,
            nome: e.nome,
            unidade: e.unidade,
            quantidade: e.quantidade,
            valorUnitario: e.valorUnitario,
            custoUnitario:
                (e.custo is num)
                    ? (e.custo as num).toDouble()
                    : double.tryParse('${e.custo}') ?? 0.0,
          ),
        );
      }
    });
  }

  // ===== Editor de Desconto (valor ou % sobre o subtotal) =====
  Future<void> _editarDesconto() async {
    final tipo = ValueNotifier<DescontoTipo>(_descontoTipo);
    final valorCtrl = TextEditingController(
      text:
          _descontoTipo == DescontoTipo.valor
              ? _fmtCampo(_descontoValor)
              : _fmtCampo(_descontoPercent),
    );

    double _preview(String s, DescontoTipo t) {
      final v = _parseMoeda(s);
      if (_subtotal <= 0) return 0.0;
      if (t == DescontoTipo.valor) return v.clamp(0.0, _subtotal);
      final perc = v.clamp(0.0, 100000.0);
      return (_subtotal * (perc / 100.0)).clamp(0.0, _subtotal);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              title: const Text('Desconto'),
              content: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tipo',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<DescontoTipo>(
                      valueListenable: tipo,
                      builder:
                          (_, t, __) => Column(
                            children: [
                              RadioListTile<DescontoTipo>(
                                value: DescontoTipo.valor,
                                groupValue: t,
                                onChanged: (v) {
                                  tipo.value = v!;
                                  setSt(() {
                                    valorCtrl.text = _fmtCampo(_descontoValor);
                                  });
                                },
                                title: const Text('Valor (R\$)'),
                              ),
                              RadioListTile<DescontoTipo>(
                                value: DescontoTipo.percentual,
                                groupValue: t,
                                onChanged: (v) {
                                  tipo.value = v!;
                                  setSt(() {
                                    valorCtrl.text = _fmtCampo(
                                      _descontoPercent,
                                    );
                                  });
                                },
                                title: const Text(
                                  'Percentual (%) sobre o subtotal',
                                ),
                              ),
                            ],
                          ),
                    ),
                    TextField(
                      controller: valorCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\., ]')),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            tipo.value == DescontoTipo.valor
                                ? 'Desconto (R\$)'
                                : 'Desconto (%)',
                        prefixText:
                            tipo.value == DescontoTipo.valor ? 'R\$ ' : null,
                      ),
                      onChanged: (_) => setSt(() {}),
                      onSubmitted: (_) => Navigator.pop(ctx, true),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(child: Text('Aplicado')),
                        Text(
                          _fmtMoeda(_preview(valorCtrl.text, tipo.value)),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ok'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      final t = tipo.value;
      final v = _parseMoeda(valorCtrl.text);
      setState(() {
        _descontoTipo = t;
        if (t == DescontoTipo.valor) {
          _descontoValor = v.clamp(0.0, double.infinity);
        } else {
          _descontoPercent = v.clamp(0.0, 100000.0);
        }
      });
    }
  }

  Future<void> _editarTaxaEntrega() async {
    final v = await _editorValorDialog(
      titulo: 'Taxa de entrega',
      valor: _taxaEntrega,
    );
    if (v != null) setState(() => _taxaEntrega = v);
  }

  Future<void> _editarOutrasTaxas() async {
    final v = await _editorValorDialog(
      titulo: 'Outras taxas',
      valor: _outrasTaxas,
    );
    if (v != null) setState(() => _outrasTaxas = v);
  }

  Future<double?> _editorValorDialog({
    required String titulo,
    required double valor,
  }) async {
    final ctrl = TextEditingController(text: _fmtCampo(valor));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          title: Text(titulo),
          content: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\., ]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
    if (ok == true) return _parseMoeda(ctrl.text);
    return null;
  }

  String _fmtCampo(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  // ---- editor de item (serviço/produto) ----
  Future<_LinhaItem?> _abrirEditorItem({
    bool isServico = true,
    _LinhaItem? initial,
  }) async {
    return showModalBottomSheet<_LinhaItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => _ItemSheet(
            isServico: isServico,
            initial: initial,
            pedidoId: widget.pedidoId, // opcional (não é usado no sheet)
            scopeUserId: _scopeUserId, // <<< passa o ESCOPO para o sheet
          ),
    );
  }
}

// ===== componentes auxiliares =====

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _LinhaItem {
  final String? refId;
  final String nome;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final double custoUnitario;

  double get total => quantidade * valorUnitario;
  double get subtotalCusto => quantidade * custoUnitario;
  double get lucroItem => total - subtotalCusto;

  _LinhaItem({
    required this.refId,
    required this.nome,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.custoUnitario,
  });

  Map<String, dynamic> toMap() => {
    'refId': refId,
    'nome': nome,
    'unidade': unidade,
    'quantidade': quantidade,
    'valorUnitario': valorUnitario,
    'custoUnitario': custoUnitario,
    'subtotalVenda': total,
    'subtotalCusto': subtotalCusto,
    'lucroItem': lucroItem,
    'total': total,
  };

  _LinhaItem copyWith({
    String? refId,
    String? nome,
    String? unidade,
    double? quantidade,
    double? valorUnitario,
    double? custoUnitario,
  }) {
    return _LinhaItem(
      refId: refId ?? this.refId,
      nome: nome ?? this.nome,
      unidade: unidade ?? this.unidade,
      quantidade: quantidade ?? this.quantidade,
      valorUnitario: valorUnitario ?? this.valorUnitario,
      custoUnitario: custoUnitario ?? this.custoUnitario,
    );
  }
}

// ===== bottom sheet para criar/editar item =====

class _ItemSheet extends StatefulWidget {
  final bool isServico;
  final _LinhaItem? initial;
  final String? pedidoId; // opcional
  final String? scopeUserId; // <<< ESCOPO recebido do pai

  const _ItemSheet({
    required this.isServico,
    this.initial,
    this.pedidoId,
    required this.scopeUserId,
  });

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _nomeCtrl = TextEditingController();
  final _unCtrl = TextEditingController(text: 'UN');
  final _qtdCtrl = TextEditingController(text: '1');
  final _valorCtrl = TextEditingController(text: '0,00');
  final _custoCtrl = TextEditingController(text: '0,00');

  String? _refId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final it = widget.initial;
    if (it != null) {
      _refId = it.refId;
      _nomeCtrl.text = it.nome;
      _unCtrl.text = it.unidade;
      _qtdCtrl.text = it.quantidade.toString().replaceAll('.', ',');
      _valorCtrl.text = it.valorUnitario
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _custoCtrl.text = it.custoUnitario
          .toStringAsFixed(2)
          .replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _unCtrl.dispose();
    _qtdCtrl.dispose();
    _valorCtrl.dispose();
    _custoCtrl.dispose();
    super.dispose();
  }

  double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  Future<void> _pickDoCatalogo() async {
    final scope = widget.scopeUserId ?? _auth.currentUser?.uid;
    if (scope == null) return;

    setState(() => _loading = true);
    try {
      final col = widget.isServico ? 'servicos' : 'produtos';
      final snap =
          await _fs
              .collection(col)
              .where('userId', isEqualTo: scope) // ESCOPO
              .orderBy('nomeLower')
              .limit(50)
              .get();

      final itens =
          snap.docs.map((d) {
            final m = d.data();
            final nome = (m['nome'] ?? '').toString();
            final un = (m['unidade'] ?? 'UN').toString();

            final preco =
                widget.isServico
                    ? ((m['valorUnitario'] is num)
                        ? (m['valorUnitario'] as num).toDouble()
                        : double.tryParse('${m['valorUnitario']}') ?? 0.0)
                    : ((m['valorVenda'] is num)
                        ? (m['valorVenda'] as num).toDouble()
                        : double.tryParse('${m['valorVenda']}') ?? 0.0);

            final custo =
                widget.isServico
                    ? ((m['custoExecucao'] is num)
                        ? (m['custoExecucao'] as num).toDouble()
                        : double.tryParse('${m['custoExecucao']}') ?? 0.0)
                    : ((m['custo'] is num)
                        ? (m['custo'] as num).toDouble()
                        : double.tryParse('${m['custo']}') ?? 0.0);

            return _CatItem(
              id: d.id,
              nome: nome,
              unidade: un,
              preco: preco,
              custo: custo,
            );
          }).toList();

      final escolhido = await showModalBottomSheet<_CatItem>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder:
            (_) => _CatalogoList(itens: itens, isServico: widget.isServico),
      );

      if (escolhido != null) {
        setState(() {
          _refId = escolhido.id;
          _nomeCtrl.text = escolhido.nome;
          _unCtrl.text = escolhido.unidade;
          _valorCtrl.text = escolhido.preco
              .toStringAsFixed(2)
              .replaceAll('.', ',');
          _custoCtrl.text = escolhido.custo
              .toStringAsFixed(2)
              .replaceAll('.', ',');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Text(
              widget.initial == null
                  ? (widget.isServico
                      ? 'Adicionar serviço'
                      : 'Adicionar produto')
                  : (widget.isServico ? 'Editar serviço' : 'Editar produto'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nomeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      border: OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _loading ? null : _pickDoCatalogo,
                  icon:
                      _loading
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.search),
                  tooltip: 'Buscar no catálogo',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtdCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Qtd.',
                          border: OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _unCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Unid.',
                          border: OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _valorCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Valor unitário',
                          prefixText: 'R\$ ',
                          border: OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _custoCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText:
                              widget.isServico
                                  ? 'Custo execução'
                                  : 'Custo unitário',
                          prefixText: 'R\$ ',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                      final nome = _nomeCtrl.text.trim();
                      final qtd =
                          double.tryParse(
                            _qtdCtrl.text
                                .trim()
                                .replaceAll('.', '')
                                .replaceAll(',', '.'),
                          ) ??
                          0.0;
                      final un =
                          _unCtrl.text.trim().isEmpty
                              ? 'UN'
                              : _unCtrl.text.trim();
                      final vu = _parseMoeda(_valorCtrl.text);
                      if (nome.isEmpty || qtd <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Preencha nome e quantidade válida.'),
                          ),
                        );
                        return;
                      }
                      final custo = _parseMoeda(_custoCtrl.text);

                      final item = _LinhaItem(
                        refId: _refId,
                        nome: nome,
                        unidade: un,
                        quantidade: qtd,
                        valorUnitario: vu,
                        custoUnitario: custo,
                      );
                      Navigator.pop(context, item);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      widget.initial == null ? 'Adicionar' : 'Salvar',
                    ),
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

class _CatItem {
  final String id;
  final String nome;
  final String unidade;
  final double preco;
  final double custo;

  _CatItem({
    required this.id,
    required this.nome,
    required this.unidade,
    required this.preco,
    required this.custo,
  });
}

class _CatalogoList extends StatelessWidget {
  final List<_CatItem> itens;
  final bool isServico;
  const _CatalogoList({
    super.key,
    required this.itens,
    required this.isServico,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isServico ? 'Serviços' : 'Produtos',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: itens.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = itens[i];
                  return ListTile(
                    title: Text(
                      it.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${it.unidade} • R\$ ${it.preco.toStringAsFixed(2).replaceAll('.', ',')}',
                    ),
                    onTap: () => Navigator.pop(context, it),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
