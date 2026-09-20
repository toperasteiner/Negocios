import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

/// Retorno do seletor
class CategoriaSelecionada {
  final String id;
  final String nome;
  final String tipo; // 'pagar' | 'receber' | 'ambos'
  const CategoriaSelecionada({
    required this.id,
    required this.nome,
    required this.tipo,
  });
}

/// Seleciona (e permite cadastrar) categorias de pagamento/recebimento.
/// - Escopo: companyId do usuário logado (users/{uid}.companyId)
/// - Coleção: categorias_pagamento
/// - Campos: companyId, nome, nomeLower, tipo, ativa, descricao, createdAt, updatedAt, createdBy
class SelecionarCategoriaPagamentoSheet extends StatefulWidget {
  /// Contexto do seletor:
  /// - 'pagar'   -> lista e permite cadastrar apenas 'pagar' ou 'ambos'
  /// - 'receber' -> lista e permite cadastrar apenas 'receber' ou 'ambos'
  /// - 'ambos' ou null -> lista/cadastra qualquer tipo
  final String? filtroTipo;

  /// Mostrar inativas no catálogo? (padrão: false, mostra só ativas)
  final bool mostrarInativasPorPadrao;

  const SelecionarCategoriaPagamentoSheet({
    super.key,
    this.filtroTipo,
    this.mostrarInativasPorPadrao = false,
  });

  @override
  State<SelecionarCategoriaPagamentoSheet> createState() =>
      _SelecionarCategoriaPagamentoSheetState();
}

class _SelecionarCategoriaPagamentoSheetState
    extends State<SelecionarCategoriaPagamentoSheet>
    with SingleTickerProviderStateMixin {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String _limitKey = 'maxPaymentCategories';

  late TabController _tab;
  final _cadKey = GlobalKey<_CadastrarCategoriaTabState>();

  String? _companyId;
  bool _loadingScope = true;
  String? _scopeError;

  // permissão
  bool _canManagePaymentCategories = false;

  // plano
  bool _loadingPlan = true;
  String? _planError;
  int _usedCount = 0;
  int _limitCount = -1; // -1 = ilimitado
  bool _canCreateByPlan = true;

  CategoriaSelecionada? _selecionada;

  bool _mostrarInativas = false;

  String? get _uid => _auth.currentUser?.uid;

  int _lastTabIndex = 0;

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _limitCount = service.getLimit('maxPaymentCategories');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan = (_limitCount == -1 || _usedCount < _limitCount);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _tab = TabController(length: 2, vsync: this);
    _lastTabIndex = _tab.index;
    _tab.addListener(_onTabChange);
    _mostrarInativas = widget.mostrarInativasPorPadrao;
    _initScope();
  }

  void _onTabChange() async {
    if (!_tab.indexIsChanging) {
      if (mounted) setState(() => _lastTabIndex = _tab.index);
      return;
    }

    final indoParaCadastrar = _tab.index == 1;
    if (!indoParaCadastrar) {
      if (mounted) setState(() => _lastTabIndex = _tab.index);
      return;
    }

    if (!_canManagePaymentCategories) {
      _tab.index = 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você não tem permissão para cadastrar categorias.'),
          ),
        );
        setState(() => _lastTabIndex = _tab.index);
      }
      return;
    }

    if (_loadingPlan) {
      _tab.index = 0;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Validando plano...')));
        setState(() => _lastTabIndex = _tab.index);
      }
      return;
    }

    final ok = await _requirePlanSlot();
    if (!mounted) return;

    if (!ok) {
      _tab.index = 0;
    }

    setState(() => _lastTabIndex = _tab.index);
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _tab.removeListener(_onTabChange);
    _tab.dispose();
    super.dispose();
  }

  Future<int> _getCurrentCategoriasCount() async {
    final companyId = _companyId;
    if (companyId == null || companyId.isEmpty) return 0;

    final snap =
        await _fs
            .collection('categorias_pagamento')
            .where('companyId', isEqualTo: companyId)
            .count()
            .get();

    return snap.count ?? 0;
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

      final usados = await _getCurrentCategoriasCount();
      final limite = PlanService.instance.getLimit(_limitKey);
      final canCreate = limite == -1 ? true : usados < limite;

      if (!mounted) return;

      setState(() {
        _usedCount = usados;
        _limitCount = limite;
        _canCreateByPlan = canCreate;
        _loadingPlan = false;
        _planError = null;
      });
      // A plan notification may have arrived while the count was loading.
      _onPlanChanged();
    } catch (e) {
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

      final usados = await _getCurrentCategoriasCount();
      final limite = PlanService.instance.getLimit(_limitKey);
      final canCreate = limite == -1 ? true : usados < limite;

      if (!mounted) return false;

      setState(() {
        _usedCount = usados;
        _limitCount = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de categorias atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de categorias de pagamento do seu plano atual.\n\n'
                    'Categorias usadas: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando.',
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao validar plano: $e')));
      return false;
    }
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
      Map<String, dynamic>? me;

      // 1) por UID
      try {
        final byUid = await _fs.collection('users').doc(u.uid).get();
        if (byUid.exists) me = byUid.data();
      } catch (_) {}

      // 2) fallback por emailKey
      if (me == null) {
        final email = (u.email ?? '').toLowerCase().trim();
        if (email.isNotEmpty) {
          final q =
              await _fs
                  .collection('users')
                  .where('emailKey', isEqualTo: email)
                  .limit(1)
                  .get();
          if (q.docs.isNotEmpty) me = q.docs.first.data();
        }
      }

      final companyId = (me?['companyId'] ?? '').toString().trim();
      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      final canCat = (perms['canManagePaymentCategories'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _canManagePaymentCategories = canCat;
        _loadingScope = false;
        _scopeError =
            _companyId == null
                ? 'Usuário sem companyId vinculado. Associe uma empresa ao usuário.'
                : null;
      });

      await _refreshPlanRules();
    } catch (e, st) {
      debugPrint('[SelecionarCategoria] _initScope erro: $e\n$st');
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao resolver escopo: $e';
      });
    }
  }

  void _concluirSelecao() {
    if (_selecionada != null) {
      debugPrint('[SelecionarCategoria] Concluir: ${_selecionada!.id}');
      Navigator.pop(context, _selecionada);
    } else {
      debugPrint('[SelecionarCategoria] Nada selecionado.');
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
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: 'Voltar',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Selecionar categoria'),
          ),
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

    final companyId = _companyId!;
    final podeCadastrarAgora =
        _canManagePaymentCategories &&
        !_loadingPlan &&
        (_canCreateByPlan || _limitCount == -1);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Selecionar categoria'),
          bottom: TabBar(
            controller: _tab,
            tabs: [
              const Tab(icon: Icon(Icons.category_outlined), text: 'Catálogo'),
              Tab(
                icon: Icon(
                  !_canManagePaymentCategories ||
                          (!_loadingPlan && !_canCreateByPlan)
                      ? Icons.lock_outline
                      : Icons.add_box_outlined,
                ),
                text:
                    !_canManagePaymentCategories
                        ? 'Cadastrar (sem acesso)'
                        : (!_loadingPlan && !_canCreateByPlan)
                        ? 'Cadastrar (limite)'
                        : 'Cadastrar',
              ),
            ],
          ),
          actions: [
            if (_tab.index == 0)
              Row(
                children: [
                  const Text('Mostrar inativos'),
                  Switch.adaptive(
                    value: _mostrarInativas,
                    onChanged: (v) => setState(() => _mostrarInativas = v),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
          ],
        ),

        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child:
                _tab.index == 0
                    ? FilledButton.icon(
                      onPressed: _selecionada == null ? null : _concluirSelecao,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Usar esta categoria'),
                    )
                    : FilledButton.icon(
                      onPressed:
                          !_canManagePaymentCategories
                              ? null
                              : (_loadingPlan
                                  ? null
                                  : (podeCadastrarAgora
                                      ? () {
                                        final st = _cadKey.currentState;
                                        if (st == null || st.salvando) return;
                                        st.salvar();
                                      }
                                      : () async {
                                        await _requirePlanSlot();
                                      })),
                      icon:
                          (_cadKey.currentState?.salvando ?? false)
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.check_rounded),
                      label: Text(
                        !_canManagePaymentCategories
                            ? 'Sem permissão para cadastrar'
                            : _loadingPlan
                            ? 'Validando plano...'
                            : (podeCadastrarAgora
                                ? 'Salvar e usar'
                                : 'Limite do plano atingido'),
                      ),
                    ),
          ),
        ),

        body: Column(
          children: [
            if (_loadingPlan)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_planError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _planError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _CatalogoCategoriasTab(
                    companyId: companyId,
                    filtroTipo: widget.filtroTipo,
                    mostrarInativas: _mostrarInativas,
                    onEscolhido: (c) => setState(() => _selecionada = c),
                    selecionada: _selecionada,
                  ),
                  _canManagePaymentCategories
                      ? _CadastrarCategoriaTab(
                        key: _cadKey,
                        companyId: companyId,
                        createdByUid: _uid,
                        filtroTipoSugerido: widget.filtroTipo,
                        requirePlanSlot: _requirePlanSlot,
                        onPlanRefreshed: _refreshPlanRules,
                        onSalvo: (novo) {
                          debugPrint(
                            '[SelecionarCategoria] Nova categoria: ${novo.id}',
                          );
                          Navigator.pop(context, novo);
                        },
                      )
                      : const _CadastrarBloqueado(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================== Catálogo ============================== */

class _CatalogoCategoriasTab extends StatefulWidget {
  final String companyId;
  final String? filtroTipo; // 'pagar' | 'receber' | 'ambos' | null
  final bool mostrarInativas;
  final void Function(CategoriaSelecionada c) onEscolhido;
  final CategoriaSelecionada? selecionada;

  const _CatalogoCategoriasTab({
    required this.companyId,
    required this.onEscolhido,
    required this.selecionada,
    this.filtroTipo,
    required this.mostrarInativas,
  });

  @override
  State<_CatalogoCategoriasTab> createState() => _CatalogoCategoriasTabState();
}

class _CatalogoCategoriasTabState extends State<_CatalogoCategoriasTab> {
  final _fs = FirebaseFirestore.instance;
  final _buscaCtrl = TextEditingController();

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _baseQuery() {
    var q = _fs
        .collection('categorias_pagamento')
        .where('companyId', isEqualTo: widget.companyId);

    if (!widget.mostrarInativas) {
      q = q.where('ativa', isEqualTo: true);
    }

    if (widget.filtroTipo == 'pagar') {
      q = q.where('tipo', whereIn: ['pagar', 'ambos']);
    } else if (widget.filtroTipo == 'receber') {
      q = q.where('tipo', whereIn: ['receber', 'ambos']);
    } else if (widget.filtroTipo == 'ambos') {
      // mostra todos
    }

    q = q.orderBy('nome');
    return q;
  }

  @override
  Widget build(BuildContext context) {
    final query = _baseQuery();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar categoria',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                debugPrint('[SelecionarCategoria] stream erro: ${snap.error}');
                return Center(child: Text('Erro: ${snap.error}'));
              }

              final filtro = _buscaCtrl.text.trim().toLowerCase();
              final docs =
                  (snap.data?.docs ?? []).where((d) {
                    final m = d.data();
                    final nome = (m['nome'] ?? '').toString().toLowerCase();
                    final desc =
                        (m['descricao'] ?? '').toString().toLowerCase();
                    return filtro.isEmpty ||
                        nome.contains(filtro) ||
                        desc.contains(filtro);
                  }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhuma categoria encontrada.'),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data();
                  final id = d.id;
                  final nome = (m['nome'] ?? '').toString();
                  final tipo = (m['tipo'] ?? 'ambos').toString();
                  final ativa = (m['ativa'] ?? true) == true;
                  final desc = (m['descricao'] ?? '').toString();

                  final sel = widget.selecionada?.id == id;
                  final podeSelecionar = ativa;

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RadioListTile<bool>(
                      value: true,
                      groupValue: sel ? true : null,
                      onChanged:
                          podeSelecionar
                              ? (_) => widget.onEscolhido(
                                CategoriaSelecionada(
                                  id: id,
                                  nome: nome,
                                  tipo: tipo,
                                ),
                              )
                              : null,
                      title: Text(
                        nome.isNotEmpty ? nome : 'Sem nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: ativa ? null : Colors.grey[600],
                          decoration: ativa ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        [
                          'Tipo: ${_tipoLabel(tipo)}',
                          if (desc.isNotEmpty) desc,
                          if (!ativa) 'INATIVA',
                        ].join(' • '),
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

  String _tipoLabel(String v) {
    switch (v) {
      case 'pagar':
        return 'Pagar';
      case 'receber':
        return 'Receber';
      default:
        return 'Ambos';
    }
  }
}

/* ============================== Cadastrar ============================== */

class _CadastrarCategoriaTab extends StatefulWidget {
  final String companyId;
  final String? createdByUid;
  final String? filtroTipoSugerido; // pré-seleciona e restringe o tipo
  final Future<bool> Function() requirePlanSlot;
  final Future<void> Function() onPlanRefreshed;
  final void Function(CategoriaSelecionada novo) onSalvo;

  const _CadastrarCategoriaTab({
    super.key,
    required this.companyId,
    required this.createdByUid,
    required this.onSalvo,
    required this.requirePlanSlot,
    required this.onPlanRefreshed,
    this.filtroTipoSugerido,
  });

  @override
  State<_CadastrarCategoriaTab> createState() => _CadastrarCategoriaTabState();
}

class _CadastrarCategoriaTabState extends State<_CadastrarCategoriaTab> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;

  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _tipo = 'ambos';
  bool _salvando = false;
  bool get salvando => _salvando;

  List<ButtonSegment<String>> get _segmentosTipo {
    if (widget.filtroTipoSugerido == 'pagar') {
      return const [
        ButtonSegment(value: 'pagar', label: Text('Pagar')),
        ButtonSegment(value: 'ambos', label: Text('Ambos')),
      ];
    }
    if (widget.filtroTipoSugerido == 'receber') {
      return const [
        ButtonSegment(value: 'receber', label: Text('Receber')),
        ButtonSegment(value: 'ambos', label: Text('Ambos')),
      ];
    }
    return const [
      ButtonSegment(value: 'pagar', label: Text('Pagar')),
      ButtonSegment(value: 'receber', label: Text('Receber')),
      ButtonSegment(value: 'ambos', label: Text('Ambos')),
    ];
  }

  @override
  void initState() {
    super.initState();
    if (widget.filtroTipoSugerido == 'pagar') {
      _tipo = 'pagar';
    } else if (widget.filtroTipoSugerido == 'receber') {
      _tipo = 'receber';
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String? _validaNome(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o nome';
    if (s.length < 2) return 'Nome muito curto';
    return null;
  }

  Future<void> salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (widget.filtroTipoSugerido == 'pagar' &&
        !(_tipo == 'pagar' || _tipo == 'ambos')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tipo inválido para Contas a Pagar.')),
      );
      return;
    }
    if (widget.filtroTipoSugerido == 'receber' &&
        !(_tipo == 'receber' || _tipo == 'ambos')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tipo inválido para Contas a Receber.')),
      );
      return;
    }

    final okPlano = await widget.requirePlanSlot();
    if (!okPlano) return;

    final companyId = widget.companyId;
    final nome = _nomeCtrl.text.trim();
    final nomeLower = nome.toLowerCase();

    setState(() => _salvando = true);
    try {
      final dup =
          await _fs
              .collection('categorias_pagamento')
              .where('companyId', isEqualTo: companyId)
              .where('tipo', isEqualTo: _tipo)
              .where('nomeLower', isEqualTo: nomeLower)
              .limit(1)
              .get();

      if (dup.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Já existe uma categoria com este nome e tipo.'),
            ),
          );
        }
        return;
      }

      final data = <String, dynamic>{
        'companyId': companyId,
        'nome': nome,
        'nomeLower': nomeLower,
        'tipo': _tipo,
        'ativa': true,
        'descricao':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (widget.createdByUid != null) 'createdBy': widget.createdByUid,
      };

      final ref = await _fs.collection('categorias_pagamento').add(data);

      await widget.onPlanRefreshed();

      if (mounted) {
        widget.onSalvo(
          CategoriaSelecionada(id: ref.id, nome: nome, tipo: _tipo),
        );
      }
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[CadastrarCategoria] FirebaseException: ${e.code} ${e.message}\n$st',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: ${e.message}')));
      }
    } catch (e, st) {
      debugPrint('[CadastrarCategoria] erro: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AbsorbPointer(
      absorbing: _salvando,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nomeCtrl,
                      validator: _validaNome,
                      decoration: const InputDecoration(
                        labelText: 'Nome *',
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tipo',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: _segmentosTipo,
                      selected: {_tipo},
                      onSelectionChanged:
                          (s) => setState(() => _tipo = s.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descrição (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                      ),
                      inputFormatters: const [],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: cs.outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Categorias novas são sempre criadas como ATIVAS.',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: cs.outline),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dica: mantenha nomes curtos e específicos. Ex.: "Serviços Públicos", "Aluguel", "Folha".',
          ),
        ],
      ),
    );
  }
}

/* ============================== Bloqueado ============================== */

class _CadastrarBloqueado extends StatelessWidget {
  const _CadastrarBloqueado();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              'Você não tem permissão para cadastrar categorias.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Peça ao administrador para liberar “Categorias de pagamento (acesso)”.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
