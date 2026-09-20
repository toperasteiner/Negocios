import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'HorarioProfissionalScreen.dart';

class ProfissionaisAgendaScreen extends StatefulWidget {
  const ProfissionaisAgendaScreen({super.key});

  @override
  State<ProfissionaisAgendaScreen> createState() =>
      _ProfissionaisAgendaScreenState();
}

class _ProfissionaisAgendaScreenState extends State<ProfissionaisAgendaScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _carregando = true;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  /* ==========================================================
     HORÁRIO DO PROFISSIONAL
     ========================================================== */

  Future<void> _abrirHorarioProfissional(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_companyId == null || _companyId!.isEmpty) {
      _mensagem('Empresa não identificada.');
      return;
    }

    final data = doc.data();

    final nome = (data['displayName'] ?? 'Profissional').toString().trim();

    final ativo = (data['active'] ?? true) == true;

    final ativoAgendamento = (data['ativoAgendamento'] ?? false) == true;

    if (!ativo) {
      _mensagem(
        'Este profissional está inativo. Ative o cadastro antes de configurar os horários.',
      );
      return;
    }

    if (!ativoAgendamento) {
      _mensagem(
        'Ative a opção "Ativo para agendamento" antes de configurar os horários.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => HorarioProfissionalScreen(
              profissionalId: doc.id,
              profissionalNome: nome.isEmpty ? 'Profissional' : nome,
              companyId: _companyId!,
            ),
      ),
    );
  }

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> _inicializar() async {
    try {
      final companyId = await _descobrirCompanyId();

      if (!mounted) return;

      setState(() {
        _companyId = companyId;
        _carregando = false;
      });

      if (companyId == null || companyId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível identificar a empresa.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao identificar empresa: $e')),
      );
    }
  }

  /* ==========================================================
     IDENTIFICAR EMPRESA
     ========================================================== */

  Future<String?> _descobrirCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) return null;

    try {
      final doc = await _fs.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        final companyId = (data['companyId'] ?? '').toString().trim();

        if (companyId.isNotEmpty) {
          return companyId;
        }
      }
    } catch (_) {}

    final email = (user.email ?? '').trim().toLowerCase();

    if (email.isEmpty) return null;

    final query =
        await _fs
            .collection('users')
            .where('emailKey', isEqualTo: email)
            .limit(1)
            .get();

    if (query.docs.isEmpty) return null;

    final data = query.docs.first.data();

    final companyId = (data['companyId'] ?? '').toString().trim();

    return companyId.isEmpty ? null : companyId;
  }

  /* ==========================================================
     CONSULTA
     ========================================================== */

  Query<Map<String, dynamic>> _queryProfissionais() {
    return _fs.collection('users').where('companyId', isEqualTo: _companyId);
  }

  /* ==========================================================
     CADASTRO
     ========================================================== */

  Future<void> _novoProfissional() async {
    if (_companyId == null || _companyId!.isEmpty) {
      _mensagem('Empresa não identificada.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfissionalAgendaFormScreen(companyId: _companyId!),
      ),
    );
  }

  Future<void> _editarProfissional(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_companyId == null || _companyId!.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ProfissionalAgendaFormScreen(
              companyId: _companyId!,
              userDocId: doc.id,
              initialData: doc.data(),
            ),
      ),
    );
  }

  void _mensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: AgendaProfissionaisStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AgendaProfissionaisStyle.bg,

      body: Column(
        children: [
          _AgendaPageHeader(
            title: 'Profissionais',
            subtitle:
                'Cadastre e configure os profissionais que poderão receber agendamentos.',
            icon: Icons.people_alt_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),

          Expanded(
            child:
                _companyId == null || _companyId!.isEmpty
                    ? _empresaNaoIdentificada()
                    : Column(
                      children: [
                        _cabecalho(),

                        Expanded(
                          child: StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: _queryProfissionais().snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              if (snapshot.hasError) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Erro ao carregar profissionais:\n${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AgendaProfissionaisStyle.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final docs = snapshot.data?.docs ?? [];

                              if (docs.isEmpty) {
                                return _estadoVazio();
                              }

                              final profissionais = [...docs];

                              profissionais.sort((a, b) {
                                final nomeA =
                                    (a.data()['displayName'] ?? '')
                                        .toString()
                                        .toLowerCase();

                                final nomeB =
                                    (b.data()['displayName'] ?? '')
                                        .toString()
                                        .toLowerCase();

                                return nomeA.compareTo(nomeB);
                              });

                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  100,
                                ),
                                itemCount: profissionais.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  return _cardProfissional(
                                    profissionais[index],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),

      floatingActionButton:
          _companyId == null || _companyId!.isEmpty
              ? null
              : FloatingActionButton.extended(
                backgroundColor: AgendaProfissionaisStyle.primary,
                foregroundColor: Colors.white,
                onPressed: _novoProfissional,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text(
                  'Novo profissional',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
    );
  }

  /* ==========================================================
     CABEÇALHO INTERNO
     ========================================================== */

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaProfissionaisStyle.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AgendaIconBadge(
            icon: Icons.people_alt_outlined,
            color: AgendaProfissionaisStyle.primary,
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profissionais da agenda',
                  style: TextStyle(
                    color: AgendaProfissionaisStyle.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                SizedBox(height: 5),

                Text(
                  'Cadastre as pessoas que poderão receber agendamentos dos seus clientes.',
                  style: TextStyle(
                    color: AgendaProfissionaisStyle.muted,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Material(
            color: AgendaProfissionaisStyle.primary.withOpacity(0.09),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _novoProfissional,
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.add_rounded,
                  color: AgendaProfissionaisStyle.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     CARD PROFISSIONAL
     ========================================================== */

  Widget _cardProfissional(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final nome = (data['displayName'] ?? '').toString().trim();

    final email = (data['email'] ?? '').toString().trim();

    final ativo = (data['active'] ?? true) == true;

    final ativoAgendamento = (data['ativoAgendamento'] ?? false) == true;

    final authUid = (data['authUid'] ?? '').toString().trim();

    final possuiAcesso = authUid.isNotEmpty;

    final disponivel = ativo && ativoAgendamento;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _editarProfissional(doc),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AgendaProfissionaisStyle.border),
          ),
          child: Row(
            children: [
              _AgendaIconBadge(
                icon: Icons.person_outline,
                color:
                    disponivel
                        ? AgendaProfissionaisStyle.green
                        : AgendaProfissionaisStyle.muted,
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Sem nome' : nome,
                      style: const TextStyle(
                        color: AgendaProfissionaisStyle.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),

                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AgendaProfissionaisStyle.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 9),

                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusTag(
                          ativo ? 'Ativo' : 'Inativo',
                          ativo
                              ? AgendaProfissionaisStyle.green
                              : AgendaProfissionaisStyle.red,
                        ),

                        _statusTag(
                          ativoAgendamento
                              ? 'Recebe agendamentos'
                              : 'Agenda desativada',
                          ativoAgendamento
                              ? AgendaProfissionaisStyle.primary
                              : AgendaProfissionaisStyle.muted,
                        ),

                        if (possuiAcesso)
                          _statusTag(
                            'Acesso ao sistema',
                            AgendaProfissionaisStyle.orange,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              PopupMenuButton<String>(
                tooltip: 'Opções',
                color: Colors.white,
                onSelected: (value) {
                  if (value == 'editar') {
                    _editarProfissional(doc);
                  }

                  if (value == 'horario') {
                    _abrirHorarioProfissional(doc);
                  }
                },
                itemBuilder:
                    (context) => const [
                      PopupMenuItem<String>(
                        value: 'editar',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: AgendaProfissionaisStyle.primary,
                            ),
                            SizedBox(width: 10),
                            Text('Editar profissional'),
                          ],
                        ),
                      ),

                      PopupMenuItem<String>(
                        value: 'horario',
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 20,
                              color: AgendaProfissionaisStyle.blue,
                            ),
                            SizedBox(width: 10),
                            Text('Horário de atendimento'),
                          ],
                        ),
                      ),
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusTag(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: cor,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /* ==========================================================
     ESTADO VAZIO
     ========================================================== */

  Widget _estadoVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AgendaIconBadgeLarge(
              icon: Icons.person_add_alt_1_outlined,
              color: AgendaProfissionaisStyle.primary,
            ),

            const SizedBox(height: 18),

            const Text(
              'Nenhum profissional cadastrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaProfissionaisStyle.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 7),

            const Text(
              'Cadastre os profissionais que poderão receber agendamentos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaProfissionaisStyle.muted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 20),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AgendaProfissionaisStyle.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _novoProfissional,
              icon: const Icon(Icons.add),
              label: const Text(
                'Cadastrar profissional',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empresaNaoIdentificada() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Não foi possível identificar a empresa.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AgendaProfissionaisStyle.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/* ============================================================
   FORMULÁRIO DO PROFISSIONAL
   ============================================================ */

class ProfissionalAgendaFormScreen extends StatefulWidget {
  final String companyId;

  final String? userDocId;

  final Map<String, dynamic>? initialData;

  const ProfissionalAgendaFormScreen({
    super.key,
    required this.companyId,
    this.userDocId,
    this.initialData,
  });

  @override
  State<ProfissionalAgendaFormScreen> createState() =>
      _ProfissionalAgendaFormScreenState();
}

class _ProfissionalAgendaFormScreenState
    extends State<ProfissionalAgendaFormScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();

  final _nomeCtrl = TextEditingController();

  final _emailCtrl = TextEditingController();

  bool _ativo = true;

  bool _ativoAgendamento = true;

  bool _salvando = false;

  bool get _editando => widget.userDocId != null;

  @override
  void initState() {
    super.initState();

    final data = widget.initialData;

    if (data != null) {
      _nomeCtrl.text = (data['displayName'] ?? '').toString();

      _emailCtrl.text = (data['email'] ?? '').toString();

      _ativo = (data['active'] ?? true) == true;

      _ativoAgendamento = (data['ativoAgendamento'] ?? true) == true;
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();

    super.dispose();
  }

  /* ==========================================================
     VALIDAÇÕES
     ========================================================== */

  String? _validarEmail(String? value) {
    final email = (value ?? '').trim();

    if (email.isEmpty) {
      return null;
    }

    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!regex.hasMatch(email)) {
      return 'Informe um e-mail válido.';
    }

    return null;
  }

  Future<bool> _emailJaExiste(String email) async {
    if (email.isEmpty) {
      return false;
    }

    final query =
        await _fs
            .collection('users')
            .where('emailKey', isEqualTo: email.toLowerCase())
            .get();

    for (final doc in query.docs) {
      if (_editando && doc.id == widget.userDocId) {
        continue;
      }

      return true;
    }

    return false;
  }

  /* ==========================================================
     PERMISSÕES
     ========================================================== */

  Map<String, dynamic> _permissoesZeradas() {
    return {
      'canAccountsPayable': false,
      'canAccountsPayableCancel': false,
      'canAccountsPayableEditOpen': false,
      'canAccountsPayableMarkPaid': false,

      'canAccountsReceivable': false,
      'canAccountsReceivableCancel': false,
      'canAccountsReceivableEditOpen': false,
      'canAccountsReceivableMarkPaid': false,

      'canAdjustStock': false,

      'canDashboardCashFlow': false,
      'canDashboardFinance': false,
      'canDashboardOrdersByPeriod': false,
      'canDashboardPayables': false,
      'canDashboardReceivables': false,
      'canDashboardSales': false,
      'canDashboardTopProducts': false,
      'canDashboardTopServices': false,

      'canManageCategories': false,
      'canManageGoals': false,
      'canManagePaymentCategories': false,
      'canManageProducts': false,
      'canManagePurchases': false,
      'canManageServices': false,

      'canRegisterClientsSuppliers': false,
      'canRegisterOrders': false,
    };
  }

  /* ==========================================================
     SALVAR
     ========================================================== */

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final nome = _nomeCtrl.text.trim();

    final email = _emailCtrl.text.trim().toLowerCase();

    if (await _emailJaExiste(email)) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Já existe um usuário cadastrado com este e-mail.'),
        ),
      );

      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      if (_editando) {
        await _atualizar(nome: nome, email: email);
      } else {
        await _criar(nome: nome, email: email);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editando
                ? 'Profissional atualizado com sucesso.'
                : 'Profissional cadastrado com sucesso.',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar profissional: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  /* ==========================================================
     CRIAR
     ========================================================== */

  Future<void> _criar({required String nome, required String email}) async {
    final dados = <String, dynamic>{
      'active': _ativo,

      'authUid': null,

      'companyId': widget.companyId,

      'createdAt': FieldValue.serverTimestamp(),

      'displayName': nome,

      'email': email,

      'emailKey': email,

      'permissions': _permissoesZeradas(),

      'role': 'user',

      'billingCycle': null,

      'planEndAt': null,
      'planId': null,
      'planStartAt': null,
      'planStatus': null,

      'purchaseToken': null,

      'subscriptionActive': false,
      'subscriptionProductId': null,
      'subscriptionProvider': null,
      'subscriptionStatus': null,

      'trialEndAt': null,
      'trialStartAt': null,

      'profissionalAgenda': true,

      'ativoAgendamento': _ativo ? _ativoAgendamento : false,

      'origemCadastro': 'agenda',

      'updatedAt': FieldValue.serverTimestamp(),

      'updatedBy': _auth.currentUser?.uid,
    };

    await _fs.collection('users').add(dados);
  }

  /* ==========================================================
     ATUALIZAR
     ========================================================== */

  Future<void> _atualizar({required String nome, required String email}) async {
    await _fs.collection('users').doc(widget.userDocId).update({
      'displayName': nome,

      'active': _ativo,

      'profissionalAgenda': true,

      'ativoAgendamento': _ativo ? _ativoAgendamento : false,

      'updatedAt': FieldValue.serverTimestamp(),

      'updatedBy': _auth.currentUser?.uid,
    });
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgendaProfissionaisStyle.bg,

      body: Column(
        children: [
          _AgendaPageHeader(
            title: _editando ? 'Editar profissional' : 'Novo profissional',
            subtitle:
                _editando
                    ? 'Atualize os dados e configurações do profissional.'
                    : 'Cadastre uma pessoa para receber agendamentos.',
            icon: Icons.person_outline,
            onBack: () => Navigator.of(context).maybePop(),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _dadosProfissionalCard(),

                    const SizedBox(height: 14),

                    _configuracoesCard(),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AgendaProfissionaisStyle.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _salvando ? null : _salvar,
                        icon:
                            _salvando
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
                          _salvando ? 'Salvando...' : 'Salvar profissional',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     CARD DADOS
     ========================================================== */

  Widget _dadosProfissionalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaProfissionaisStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _AgendaIconBadge(
                icon: Icons.badge_outlined,
                color: AgendaProfissionaisStyle.primary,
              ),

              const SizedBox(width: 12),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dados do profissional',
                      style: TextStyle(
                        color: AgendaProfissionaisStyle.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Informe os dados básicos do profissional.',
                      style: TextStyle(
                        color: AgendaProfissionaisStyle.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              _statusTagForm(),
            ],
          ),

          const SizedBox(height: 18),

          _campoNome(),

          const SizedBox(height: 14),

          _campoEmail(),
        ],
      ),
    );
  }

  Widget _statusTagForm() {
    final cor =
        _ativo
            ? AgendaProfissionaisStyle.green
            : AgendaProfissionaisStyle.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _ativo ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 15,
            color: cor,
          ),

          const SizedBox(width: 5),

          Text(
            _ativo ? 'Ativo' : 'Inativo',
            style: TextStyle(
              color: cor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoNome() {
    return TextFormField(
      controller: _nomeCtrl,
      textCapitalization: TextCapitalization.words,
      decoration: _inputDecoration(label: 'Nome', icon: Icons.person_outline),
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return 'Informe o nome do profissional.';
        }

        return null;
      },
    );
  }

  Widget _campoEmail() {
    return TextFormField(
      controller: _emailCtrl,
      readOnly: _editando,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textCapitalization: TextCapitalization.none,
      decoration: _inputDecoration(
        label: 'Email',
        icon: Icons.alternate_email,
        helperText:
            _editando
                ? 'O e-mail não pode ser alterado.'
                : 'Informe um e-mail válido caso o profissional tenha acesso ao sistema futuramente.',
        filled: _editando,
      ),
      validator: _validarEmail,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? helperText,
    bool filled = false,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      prefixIcon: Icon(icon, color: AgendaProfissionaisStyle.primary),
      filled: true,
      fillColor: filled ? AgendaProfissionaisStyle.bg : Colors.white,
      labelStyle: const TextStyle(
        color: AgendaProfissionaisStyle.muted,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: const TextStyle(
        color: AgendaProfissionaisStyle.muted,
        fontSize: 11.5,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AgendaProfissionaisStyle.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AgendaProfissionaisStyle.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AgendaProfissionaisStyle.primary,
          width: 1.5,
        ),
      ),
    );
  }

  /* ==========================================================
     CONFIGURAÇÕES
     ========================================================== */

  Widget _configuracoesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaProfissionaisStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _AgendaIconBadge(
                icon: Icons.tune_outlined,
                color: AgendaProfissionaisStyle.orange,
              ),

              SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configurações',
                      style: TextStyle(
                        color: AgendaProfissionaisStyle.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Defina a disponibilidade deste profissional.',
                      style: TextStyle(
                        color: AgendaProfissionaisStyle.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _switchConfiguracao(
            icon: Icons.check_circle_outline,
            iconColor: AgendaProfissionaisStyle.green,
            title: 'Ativo',
            subtitle:
                'Quando inativo, o profissional fica desativado no cadastro.',
            value: _ativo,
            onChanged: (value) {
              setState(() {
                _ativo = value;

                if (!_ativo) {
                  _ativoAgendamento = false;
                }
              });
            },
          ),

          const Divider(color: AgendaProfissionaisStyle.border, height: 1),

          _switchConfiguracao(
            icon: Icons.calendar_month_outlined,
            iconColor: AgendaProfissionaisStyle.primary,
            title: 'Ativo para agendamento',
            subtitle:
                'Quando ativo, este profissional poderá receber agendamentos pela Agenda Online.',
            value: _ativoAgendamento,
            onChanged:
                !_ativo
                    ? null
                    : (value) {
                      setState(() {
                        _ativoAgendamento = value;
                      });
                    },
          ),
        ],
      ),
    );
  }

  Widget _switchConfiguracao({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AgendaProfissionaisStyle.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AgendaProfissionaisStyle.muted,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Switch.adaptive(
            value: value,
            activeColor: AgendaProfissionaisStyle.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   HEADER PADRÃO DA AGENDA
   ============================================================ */

class _AgendaPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  const _AgendaPageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AgendaProfissionaisStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        20,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _AgendaHeaderButton(
                icon: Icons.arrow_back_rounded,
                onTap: onBack,
              ),

              Expanded(
                child: Center(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 42),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.92), size: 19),

              const SizedBox(width: 7),

              Flexible(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 13.5,
                    height: 1.30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   COMPONENTES VISUAIS
   ============================================================ */

class _AgendaHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AgendaHeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _AgendaIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 25),
    );
  }
}

class _AgendaIconBadgeLarge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaIconBadgeLarge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(icon, color: color, size: 34),
    );
  }
}

/* ============================================================
   CORES
   ============================================================ */

class AgendaProfissionaisStyle {
  static const Color primary = Color(0xFF5B21B6);

  static const Color primaryDark = Color(0xFF3B0CA3);

  static const Color orange = Color(0xFFF97316);

  static const Color green = Color(0xFF16A34A);

  static const Color blue = Color(0xFF2563EB);

  static const Color purple = Color(0xFF7C3AED);

  static const Color red = Color(0xFFDC2626);

  static const Color bg = Color(0xFFF8FAFC);

  static const Color text = Color(0xFF111827);

  static const Color muted = Color(0xFF64748B);

  static const Color border = Color(0xFFE5E7EB);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
