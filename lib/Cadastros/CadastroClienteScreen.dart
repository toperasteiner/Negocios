import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CadastroClienteStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get headerGradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

class CadastroClienteScreen extends StatefulWidget {
  final String? clienteId; // null -> inclusão | not null -> edição
  const CadastroClienteScreen({super.key, this.clienteId});

  @override
  State<CadastroClienteScreen> createState() => _CadastroClienteScreenState();
}

class _CadastroClienteScreenState extends State<CadastroClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Controllers
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _whatsCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  // PF/PJ
  String _tipoCliente = 'pf';
  final _cpfCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _razaoCtrl = TextEditingController();

  // Relação com a empresa
  String _perfilRelacionamento =
      'cliente'; // 'cliente' | 'fornecedor' | 'ambos'

  // Endereço
  final _ruaCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();

  // Estado
  bool _carregando = false;
  bool _inicializando = true;
  bool _dirty = false;

  // UI/UX
  bool _expInfo = true;
  bool _expContato = true;
  bool _expEndereco = false;

  final _scroll = ScrollController();
  AutovalidateMode _autoValidate = AutovalidateMode.onUserInteraction;

  // Focus
  final _fNome = FocusNode();
  final _fEmail = FocusNode();
  final _fTel = FocusNode();
  final _fWhats = FocusNode();
  final _fCPF = FocusNode();
  final _fCNPJ = FocusNode();
  final _fRazao = FocusNode();
  final _fRua = FocusNode();
  final _fNumero = FocusNode();
  final _fCompl = FocusNode();
  final _fBairro = FocusNode();
  final _fCidade = FocusNode();
  final _fEstado = FocusNode();
  final _fCEP = FocusNode();
  final _fObs = FocusNode();

  String? get _uid => _auth.currentUser?.uid;

  String? _validaRazao(String? v) {
    if (_tipoCliente != 'pj') return null;
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe a Razão Social';
    if (s.length < 3) return 'Razão Social muito curta';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _carregarSeEdicao();

    _telefoneCtrl.addListener(
      () => _aplicarMascaraLive(_telefoneCtrl, _formataTelefone),
    );
    _whatsCtrl.addListener(
      () => _aplicarMascaraLive(_whatsCtrl, _formataTelefone),
    );
    _cpfCtrl.addListener(() => _aplicarMascaraLive(_cpfCtrl, _formataCPF));
    _cnpjCtrl.addListener(() => _aplicarMascaraLive(_cnpjCtrl, _formataCNPJ));
    _cepCtrl.addListener(() => _aplicarMascaraLive(_cepCtrl, _formataCEP));

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
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _telefoneCtrl.dispose();
    _whatsCtrl.dispose();
    _cpfCtrl.dispose();
    _cnpjCtrl.dispose();
    _razaoCtrl.dispose();
    _ruaCtrl.dispose();
    _numeroCtrl.dispose();
    _complCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _estadoCtrl.dispose();
    _cepCtrl.dispose();
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _obsCtrl.dispose();
    _scroll.dispose();

    _fNome.dispose();
    _fEmail.dispose();
    _fTel.dispose();
    _fWhats.dispose();
    _fCPF.dispose();
    _fCNPJ.dispose();
    _fRazao.dispose();
    _fRua.dispose();
    _fNumero.dispose();
    _fCompl.dispose();
    _fBairro.dispose();
    _fCidade.dispose();
    _fEstado.dispose();
    _fCEP.dispose();
    _fObs.dispose();
    super.dispose();
  }

  // ----------------- Helpers de máscara -----------------
  String _somenteDigitos(String v) => v.replaceAll(RegExp(r'\D'), '');
  void _aplicarMascaraLive(
    TextEditingController c,
    String Function(String) fn,
  ) {
    final formatado = fn(_somenteDigitos(c.text));
    if (c.text != formatado) {
      final sel = formatado.length;
      c.value = TextEditingValue(
        text: formatado,
        selection: TextSelection.collapsed(offset: sel),
      );
    }
  }

  String _formataTelefone(String d) {
    if (d.isEmpty) return '';
    if (d.length <= 2) return '($d';
    if (d.length <= 6) return '(${d.substring(0, 2)}) ${d.substring(2)}';
    if (d.length <= 10)
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    final x = d.substring(0, 11);
    return '(${x.substring(0, 2)}) ${x.substring(2, 7)}-${x.substring(7)}';
  }

  String _formataCPF(String d) {
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

  String _formataCNPJ(String d) {
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

  String _formataCEP(String d) {
    final x = d.length > 8 ? d.substring(0, 8) : d;
    if (x.isEmpty) return '';
    if (x.length <= 5) return x;
    return '${x.substring(0, 5)}-${x.substring(5)}';
  }

  // ----------------- USER LOOKUP ROBUSTO -----------------
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

    // 2) por emailKey
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

  /// Retorna (ownerId, companyId) — multiempresa estrito exige companyId
  Future<(String?, String?)> _resolveOwnerAndCompany() async {
    final me = await _loadCurrentUserRecord();
    if (me == null) return (null, null);

    final role = (me['role'] ?? '').toString().toLowerCase();
    final companyId = (me['companyId'] ?? '').toString().trim();

    // 🔁 multiempresa estrito: companyId obrigatório (inclusive para admin)
    if (companyId.isEmpty) return (null, null);

    if (role == 'admin') {
      return (companyId, companyId);
    }
    if (role == 'funcionario') {
      return (companyId, companyId);
    }
    return (null, null);
  }

  /// Gate de permissão para criar cliente — multiempresa estrito
  Future<bool> _temPermissaoCriarCliente() async {
    final me = await _loadCurrentUserRecord();
    if (me == null) return false;

    final role = (me['role'] ?? '').toString().toLowerCase();
    final companyId = (me['companyId'] ?? '').toString().trim();
    final perms = (me['permissions'] ?? {}) as Map<String, dynamic>;

    bool _p(String k) => (perms[k] ?? me[k] ?? false) == true;

    // 🔁 exige vinculação a empresa para qualquer perfil
    if (companyId.isEmpty) return false;

    if (role == 'admin') return true;
    if (role == 'funcionario') {
      // exige permissão de cadastro OU ver clientes de outros
      final podePorPerm =
          _p('canRegisterClientsSuppliers') || _p('canSeeOthersClients');
      return podePorPerm;
    }
    return false;
  }

  // ----------------- Carregar Edição -----------------
  Future<void> _carregarSeEdicao() async {
    if (widget.clienteId == null) {
      setState(() => _inicializando = false);
      return;
    }
    try {
      final doc = await _fs.collection('clientes').doc(widget.clienteId).get();
      if (doc.exists) {
        final d = doc.data() as Map<String, dynamic>;
        _tipoCliente = (d['tipoCliente'] ?? 'pf').toString();
        _perfilRelacionamento =
            (d['perfilRelacionamento'] ?? 'cliente').toString();

        _nomeCtrl.text = (d['nome'] ?? '').toString();
        _emailCtrl.text = (d['email'] ?? '').toString();
        _telefoneCtrl.text = _formataTelefone(
          _somenteDigitos((d['telefone'] ?? '').toString()),
        );
        _whatsCtrl.text = _formataTelefone(
          _somenteDigitos((d['whatsapp'] ?? '').toString()),
        );
        _cpfCtrl.text = _formataCPF(
          _somenteDigitos((d['cpf'] ?? '').toString()),
        );
        _cnpjCtrl.text = _formataCNPJ(
          _somenteDigitos((d['cnpj'] ?? '').toString()),
        );
        _razaoCtrl.text = (d['razaoSocial'] ?? '').toString();

        final end = (d['endereco'] ?? {}) as Map<String, dynamic>;
        _ruaCtrl.text = (end['rua'] ?? '').toString();
        _numeroCtrl.text = (end['numero'] ?? '').toString();
        _complCtrl.text = (end['complemento'] ?? '').toString();
        _bairroCtrl.text = (end['bairro'] ?? '').toString();
        _cidadeCtrl.text = (end['cidade'] ?? '').toString();
        _estadoCtrl.text = (end['estado'] ?? '').toString();
        _cepCtrl.text = _formataCEP(
          _somenteDigitos((end['cep'] ?? '').toString()),
        );

        _obsCtrl.text = (d['observacao'] ?? '').toString();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cliente não encontrado.')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _inicializando = false);
    }
  }

  // ----------------- Salvar -----------------
  Future<void> _salvar() async {
    if (_uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login para salvar clientes.')),
      );
      return;
    }

    // Gate de permissão
    if (!await _temPermissaoCriarCliente()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para cadastrar clientes.')),
      );
      return;
    }

    final valid = _formKey.currentState!.validate();
    if (!valid) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }

    final dados = <String, dynamic>{
      'tipoCliente': _tipoCliente,
      'perfilRelacionamento': _perfilRelacionamento,
      'isCliente':
          _perfilRelacionamento == 'cliente' ||
          _perfilRelacionamento == 'ambos',
      'isFornecedor':
          _perfilRelacionamento == 'fornecedor' ||
          _perfilRelacionamento == 'ambos',
      'nome': _nomeCtrl.text.trim(),
      'nomeLower': _nomeCtrl.text.trim().toLowerCase(),
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
              ? (_razaoCtrl.text.trim().isEmpty ? null : _razaoCtrl.text.trim())
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
      'observacao': _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    setState(() => _carregando = true);
    try {
      if (widget.clienteId == null) {
        final (ownerId, companyId) = await _resolveOwnerAndCompany();
        // 🔁 owner/company obrigatórios
        if (ownerId == null || companyId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sem empresa vinculada: configure o companyId no cadastro do usuário.',
                ),
              ),
            );
          }
          setState(() => _carregando = false);
          return;
        }

        await _fs.collection('clientes').add({
          ...dados,
          'ownerId': ownerId, // 🔁 mantém compatibilidade
          'companyId': companyId, // ✅ chave de escopo multiempresa
          'userId': _uid, // ✅ quem criou (UID do logado)
          'createdByUid': _uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _fs.collection('clientes').doc(widget.clienteId).update(dados);
      }

      if (mounted) {
        _dirty = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.clienteId == null
                  ? 'Cliente cadastrado com sucesso.'
                  : 'Cliente atualizado com sucesso.',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // ----------------- Validações -----------------
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
    if (d.isEmpty) return null; // ✅ opcional
    if (d.length != 11) return 'CPF deve ter 11 dígitos';
    return null;
  }

  String? _validaCNPJ(String? v) {
    if (_tipoCliente != 'pj') return null;
    final d = _somenteDigitos(v ?? '');
    if (d.isEmpty) return null; // ✅ opcional
    if (d.length != 14) return 'CNPJ deve ter 14 dígitos';
    return null;
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    if (_inicializando) {
      return const Scaffold(
        backgroundColor: CadastroClienteStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (!_dirty) return true;
        final sair = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('Descartar alterações?'),
                content: const Text(
                  'Você tem alterações não salvas. Deseja sair mesmo assim?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: CadastroClienteStyle.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Sair'),
                  ),
                ],
              ),
        );
        return sair ?? false;
      },
      child: Scaffold(
        backgroundColor: CadastroClienteStyle.bg,
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CadastroClienteStyle.primary,
                      side: const BorderSide(
                        color: CadastroClienteStyle.primary,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient:
                          _carregando
                              ? null
                              : CadastroClienteStyle.headerGradient,
                      color: _carregando ? const Color(0xFFE5E7EB) : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow:
                          _carregando
                              ? null
                              : [
                                BoxShadow(
                                  color: CadastroClienteStyle.primary
                                      .withOpacity(0.20),
                                  blurRadius: 16,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _carregando ? null : _salvar,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_carregando)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.save_outlined,
                                  color: Colors.white,
                                ),
                              const SizedBox(width: 8),
                              Text(
                                widget.clienteId == null
                                    ? 'Salvar'
                                    : 'Atualizar',
                                style: TextStyle(
                                  color:
                                      _carregando
                                          ? CadastroClienteStyle.muted
                                          : Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: _carregando,
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _autoValidate,
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                        children: [
                          _SectionCard(
                            icon: Icons.badge_outlined,
                            title: 'Informações',
                            initiallyExpanded: _expInfo,
                            onExpansionChanged:
                                (v) => setState(() => _expInfo = v),
                            child: Column(
                              children: [
                                _field(
                                  controller: _nomeCtrl,
                                  focus: _fNome,
                                  next: _fEmail,
                                  label: 'Nome *',
                                  hint: 'Ex.: Maria da Silva',
                                  validator: _validaNome,
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: Icons.person_outline_rounded,
                                ),
                                const SizedBox(height: 14),
                                _label('Tipo *'),
                                const SizedBox(height: 8),
                                _segmented(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'pf',
                                      icon: Icon(Icons.person_outline),
                                      label: Text('Pessoa Física'),
                                    ),
                                    ButtonSegment(
                                      value: 'pj',
                                      icon: Icon(Icons.business_outlined),
                                      label: Text('Pessoa Jurídica'),
                                    ),
                                  ],
                                  selected: _tipoCliente,
                                  onChanged: (value) {
                                    setState(() {
                                      _tipoCliente = value;
                                      _dirty = true;
                                    });
                                  },
                                ),
                                const SizedBox(height: 14),
                                if (_tipoCliente == 'pf') ...[
                                  _field(
                                    controller: _cpfCtrl,
                                    focus: _fCPF,
                                    next: _fEmail,
                                    label: 'CPF',
                                    hint: '000.000.000-00',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: _validaCPF,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.badge_outlined,
                                  ),
                                ] else ...[
                                  _field(
                                    controller: _cnpjCtrl,
                                    focus: _fCNPJ,
                                    next: _fRazao,
                                    label: 'CNPJ',
                                    hint: '00.000.000/0000-00',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: _validaCNPJ,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.apartment_outlined,
                                  ),
                                  const SizedBox(height: 14),
                                  _field(
                                    controller: _razaoCtrl,
                                    focus: _fRazao,
                                    next: _fEmail,
                                    label: 'Razão Social',
                                    hint: 'Ex.: Minha Empresa LTDA',
                                    validator: _validaRazao,
                                    textInputAction: TextInputAction.next,
                                    prefixIcon: Icons.domain_outlined,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _label('Relação com a empresa *'),
                                const SizedBox(height: 8),
                                _segmented(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'cliente',
                                      icon: Icon(Icons.person_outline_rounded),
                                      label: Text('Cliente'),
                                    ),
                                    ButtonSegment(
                                      value: 'fornecedor',
                                      icon: Icon(Icons.local_shipping_outlined),
                                      label: Text('Fornecedor'),
                                    ),
                                    ButtonSegment(
                                      value: 'ambos',
                                      icon: Icon(Icons.sync_alt_rounded),
                                      label: Text('Ambos'),
                                    ),
                                  ],
                                  selected: _perfilRelacionamento,
                                  compact: true,
                                  onChanged: (value) {
                                    setState(() {
                                      _perfilRelacionamento = value;
                                      _dirty = true;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            icon: Icons.contact_mail_outlined,
                            title: 'Contato',
                            initiallyExpanded: _expContato,
                            onExpansionChanged:
                                (v) => setState(() => _expContato = v),
                            child: Column(
                              children: [
                                _field(
                                  controller: _emailCtrl,
                                  focus: _fEmail,
                                  next: _fTel,
                                  label: 'E-mail',
                                  hint: 'nome@dominio.com',
                                  keyboardType: TextInputType.emailAddress,
                                  validator: _validaEmail,
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: Icons.email_outlined,
                                ),
                                const SizedBox(height: 14),
                                _field(
                                  controller: _telefoneCtrl,
                                  focus: _fTel,
                                  next: _fWhats,
                                  label: 'Telefone',
                                  hint: '(11) 91234-5678',
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: Icons.phone_outlined,
                                ),
                                const SizedBox(height: 14),
                                _field(
                                  controller: _whatsCtrl,
                                  focus: _fWhats,
                                  next: _fRua,
                                  label: 'WhatsApp',
                                  hint: '(11) 91234-5678',
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: Icons.chat_outlined,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SectionCard(
                            icon: Icons.location_on_outlined,
                            title: 'Endereço',
                            initiallyExpanded: _expEndereco,
                            onExpansionChanged:
                                (v) => setState(() => _expEndereco = v),
                            child: Column(
                              children: [
                                _field(
                                  controller: _ruaCtrl,
                                  focus: _fRua,
                                  next: _fNumero,
                                  label: 'Rua',
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: Icons.signpost_outlined,
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _field(
                                        controller: _numeroCtrl,
                                        focus: _fNumero,
                                        next: _fCompl,
                                        label: 'Número',
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.next,
                                        prefixIcon: Icons.pin_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: _field(
                                        controller: _complCtrl,
                                        focus: _fCompl,
                                        next: _fBairro,
                                        label: 'Complemento',
                                        textInputAction: TextInputAction.next,
                                        prefixIcon:
                                            Icons.add_home_work_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _field(
                                        controller: _bairroCtrl,
                                        focus: _fBairro,
                                        next: _fCidade,
                                        label: 'Bairro',
                                        textInputAction: TextInputAction.next,
                                        prefixIcon:
                                            Icons.location_city_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _field(
                                        controller: _cidadeCtrl,
                                        focus: _fCidade,
                                        next: _fEstado,
                                        label: 'Cidade',
                                        textInputAction: TextInputAction.next,
                                        prefixIcon: Icons.location_city_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _field(
                                        controller: _estadoCtrl,
                                        focus: _fEstado,
                                        next: _fCEP,
                                        label: 'Estado',
                                        hint: 'UF',
                                        maxLength: 2,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        buildCounter:
                                            (
                                              _, {
                                              required currentLength,
                                              required isFocused,
                                              maxLength,
                                            }) => const SizedBox.shrink(),
                                        textInputAction: TextInputAction.next,
                                        prefixIcon: Icons.map_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: _field(
                                        controller: _cepCtrl,
                                        focus: _fCEP,
                                        next: _fObs,
                                        label: 'CEP',
                                        hint: '00000-000',
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        textInputAction: TextInputAction.next,
                                        prefixIcon:
                                            Icons.markunread_mailbox_outlined,
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
                            title: 'Observações',
                            initiallyExpanded: true,
                            child: _field(
                              controller: _obsCtrl,
                              focus: _fObs,
                              label: 'Observação',
                              hint: 'Anote algo importante…',
                              maxLines: 3,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _salvar(),
                              prefixIcon: Icons.notes_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_carregando) const PositionedFillOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titulo =
        widget.clienteId == null
            ? 'Novo cliente/fornecedor'
            : 'Editar cliente/fornecedor';

    return Container(
      decoration: BoxDecoration(
        gradient: CadastroClienteStyle.headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      child: Row(
        children: [
          _HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _HeaderIconButton(
            icon: Icons.check_rounded,
            onTap: _carregando ? () {} : _salvar,
          ),
        ],
      ),
    );
  }

  Widget _segmented({
    required List<ButtonSegment<String>> segments,
    required String selected,
    required ValueChanged<String> onChanged,
    bool compact = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        style: ButtonStyle(
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
          textStyle: const MaterialStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return CadastroClienteStyle.primary.withOpacity(0.10);
            }
            return Colors.white;
          }),
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return CadastroClienteStyle.primary;
            }
            return CadastroClienteStyle.muted;
          }),
          side: MaterialStateProperty.resolveWith((states) {
            return BorderSide(
              color:
                  states.contains(MaterialState.selected)
                      ? CadastroClienteStyle.primary
                      : const Color(0xFFE2E8F0),
            );
          }),
        ),
        segments: segments,
        selected: {selected},
        onSelectionChanged: (set) => onChanged(set.first),
        showSelectedIcon: false,
      ),
    );
  }

  // ---------- Widgets auxiliares ----------
  Widget _field({
    required TextEditingController controller,
    FocusNode? focus,
    FocusNode? next,
    String? label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    int? maxLines = 1,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    Widget Function(
      BuildContext, {
      required int currentLength,
      required bool isFocused,
      int? maxLength,
    })?
    buildCounter,
    void Function(String)? onSubmitted,
    IconData? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focus,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      onFieldSubmitted: (v) {
        if (onSubmitted != null) onSubmitted(v);
        if (next != null) FocusScope.of(context).requestFocus(next);
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: CadastroClienteStyle.muted),
        prefixIcon:
            prefixIcon == null
                ? null
                : Icon(prefixIcon, color: CadastroClienteStyle.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: CadastroClienteStyle.primary,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CadastroClienteStyle.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: CadastroClienteStyle.red,
            width: 1.4,
          ),
        ),
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
                  icon: const Icon(Icons.close_rounded),
                ),
      ),
      onChanged: (_) => setState(() {}),
      buildCounter: buildCounter,
    );
  }

  Widget _label(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(
        color: CadastroClienteStyle.text,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: CadastroClienteStyle.softShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpansionChanged,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: CadastroClienteStyle.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: CadastroClienteStyle.primary, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: CadastroClienteStyle.text,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          iconColor: CadastroClienteStyle.primary,
          collapsedIconColor: CadastroClienteStyle.muted,
          children: [child],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

// Overlay simples para loading
class PositionedFillOverlay extends StatelessWidget {
  const PositionedFillOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ColoredBox(
        color: Color(0x66FFFFFF),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
