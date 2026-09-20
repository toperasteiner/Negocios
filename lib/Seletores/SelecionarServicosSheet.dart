// lib/Pedidos/SelecionarServicosSheet.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

enum TipoPrecoServico { venda, compra }

/// Modelo simples usado pelo Pedido
class LinhaItemServicoPedido {
  final String? refId;
  final String nome;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final double custoExecucao;

  LinhaItemServicoPedido({
    required this.refId,
    required this.nome,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.custoExecucao,
  });
}

class SelecionarServicosSheet extends StatefulWidget {
  final TipoPrecoServico tipoPreco;

  const SelecionarServicosSheet({
    super.key,
    this.tipoPreco = TipoPrecoServico.venda,
  });

  @override
  State<SelecionarServicosSheet> createState() =>
      _SelecionarServicosSheetState();
}

class _SelecionarServicosSheetState extends State<SelecionarServicosSheet>
    with TickerProviderStateMixin {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late final TabController _tab;

  String? _companyId;
  bool _loadingScope = true;
  String? _scopeError;

  bool _podeCadastrar = false;
  String? _motivoCadastroBloqueado;

  bool _loadingPlan = true;
  String? _planError;
  int _servicesUsed = 0;
  int _servicesLimit = -1;
  bool _canCreateByPlan = true;

  String? get _uid => _auth.currentUser?.uid;

  final Map<String, _Selecionado> _selecionados = {};
  final Map<String, double> _qtd = {};

  final _nomeCtrl = TextEditingController();
  final _detCtrl = TextEditingController();
  final _valorCtrl = TextEditingController(text: '0,00');
  final _custoCtrl = TextEditingController(text: '0,00');

  String _unidade = 'UN';
  bool _salvando = false;

  static const Map<String, String> _unidadesDesc = {
    'UN': 'Unidade',
    'H': 'Hora',
    'DI': 'Diária',
    'M': 'Metro',
    'M²': 'Metro quadrado',
    'M³': 'Metro cúbico',
    'KG': 'Quilograma',
    'PÇ': 'Peça',
    'CX': 'Caixa',
    'DZ': 'Dúzia',
    'KIT': 'Kit / Conjunto',
    'PAR': 'Par',
  };

  void _logError(Object error, [StackTrace? stack, String where = '']) {
    final tag =
        where.isEmpty
            ? 'SelecionarServicosSheet'
            : 'SelecionarServicosSheet::$where';

    // ignore: avoid_print
    print('[$tag] ERROR: $error');

    if (stack != null) {
      // ignore: avoid_print
      print(stack);
    }

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'SelecionarServicosSheet',
        informationCollector: () sync* {
          yield ErrorDescription('Tela: Selecionar serviços');
          if (where.isNotEmpty) yield ErrorDescription('Bloco: $where');
        },
      ),
    );
  }

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _servicesLimit = service.getLimit('maxServices');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan =
            (service.companyId ?? '').isNotEmpty &&
            (_servicesLimit == -1 || _servicesUsed < _servicesLimit);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);

    _tab = TabController(length: 2, vsync: this);

    _tab.addListener(() async {
      if (!_tab.indexIsChanging) {
        if (mounted) setState(() {});
        return;
      }

      final indoParaCadastrar = _tab.index == 1;

      if (!indoParaCadastrar) {
        if (mounted) setState(() {});
        return;
      }

      if (!_podeCadastrar) {
        _tab.index = 0;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _motivoCadastroBloqueado ??
                    'Sem permissão para cadastrar serviços.',
              ),
            ),
          );
          setState(() {});
        }
        return;
      }

      if (_loadingPlan) {
        _tab.index = 0;

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Validando plano...')));
          setState(() {});
        }
        return;
      }

      final ok = await _requirePlanSlot();

      if (!mounted) return;

      if (!ok) {
        _tab.index = 0;
      }

      setState(() {});
    });

    _initScope();
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _tab.dispose();
    _nomeCtrl.dispose();
    _detCtrl.dispose();
    _valorCtrl.dispose();
    _custoCtrl.dispose();
    super.dispose();
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;

    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Faça login para continuar.';
      });
      return;
    }

    try {
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();

      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      final canManageServices = (perms['canManageServices'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _podeCadastrar = canManageServices;
        _motivoCadastroBloqueado =
            canManageServices
                ? null
                : 'Você não tem permissão para cadastrar serviços.';
        _loadingScope = false;
        _scopeError =
            _companyId == null
                ? 'Usuário sem companyId vinculado. Associe uma empresa ao usuário.'
                : null;
      });

      await _refreshPlanRules();
    } catch (e, st) {
      _logError(e, st, '_initScope');
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao resolver escopo: $e';
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid.data() ?? {};
    } catch (_) {}

    final email = (u.email ?? '').toLowerCase().trim();

    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();

        if (q.docs.isNotEmpty) return q.docs.first.data();
      } catch (_) {}
    }

    return null;
  }

  Future<void> _refreshPlanRules() async {
    try {
      setState(() {
        _loadingPlan = true;
        _planError = null;
      });

      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await PlanService.instance.getCurrentServicesCount();
      final limite = PlanService.instance.getLimit('maxServices');
      final canCreate = await PlanService.instance.canCreateService();

      if (!mounted) return;

      setState(() {
        _servicesUsed = usados;
        _servicesLimit = limite;
        _canCreateByPlan = canCreate;
        _loadingPlan = false;
        _planError = null;
      });
      // A plan notification may have arrived while the count was loading.
      _onPlanChanged();
    } catch (e, st) {
      _logError(e, st, '_refreshPlanRules');

      if (!mounted) return;

      setState(() {
        _loadingPlan = false;
        _planError = 'Erro ao validar plano: $e';
      });
    }
  }

  void _showPlanLimitDialog({
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<bool> _requirePlanSlot() async {
    try {
      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final canCreate = await PlanService.instance.canCreateService();
      final usados = await PlanService.instance.getCurrentServicesCount();
      final limite = PlanService.instance.getLimit('maxServices');

      if (!mounted) return false;

      setState(() {
        _servicesUsed = usados;
        _servicesLimit = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de serviços atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de serviços do seu plano atual.\n\n'
                    'Serviços usados: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando serviços.',
      );

      return false;
    } catch (e, st) {
      _logError(e, st, '_requirePlanSlot');

      if (!mounted) return false;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao validar plano: $e')));

      return false;
    }
  }

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

  Future<void> _confirmarSelecao() async {
    try {
      if (_selecionados.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione pelo menos um serviço.')),
        );
        return;
      }

      final items =
          _selecionados.values.map((s) {
            final qtd = _qtd[s.id] ?? 1.0;

            return LinhaItemServicoPedido(
              refId: s.id,
              nome: s.nome,
              unidade: s.unidade,
              quantidade: qtd,
              valorUnitario: s.precoSelecionado,
              custoExecucao: s.custoExecucao,
            );
          }).toList();

      Navigator.pop(context, items);
    } catch (e, st) {
      _logError(e, st, '_confirmarSelecao');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao confirmar seleção. Veja o console.'),
        ),
      );
    }
  }

  Future<void> _cadastrarRapido() async {
    if (!_podeCadastrar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _motivoCadastroBloqueado ??
                'Sem permissão para cadastrar serviços.',
          ),
        ),
      );
      return;
    }

    final okPlano = await _requirePlanSlot();
    if (!okPlano) return;

    final companyId = _companyId;

    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível determinar o escopo.')),
      );
      return;
    }

    final nome = _nomeCtrl.text.trim();

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do serviço.')),
      );
      return;
    }

    final valor = _parseMoeda(_valorCtrl.text);
    final custo = _parseMoeda(_custoCtrl.text);

    setState(() => _salvando = true);

    try {
      final doc = await _fs.collection('servicos').add({
        'companyId': companyId,
        'userId': _uid,
        'createdByUid': _uid,
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'descricao': _detCtrl.text.trim().isEmpty ? null : _detCtrl.text.trim(),
        'unidade': _unidade,
        'valorUnitario': valor,
        'custoExecucao': custo,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final novoId = doc.id;

      await _refreshPlanRules();

      final precoSelecionado =
          widget.tipoPreco == TipoPrecoServico.compra ? custo : valor;

      final item = LinhaItemServicoPedido(
        refId: novoId,
        nome: nome,
        unidade: _unidade,
        quantidade: 1.0,
        valorUnitario: precoSelecionado,
        custoExecucao: custo,
      );

      if (mounted) Navigator.pop(context, [item]);
    } catch (e, st) {
      _logError(e, st, '_cadastrarRapido');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao salvar. Veja o console.')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const SafeArea(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_scopeError != null || _companyId == null) {
      return SafeArea(
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                _scopeError ?? 'Não foi possível determinar o escopo.',
              ),
            ),
          ),
        ),
      );
    }

    final padding =
        MediaQuery.of(context).viewInsets +
        const EdgeInsets.fromLTRB(12, 12, 12, 16);

    final podeCadastrarAgora =
        _podeCadastrar &&
        !_loadingPlan &&
        (_canCreateByPlan || _servicesLimit == -1);

    final titulo =
        widget.tipoPreco == TipoPrecoServico.compra
            ? 'Adicionar serviço à compra'
            : 'Adicionar serviço ao pedido';

    return SafeArea(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tab,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: [
                  const Tab(
                    icon: Icon(Icons.library_books_outlined),
                    text: 'Catálogo',
                  ),
                  Tab(
                    icon: Icon(
                      !_podeCadastrar || (!_loadingPlan && !_canCreateByPlan)
                          ? Icons.lock_outline
                          : Icons.add_circle_outline,
                    ),
                    text:
                        !_podeCadastrar
                            ? 'Cadastrar (bloqueado)'
                            : (!_loadingPlan && !_canCreateByPlan)
                            ? 'Cadastrar (limite)'
                            : 'Cadastrar serviço',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingPlan)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(),
              ),
            if (_planError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _planError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _CatalogoServicosTab(
                    fs: _fs,
                    companyId: _companyId!,
                    tipoPreco: widget.tipoPreco,
                    isChecked: (id) => _selecionados.containsKey(id),
                    getQty: (id) => _qtd[id] ?? 1.0,
                    onQtyChanged: (id, v) {
                      _qtd[id] = v;
                    },
                    onToggle: (s, checked) {
                      setState(() {
                        if (checked) {
                          _selecionados[s.id] = s;
                          _qtd[s.id] = _qtd[s.id] ?? 1.0;
                        } else {
                          _selecionados.remove(s.id);
                          _qtd.remove(s.id);
                        }
                      });
                    },
                  ),
                  !_podeCadastrar
                      ? _AbaBloqueada(
                        motivo:
                            _motivoCadastroBloqueado ??
                            'Você não tem permissão para cadastrar serviços.',
                      )
                      : _tabCadastro(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_tab.index == 0)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _confirmarSelecao,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        _selecionados.isEmpty
                            ? 'Adicionar selecionados'
                            : 'Adicionar (${_selecionados.length})',
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          !_podeCadastrar
                              ? null
                              : (_loadingPlan
                                  ? null
                                  : (podeCadastrarAgora
                                      ? (_salvando ? null : _cadastrarRapido)
                                      : () async {
                                        await _requirePlanSlot();
                                      })),
                      icon:
                          _salvando
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.save_outlined),
                      label: Text(
                        !_podeCadastrar
                            ? 'Sem permissão para cadastrar'
                            : _loadingPlan
                            ? 'Validando plano...'
                            : (podeCadastrarAgora
                                ? 'Adicionar este serviço'
                                : 'Limite do plano atingido'),
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

  Widget _tabCadastro() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _boxText('Qual é o serviço?', _nomeCtrl),
          const SizedBox(height: 10),
          _boxText('Detalhes (opcional)', _detCtrl, maxLines: 3),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _unidade,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Unidade de medida',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              filled: true,
              prefixIcon: const Icon(Icons.straighten_outlined),
            ),
            items:
                _unidadesDesc.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              e.value,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color?.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
            selectedItemBuilder: (ctx) {
              final keys = _unidadesDesc.keys.toList();
              return keys
                  .map(
                    (k) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          k,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  )
                  .toList();
            },
            onChanged: (v) => setState(() => _unidade = v ?? 'UN'),
          ),
          const SizedBox(height: 10),
          _boxText(
            'Preço unitário de venda',
            _valorCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\., ]')),
            ],
            prefixText: 'R\$ ',
          ),
          const SizedBox(height: 10),
          _boxText(
            'Custo para execução',
            _custoCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\., ]')),
            ],
            prefixText: 'R\$ ',
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.tipoPreco == TipoPrecoServico.compra
                  ? 'Na compra, será usado o custo de execução como valor unitário.'
                  : 'Na venda, será usado o preço unitário de venda.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _boxText(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        filled: true,
        prefixText: prefixText,
      ),
      onChanged: (_) {
        try {
          setState(() {});
        } catch (e, st) {
          _logError(e, st, 'onChanged($label)');
        }
      },
    );
  }
}

class _CatalogoServicosTab extends StatefulWidget {
  final FirebaseFirestore fs;
  final String companyId;
  final TipoPrecoServico tipoPreco;

  final bool Function(String id) isChecked;
  final double Function(String id) getQty;
  final void Function(String id, double qtd) onQtyChanged;
  final void Function(_Selecionado item, bool checked) onToggle;

  const _CatalogoServicosTab({
    super.key,
    required this.fs,
    required this.companyId,
    required this.tipoPreco,
    required this.isChecked,
    required this.getQty,
    required this.onQtyChanged,
    required this.onToggle,
  });

  @override
  State<_CatalogoServicosTab> createState() => _CatalogoServicosTabState();
}

class _CatalogoServicosTabState extends State<_CatalogoServicosTab>
    with AutomaticKeepAliveClientMixin<_CatalogoServicosTab> {
  final _buscaCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _deb;
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _buscaCtrl.addListener(() {
      _deb?.cancel();
      _deb = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() => _q = _buscaCtrl.text.trim());
      });
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    _scroll.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
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

  double _stepFor(String u) {
    const frac = {'H', 'M', 'M²', 'M³', 'KG'};
    return frac.contains(u.toUpperCase()) ? 0.1 : 1.0;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Query col = widget.fs
        .collection('servicos')
        .where('companyId', isEqualTo: widget.companyId);

    if (_q.isNotEmpty) {
      final start = _q.toLowerCase();
      final end = '$start\uf8ff';
      col = col.orderBy('nomeLower').startAt([start]).endAt([end]);
    } else {
      col = col.orderBy('nomeLower');
    }

    return Column(
      children: [
        TextField(
          controller: _buscaCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            filled: true,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: col.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }

              final docs = snap.data?.docs ?? [];

              if (docs.isEmpty) {
                return const Center(child: Text('Nenhum serviço encontrado.'));
              }

              return ListView.separated(
                key: const PageStorageKey('servicos_catalogo_list'),
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final id = docs[i].id;
                  final d = docs[i].data() as Map<String, dynamic>;

                  final nome = (d['nome'] ?? '').toString();
                  final desc = (d['descricao'] ?? '').toString();
                  final unidade = (d['unidade'] ?? 'UN').toString();

                  final valorUnitario = _toDouble(d['valorUnitario']);
                  final custoExecucao = _toDouble(d['custoExecucao']);

                  final precoSelecionado =
                      widget.tipoPreco == TipoPrecoServico.compra
                          ? custoExecucao
                          : valorUnitario;

                  final labelPreco =
                      widget.tipoPreco == TipoPrecoServico.compra
                          ? 'Custo por ${unidade.isEmpty ? "unidade" : unidade}:'
                          : 'Preço por ${unidade.isEmpty ? "unidade" : unidade}:';

                  final marcado = widget.isChecked(id);
                  final step = _stepFor(unidade);
                  final qtdAtual =
                      widget.getQty(id) == 0.0 ? step : widget.getQty(id);

                  void toggle(bool checked) {
                    widget.onToggle(
                      _Selecionado(
                        id: id,
                        nome: nome,
                        unidade: unidade,
                        valorUnitario: valorUnitario,
                        custoExecucao: custoExecucao,
                        precoSelecionado: precoSelecionado,
                      ),
                      checked,
                    );
                  }

                  return InkWell(
                    onTap: () => toggle(!marcado),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (desc.isNotEmpty)
                                  Text(
                                    desc,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: Text(labelPreco)),
                                    Text(
                                      _fmtMoeda(precoSelecionado),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (widget.tipoPreco ==
                                    TipoPrecoServico.compra) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Preço venda: ${_fmtMoeda(valorUnitario)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _QtyStepper(
                                  value: qtdAtual,
                                  enabled: marcado,
                                  step: step,
                                  unidade: unidade,
                                  onChanged: (v) {
                                    final clipped = v < step ? step : v;
                                    widget.onQtyChanged(
                                      id,
                                      double.parse(clipped.toStringAsFixed(3)),
                                    );
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Transform.scale(
                            scale: 0.95,
                            child: Checkbox(
                              value: marcado,
                              onChanged: (v) => toggle(v ?? false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Selecionado {
  final String id;
  final String nome;
  final String unidade;
  final double valorUnitario;
  final double custoExecucao;
  final double precoSelecionado;

  _Selecionado({
    required this.id,
    required this.nome,
    required this.unidade,
    required this.valorUnitario,
    required this.custoExecucao,
    required this.precoSelecionado,
  });
}

class _QtyStepper extends StatelessWidget {
  final double value;
  final bool enabled;
  final double step;
  final String unidade;
  final ValueChanged<double> onChanged;

  const _QtyStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.step = 1.0,
    this.unidade = 'UN',
  });

  String _fmt(double v) {
    if (step >= 1.0) return v.toStringAsFixed(0);
    if (step >= 0.1) return v.toStringAsFixed(1);
    if (step >= 0.01) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }

  Future<void> _showEditDialog(BuildContext context) async {
    if (!enabled) return;

    final ctrl = TextEditingController(text: _fmt(value).replaceAll('.', ','));
    String? errorText;

    double? parseValue(String s) {
      final t = s
          .trim()
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .replaceAll(',', '.');

      return double.tryParse(t);
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            void apply() {
              final parsed = parseValue(ctrl.text);

              if (parsed == null) {
                setState(() => errorText = 'Valor inválido');
                return;
              }

              final clipped = parsed < step ? step : parsed;
              final rounded = double.parse(clipped.toStringAsFixed(3));

              Navigator.of(ctx).pop();
              onChanged(rounded);
            }

            return AlertDialog(
              title: const Text('Quantidade'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]')),
                ],
                onSubmitted: (_) => apply(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.numbers),
                  suffixText: unidade,
                  hintText: 'Ex.: ${_fmt(step)}',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(onPressed: apply, child: const Text('Aplicar')),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    void dec() {
      final next = (value - step) < step ? step : (value - step);
      onChanged(double.parse(next.toStringAsFixed(3)));
    }

    void inc() {
      final next = value + step;
      onChanged(double.parse(next.toStringAsFixed(3)));
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sqIconBtn(Icons.remove, onTap: dec),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _showEditDialog(context),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    '${_fmt(value)} $unidade',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _sqIconBtn(Icons.add, onTap: inc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sqIconBtn(IconData icon, {required VoidCallback onTap}) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _AbaBloqueada extends StatelessWidget {
  final String motivo;

  const _AbaBloqueada({required this.motivo});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Cadastro bloqueado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              motivo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
