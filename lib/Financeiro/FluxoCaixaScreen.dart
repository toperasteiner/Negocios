import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ======================== TELA FLUXO DE CAIXA ========================

class FluxoCaixaScreen extends StatefulWidget {
  const FluxoCaixaScreen({super.key});

  @override
  State<FluxoCaixaScreen> createState() => _FluxoCaixaScreenState();
}

class _FluxoCaixaScreenState extends State<FluxoCaixaScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Escopo
  String? _uid; // uid do usuário logado
  String? _companyId;
  String? _scopeUserId; // companyId do users/{uid}
  bool _loadingScope = true;
  String? _scopeError;

  // Filtros
  DateTime _ini = _at00(DateTime.now().subtract(const Duration(days: 29)));
  DateTime _fim = _at2359(DateTime.now());
  // 0=hoje, 7, 30, 90, -1=custom, -2=desde o início
  int _preset = 30;
  String? _tipo; // null|entrada|saida

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _initScope();
    _auth.authStateChanges().listen((u) async {
      _uid = u?.uid;
      await _initScope();
      if (mounted) setState(() {});
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?>
  _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    // 1) tenta users/{uid}
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid;
    } catch (e) {
      debugPrint('[FluxoCaixa] erro lendo users/${u.uid}: $e');
    }

    // 2) fallback por emailKey
    final emailKey =
        (u.email ?? '')
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
            .trim()
            .toLowerCase();
    if (emailKey.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: emailKey)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) return q.docs.first;
      } catch (e) {
        debugPrint('[FluxoCaixa] erro buscando por emailKey=$emailKey: $e');
      }
    }
    return null;
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Faça login para continuar.';
        _scopeUserId = null;
        _companyId = null;
      });
      return;
    }

    setState(() {
      _loadingScope = true;
      _scopeError = null;
    });

    try {
      final meSnap = await _loadCurrentUserRecord();
      final me = meSnap?.data() ?? {};
      final fetchedCompanyId = (me['companyId'] ?? '').toString().trim();

      debugPrint(
        '[FluxoCaixa] UID=${u.uid} email=${u.email} userDocId=${meSnap?.id} companyId="$fetchedCompanyId"',
      );

      if (fetchedCompanyId.isEmpty) {
        setState(() {
          _loadingScope = false;
          _companyId = null;
          _scopeError =
              'Seu usuário não possui companyId definido em users/{uid}.companyId.\nUID: ${u.uid}';
        });
        return;
      }

      setState(() {
        _scopeUserId = u.uid; // SEMPRE o uid do logado
        _companyId = fetchedCompanyId; // SEMPRE o companyId do users.companyId
        _loadingScope = false;
        _scopeError = null;
      });
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao resolver escopo: $e';
        _scopeUserId = null;
        _companyId = null;
      });
    }
  }

  void _setPreset(int days) {
    final now = DateTime.now();
    setState(() {
      _preset = days;
      if (days == 0) {
        _ini = _at00(now);
        _fim = _at2359(now);
      } else if (days > 0) {
        _ini = _at00(now.subtract(Duration(days: days - 1)));
        _fim = _at2359(now);
      } else if (days == -2) {
        _ini = DateTime(1970, 1, 1);
        _fim = _at2359(now);
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final ini = await showDatePicker(
      context: context,
      initialDate: _ini,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Data inicial',
    );
    if (ini == null) return;
    final fim = await showDatePicker(
      context: context,
      initialDate: _fim,
      firstDate: ini,
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Data final',
    );
    if (fim == null) return;
    setState(() {
      _preset = -1;
      _ini = _at00(ini);
      _fim = _at2359(fim);
    });
  }

  /// Consulta por companyId (escopo da empresa).
  /// Se _preset == -2 (desde o início), **não filtra por data**.
  Query<Map<String, dynamic>> _query() {
    final companyScope = _companyId!; // obrigatório
    var q = _fs
        .collection('fluxo_caixa')
        .where('companyId', isEqualTo: companyScope)
        .orderBy('data');

    if (_preset != -2) {
      final iniTs = Timestamp.fromDate(_ini);
      final fimExc = _at00(_fim.add(const Duration(days: 1)));
      q = q
          .where('data', isGreaterThanOrEqualTo: iniTs)
          .where('data', isLessThan: Timestamp.fromDate(fimExc));
    }

    if (_tipo != null && _tipo!.isNotEmpty) {
      q = q.where('tipo', isEqualTo: _tipo);
    }
    return q;
  }

  /// Stream do saldo TOTAL da empresa (soma de `valor` em todos os docs do companyId).
  Stream<double> _saldoTotalStream() {
    if (_companyId == null) {
      return Stream<double>.value(0.0);
    }
    return _fs
        .collection('fluxo_caixa')
        .where('companyId', isEqualTo: _companyId)
        .snapshots()
        .map((snap) {
          double total = 0;
          for (final d in snap.docs) {
            final m = d.data();
            final v = m['valor'];
            if (v is num) total += v.toDouble();
          }
          return total;
        });
  }

  Future<void> _editarLancamento(
    String docId,
    Map<String, dynamic> initial,
  ) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => NovoLancamentoSheet(
            currentUid: _uid!,
            currentCompanyId: _companyId!, // obrigatório
            docId: docId,
            initial: initial,
          ),
    );
    if (ok == true) setState(() {});
  }

  Future<void> _excluirLancamento(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Excluir lançamento?'),
            content: const Text('Esta ação não pode ser desfeita.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.delete_forever),
                label: const Text('Excluir'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
    );
    if (ok != true) return;

    try {
      await _fs.collection('fluxo_caixa').doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lançamento excluído.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  // Utils
  static double _asNum(dynamic v) =>
      v is int ? v.toDouble() : (v is double ? v : 0.0);
  static String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  static String _fmtMoeda(num v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_scopeError != null || _uid == null || _companyId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fluxo de Caixa')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _scopeError ??
                  'Não foi possível determinar o companyId do usuário logado.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo de Caixa'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Tipo',
            initialValue: _tipo,
            onSelected: (v) => setState(() => _tipo = v),
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: null, child: Text('Todos')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'entrada', child: Text('Entradas')),
                  PopupMenuItem(value: 'saida', child: Text('Saídas')),
                ],
            child: Row(
              children: [
                const Icon(Icons.filter_alt_outlined),
                const SizedBox(width: 8),
                Text(
                  _tipo == null
                      ? 'Tipo: Todos'
                      : 'Tipo: ${_tipo == 'entrada' ? 'Entradas' : 'Saídas'}',
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Período',
            onSelected: (v) {
              if (v == -1) {
                _pickCustomRange();
              } else {
                _setPreset(v);
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: 0, child: Text('Hoje')),
                  PopupMenuItem(value: 7, child: Text('Últimos 7 dias')),
                  PopupMenuItem(value: 30, child: Text('Últimos 30 dias')),
                  PopupMenuItem(value: 90, child: Text('Últimos 90 dias')),
                  PopupMenuItem(value: -2, child: Text('Desde o início')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: -1, child: Text('Personalizado…')),
                ],
            child: Row(
              children: [
                const Icon(Icons.date_range),
                const SizedBox(width: 8),
                Text(
                  _preset == -2
                      ? 'Desde o início'
                      : _preset == -1
                      ? '${_fmtData(_ini)} • ${_fmtData(_fim)}'
                      : _preset == 0
                      ? 'Hoje'
                      : 'Últimos $_preset dias',
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder:
                (_) => NovoLancamentoSheet(
                  currentUid: _uid!, // UID do logado
                  currentCompanyId: _companyId!, // companyId do users/{uid}
                ),
          );
          if (ok == true) setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo lançamento'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query().snapshots(),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'Erro: ${snap.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          // Totais do período/consulta
          double entradas = 0, saidas = 0;
          for (final d in docs) {
            final m = d.data();
            final tipo = (m['tipo'] ?? '').toString();
            final val = _asNum(m['valorAbs']);
            if (tipo == 'entrada') entradas += val;
            if (tipo == 'saida') saidas += val;
          }
          final saldoPeriodo = entradas - saidas;

          if (docs.isEmpty) {
            return _EmptyState(
              title: 'Sem lançamentos no filtro atual.',
              subtitle:
                  _preset == -2
                      ? 'Empresa: ${_companyId}\nPeríodo: Desde o início • ${_tipo == null
                          ? 'Todos'
                          : _tipo == 'entrada'
                          ? 'Entradas'
                          : 'Saídas'}'
                      : 'Empresa: ${_companyId}\nPeríodo: ${_fmtData(_ini)} a ${_fmtData(_fim)} • ${_tipo == null
                          ? 'Todos'
                          : _tipo == 'entrada'
                          ? 'Entradas'
                          : 'Saídas'}',
              onSet30: () => _setPreset(30),
              onSet90: () => _setPreset(90),
              onCustom: _pickCustomRange,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                // ===== KPIs: 1 por linha =====
                _KpiCard(
                  icon: Icons.arrow_downward_outlined,
                  label: 'Entradas',
                  value: _fmtMoeda(entradas),
                  color: Colors.teal,
                ),
                const SizedBox(height: 12),
                _KpiCard(
                  icon: Icons.arrow_upward_outlined,
                  label: 'Saídas',
                  value: _fmtMoeda(saidas),
                  color: Colors.red,
                ),
                const SizedBox(height: 12),
                _KpiCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: _preset == -2 ? 'Saldo (geral)' : 'Saldo (período)',
                  value: _fmtMoeda(saldoPeriodo),
                  color: saldoPeriodo >= 0 ? Colors.indigo : Colors.orange,
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  icon: Icons.list_alt_outlined,
                  title:
                      'Lançamentos (${docs.length}'
                      '${_preset == -1 ? ' • ${_fmtData(_ini)} a ${_fmtData(_fim)}' : ''}'
                      '${_preset == -2 ? ' • Desde o início' : ''}'
                      '${_tipo == null ? '' : ' • ${_tipo == 'entrada' ? 'Entradas' : 'Saídas'}'})',
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final doc = docs[i];
                      final m = doc.data();

                      final data = (m['data'] as Timestamp?)?.toDate();
                      final tipo = (m['tipo'] ?? '').toString();
                      final obs = (m['observacao'] ?? '').toString();
                      final pedidoNumero =
                          (m['pedidoNumero'] ?? 0) as int? ?? 0;
                      final parcela = (m['parcela'] ?? 0) as int? ?? 0;
                      final clienteNome = (m['clienteNome'] ?? '').toString();
                      final fornecedorNome =
                          (m['fornecedorNome'] ?? '').toString();
                      final valor = _asNum(m['valorAbs']);

                      final contra =
                          clienteNome.isNotEmpty
                              ? clienteNome
                              : (fornecedorNome.isNotEmpty
                                  ? fornecedorNome
                                  : '—');
                      final badge = tipo == 'entrada' ? 'Entrada' : 'Saída';
                      final color =
                          tipo == 'entrada' ? Colors.teal : Colors.red;

                      final chips = <String>[
                        if (pedidoNumero > 0)
                          'Pedido #${pedidoNumero.toString().padLeft(3, '0')}',
                        if (parcela > 0) 'Parcela $parcela',
                        if (contra != '—') contra,
                        badge,
                      ];

                      return ListTile(
                        onTap: () => _editarLancamento(doc.id, m),
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.12),
                          child: Icon(
                            tipo == 'entrada'
                                ? Icons.call_received
                                : Icons.call_made,
                            color: color,
                          ),
                        ),
                        title: Text(
                          '${data == null ? '—' : _fmtData(data)} • ${_fmtMoeda(tipo == 'entrada' ? valor : -valor)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (obs.isNotEmpty) obs,
                            if (chips.isNotEmpty) chips.join(' • '),
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _editarLancamento(doc.id, m);
                            if (v == 'del') _excluirLancamento(doc.id);
                          },
                          itemBuilder:
                              (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Editar'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'del',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Excluir'),
                                  ),
                                ),
                              ],
                          child: const Icon(Icons.more_vert),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ======================== Novo Lançamento (sheet) ========================

class NovoLancamentoSheet extends StatefulWidget {
  final String currentUid; // UID do logado (grava em userId)
  final String currentCompanyId; // companyId vindo de users/{uid}

  // Edição
  final String? docId; // null = novo
  final Map<String, dynamic>? initial;

  const NovoLancamentoSheet({
    super.key,
    required this.currentUid,
    required this.currentCompanyId,
    this.docId,
    this.initial,
  });

  @override
  State<NovoLancamentoSheet> createState() => _NovoLancamentoSheetState();
}

class _NovoLancamentoSheetState extends State<NovoLancamentoSheet> {
  final _fs = FirebaseFirestore.instance;
  final _form = GlobalKey<FormState>();

  DateTime _data = DateTime.now();
  String _tipo = 'entrada'; // entrada | saida
  final _valorCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _pedidoNumeroCtrl = TextEditingController();
  final _parcelaCtrl = TextEditingController();
  final _contraParteCtrl = TextEditingController(); // nome exibido

  bool get _isEdicao => widget.docId != null;
  bool get _isEntrada => _tipo == 'entrada';

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m != null) {
      _data = (m['data'] as Timestamp?)?.toDate() ?? DateTime.now();
      _tipo = (m['tipo'] ?? 'entrada').toString();
      final valorAbs =
          (m['valorAbs'] is num) ? (m['valorAbs'] as num).toDouble() : 0.0;
      if (valorAbs > 0)
        _valorCtrl.text = valorAbs.toStringAsFixed(2).replaceAll('.', ',');
      _obsCtrl.text = (m['observacao'] ?? '').toString();
      _pedidoNumeroCtrl.text =
          ((m['pedidoNumero'] ?? 0) as int? ?? 0) == 0
              ? ''
              : ((m['pedidoNumero'] ?? 0) as int).toString();
      _parcelaCtrl.text =
          ((m['parcela'] ?? 0) as int? ?? 0) == 0
              ? ''
              : ((m['parcela'] ?? 0) as int).toString();
      final cliente = (m['clienteNome'] ?? '').toString();
      final fornecedor = (m['fornecedorNome'] ?? '').toString();
      _contraParteCtrl.text =
          cliente.isNotEmpty
              ? cliente
              : (fornecedor.isNotEmpty ? fornecedor : '');
    }
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _obsCtrl.dispose();
    _pedidoNumeroCtrl.dispose();
    _parcelaCtrl.dispose();
    _contraParteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 3),
      helpText: 'Data do lançamento',
    );
    if (d != null) setState(() => _data = d);
  }

  double _parseValor(String s) {
    if (s.isEmpty) return 0.0;
    String x = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    final lastComma = x.lastIndexOf(',');
    final lastDot = x.lastIndexOf('.');
    final sep = (lastComma > lastDot) ? lastComma : lastDot;
    final isNeg = x.startsWith('-');

    if (sep >= 0) {
      final intPart = x.substring(0, sep).replaceAll(RegExp(r'[^0-9]'), '');
      final fracPart = x.substring(sep + 1).replaceAll(RegExp(r'[^0-9]'), '');
      x = '${isNeg ? '-' : ''}$intPart.${fracPart.isEmpty ? '0' : fracPart}';
    } else {
      x = '${isNeg ? '-' : ''}${x.replaceAll(RegExp(r'[^0-9]'), '')}';
    }
    return double.tryParse(x) ?? 0.0;
  }

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final valorAbs = _parseValor(_valorCtrl.text);
    if (valorAbs <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um valor válido.')));
      return;
    }

    final pedidoNumero = int.tryParse(_pedidoNumeroCtrl.text.trim()) ?? 0;
    final parcela = int.tryParse(_parcelaCtrl.text.trim()) ?? 0;

    final now = FieldValue.serverTimestamp();

    final common = <String, dynamic>{
      'data': Timestamp.fromDate(DateTime(_data.year, _data.month, _data.day)),
      'tipo': _tipo,
      'valorAbs': valorAbs,
      'valor': _isEntrada ? valorAbs : -valorAbs,
      'observacao': _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      'clienteNome':
          _isEntrada
              ? (_contraParteCtrl.text.trim().isEmpty
                  ? null
                  : _contraParteCtrl.text.trim())
              : null,
      'fornecedorNome':
          !_isEntrada
              ? (_contraParteCtrl.text.trim().isEmpty
                  ? null
                  : _contraParteCtrl.text.trim())
              : null,
      'pedidoNumero': pedidoNumero == 0 ? null : pedidoNumero,
      'parcela': parcela == 0 ? null : parcela,
      'updatedAt': now,
    };

    try {
      if (_isEdicao) {
        await _fs.collection('fluxo_caixa').doc(widget.docId!).update(common);
      } else {
        final payload = <String, dynamic>{
          ...common,
          'userId': widget.currentUid,
          'companyId': widget.currentCompanyId,
          'createdByUid': widget.currentUid,
          'createdAt': now,
        };
        await _fs.collection('fluxo_caixa').add(payload);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad =
        MediaQuery.of(context).viewInsets +
        const EdgeInsets.fromLTRB(16, 12, 16, 24);

    return SafeArea(
      child: Padding(
        padding: pad,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Text(
                _isEdicao ? 'Editar lançamento' : 'Novo lançamento',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'entrada', label: Text('Entrada')),
                        ButtonSegment(value: 'saida', label: Text('Saída')),
                      ],
                      selected: {_tipo},
                      onSelectionChanged:
                          (s) => setState(() => _tipo = s.first),
                      showSelectedIcon: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _pickData,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _valorCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor (ex.: 1.234,56 ou 1234.56)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
                validator:
                    (v) =>
                        (_parseValor(v ?? '') <= 0)
                            ? 'Informe um valor > 0'
                            : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _contraParteCtrl,
                decoration: InputDecoration(
                  labelText:
                      _tipo == 'entrada'
                          ? 'Cliente (origem)'
                          : 'Fornecedor (origem)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pedidoNumeroCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Número do pedido (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _parcelaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Parcela (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _obsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salvar,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_isEdicao ? 'Salvar alterações' : 'Salvar'),
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
}

// ============================== Reusáveis ==============================

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, // ocupa a linha inteira
      child: Card(
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 2),
                    // Evita corte do valor: cabe em uma linha, reduz a fonte se necessário
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onSet30;
  final VoidCallback onSet90;
  final VoidCallback onCustom;

  const _EmptyState({
    required this.title,
    this.subtitle,
    required this.onSet30,
    required this.onSet90,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onSet30,
                  child: const Text('Últimos 30 dias'),
                ),
                OutlinedButton(
                  onPressed: onSet90,
                  child: const Text('Últimos 90 dias'),
                ),
                OutlinedButton(
                  onPressed: onCustom,
                  child: const Text('Personalizar…'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
