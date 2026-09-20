import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PessoaSelecionada {
  final String id;
  final String nome;
  const PessoaSelecionada({required this.id, required this.nome});
}

/// Modo do seletor: lista quem?
enum PessoaFiltro { clientes, fornecedores, ambos }

class SelecionarPessoaSheet extends StatefulWidget {
  /// Define o filtro padrão da aba Catálogo e o perfil ao salvar na aba Cadastrar
  final PessoaFiltro filtroInicial;

  /// Seleção inicial (opcional)
  final PessoaSelecionada? initial;

  const SelecionarPessoaSheet({
    super.key,
    this.filtroInicial = PessoaFiltro.ambos, // padrão: mostrar TODOS
    this.initial,
  });

  @override
  State<SelecionarPessoaSheet> createState() => _SelecionarPessoaSheetState();
}

class _SelecionarPessoaSheetState extends State<SelecionarPessoaSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  // chave para acionar salvar() na aba de cadastro
  final _cadKey = GlobalKey<_CadastrarPessoaTabState>();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== Escopo multiempresa =====
  String? _companyId; // users.companyId (obrigatório)
  bool _loadingScope = true;
  String? _scopeError;

  // Estado de UI
  PessoaFiltro _filtro = PessoaFiltro.ambos;
  PessoaSelecionada? _selecionado;

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial;
    _selecionado = widget.initial;
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {}); // atualiza a bottom bar
    });
    _initScope();
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
      setState(() {
        _companyId = companyId.isEmpty ? null : companyId; // 🔁 exige companyId
        _loadingScope = false;
        _scopeError =
            _companyId == null
                ? 'Usuário sem companyId vinculado. Associe uma empresa ao usuário.'
                : null;
      });
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

    // 1) por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return (byUid.data() ?? {}) as Map<String, dynamic>;
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
        if (q.docs.isNotEmpty) return q.docs.first.data();
      } catch (_) {}
    }
    return null;
  }

  void _concluirSelecao() {
    if (_selecionado != null) {
      Navigator.pop(context, _selecionado);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
            title: const Text('Selecionar pessoa'),
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

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Selecionar pessoa'),
          bottom: TabBar(
            controller: _tab,
            tabs: const [
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Catálogo'),
              Tab(
                icon: Icon(Icons.person_add_alt_1_outlined),
                text: 'Cadastrar',
              ),
            ],
          ),
        ),

        // Barra inferior única, muda a ação conforme a aba
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child:
                _tab.index == 0
                    // Catálogo: habilita somente com pessoa selecionada
                    ? FilledButton.icon(
                      onPressed: _selecionado == null ? null : _concluirSelecao,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Adicionar esta pessoa'),
                    )
                    // Cadastrar: chama salvar() na aba de cadastro via GlobalKey
                    : FilledButton.icon(
                      onPressed: () {
                        final st = _cadKey.currentState;
                        if (st == null || st._salvando) return;
                        st._salvar();
                      },
                      icon:
                          (_cadKey.currentState?._salvando ?? false)
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.check_rounded),
                      label: const Text('Adicionar esta pessoa'),
                    ),
          ),
        ),

        body: TabBarView(
          controller: _tab,
          children: [
            _CatalogoPessoasTab(
              companyId: companyId, // 🔁 usa companyId como escopo
              filtro: _filtro,
              onFiltroChanged: (f) => setState(() => _filtro = f),
              onEscolhido: (p) => setState(() => _selecionado = p),
              selecionado: _selecionado,
            ),
            _CadastrarPessoaTab(
              key: _cadKey, // chave para acionar salvar() e ler _salvando
              companyId: companyId, // 🔁 escopo multiempresa
              createdByUid: _auth.currentUser?.uid,
              filtroInicial: _filtro,
              onSalvo: (novo) {
                Navigator.pop(context, novo); // já volta com a pessoa
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================ ABA CATÁLOGO ============================ */

class _CatalogoPessoasTab extends StatefulWidget {
  final String companyId; // 🔁
  final PessoaFiltro filtro;
  final void Function(PessoaFiltro) onFiltroChanged;
  final void Function(PessoaSelecionada p) onEscolhido;
  final PessoaSelecionada? selecionado;

  const _CatalogoPessoasTab({
    required this.companyId,
    required this.filtro,
    required this.onFiltroChanged,
    required this.onEscolhido,
    required this.selecionado,
  });

  @override
  State<_CatalogoPessoasTab> createState() => _CatalogoPessoasTabState();
}

class _CatalogoPessoasTabState extends State<_CatalogoPessoasTab> {
  final _fs = FirebaseFirestore.instance;
  final _buscaCtrl = TextEditingController();

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Base: filtra por companyId (multiempresa)
    Query q = _fs
        .collection('clientes')
        .where('companyId', isEqualTo: widget.companyId) // 🔁 era userId
        .orderBy('nomeLower');

    // Filtros de papel
    if (widget.filtro == PessoaFiltro.clientes) {
      q = q.where('isCliente', isEqualTo: true);
    } else if (widget.filtro == PessoaFiltro.fornecedores) {
      q = q.where('isFornecedor', isEqualTo: true);
    }

    return Column(
      children: [
        // Filtro e busca
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscaCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar por nome ou e-mail',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<PessoaFiltro>(
                tooltip: 'Filtrar',
                onSelected: widget.onFiltroChanged,
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: PessoaFiltro.clientes,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.person_outline),
                          title: Text('Clientes'),
                        ),
                      ),
                      PopupMenuItem(
                        value: PessoaFiltro.fornecedores,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.store_mall_directory_outlined),
                          title: Text('Fornecedores'),
                        ),
                      ),
                      PopupMenuItem(
                        value: PessoaFiltro.ambos,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.all_inclusive),
                          title: Text('Todos'),
                        ),
                      ),
                    ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.filter_alt_outlined),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }

              final filtroTxt = _buscaCtrl.text.trim().toLowerCase();
              final docs =
                  (snap.data?.docs ?? []).where((d) {
                    final m = d.data() as Map<String, dynamic>;
                    final nome = (m['nome'] ?? '').toString().toLowerCase();
                    final email = (m['email'] ?? '').toString().toLowerCase();
                    return filtroTxt.isEmpty ||
                        nome.contains(filtroTxt) ||
                        email.contains(filtroTxt);
                  }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhuma pessoa encontrada.'),
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

                  // badge (cliente, fornecedor, ambos)
                  final isC = m['isCliente'] == true;
                  final isF = m['isFornecedor'] == true;
                  Widget? badge;
                  if (isC && isF) {
                    badge = _chip('Ambos');
                  } else if (isC) {
                    badge = _chip('Cliente');
                  } else if (isF) {
                    badge = _chip('Fornecedor');
                  }

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
                            PessoaSelecionada(id: id, nome: nome),
                          ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (badge != null) badge,
                        ],
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

  Widget _chip(String text) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Chip(
      label: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      side: BorderSide.none,
    ),
  );
}

/* ============================ ABA CADASTRAR ============================ */

class _CadastrarPessoaTab extends StatefulWidget {
  final void Function(PessoaSelecionada novo) onSalvo;
  final String companyId; // 🔁 obrigatório
  final String? createdByUid;
  final PessoaFiltro filtroInicial;

  const _CadastrarPessoaTab({
    super.key,
    required this.onSalvo,
    required this.companyId,
    required this.createdByUid,
    required this.filtroInicial,
  });

  @override
  State<_CadastrarPessoaTab> createState() => _CadastrarPessoaTabState();
}

class _CadastrarPessoaTabState extends State<_CadastrarPessoaTab> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;

  // Controllers
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _whatsCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _razaoCtrl = TextEditingController();
  final _ruaCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();

  String _tipoPessoa = 'pf'; // 'pf' | 'pj'
  late PessoaFiltro _perfil; // clientes | fornecedores | ambos

  bool _salvando = false; // lido pelo pai para spinner na bottom bar

  // Máscaras simples
  String _digits(String v) => v.replaceAll(RegExp(r'\D'), '');
  void _maskLive(TextEditingController c, String Function(String) fn) {
    final f = fn(_digits(c.text));
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
    _perfil = widget.filtroInicial;
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

  // Validações mínimas
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
    if (_tipoPessoa != 'pf') return null;
    final d = _digits(v ?? '');
    if (d.isEmpty) return null;
    if (d.length != 11) return 'CPF deve ter 11 dígitos';
    return null;
  }

  String? _validaCNPJ(String? v) {
    if (_tipoPessoa != 'pj') return null;
    final d = _digits(v ?? '');
    if (d.isEmpty) return null;
    if (d.length != 14) return 'CNPJ deve ter 14 dígitos';
    return null;
  }

  // chamado pela tela pai (via GlobalKey)
  Future<void> _salvar() async {
    if (widget.companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível determinar o escopo.')),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final nome = _nomeCtrl.text.trim();
    if (nome.length < 2) return;

    setState(() => _salvando = true);
    try {
      final isCli =
          _perfil == PessoaFiltro.clientes || _perfil == PessoaFiltro.ambos;
      final isFor =
          _perfil == PessoaFiltro.fornecedores || _perfil == PessoaFiltro.ambos;

      final dados = <String, dynamic>{
        // ESCOPO multiempresa
        'companyId': widget.companyId, // 🔁 chave oficial
        'userId': widget.createdByUid, // legado p/ listagens antigas
        'createdByUid': widget.createdByUid,

        // Dados
        'tipoCliente': _tipoPessoa, // compatibilidade (pf/pj)
        'perfilRelacionamento':
            isCli && isFor ? 'ambos' : (isCli ? 'cliente' : 'fornecedor'),
        'isCliente': isCli,
        'isFornecedor': isFor,

        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'telefone':
            _digits(_telefoneCtrl.text).isEmpty
                ? null
                : _digits(_telefoneCtrl.text),
        'whatsapp':
            _digits(_whatsCtrl.text).isEmpty ? null : _digits(_whatsCtrl.text),
        'cpf':
            _tipoPessoa == 'pf'
                ? (_digits(_cpfCtrl.text).isEmpty
                    ? null
                    : _digits(_cpfCtrl.text))
                : null,
        'cnpj':
            _tipoPessoa == 'pj'
                ? (_digits(_cnpjCtrl.text).isEmpty
                    ? null
                    : _digits(_cnpjCtrl.text))
                : null,
        'razaoSocial':
            _tipoPessoa == 'pj'
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
          'cep': _digits(_cepCtrl.text).isEmpty ? null : _digits(_cepCtrl.text),
        },
        'observacao':
            _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final ref = await _fs.collection('clientes').add(dados);
      if (mounted) {
        widget.onSalvo(PessoaSelecionada(id: ref.id, nome: nome));
      }
    } catch (e) {
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
        // sem botões internos — ação na bottom bar
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionCard(
            icon: Icons.badge_outlined,
            title: 'Informações',
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
                  _label('Perfil'),
                  const SizedBox(height: 6),
                  SegmentedButton<PessoaFiltro>(
                    segments: const [
                      ButtonSegment(
                        value: PessoaFiltro.clientes,
                        label: Text('Cliente'),
                      ),
                      ButtonSegment(
                        value: PessoaFiltro.fornecedores,
                        label: Text('Fornecedor'),
                      ),
                      ButtonSegment(
                        value: PessoaFiltro.ambos,
                        label: Text('Ambos'),
                      ),
                    ],
                    selected: {_perfil},
                    onSelectionChanged:
                        (s) => setState(() => _perfil = s.first),
                    showSelectedIcon: false,
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
                    selected: {_tipoPessoa},
                    onSelectionChanged:
                        (s) => setState(() => _tipoPessoa = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  if (_tipoPessoa == 'pf')
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
                          textInputAction: TextInputAction.next,
                        ),
                      ],
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ---------- widgets auxiliares ----------
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
