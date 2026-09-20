import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

class FornecedorSelecionado {
  final String id;
  final String nome;
  const FornecedorSelecionado({required this.id, required this.nome});
}

class SelecionarFornecedorSheet extends StatefulWidget {
  const SelecionarFornecedorSheet({super.key});

  @override
  State<SelecionarFornecedorSheet> createState() =>
      _SelecionarFornecedorSheetState();
}

class _SelecionarFornecedorSheetState extends State<SelecionarFornecedorSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _cadKey = GlobalKey<_CadastrarFornecedorTabState>();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== Escopo multiempresa =====
  String? _companyId;
  bool _loadingScope = true;
  String? _scopeError;

  // ===== Permissão =====
  bool _canRegisterClientsSuppliers = false;

  // ===== Plano =====
  bool _loadingPlan = true;
  String? _planError;
  int _clientsUsed = 0;
  int _clientsLimit = -1; // -1 = ilimitado
  bool _canCreateByPlan = true;

  FornecedorSelecionado? _selecionado;

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _clientsLimit = service.getLimit('maxClients');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan =
            (service.companyId ?? '').isNotEmpty &&
            (_clientsLimit == -1 || _clientsUsed < _clientsLimit);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChange);
    _initScope();
  }

  Future<void> _onTabChange() async {
    if (!_tab.indexIsChanging) {
      if (mounted) setState(() {});
      return;
    }

    final indoParaCadastrar = _tab.index == 1;
    if (!indoParaCadastrar) {
      if (mounted) setState(() {});
      return;
    }

    if (!_canRegisterClientsSuppliers) {
      _tab.index = 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Você não tem permissão para cadastrar fornecedores.',
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
      final canReg = (perms['canRegisterClientsSuppliers'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _canRegisterClientsSuppliers = canReg;
        _loadingScope = false;
        _scopeError =
            _companyId == null
                ? 'Usuário sem companyId vinculado. Associe uma empresa ao usuário.'
                : null;
      });

      await _refreshPlanRules();
    } catch (e) {
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
      if (byUid.exists) return (byUid.data() ?? {}) as Map<String, dynamic>;
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

      final usados = await PlanService.instance.getCurrentClientsCount();
      final limite = PlanService.instance.getLimit('maxClients');
      final canCreate = await PlanService.instance.canCreateClient();

      if (!mounted) return;

      setState(() {
        _clientsUsed = usados;
        _clientsLimit = limite;
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

      final canCreate = await PlanService.instance.canCreateClient();
      final usados = await PlanService.instance.getCurrentClientsCount();
      final limite = PlanService.instance.getLimit('maxClients');

      if (!mounted) return false;

      setState(() {
        _clientsUsed = usados;
        _clientsLimit = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de clientes/fornecedores atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de clientes/fornecedores do seu plano atual.\n\n'
                    'Cadastros usados: $usados\n'
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

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _tab.removeListener(_onTabChange);
    _tab.dispose();
    super.dispose();
  }

  void _concluirSelecao() {
    if (_selecionado != null) {
      debugPrint(
        '[SelecionarFornecedor] Concluir seleção: ${_selecionado!.id}',
      );
      Navigator.pop(context, _selecionado);
    } else {
      debugPrint('[SelecionarFornecedor] Nenhum fornecedor selecionado.');
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
            title: const Text('Selecionar fornecedor'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
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
        _canRegisterClientsSuppliers &&
        !_loadingPlan &&
        (_canCreateByPlan || _clientsLimit == -1);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Selecionar fornecedor'),
          bottom: TabBar(
            controller: _tab,
            tabs: [
              const Tab(
                icon: Icon(Icons.store_mall_directory_outlined),
                text: 'Catálogo',
              ),
              Tab(
                icon: Icon(
                  !_canRegisterClientsSuppliers ||
                          (!_loadingPlan && !_canCreateByPlan)
                      ? Icons.lock_outline
                      : Icons.person_add_alt_1_outlined,
                ),
                text:
                    !_canRegisterClientsSuppliers
                        ? 'Cadastrar (sem acesso)'
                        : (!_loadingPlan && !_canCreateByPlan)
                        ? 'Cadastrar (limite)'
                        : 'Cadastrar',
              ),
            ],
          ),
        ),

        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child:
                _tab.index == 0
                    ? FilledButton.icon(
                      onPressed: _selecionado == null ? null : _concluirSelecao,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Adicionar este fornecedor'),
                    )
                    : FilledButton.icon(
                      onPressed:
                          !_canRegisterClientsSuppliers
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
                        !_canRegisterClientsSuppliers
                            ? 'Sem permissão para cadastrar'
                            : _loadingPlan
                            ? 'Validando plano...'
                            : (podeCadastrarAgora
                                ? 'Adicionar este fornecedor'
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
                  _CatalogoFornecedoresTab(
                    companyId: companyId,
                    onEscolhido: (c) => setState(() => _selecionado = c),
                    selecionado: _selecionado,
                  ),
                  _canRegisterClientsSuppliers
                      ? _CadastrarFornecedorTab(
                        key: _cadKey,
                        companyId: companyId,
                        createdByUid: _auth.currentUser?.uid,
                        requirePlanSlot: _requirePlanSlot,
                        onPlanRefreshed: _refreshPlanRules,
                        onSalvo: (novo) {
                          debugPrint(
                            '[SelecionarFornecedor] Novo fornecedor salvo: ${novo.id}',
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

/* ============================ ABA CATÁLOGO ============================ */

class _CatalogoFornecedoresTab extends StatefulWidget {
  final String companyId;
  final void Function(FornecedorSelecionado c) onEscolhido;
  final FornecedorSelecionado? selecionado;
  const _CatalogoFornecedoresTab({
    required this.companyId,
    required this.onEscolhido,
    required this.selecionado,
  });

  @override
  State<_CatalogoFornecedoresTab> createState() =>
      _CatalogoFornecedoresTabState();
}

class _CatalogoFornecedoresTabState extends State<_CatalogoFornecedoresTab> {
  final _fs = FirebaseFirestore.instance;
  final _buscaCtrl = TextEditingController();

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _fs
        .collection('clientes')
        .where('companyId', isEqualTo: widget.companyId)
        .where('isFornecedor', isEqualTo: true)
        .orderBy('nomeLower');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar fornecedor',
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
          child: StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                debugPrint(
                  '[SelecionarFornecedor] Erro ao carregar: ${snap.error}',
                );
                return Center(child: Text('Erro: ${snap.error}'));
              }

              final filtro = _buscaCtrl.text.trim().toLowerCase();
              final docs =
                  (snap.data?.docs ?? []).where((d) {
                    final m = d.data() as Map<String, dynamic>;
                    final nome = (m['nome'] ?? '').toString().toLowerCase();
                    final email = (m['email'] ?? '').toString().toLowerCase();
                    return filtro.isEmpty ||
                        nome.contains(filtro) ||
                        email.contains(filtro);
                  }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum fornecedor encontrado.'),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data() as Map<String, dynamic>;
                  final id = d.id;
                  final nome = (m['nome'] ?? '').toString();
                  final email = (m['email'] ?? '').toString();

                  final sel = widget.selecionado?.id == id;

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RadioListTile<bool>(
                      value: true,
                      groupValue: sel ? true : null,
                      onChanged:
                          (_) => widget.onEscolhido(
                            FornecedorSelecionado(id: id, nome: nome),
                          ),
                      title: Text(
                        nome.isNotEmpty ? nome : 'Sem nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: email.isEmpty ? null : Text(email),
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

/* ======================== ABA CADASTRAR FORNECEDOR ======================== */

class _CadastrarFornecedorTab extends StatefulWidget {
  final void Function(FornecedorSelecionado novo) onSalvo;
  final String companyId;
  final String? createdByUid;
  final Future<bool> Function() requirePlanSlot;
  final Future<void> Function() onPlanRefreshed;

  const _CadastrarFornecedorTab({
    super.key,
    required this.onSalvo,
    required this.companyId,
    required this.createdByUid,
    required this.requirePlanSlot,
    required this.onPlanRefreshed,
  });

  @override
  State<_CadastrarFornecedorTab> createState() =>
      _CadastrarFornecedorTabState();
}

class _CadastrarFornecedorTabState extends State<_CadastrarFornecedorTab> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;

  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _whatsCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  String _tipoCliente = 'pf';
  final _cpfCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _razaoCtrl = TextEditingController();

  String _perfilRelacionamento = 'fornecedor';

  final _ruaCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();

  bool _salvando = false;
  bool get salvando => _salvando;

  String _somenteDigitos(String v) => v.replaceAll(RegExp(r'\D'), '');
  void _maskLive(TextEditingController c, String Function(String) fn) {
    final f = fn(_somenteDigitos(c.text));
    if (f != c.text) {
      c.value = TextEditingValue(
        text: f,
        selection: TextSelection.collapsed(offset: f.length),
      );
    }
  }

  String _tel(String d) {
    if (d.isEmpty) return '';
    if (d.length <= 2) return '($d';
    if (d.length <= 6) return '(${d.substring(0, 2)}) ${d.substring(2)}';
    if (d.length <= 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    final x = d.substring(0, 11);
    return '(${x.substring(0, 2)}) ${x.substring(2, 7)}-${x.substring(7)}';
  }

  String _cpf(String d) {
    final x = d.length > 11 ? d.substring(0, 11) : d;
    if (x.isEmpty) return '';
    final b = StringBuffer();
    for (int i = 0; i < x.length; i++) {
      b.write(x[i]);
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('-');
    }
    return b.toString().replaceAll(RegExp(r'[.\-]+$'), '');
  }

  String _cnpj(String d) {
    final x = d.length > 14 ? d.substring(0, 14) : d;
    if (x.isEmpty) return '';
    final b = StringBuffer();
    for (int i = 0; i < x.length; i++) {
      b.write(x[i]);
      if (i == 1 || i == 4) b.write('.');
      if (i == 7) b.write('/');
      if (i == 11) b.write('-');
    }
    return b.toString().replaceAll(RegExp(r'[.\-\/]+$'), '');
  }

  String _cep(String d) {
    final x = d.length > 8 ? d.substring(0, 8) : d;
    if (x.isEmpty) return '';
    if (x.length <= 5) return x;
    return '${x.substring(0, 5)}-${x.substring(5)}';
  }

  @override
  void initState() {
    super.initState();
    _telefoneCtrl.addListener(() => _maskLive(_telefoneCtrl, _tel));
    _whatsCtrl.addListener(() => _maskLive(_whatsCtrl, _tel));
    _cpfCtrl.addListener(() => _maskLive(_cpfCtrl, _cpf));
    _cnpjCtrl.addListener(() => _maskLive(_cnpjCtrl, _cnpj));
    _cepCtrl.addListener(() => _maskLive(_cepCtrl, _cep));
  }

  @override
  void dispose() {
    for (final c in [
      _nomeCtrl,
      _emailCtrl,
      _telefoneCtrl,
      _whatsCtrl,
      _obsCtrl,
      _cpfCtrl,
      _cnpjCtrl,
      _razaoCtrl,
      _ruaCtrl,
      _numeroCtrl,
      _complCtrl,
      _bairroCtrl,
      _cidadeCtrl,
      _estadoCtrl,
      _cepCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validaNome(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o nome';
    if (s.length < 2) return 'Nome muito curto';
    return null;
  }

  String? _validaEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    return ok ? null : 'E-mail inválido';
  }

  String? _validaCPF(String? v) {
    if (_tipoCliente != 'pf') return null;
    final d = _somenteDigitos(v ?? '');
    if (d.isEmpty) return null;
    if (d.length != 11) return 'CPF deve ter 11 dígitos';
    return null;
  }

  String? _validaCNPJ(String? v) {
    if (_tipoCliente != 'pj') return null;
    final d = _somenteDigitos(v ?? '');
    if (d.isEmpty) return null;
    if (d.length != 14) return 'CNPJ deve ter 14 dígitos';
    return null;
  }

  String? _validaRazao(String? v) {
    if (_tipoCliente != 'pj') return null;
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (s.length < 3) return 'Razão Social muito curta';
    return null;
  }

  Future<void> salvar() async {
    if (widget.companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível determinar o escopo.')),
      );
      return;
    }

    debugPrint('[SelecionarFornecedor] Botão Adicionar (cadastro) pressionado');
    final nome = _nomeCtrl.text.trim();
    final nomeOK = nome.length >= 2;

    _formKey.currentState?.validate();

    if (!nomeOK) {
      debugPrint(
        '[SelecionarFornecedor] Validação falhou (nome vazio/curto). Nome="$nome"',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o nome do fornecedor.')),
        );
      }
      return;
    }

    final okPlano = await widget.requirePlanSlot();
    if (!okPlano) return;

    setState(() => _salvando = true);
    try {
      final dados = <String, dynamic>{
        'companyId': widget.companyId,
        'userId': widget.createdByUid,
        'createdByUid': widget.createdByUid,
        'tipoCliente': _tipoCliente,
        'perfilRelacionamento': _perfilRelacionamento,
        'isCliente': _perfilRelacionamento == 'ambos',
        'isFornecedor': true,
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'telefone':
            _somenteDigitos(_telefoneCtrl.text).isEmpty
                ? null
                : _somenteDigitos(_telefoneCtrl.text),
        'whatsapp':
            _somenteDigitos(_whatsCtrl.text).isEmpty
                ? null
                : _somenteDigitos(_whatsCtrl.text),
        'cpf':
            _tipoCliente == 'pf'
                ? (_somenteDigitos(_cpfCtrl.text).isEmpty
                    ? null
                    : _somenteDigitos(_cpfCtrl.text))
                : null,
        'cnpj':
            _tipoCliente == 'pj'
                ? (_somenteDigitos(_cnpjCtrl.text).isEmpty
                    ? null
                    : _somenteDigitos(_cnpjCtrl.text))
                : null,
        'razaoSocial':
            _tipoCliente == 'pj'
                ? (_razaoCtrl.text.trim().isEmpty
                    ? null
                    : _razaoCtrl.text.trim())
                : null,
        'endereco': {
          'rua': _ruaCtrl.text.trim().isEmpty ? null : _ruaCtrl.text.trim(),
          'numero':
              _numeroCtrl.text.trim().isEmpty ? null : _numeroCtrl.text.trim(),
          'complemento':
              _complCtrl.text.trim().isEmpty ? null : _complCtrl.text.trim(),
          'bairro':
              _bairroCtrl.text.trim().isEmpty ? null : _bairroCtrl.text.trim(),
          'cidade':
              _cidadeCtrl.text.trim().isEmpty ? null : _cidadeCtrl.text.trim(),
          'estado':
              _estadoCtrl.text.trim().isEmpty ? null : _estadoCtrl.text.trim(),
          'cep':
              _somenteDigitos(_cepCtrl.text).isEmpty
                  ? null
                  : _somenteDigitos(_cepCtrl.text),
        },
        'observacao':
            _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      debugPrint(
        '[SelecionarFornecedor] Salvando... tipo=$_tipoCliente perfil=$_perfilRelacionamento nome="$nome"',
      );
      final ref = await _fs.collection('clientes').add(dados);
      debugPrint('[SelecionarFornecedor] Fornecedor salvo: ${ref.id}');

      await widget.onPlanRefreshed();

      if (mounted) {
        widget.onSalvo(FornecedorSelecionado(id: ref.id, nome: nome));
      }
    } catch (e) {
      debugPrint('Erro ao salvar fornecedor: $e');
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
    return AbsorbPointer(
      absorbing: _salvando,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionCard(
            icon: Icons.badge_outlined,
            title: 'Informações do Fornecedor',
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  _field(
                    controller: _nomeCtrl,
                    label: 'Nome *',
                    validator: _validaNome,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _label('Tipo de cadastro'),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pf', label: Text('Pessoa Física')),
                      ButtonSegment(
                        value: 'pj',
                        label: Text('Pessoa Jurídica'),
                      ),
                    ],
                    selected: {_tipoCliente},
                    onSelectionChanged:
                        (s) => setState(() => _tipoCliente = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  if (_tipoCliente == 'pf')
                    _field(
                      controller: _cpfCtrl,
                      label: 'CPF (opcional)',
                      hint: '000.000.000-00',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validaCPF,
                      textInputAction: TextInputAction.next,
                    )
                  else
                    Column(
                      children: [
                        _field(
                          controller: _cnpjCtrl,
                          label: 'CNPJ (opcional)',
                          hint: '00.000.000/0000-00',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: _validaCNPJ,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _razaoCtrl,
                          label: 'Razão Social (opcional)',
                          validator: _validaRazao,
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  _label('Relação com a empresa'),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'fornecedor',
                        label: Text('Fornecedor'),
                      ),
                      ButtonSegment(value: 'ambos', label: Text('Ambos')),
                    ],
                    selected: {_perfilRelacionamento},
                    onSelectionChanged:
                        (s) => setState(() => _perfilRelacionamento = s.first),
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          _SectionCard(
            icon: Icons.contact_mail_outlined,
            title: 'Contato',
            child: Column(
              children: [
                _field(
                  controller: _emailCtrl,
                  label: 'E-mail (opcional)',
                  validator: _validaEmail,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _telefoneCtrl,
                  label: 'Telefone (opcional)',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _whatsCtrl,
                  label: 'WhatsApp (opcional)',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _SectionCard(
            icon: Icons.location_on_outlined,
            title: 'Endereço (opcional)',
            child: Column(
              children: [
                _field(
                  controller: _ruaCtrl,
                  label: 'Rua',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _numeroCtrl,
                        label: 'Número',
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        controller: _complCtrl,
                        label: 'Complemento',
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _bairroCtrl,
                        label: 'Bairro',
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        controller: _cidadeCtrl,
                        label: 'Cidade',
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _estadoCtrl,
                        label: 'Estado',
                        hint: 'UF',
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        controller: _cepCtrl,
                        label: 'CEP',
                        hint: '00000-000',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _SectionCard(
            icon: Icons.note_outlined,
            title: 'Observações (opcional)',
            child: _field(
              controller: _obsCtrl,
              label: 'Observação',
              maxLines: 3,
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    String? label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    int? maxLines = 1,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        filled: true,
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon:
            controller.text.isEmpty
                ? null
                : IconButton(
                  tooltip: 'Limpar',
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _label(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
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
              'Você não tem permissão para cadastrar fornecedores.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Peça ao administrador para liberar “Cadastrar clientes/fornecedores”.',
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

/* =============================== UI BASE =============================== */

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
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
