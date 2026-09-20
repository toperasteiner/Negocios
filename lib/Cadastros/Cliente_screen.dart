import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Cadastros/CadastroClienteScreen.dart';
import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

class ClienteStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
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

enum PapelFiltro { todos, cliente, fornecedor, ambos, web }

class ClienteScreen extends StatefulWidget {
  const ClienteScreen({super.key});

  @override
  State<ClienteScreen> createState() => _ClienteScreenState();
}

class _ClienteScreenState extends State<ClienteScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  String? _companyId;
  bool _loadingCompany = true;
  String? _loadError;
  bool _canCadClientes = false;

  bool _loadingPlan = true;
  String? _planError;
  int _clientsUsed = 0;
  int _clientsLimit = -1;
  bool _canCreateByPlan = true;

  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _q = '';

  PapelFiltro _filtro = PapelFiltro.todos;

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
    _buscaCtrl.addListener(_onSearchChange);
    _loadCompanyAndPerms();
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _debounce?.cancel();
    _buscaCtrl.removeListener(_onSearchChange);
    _buscaCtrl.dispose();
    super.dispose();
  }

  String _labelFiltro(PapelFiltro filtro) {
    switch (filtro) {
      case PapelFiltro.todos:
        return 'Todos';
      case PapelFiltro.cliente:
        return 'Clientes';
      case PapelFiltro.fornecedor:
        return 'Fornecedores';
      case PapelFiltro.ambos:
        return 'Clientes e fornecedores';
      case PapelFiltro.web:
        return 'Clientes Web';
    }
  }

  void _logPlanState(String origem) {
    debugPrint('========== CLIENTE_SCREEN / $origem ==========');
    debugPrint('uid atual: ${_uid ?? '-'}');
    debugPrint('companyId tela: ${_companyId ?? '-'}');
    debugPrint('planId: ${PlanService.instance.planId}');
    debugPrint('planStatus: ${PlanService.instance.planStatus}');
    debugPrint('billingCycle: ${PlanService.instance.billingCycle}');
    debugPrint('clientsUsed: $_clientsUsed');
    debugPrint('clientsLimit: $_clientsLimit');
    debugPrint('canCreateByPlan: $_canCreateByPlan');
    debugPrint('planError: ${_planError ?? '-'}');
    debugPrint('==============================================');
  }

  Future<void> _refreshPlanRules() async {
    try {
      setState(() {
        _loadingPlan = true;
        _planError = null;
      });

      await PlanService.instance.reload();

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

      _logPlanState('_refreshPlanRules');
    } catch (e, st) {
      debugPrint('CLIENTE_SCREEN - erro ao validar plano: $e');
      debugPrint('$st');

      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _planError = 'Erro ao validar plano: $e';
      });
    }
  }

  void _abrirTelaPlanos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlanosScreen()),
    ).then((_) async {
      await _refreshPlanRules();
    });
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
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _abrirTelaPlanos();
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Fazer upgrade'),
              ),
            ],
          ),
    );
  }

  Future<bool> _requirePlanSlot() async {
    try {
      await PlanService.instance.reload();

      final canCreate = await PlanService.instance.canCreateClient();
      final usados = await PlanService.instance.getCurrentClientsCount();
      final limite = PlanService.instance.getLimit('maxClients');

      if (!mounted) return false;

      setState(() {
        _clientsUsed = usados;
        _clientsLimit = limite;
        _canCreateByPlan = canCreate;
      });

      _logPlanState('_requirePlanSlot');

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de clientes atingido',
        mensagem:
            limite == -1
                ? 'Seu plano atual não permite esta ação.'
                : 'Você já atingiu o limite de clientes/fornecedores do seu plano atual.\n\n'
                    'Cadastros usados: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando.',
      );
      return false;
    } catch (e, st) {
      debugPrint('CLIENTE_SCREEN - erro no requirePlanSlot: $e');
      debugPrint('$st');

      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao validar plano: $e')));
      return false;
    }
  }

  Future<void> _loadCompanyAndPerms() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingCompany = false;
        _loadError = 'Usuário não autenticado.';
      });
      return;
    }

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();

      Map<String, dynamic>? me;
      if (byUid.exists) {
        me = byUid.data() ?? {};
      } else {
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

      if (me == null) {
        setState(() {
          _loadingCompany = false;
          _loadError = 'Registro do usuário não encontrado em "users".';
        });
        return;
      }

      final companyId = (me['companyId'] ?? '').toString().trim();
      final perms = (me['permissions'] ?? {}) as Map<String, dynamic>;
      final can = (perms['canRegisterClientsSuppliers'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _canCadClientes = can;
        _loadingCompany = false;
        _loadError = null;
      });

      await _refreshPlanRules();
    } catch (e, st) {
      debugPrint('CLIENTE_SCREEN - erro ao carregar empresa/permissões: $e');
      debugPrint('$st');

      setState(() {
        _loadingCompany = false;
        _loadError = 'Erro ao carregar empresa/permissões: $e';
      });
    }
  }

  void _onSearchChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() => _q = _buscaCtrl.text.trim());
    });
  }

  Future<void> _novoCliente() async {
    if (!_requirePerm()) return;

    final ok = await _requirePlanSlot();
    if (!ok) return;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CadastroClienteScreen()),
    );

    await _refreshPlanRules();
  }

  Future<void> _editarCliente(String clienteId) async {
    if (!_requirePerm()) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CadastroClienteScreen(clienteId: clienteId),
      ),
    );

    await _refreshPlanRules();
  }

  Future<void> _excluirCliente(String clienteId, String nome) async {
    if (!_requirePerm()) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Excluir cliente'),
            content: Text(
              'Tem certeza que deseja excluir "${nome.isEmpty ? 'cliente' : nome}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir'),
              ),
            ],
          ),
    );

    if (confirmar != true) return;

    try {
      await _fs.collection('clientes').doc(clienteId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente excluído com sucesso.')),
        );
      }
      await _refreshPlanRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
  }

  bool _requirePerm() {
    if (_canCadClientes) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissão. É necessário permissão de "Cadastrar clientes/fornecedores".',
        ),
      ),
    );
    return false;
  }

  Query<Map<String, dynamic>> _baseQuery(String companyId) {
    return _fs
        .collection('clientes')
        .where('companyId', isEqualTo: companyId)
        .orderBy('nomeLower');
  }

  Query<Map<String, dynamic>> _query(String companyId) {
    var q = _baseQuery(companyId);

    final text = _q.trim();
    if (text.isEmpty) return q;

    final qLower = text.toLowerCase();
    return q.startAt([qLower]).endAt(['$qLower\uf8ff']);
  }

  Widget _buildPlanWarningCard(BuildContext context) {
    final planoAtual = PlanService.instance.planId.toUpperCase();
    final ilimitado = _clientsLimit == -1;
    final restantes = ilimitado ? 999999 : (_clientsLimit - _clientsUsed);
    final atingiuLimite = !ilimitado && _clientsUsed >= _clientsLimit;
    final mostrarAviso = atingiuLimite || (!ilimitado && restantes <= 5);

    if (!mostrarAviso && _planError == null) {
      return const SizedBox.shrink();
    }

    final accent = atingiuLimite ? ClienteStyle.red : ClienteStyle.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.20)),
        boxShadow: ClienteStyle.softShadow,
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
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.workspace_premium_outlined, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Plano: $planoAtual',
                  style: const TextStyle(
                    color: ClienteStyle.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (!ilimitado)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_clientsUsed / $_clientsLimit',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ilimitado
                ? 'Seu plano possui cadastros ilimitados.'
                : atingiuLimite
                ? 'Você atingiu o limite do seu plano para clientes/fornecedores.'
                : 'Faltam apenas $restantes registro(s) para atingir o limite do seu plano.',
            style: const TextStyle(
              color: ClienteStyle.muted,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _abrirTelaPlanos,
            style: FilledButton.styleFrom(
              backgroundColor: ClienteStyle.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Fazer upgrade'),
          ),
          if (_planError != null) ...[
            const SizedBox(height: 8),
            Text(
              _planError!,
              style: const TextStyle(
                color: ClienteStyle.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFiltroDropdown() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ClienteStyle.softShadow,
      ),
      child: DropdownButtonFormField<PapelFiltro>(
        value: _filtro,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Filtrar cadastros',
          prefixIcon: const Icon(
            Icons.filter_list_outlined,
            color: ClienteStyle.primary,
          ),
          filled: true,
          fillColor: ClienteStyle.bg,
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
              color: ClienteStyle.primary,
              width: 1.4,
            ),
          ),
          isDense: true,
        ),
        items:
            PapelFiltro.values.map((filtro) {
              return DropdownMenuItem<PapelFiltro>(
                value: filtro,
                child: Text(_labelFiltro(filtro)),
              );
            }).toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _filtro = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCompany) {
      return const Scaffold(
        backgroundColor: ClienteStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: ClienteStyle.bg,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_companyId == null || _companyId!.isEmpty) {
      return Scaffold(
        backgroundColor: ClienteStyle.bg,
        body: Column(
          children: [
            _buildHeader(),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nenhuma empresa vinculada ao usuário.\n'
                    'Associe um companyId ao usuário para listar os clientes.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _novoCliente,
          backgroundColor: Colors.white,
          foregroundColor: ClienteStyle.muted,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Novo cadastro'),
        ),
      );
    }

    final fabEnabled =
        _canCadClientes &&
        !_loadingPlan &&
        (_canCreateByPlan || _clientsLimit == -1);

    return Scaffold(
      backgroundColor: ClienteStyle.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            _loadingPlan
                ? null
                : (fabEnabled
                    ? _novoCliente
                    : () async {
                      if (!_requirePerm()) return;
                      await _requirePlanSlot();
                    }),
        backgroundColor: fabEnabled ? ClienteStyle.primary : Colors.white,
        foregroundColor: fabEnabled ? Colors.white : ClienteStyle.muted,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_loadingPlan ? 'Validando...' : 'Novo cadastro'),
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (_loadingPlan)
            const LinearProgressIndicator(
              color: ClienteStyle.orange,
              backgroundColor: Color(0xFFEDE9FE),
            ),
          if (!_loadingPlan) _buildPlanWarningCard(context),
          _buildFiltroDropdown(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query(_companyId!).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  debugPrint('⚠️ Firestore stream error: ${snap.error}');
                  if (snap.stackTrace != null) {
                    debugPrint('Stack: ${snap.stackTrace}');
                  }
                }

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snap.data?.docs ?? [];

                docs =
                    docs.where((d) {
                      final m = d.data();
                      final isCli = m['isCliente'] == true;
                      final isForn = m['isFornecedor'] == true;
                      final isWeb =
                          m['isWebCliente'] == true ||
                          m['perfilRelacionamento'] == 'WEB' ||
                          m['origem'] == 'catalogo_publico';

                      switch (_filtro) {
                        case PapelFiltro.todos:
                          return true;
                        case PapelFiltro.cliente:
                          return isCli && !isWeb;
                        case PapelFiltro.fornecedor:
                          return isForn;
                        case PapelFiltro.ambos:
                          return isCli && isForn;
                        case PapelFiltro.web:
                          return isWeb;
                      }
                    }).toList();

                if (_q.isNotEmpty) {
                  final qLower = _q.toLowerCase();
                  docs =
                      docs.where((d) {
                        final m = d.data();
                        final nomeLower =
                            (m['nomeLower'] ?? m['nome'] ?? '')
                                .toString()
                                .toLowerCase();
                        return nomeLower.contains(qLower);
                      }).toList();
                }

                if (docs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshPlanRules,
                    color: ClienteStyle.primary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: ClienteStyle.softShadow,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: ClienteStyle.primary.withOpacity(
                                          0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: const Icon(
                                        Icons.person_search_outlined,
                                        size: 36,
                                        color: ClienteStyle.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _q.isEmpty
                                          ? 'Nenhum cadastro encontrado'
                                          : 'Nenhum resultado para “$_q”.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: ClienteStyle.text,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Cadastre clientes e fornecedores para manter seus contatos organizados.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: ClienteStyle.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_q.isNotEmpty ||
                                        _filtro != PapelFiltro.todos) ...[
                                      const SizedBox(height: 14),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _buscaCtrl.clear();
                                          setState(
                                            () => _filtro = PapelFiltro.todos,
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: ClienteStyle.primary,
                                          side: const BorderSide(
                                            color: ClienteStyle.primary,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.filter_alt_off_outlined,
                                        ),
                                        label: const Text('Limpar filtros'),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 14),
                                      FilledButton.icon(
                                        onPressed:
                                            _loadingPlan
                                                ? null
                                                : (fabEnabled
                                                    ? _novoCliente
                                                    : () async {
                                                      if (!_requirePerm())
                                                        return;
                                                      await _requirePlanSlot();
                                                    }),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: ClienteStyle.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.person_add_alt_1,
                                        ),
                                        label: const Text('Cadastrar primeiro'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshPlanRules,
                  color: ClienteStyle.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final nome = (data['nome'] ?? '').toString();
                      final email = (data['email'] ?? '').toString();
                      final telefone =
                          (data['telefone'] ?? data['whatsapp'] ?? '')
                              .toString();
                      final papel = _descricaoPapel(data);
                      final isWeb =
                          data['isWebCliente'] == true ||
                          data['perfilRelacionamento'] == 'WEB' ||
                          data['origem'] == 'catalogo_publico';

                      return Dismissible(
                        key: ValueKey(doc.id),
                        direction:
                            _canCadClientes
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                        background: Container(
                          decoration: BoxDecoration(
                            color: ClienteStyle.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: const Icon(
                            Icons.delete_outline,
                            color: ClienteStyle.red,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          if (!_requirePerm()) return false;
                          await _excluirCliente(doc.id, nome);
                          return false;
                        },
                        child: _buildClienteCard(
                          docId: doc.id,
                          data: data,
                          nome: nome,
                          email: email,
                          telefone: telefone,
                          papel: papel,
                          isWeb: isWeb,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: ClienteStyle.headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Clientes e fornecedores',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: Icons.refresh_rounded,
                onTap: _refreshPlanRules,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: ClienteStyle.softShadow,
            ),
            child: TextField(
              controller: _buscaCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por nome',
                hintStyle: const TextStyle(color: ClienteStyle.muted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: ClienteStyle.primary,
                ),
                suffixIcon:
                    _q.isEmpty
                        ? null
                        : IconButton(
                          tooltip: 'Limpar',
                          onPressed: () {
                            _buscaCtrl.clear();
                            FocusScope.of(context).unfocus();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteCard({
    required String docId,
    required Map<String, dynamic> data,
    required String nome,
    required String email,
    required String telefone,
    required String papel,
    required bool isWeb,
  }) {
    final letra = (nome.isNotEmpty ? nome[0] : '?').toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ClienteStyle.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _canCadClientes ? _editarCliente(docId) : _requirePerm(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [ClienteStyle.primary, ClienteStyle.orange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    letra,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome.isNotEmpty ? nome : 'Sem nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ClienteStyle.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (papel.isNotEmpty)
                            _ClientePill(
                              icon:
                                  papel == 'Fornecedor'
                                      ? Icons.local_shipping_outlined
                                      : Icons.person_outline_rounded,
                              text: papel,
                              color: ClienteStyle.primary,
                            ),
                          if (isWeb)
                            const _ClientePill(
                              icon: Icons.language_rounded,
                              text: 'Cliente Web',
                              color: ClienteStyle.orange,
                            ),
                        ],
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ClienteInfoLine(
                          icon: Icons.email_outlined,
                          text: email,
                        ),
                      ],
                      if (telefone.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _ClienteInfoLine(
                          icon: Icons.phone_outlined,
                          text: _formataTelefone(telefone),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opções',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: ClienteStyle.muted,
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'editar':
                        _editarCliente(docId);
                        break;
                      case 'excluir':
                        _excluirCliente(docId, nome);
                        break;
                    }
                  },
                  itemBuilder:
                      (_) => [
                        PopupMenuItem(
                          value: 'editar',
                          enabled: _canCadClientes,
                          child: const Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('Alterar'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'excluir',
                          enabled: _canCadClientes,
                          child: const Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: ClienteStyle.red,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Excluir',
                                style: TextStyle(color: ClienteStyle.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _descricaoPapel(Map<String, dynamic> m) {
    final cli = m['isCliente'] == true;
    final forn = m['isFornecedor'] == true;
    if (cli && forn) return 'Cliente e fornecedor';
    if (cli) return 'Cliente';
    if (forn) return 'Fornecedor';
    return '';
  }

  String _formataTelefone(String d) {
    final dig = d.replaceAll(RegExp(r'\D'), '');
    if (dig.isEmpty) return '';
    if (dig.length <= 2) return '($dig';
    if (dig.length <= 6) return '(${dig.substring(0, 2)}) ${dig.substring(2)}';
    if (dig.length <= 10) {
      return '(${dig.substring(0, 2)}) ${dig.substring(2, 6)}-${dig.substring(6)}';
    }
    final x = dig.substring(0, 11);
    return '(${x.substring(0, 2)}) ${x.substring(2, 7)}-${x.substring(7)}';
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

class _ClientePill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _ClientePill({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClienteInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ClienteInfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 1),
        Icon(icon, size: 16, color: ClienteStyle.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ClienteStyle.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
