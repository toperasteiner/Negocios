// lib/Metas/MetasHomeScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

/* ====================== IDENTIDADE VISUAL ====================== */

class MetasStyle {
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

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// ======================= MODELOS & CONSTANTES =======================

enum GoalStatus { active, inactive }

// === KPI keys (apenas 3)
const String _KPI_PROD_SERV = 'produtos_servicos';
const String _KPI_PEDIDOS = 'pedidos';
const String _KPI_NOVOS_CLIENTES_QTD = 'novos_clientes_faturamento_qtd';

class _KpiDef {
  final String key;
  final String label;
  final String unit; // unid | count | BRL
  const _KpiDef(this.key, this.label, this.unit);
}

const List<_KpiDef> _kpis = [
  _KpiDef(_KPI_PROD_SERV, 'Produtos/Serviços', 'unid'),
  _KpiDef(_KPI_PEDIDOS, 'Pedidos', 'BRL'),
  _KpiDef(
    _KPI_NOVOS_CLIENTES_QTD,
    'Novos Clientes com faturamento (Qtd)',
    'count',
  ),
];

String _kpiLabel(String key) =>
    _kpis.firstWhere((k) => k.key == key, orElse: () => _kpis.first).label;

String _kpiUnit(String key) =>
    _kpis.firstWhere((k) => k.key == key, orElse: () => _kpis.first).unit;

/// ======================= ITEM (Produtos/Serviços) =======================

class _ItemTarget {
  final String itemId;
  final String nome;
  final String tipo; // 'produto' | 'servico'
  int quantidade;

  _ItemTarget({
    required this.itemId,
    required this.nome,
    required this.tipo,
    required this.quantidade,
  });

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'nome': nome,
    'tipo': tipo,
    'quantidade': quantidade,
  };

  static _ItemTarget fromMap(Map<String, dynamic> m) => _ItemTarget(
    itemId: (m['itemId'] ?? '').toString(),
    nome: (m['nome'] ?? '').toString(),
    tipo: (m['tipo'] ?? 'produto').toString(),
    quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
  );
}

/// ======================= TELA PRINCIPAL =======================

class MetasHomeScreen extends StatefulWidget {
  const MetasHomeScreen({super.key});

  @override
  State<MetasHomeScreen> createState() => _MetasHomeScreenState();
}

class _MetasHomeScreenState extends State<MetasHomeScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  bool _loading = true;
  String? _loadError;

  String _statusFilter = 'open'; // open|active|inactive|all

  // ---------- Plano ----------
  bool _loadingPlan = true;
  String? _planError;
  int _goalsUsed = 0;
  int _goalsLimit = -1; // -1 = ilimitado
  bool _canCreateByPlan = true;

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _goalsLimit = service.getLimit('maxGoals');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan =
            (service.companyId ?? '').isNotEmpty &&
            (_goalsLimit == -1 || _goalsUsed < _goalsLimit);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _initScope();
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

      final usados = await PlanService.instance.getCurrentGoalsCount();
      final limite = PlanService.instance.getLimit('maxGoals');
      final canCreate = await PlanService.instance.canCreateGoal();

      if (!mounted) return;

      setState(() {
        _goalsUsed = usados;
        _goalsLimit = limite;
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

      final canCreate = await PlanService.instance.canCreateGoal();
      final usados = await PlanService.instance.getCurrentGoalsCount();
      final limite = PlanService.instance.getLimit('maxGoals');

      if (!mounted) return false;

      setState(() {
        _goalsUsed = usados;
        _goalsLimit = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de metas atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de metas do seu plano atual.\n\n'
                    'Metas usadas: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando metas.',
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

  Widget _buildPlanWarningCard(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final planoAtual = PlanService.instance.planId.toUpperCase();
    final ilimitado = _goalsLimit == -1;
    final restantes = ilimitado ? 999999 : (_goalsLimit - _goalsUsed);
    final atingiuLimite = !ilimitado && _goalsUsed >= _goalsLimit;
    final mostrarAviso = !ilimitado && restantes <= 5;

    if (!mostrarAviso) {
      return const SizedBox.shrink();
    }

    final accentColor = atingiuLimite ? MetasStyle.red : MetasStyle.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: accentColor, size: 22),
              const SizedBox(width: 8),
              Text(
                'Plano: $planoAtual',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: MetasStyle.text,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_goalsUsed / $_goalsLimit metas',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            atingiuLimite
                ? 'Você atingiu o limite do seu plano para metas.'
                : 'Atenção: faltam apenas $restantes meta(s) para atingir o limite do seu plano.',
            style: const TextStyle(
              color: MetasStyle.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlanosScreen()),
                );
              },
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text(
                'Fazer upgrade',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (_planError != null) ...[
            const SizedBox(height: 8),
            Text(
              _planError!,
              style: const TextStyle(
                color: MetasStyle.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openForm({
    String? goalId,
    Map<String, dynamic>? initial,
  }) async {
    if (_companyId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('companyId não carregado. Tente novamente.'),
        ),
      );
      return;
    }

    if (goalId == null) {
      final okToCreate = await _requirePlanSlot();
      if (!okToCreate) return;
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder:
          (_) => GoalFormSheet(
            companyId: _companyId!,
            goalId: goalId,
            initial: initial,
          ),
    );

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goalId == null ? 'Meta criada.' : 'Meta atualizada.'),
        ),
      );
      await _refreshPlanRules();
    }
  }

  Future<void> _initScope() async {
    try {
      final u = _auth.currentUser;
      if (u == null) {
        setState(() {
          _loading = false;
          _loadError = 'Usuário não autenticado.';
        });
        return;
      }
      final usersDoc = await _fs.collection('users').doc(u.uid).get();
      if (!usersDoc.exists) {
        setState(() {
          _loading = false;
          _loadError = 'Perfil do usuário não encontrado em /users.';
        });
        return;
      }
      final m = usersDoc.data()!;
      final companyId = (m['companyId'] ?? '').toString();
      if (companyId.isEmpty) {
        setState(() {
          _loading = false;
          _loadError = 'companyId não definido para o usuário.';
        });
        return;
      }
      setState(() {
        _companyId = companyId;
        _loading = false;
        _loadError = null;
      });

      await _refreshPlanRules();
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = 'Falha ao carregar escopo: $e';
      });
    }
  }

  Query<Map<String, dynamic>> _baseQuery() {
    var q = _fs.collection('goals').where('companyId', isEqualTo: _companyId);
    switch (_statusFilter) {
      case 'open':
        q = q.where('status', whereIn: ['active', 'inactive']);
        break;
      case 'active':
        q = q.where('status', isEqualTo: 'active');
        break;
      case 'inactive':
        q = q.where('status', isEqualTo: 'inactive');
        break;
      case 'all':
      default:
        break;
    }
    return q;
  }

  Future<void> _toggleActive(String goalId, String current) async {
    final next = current == 'active' ? 'inactive' : 'active';
    await _fs.collection('goals').doc(goalId).update({
      'status': next,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next == 'active' ? 'Meta ativada.' : 'Meta inativada.'),
      ),
    );
    await _refreshPlanRules();
  }

  Future<void> _duplicateViaForm(Map<String, dynamic> m) async {
    final okToCreate = await _requirePlanSlot();
    if (!okToCreate) return;

    final originalName =
        (m['name'] ?? _kpiLabel((m['kpi'] ?? '').toString())).toString();
    final initial = Map<String, dynamic>.from(m);
    initial['name'] = '${originalName.trim()} (cópia)';
    initial.remove('status');
    initial.remove('createdAt');
    initial.remove('updatedAt');
    initial.remove('createdBy');

    await _openForm(goalId: null, initial: initial);
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  String _statusFilterLabel(String filter) {
    switch (filter) {
      case 'active':
        return 'Somente Ativas';
      case 'inactive':
        return 'Somente Inativas';
      case 'all':
        return 'Todas';
      case 'open':
      default:
        return 'Ativas e Inativas';
    }
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
      decoration: BoxDecoration(
        gradient: MetasStyle.headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
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
                    'Metas',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                initialValue: _statusFilter,
                onSelected: (v) => setState(() => _statusFilter = v),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: 'open',
                        child: Text('Ativas e Inativas'),
                      ),
                      PopupMenuItem(
                        value: 'active',
                        child: Text('Somente Ativas'),
                      ),
                      PopupMenuItem(
                        value: 'inactive',
                        child: Text('Somente Inativas'),
                      ),
                      PopupMenuItem(value: 'all', child: Text('Todas')),
                    ],
                tooltip: 'Filtrar status',
                child: Material(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.filter_list_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Acompanhe e gerencie as metas do seu negócio.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Filtro: ${_statusFilterLabel(_statusFilter)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: MetasStyle.bg,
        body: Center(
          child: CircularProgressIndicator(color: MetasStyle.primary),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: MetasStyle.bg,
        body: Column(
          children: [
            _cabecalho(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MetasStyle.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fabEnabled = !_loadingPlan && (_canCreateByPlan || _goalsLimit == -1);

    return Scaffold(
      backgroundColor: MetasStyle.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:
            fabEnabled ? MetasStyle.orange : Colors.grey.shade400,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onPressed:
            _loadingPlan
                ? null
                : (fabEnabled
                    ? () => _openForm()
                    : () async {
                      await _requirePlanSlot();
                    }),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          _loadingPlan ? 'Validando...' : 'Nova meta',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _cabecalho(),
          if (_loadingPlan)
            const LinearProgressIndicator(
              minHeight: 3,
              color: MetasStyle.orange,
              backgroundColor: Color(0xFFE9E2FA),
            ),
          if (!_loadingPlan) _buildPlanWarningCard(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _baseQuery().snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Erro ao carregar metas: ${snap.error}\n'
                        'Dica: se você usa filtro + ordenação, pode faltar um índice composto.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: MetasStyle.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: MetasStyle.primary,
                    ),
                  );
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshPlanRules,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _IconBadge(
                                      icon: Icons.flag_outlined,
                                      color: MetasStyle.muted,
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'Nenhuma meta encontrada.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: MetasStyle.text,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Toque no botão abaixo para definir sua primeira meta.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: MetasStyle.muted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: MetasStyle.primary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      onPressed:
                                          _loadingPlan
                                              ? null
                                              : (fabEnabled
                                                  ? () => _openForm()
                                                  : () async {
                                                    await _requirePlanSlot();
                                                  }),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text(
                                        'Cadastrar primeira meta',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
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

                final docs = snap.data!.docs;

                return RefreshIndicator(
                  onRefresh: _refreshPlanRules,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final m = d.data();
                      final id = d.id;

                      final name = (m['name'] ?? '').toString();
                      final kpi = (m['kpi'] ?? '').toString();
                      final scopeLevel =
                          (m['scope']?['level'] ?? 'company').toString();
                      final target = (m['target'] as num?)?.toDouble() ?? 0.0;
                      final unit = (m['unit'] ?? _kpiUnit(kpi)).toString();
                      final status = (m['status'] ?? 'inactive').toString();

                      final ps =
                          (m['periodStart'] is Timestamp)
                              ? (m['periodStart'] as Timestamp).toDate()
                              : null;
                      final pe =
                          (m['periodEnd'] is Timestamp)
                              ? (m['periodEnd'] as Timestamp).toDate()
                              : null;

                      String? targetLine() {
                        if (kpi == _KPI_PROD_SERV) return null;
                        if (unit == 'BRL') {
                          return 'Alvo: R\$ ${target.toStringAsFixed(2)}';
                        }
                        return 'Alvo: ${target.toStringAsFixed(0)} ${unit == "count" ? "itens" : unit}';
                      }

                      final escopoLabel =
                          scopeLevel == 'user' ? 'Usuário' : 'Empresa';
                      final isActive = status == 'active';

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: MetasStyle.softShadow,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _IconBadge(
                                  icon: Icons.flag_outlined,
                                  color:
                                      isActive
                                          ? MetasStyle.primary
                                          : MetasStyle.muted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isEmpty ? _kpiLabel(kpi) : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color:
                                              isActive
                                                  ? MetasStyle.text
                                                  : MetasStyle.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _kpiLabel(kpi),
                                        style: const TextStyle(
                                          color: MetasStyle.muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isActive
                                            ? MetasStyle.green.withOpacity(0.12)
                                            : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    isActive ? 'Ativo' : 'Inativo',
                                    style: TextStyle(
                                      color:
                                          isActive
                                              ? MetasStyle.green
                                              : MetasStyle.muted,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  onSelected: (v) async {
                                    if (v == 'edit') {
                                      _openForm(goalId: id, initial: m);
                                    } else if (v == 'toggle') {
                                      await _toggleActive(id, status);
                                    } else if (v == 'dup') {
                                      await _duplicateViaForm(m);
                                    }
                                  },
                                  itemBuilder:
                                      (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: ListTile(
                                            dense: true,
                                            leading: Icon(Icons.edit_outlined),
                                            title: Text('Editar'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: ListTile(
                                            dense: true,
                                            leading: Icon(
                                              status == 'active'
                                                  ? Icons.pause_circle_outline
                                                  : Icons.play_circle_outline,
                                            ),
                                            title: Text(
                                              status == 'active'
                                                  ? 'Inativar'
                                                  : 'Ativar',
                                            ),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'dup',
                                          child: ListTile(
                                            dense: true,
                                            leading: Icon(
                                              Icons.copy_all_outlined,
                                            ),
                                            title: Text('Duplicar'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                  tooltip: 'Mais ações',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: MetasStyle.bg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        scopeLevel == 'user'
                                            ? Icons.person_outline
                                            : Icons.business_outlined,
                                        size: 14,
                                        color: MetasStyle.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        escopoLabel,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: MetasStyle.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: MetasStyle.bg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 14,
                                        color: MetasStyle.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_fmtDate(ps)} a ${_fmtDate(pe)}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: MetasStyle.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (targetLine() != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: MetasStyle.orange.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: MetasStyle.orange.withOpacity(0.20),
                                  ),
                                ),
                                child: Text(
                                  targetLine()!,
                                  style: const TextStyle(
                                    color: MetasStyle.orange,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ],
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

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }
}

/// ======================= SHEET DE FORMULÁRIO =======================

class GoalFormSheet extends StatefulWidget {
  final String companyId;
  final String? goalId;
  final Map<String, dynamic>? initial;
  const GoalFormSheet({
    super.key,
    required this.companyId,
    this.goalId,
    this.initial,
  });

  @override
  State<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<GoalFormSheet> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();

  String _name = '';
  String _kpi = _KPI_PROD_SERV;
  String _unit = _kpiUnit(_KPI_PROD_SERV);
  String _scopeLevel = 'company';

  final List<String> _scopeUserIds = [];
  final Map<String, String> _scopeUserNames = {};

  final _targetPedidosCtrl = TextEditingController();
  final _targetNovosClientesCtrl = TextEditingController();

  DateTime? _periodStart;
  DateTime? _periodEnd;

  bool _saving = false;

  String? _periodError;
  String? _scopeError;
  String? _formError;
  final _scrollCtrl = ScrollController();

  List<Map<String, String>> _users = [];
  bool _loadingUsers = false;

  final List<_ItemTarget> _itemTargets = [];

  @override
  void initState() {
    super.initState();
    _hydrateFromInitial();
    if (_scopeLevel == 'user') {
      _loadUsers();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    (messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _hydrateFromInitial() {
    final m = widget.initial;
    if (m == null) return;
    _name = (m['name'] ?? '').toString();
    _kpi = (m['kpi'] ?? _KPI_PROD_SERV).toString();
    _unit = (m['unit'] ?? _kpiUnit(_kpi)).toString();
    _scopeLevel = (m['scope']?['level'] ?? 'company').toString();

    final rawList = m['scope']?['userIds'];
    final rawSingle = m['scope']?['userId'];
    final ids = <String>[];
    if (rawList is List) {
      ids.addAll(rawList.map((e) => e.toString()).where((s) => s.isNotEmpty));
    } else if (rawSingle != null) {
      ids.add(rawSingle.toString());
    }
    _scopeUserIds.addAll(ids);

    final targetNum = ((m['target'] as num?)?.toDouble() ?? 0.0);
    if (_kpi == _KPI_PEDIDOS) {
      _targetPedidosCtrl.text =
          targetNum > 0
              ? targetNum.toStringAsFixed(2).replaceAll('.', ',')
              : '';
    } else if (_kpi == _KPI_NOVOS_CLIENTES_QTD) {
      _targetNovosClientesCtrl.text =
          targetNum > 0 ? targetNum.toStringAsFixed(0) : '';
    }

    final ps = m['periodStart'];
    final pe = m['periodEnd'];
    if (ps is Timestamp) _periodStart = ps.toDate();
    if (pe is Timestamp) _periodEnd = pe.toDate();

    final List items = (m['itemsTargets'] as List?) ?? const [];
    for (final it in items) {
      if (it is Map<String, dynamic>) {
        _itemTargets.add(_ItemTarget.fromMap(it));
      }
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final qs =
          await _fs
              .collection('users')
              .where('companyId', isEqualTo: widget.companyId)
              .orderBy('displayName')
              .limit(500)
              .get();
      _users =
          qs.docs.map((d) {
            final m = d.data();
            final name = (m['displayName'] ?? m['name'] ?? d.id).toString();
            if (_scopeUserIds.contains(d.id)) {
              _scopeUserNames[d.id] = name;
            }
            return {'id': d.id, 'name': name};
          }).toList();
    } catch (e) {
      debugPrint('[GoalFormSheet::_loadUsers] $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final base =
        start
            ? (_periodStart ?? DateTime.now())
            : (_periodEnd ?? _periodStart ?? DateTime.now());
    final dt = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Início do período' : 'Fim do período',
      locale: const Locale('pt', 'BR'),
    );
    if (dt != null) {
      setState(() {
        if (start) {
          _periodStart = DateTime(dt.year, dt.month, dt.day, 0, 0, 0);
          if (_periodEnd != null && _periodEnd!.isBefore(_periodStart!)) {
            _periodEnd = _periodStart;
          }
        } else {
          _periodEnd = DateTime(dt.year, dt.month, dt.day, 23, 59, 59);
          if (_periodStart != null && _periodEnd!.isBefore(_periodStart!)) {
            _periodStart = DateTime(dt.year, dt.month, dt.day, 0, 0, 0);
          }
        }
        _periodError = null;
      });
    }
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return 'Selecionar...';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  Future<void> _openUsersMultiSelector() async {
    if (_loadingUsers) return;
    if (_users.isEmpty) await _loadUsers();

    final buscaCtrl = TextEditingController();
    Set<String> tempSelected = Set<String>.from(_scopeUserIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        List<Map<String, String>> _filtered(String q) {
          if (q.isEmpty) return _users;
          final qq = q.toLowerCase();
          return _users.where((u) {
            final n = (u['name'] ?? '').toLowerCase();
            final id = (u['id'] ?? '').toLowerCase();
            return n.contains(qq) || id.contains(qq);
          }).toList();
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            final kb = MediaQuery.of(context).viewInsets.bottom;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: kb),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: StatefulBuilder(
                    builder: (innerCtx, setStateInner) {
                      final list = _filtered(buscaCtrl.text.trim());
                      return Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.group_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: buscaCtrl,
                                  onChanged: (_) => setStateInner(() {}),
                                  decoration: const InputDecoration(
                                    hintText: 'Buscar usuários (nome ou id)...',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Selecionar todos (lista filtrada)',
                                onPressed: () {
                                  for (final u in list) {
                                    tempSelected.add(u['id']!);
                                  }
                                  setStateInner(() {});
                                },
                                icon: const Icon(Icons.select_all_outlined),
                              ),
                              IconButton(
                                tooltip: 'Limpar seleção',
                                onPressed: () {
                                  tempSelected.clear();
                                  setStateInner(() {});
                                },
                                icon: const Icon(Icons.clear_all_outlined),
                              ),
                            ],
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.builder(
                              controller: controller,
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final u = list[i];
                                final uid = u['id']!;
                                final nome = u['name'] ?? uid;
                                final checked = tempSelected.contains(uid);
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: (v) {
                                    if (v == true) {
                                      tempSelected.add(uid);
                                    } else {
                                      tempSelected.remove(uid);
                                    }
                                    setStateInner(() {});
                                  },
                                  title: Text(nome),
                                  subtitle: Text(uid),
                                );
                              },
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.check),
                                  label: const Text('Concluir seleção'),
                                  onPressed: () {
                                    setState(() {
                                      _scopeUserIds
                                        ..clear()
                                        ..addAll(tempSelected);
                                      for (final u in _users) {
                                        final id = u['id']!;
                                        if (_scopeUserIds.contains(id)) {
                                          _scopeUserNames[id] = u['name'] ?? id;
                                        }
                                      }
                                      _scopeError = null;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int get _totalQuantidadeItens {
    int sum = 0;
    for (final it in _itemTargets) {
      sum += it.quantidade;
    }
    return sum;
  }

  Future<void> _openItemSelector() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => _ItemPickerSheet(
            companyId: widget.companyId,
            onPicked: (picked) {
              setState(() {
                for (final p in picked) {
                  final idx = _itemTargets.indexWhere(
                    (x) => x.itemId == p.itemId && x.tipo == p.tipo,
                  );
                  if (idx >= 0) {
                    _itemTargets[idx].quantidade = p.quantidade;
                  } else {
                    _itemTargets.add(p);
                  }
                }
              });
            },
          ),
    );
  }

  void _editarQuantidade(_ItemTarget it) async {
    final ctrl = TextEditingController(text: it.quantidade.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dCtx) => AlertDialog(
            title: Text('Quantidade para "${it.nome}"'),
            content: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
    );
    if (ok == true) {
      final q = int.tryParse(ctrl.text.trim()) ?? 0;
      if (q > 0) {
        setState(() => it.quantidade = q);
      } else {
        _showSnack('Informe uma quantidade válida (>0).');
      }
    }
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form != null) {
      final ok = form.validate();
      if (!ok) {
        _showSnack('Corrija os campos destacados.');
        return;
      }
      form.save();
    }

    setState(() {
      _periodError = null;
      _scopeError = null;
      _formError = null;
    });

    if (_periodStart == null || _periodEnd == null) {
      setState(() => _periodError = 'Defina o período (início e fim).');
      _showSnack('Defina o período (início e fim).');
      return;
    }
    if (_scopeLevel == 'user' && _scopeUserIds.isEmpty) {
      setState(() => _scopeError = 'Selecione pelo menos um usuário.');
      _showSnack('Selecione pelo menos um usuário.');
      return;
    }

    double target = 0;
    if (_kpi == _KPI_PROD_SERV) {
      if (_itemTargets.isEmpty) {
        setState(
          () => _formError = 'Adicione pelo menos um produto/serviço à meta.',
        );
        await Future.delayed(const Duration(milliseconds: 10));
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
        _showSnack('Adicione pelo menos um produto/serviço à meta.');
        return;
      }
      target = _totalQuantidadeItens.toDouble();
      _unit = 'unid';
    } else if (_kpi == _KPI_PEDIDOS) {
      final t =
          double.tryParse(
            _targetPedidosCtrl.text.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0.0;
      if (t <= 0) {
        _showSnack('Informe um valor (R\$) maior que zero.');
        return;
      }
      target = t;
      _unit = 'BRL';
    } else if (_kpi == _KPI_NOVOS_CLIENTES_QTD) {
      final tInt = int.tryParse(_targetNovosClientesCtrl.text.trim()) ?? 0;
      if (tInt <= 0) {
        _showSnack('Informe uma quantidade maior que zero.');
        return;
      }
      target = tInt.toDouble();
      _unit = 'count';
    }

    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      final currentUser = _auth.currentUser;

      final data = <String, dynamic>{
        'companyId': widget.companyId,
        'name': _name,
        'kpi': _kpi,
        'unit': _unit,
        'target': target,
        'periodStart': Timestamp.fromDate(_periodStart!),
        'periodEnd': Timestamp.fromDate(_periodEnd!),
        'scope': {
          'level': _scopeLevel,
          'userIds': _scopeLevel == 'user' ? _scopeUserIds : [],
          'userId': null,
        },
        'updatedAt': now,
      };

      if (_kpi == _KPI_PROD_SERV) {
        data['itemsTargets'] = _itemTargets.map((e) => e.toMap()).toList();
      } else {
        data['itemsTargets'] = [];
      }

      if (widget.goalId == null) {
        await _fs.collection('goals').add({
          ...data,
          'status': 'active',
          'createdAt': now,
          'createdBy': currentUser?.uid,
        });
      } else {
        await _fs.collection('goals').doc(widget.goalId).update(data);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      String msg = 'Falha ao salvar.';
      if (e is FirebaseException) {
        switch (e.code) {
          case 'permission-denied':
            msg = 'Você não tem permissão para salvar esta meta.';
            break;
          case 'unavailable':
            msg = 'Serviço temporariamente indisponível. Tente novamente.';
            break;
          case 'cancelled':
            msg = 'Operação cancelada.';
            break;
          default:
            msg = 'Falha ao salvar (${e.code}).';
        }
      } else {
        msg = 'Falha ao salvar: $e';
      }
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    final isProdServ = _kpi == _KPI_PROD_SERV;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (_formError != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MetasStyle.red.withOpacity(0.08),
                        border: Border.all(
                          color: MetasStyle.red.withOpacity(0.35),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: MetasStyle.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(
                                color: MetasStyle.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _formError = null),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: MetasStyle.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      _IconBadge(
                        icon: Icons.flag_outlined,
                        color: MetasStyle.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.goalId == null
                                  ? 'Nova meta'
                                  : 'Editar meta',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: MetasStyle.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Defina o objetivo, período e escopo.',
                              style: TextStyle(
                                fontSize: 12,
                                color: MetasStyle.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    initialValue: _name,
                    decoration: InputDecoration(
                      labelText: 'Nome da meta *',
                      hintText: 'Ex.: Meta Novembro Vendas',
                      filled: true,
                      fillColor: MetasStyle.bg,
                      prefixIcon: const Icon(
                        Icons.label_outline,
                        color: MetasStyle.primary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: MetasStyle.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    validator:
                        (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Informe o nome da meta.'
                                : null,
                    onSaved: (v) => _name = (v ?? '').trim(),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _kpi,
                    decoration: InputDecoration(
                      labelText: 'Indicador (KPI) *',
                      filled: true,
                      fillColor: MetasStyle.bg,
                      prefixIcon: const Icon(
                        Icons.insights_outlined,
                        color: MetasStyle.primary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: MetasStyle.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    items:
                        _kpis
                            .map(
                              (k) => DropdownMenuItem(
                                value: k.key,
                                child: Text(k.label),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _kpi = v;
                        _unit = _kpiUnit(v);
                        _formError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  if (isProdServ) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MetasStyle.primary,
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(
                          color: MetasStyle.primary.withOpacity(0.30),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text(
                        'Adicionar produtos/serviços',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: _openItemSelector,
                    ),
                    const SizedBox(height: 8),
                    if (_itemTargets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Nenhum item selecionado ainda.',
                            style: TextStyle(
                              color: MetasStyle.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children:
                                _itemTargets
                                    .map(
                                      (it) => InputChip(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        label: Text(
                                          '${it.nome} • ${it.quantidade} un',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        avatar: Icon(
                                          it.tipo == 'servico'
                                              ? Icons.build_outlined
                                              : Icons.inventory_2_outlined,
                                          size: 16,
                                        ),
                                        onPressed: () => _editarQuantidade(it),
                                        onDeleted:
                                            () => setState(
                                              () => _itemTargets.remove(it),
                                            ),
                                      ),
                                    )
                                    .toList(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Quantidade total alvo: $_totalQuantidadeItens unid',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: MetasStyle.primary,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 14),
                  ],
                  if (_kpi == _KPI_PEDIDOS)
                    TextFormField(
                      controller: _targetPedidosCtrl,
                      decoration: InputDecoration(
                        labelText: 'Alvo (Valor R\$) *',
                        hintText: r'Ex.: R$ 5.000,00',
                        filled: true,
                        fillColor: MetasStyle.bg,
                        prefixIcon: const Icon(
                          Icons.attach_money_rounded,
                          color: MetasStyle.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: MetasStyle.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final t =
                            double.tryParse(
                              (v ?? '')
                                  .replaceAll('.', '')
                                  .replaceAll(',', '.'),
                            ) ??
                            0.0;
                        return t <= 0
                            ? 'Informe um valor em R\$ maior que zero.'
                            : null;
                      },
                    ),
                  if (_kpi == _KPI_NOVOS_CLIENTES_QTD)
                    TextFormField(
                      controller: _targetNovosClientesCtrl,
                      decoration: InputDecoration(
                        labelText: 'Alvo (Quantidade de clientes) *',
                        hintText: 'Ex.: 20',
                        filled: true,
                        fillColor: MetasStyle.bg,
                        prefixIcon: const Icon(
                          Icons.person_add_outlined,
                          color: MetasStyle.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: MetasStyle.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: false,
                      ),
                      validator: (v) {
                        final t = int.tryParse((v ?? '').trim()) ?? 0;
                        return t <= 0
                            ? 'Informe uma quantidade maior que zero.'
                            : null;
                      },
                    ),
                  if (!isProdServ) const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _scopeLevel,
                    decoration: InputDecoration(
                      labelText: 'Escopo *',
                      filled: true,
                      fillColor: MetasStyle.bg,
                      prefixIcon: const Icon(
                        Icons.business_outlined,
                        color: MetasStyle.primary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: MetasStyle.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'company',
                        child: Text('Empresa (todos usuários)'),
                      ),
                      DropdownMenuItem(
                        value: 'user',
                        child: Text('Usuário(s) específico(s)'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() {
                        _scopeLevel = v;
                        _scopeError = null;
                      });
                      if (v == 'user') await _loadUsers();
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_scopeLevel == 'user') ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MetasStyle.primary,
                          side: BorderSide(
                            color: MetasStyle.primary.withOpacity(0.30),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.group_add_outlined),
                        label: const Text(
                          'Selecionar usuários',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onPressed: _openUsersMultiSelector,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child:
                          _scopeUserIds.isEmpty
                              ? const Text(
                                'Nenhum usuário selecionado.',
                                style: TextStyle(
                                  color: MetasStyle.muted,
                                  fontSize: 12,
                                ),
                              )
                              : Wrap(
                                spacing: 6,
                                runSpacing: -6,
                                children:
                                    _scopeUserIds.map((uid) {
                                      final nome = _scopeUserNames[uid] ?? uid;
                                      return InputChip(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        label: Text(nome),
                                        onDeleted: () {
                                          setState(() {
                                            _scopeUserIds.remove(uid);
                                            _scopeUserNames.remove(uid);
                                          });
                                        },
                                      );
                                    }).toList(),
                              ),
                    ),
                    if (_scopeError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _scopeError!,
                            style: const TextStyle(
                              color: MetasStyle.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MetasStyle.text,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: MetasStyle.primary,
                          ),
                          label: Text(
                            'Início: ${_fmtDate(_periodStart)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => _pickDate(start: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MetasStyle.text,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: MetasStyle.orange,
                          ),
                          label: Text(
                            'Fim: ${_fmtDate(_periodEnd)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => _pickDate(start: false),
                        ),
                      ),
                    ],
                  ),
                  if (_periodError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _periodError!,
                          style: const TextStyle(
                            color: MetasStyle.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MetasStyle.primary,
                            minimumSize: const Size.fromHeight(50),
                            side: BorderSide(
                              color: MetasStyle.primary.withOpacity(0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              _saving
                                  ? null
                                  : () => Navigator.pop(context, false),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: MetasStyle.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saving ? null : _save,
                          icon:
                              _saving
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'Salvando...' : 'Salvar meta',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ======================= SELETOR DE ITENS (PRODUTOS + SERVIÇOS) =======================

class _ItemPickerSheet extends StatefulWidget {
  final String companyId;
  final void Function(List<_ItemTarget> picked) onPicked;
  const _ItemPickerSheet({required this.companyId, required this.onPicked});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  final _fs = FirebaseFirestore.instance;

  final _buscaCtrl = TextEditingController();
  bool _loading = true;
  String? _error;

  final List<Map<String, String>> _rows = [];
  final Map<String, _ItemTarget> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
    _buscaCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
      _picked.clear();
    });
    try {
      final produtos =
          await _fs
              .collection('produtos')
              .where('companyId', isEqualTo: widget.companyId)
              .limit(500)
              .get();
      for (final d in produtos.docs) {
        final m = d.data();
        final nome = (m['nome'] ?? d.id).toString();
        _rows.add({'id': d.id, 'nome': nome, 'tipo': 'produto'});
      }

      final servicos =
          await _fs
              .collection('servicos')
              .where('companyId', isEqualTo: widget.companyId)
              .limit(500)
              .get();
      for (final d in servicos.docs) {
        final m = d.data();
        final nome = (m['nome'] ?? d.id).toString();
        _rows.add({'id': d.id, 'nome': nome, 'tipo': 'servico'});
      }

      _rows.sort((a, b) => (a['nome'] ?? '').compareTo(b['nome'] ?? ''));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Falha ao carregar itens: $e';
        });
      }
    }
  }

  void _filter() => setState(() {});

  void _addOrEdit(Map<String, String> row) async {
    final key = '${row['tipo']}|${row['id']}';
    final existing = _picked[key];
    final ctrl = TextEditingController(
      text: existing?.quantidade.toString() ?? '1',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dCtx) => AlertDialog(
            title: Text('Quantidade - ${row['nome']}'),
            content: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('Adicionar'),
              ),
            ],
          ),
    );

    if (ok == true) {
      final q = int.tryParse(ctrl.text.trim()) ?? 0;
      if (q <= 0) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        (messenger ?? ScaffoldMessenger.of(context)).showSnackBar(
          const SnackBar(content: Text('Informe uma quantidade válida (>0).')),
        );
        return;
      }
      setState(() {
        _picked[key] = _ItemTarget(
          itemId: row['id']!,
          nome: row['nome']!,
          tipo: row['tipo']!,
          quantidade: q,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _buscaCtrl.text.trim().toLowerCase();
    final filtered =
        q.isEmpty
            ? _rows
            : _rows
                .where((r) => (r['nome'] ?? '').toLowerCase().contains(q))
                .toList();

    final kb = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + kb),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar produtos ou serviços...',
                      hintStyle: const TextStyle(color: MetasStyle.muted),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: MetasStyle.primary,
                      ),
                      filled: true,
                      fillColor: MetasStyle.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: MetasStyle.primary),
                  onPressed: _load,
                  tooltip: 'Recarregar',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: MetasStyle.primary),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: MetasStyle.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    final key = '${r['tipo']}|${r['id']}';
                    final isPicked = _picked.containsKey(key);

                    return Container(
                      decoration: BoxDecoration(
                        color: isPicked
                            ? MetasStyle.primary.withOpacity(0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isPicked
                              ? MetasStyle.primary.withOpacity(0.35)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: ListTile(
                        leading: _IconBadge(
                          icon: r['tipo'] == 'servico'
                              ? Icons.build_outlined
                              : Icons.inventory_2_outlined,
                          color: r['tipo'] == 'servico'
                              ? MetasStyle.orange
                              : MetasStyle.primary,
                        ),
                        title: Text(
                          r['nome'] ?? r['id']!,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          r['tipo'] == 'servico' ? 'Serviço' : 'Produto',
                          style: const TextStyle(
                            color: MetasStyle.muted,
                            fontSize: 12,
                          ),
                        ),
                        trailing: isPicked
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: MetasStyle.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Qtd: ${_picked[key]!.quantidade}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.add_circle_outline,
                                color: MetasStyle.primary,
                              ),
                        onTap: () => _addOrEdit(r),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MetasStyle.primary,
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(
                        color: MetasStyle.primary.withOpacity(0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: MetasStyle.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed:
                        _picked.isEmpty
                            ? null
                            : () {
                              widget.onPicked(_picked.values.toList());
                              Navigator.pop(context);
                            },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Adicionar à meta',
                      style: TextStyle(fontWeight: FontWeight.w900),
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
