// lib/Dashboard/ContasReceberDashboardScreen.dart
// Dashboard de Contas a Receber (contas_receber)
// - Filtros: período, status (aberto/pago/atrasado[derivado]) e categoria
// - KPIs: A receber, Recebido, Em atraso, Títulos, % Recebido
// - Gráfico: BARRAS AGRUPADAS (Valor por VENCIMENTO x Recebido por DATA DE PAGAMENTO)
// - Top clientes por saldo
// - Lista de títulos (respeita chips de status; "atrasado" é filtrado em memória)
//
// Índices Firestore sugeridos (multiempresa):
// 1) companyId ASC, status ASC, vencimento ASC
// 2) companyId ASC, vencimento ASC

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ContasReceberDashboardStyle {
  static const Color primary = Color(0xFF6A2BFF);
  static const Color primaryDark = Color(0xFF32106C);
  static const Color orange = Color(0xFFFF9800);
  static const Color green = Color(0xFF16A34A);
  static const Color red = Color(0xFFDC2626);
  static const Color teal = Color(0xFF0F9D8A);
  static const Color indigo = Color(0xFF4F46E5);
  static const Color background = Color(0xFFF7F7FB);
  static const Color surface = Colors.white;
  static const Color text = Color(0xFF17152B);
  static const Color muted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE7E5EF);

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ];
}

class ContasReceberDashboardScreen extends StatefulWidget {
  const ContasReceberDashboardScreen({super.key});

  @override
  State<ContasReceberDashboardScreen> createState() =>
      _ContasReceberDashboardScreenState();
}

class _ContasReceberDashboardScreenState
    extends State<ContasReceberDashboardScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== AUTH/ESCOPO =====
  String? _uid;
  String? _companyId; // users.companyId
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  // ====== CONFIG (coleção e campos) ======
  static const String kCollection = 'contas_receber';
  static const String kScopeField = 'companyId'; // << escopo multiempresa
  static const String kDateField = 'vencimento';
  static const String kValorField = 'valor';
  static const String kValorPagoField = 'valorPago';
  static const String kStatusField = 'status'; // 'aberto'|'pago'|'cancelado'
  static const String kClienteField = 'clienteNome';

  // >>> campos de CATEGORIA
  static const String kCatKeyField = 'categoriaKey';
  static const String kCatNomeField = 'categoriaNome';

  static const String _kAllStatus = '__ALL__';
  static const String _kAllCats = '__ALL_CATS__';

  // ====== filtros ======
  DateTime _ini = _at00(DateTime.now().subtract(const Duration(days: 29)));
  DateTime _fim = _at2359(DateTime.now());
  int _preset = 30; // 0=hoje, 7, 30, 90, -1=custom

  // null | 'aberto' | 'pago' | 'atrasado' (sem 'cancelado')
  String? _status;

  // Categoria selecionada (preferir key; nome é fallback)
  String? _categoriaKeySel;
  String? _categoriaNomeSel;

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid;
    _initScope();
    _auth.authStateChanges().listen((u) async {
      _uid = u?.uid;
      await _initScope();
      if (mounted) setState(() {});
    });
  }

  // ============ RESOLUÇÃO DE ESCOPO (companyId ?? uid) ============
  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
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
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();
      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid;
        _loadingScope = false;
      });
      debugPrint(
        '[CRDash] escopo resolvido: scopeUserId=$_scopeUserId (companyId=$_companyId, uid=${u.uid})',
      );
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar escopo: $e';
        _scopeUserId = null;
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    // 1) por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid.data();
    } catch (_) {}

    // 2) fallback por emailKey
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

  void _setPreset(int days) {
    final now = DateTime.now();
    setState(() {
      _preset = days;
      if (days == 0) {
        _ini = _at00(now);
        _fim = _at2359(now);
      } else {
        _ini = _at00(now.subtract(Duration(days: days - 1)));
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

  // ================== QUERY (SEM CANCELADOS) ==================
  Query<Map<String, dynamic>> _query() {
    final scope = _scopeUserId ?? '__';
    final iniTs = Timestamp.fromDate(_ini);
    final fimExclusive = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExclusive);

    // Exclui 'cancelado' no servidor
    var q = _fs
        .collection(kCollection)
        .where(kScopeField, isEqualTo: scope)
        .where(kStatusField, whereIn: ['aberto', 'pago'])
        .where(kDateField, isGreaterThanOrEqualTo: iniTs)
        .where(kDateField, isLessThan: fimTs)
        .orderBy(kDateField);

    debugPrint(
      '[CRDash] query (sem cancelados): scope=$scope ini=$_ini fim=$_fim statusUI=$_status catKey=$_categoriaKeySel',
    );
    return q;
  }

  // Coleta opções de categoria a partir dos docs
  List<({String? key, String? nome})> _collectCategoriaOpts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final cats = <String, ({String? key, String? nome})>{};
    for (final d in docs) {
      final m = d.data();
      final key =
          (m[kCatKeyField]?.toString().trim().isEmpty ?? true)
              ? null
              : (m[kCatKeyField] as String);
      final nome =
          (m[kCatNomeField]?.toString().trim().isEmpty ?? true)
              ? null
              : (m[kCatNomeField] as String);
      final id = (key ?? nome ?? '').trim();
      if (id.isEmpty) continue;
      cats[id] = (key: key, nome: nome);
    }
    final list =
        cats.values.toList()..sort(
          (a, b) => (a.nome ?? a.key ?? '').toLowerCase().compareTo(
            (b.nome ?? b.key ?? '').toLowerCase(),
          ),
        );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: ContasReceberDashboardStyle.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: ContasReceberDashboardStyle.background,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _scopeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ContasReceberDashboardStyle.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_scopeUserId == null) {
      return const Scaffold(
        backgroundColor: ContasReceberDashboardStyle.background,
        body: Center(child: Text('Faça login para visualizar.')),
      );
    }

    return Scaffold(
      backgroundColor: ContasReceberDashboardStyle.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query().snapshots(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'Erro ao carregar: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return _EmptyState(
                    title: 'Sem títulos no período selecionado.',
                    subtitle:
                        'Período: ${_fmtData(_ini)} a ${_fmtData(_fim)}\nEscopo: ${_scopeUserId!}',
                    onSet30: () => _setPreset(30),
                    onSet90: () => _setPreset(90),
                    onCustom: _pickCustomRange,
                  );
                }

                List<QueryDocumentSnapshot<Map<String, dynamic>>> viewDocs =
                    docs;

                if (_status == 'aberto' || _status == 'pago') {
                  viewDocs =
                      viewDocs
                          .where(
                            (d) =>
                                (d.data()[kStatusField] ?? '').toString() ==
                                _status,
                          )
                          .toList();
                } else if (_status == 'atrasado') {
                  final hoje = _at00(DateTime.now());
                  viewDocs =
                      viewDocs.where((d) {
                        final m = d.data();
                        final st = (m[kStatusField] ?? '').toString();
                        final dtV = (m[kDateField] as Timestamp?)?.toDate();
                        final valor = _asNum(m[kValorField]);
                        final pago = _asNum(m[kValorPagoField]);
                        final saldo = max(0.0, valor - pago);
                        return st != 'pago' &&
                            dtV != null &&
                            _at00(dtV).isBefore(hoje) &&
                            saldo > 0;
                      }).toList();
                }

                if (_categoriaKeySel != null || _categoriaNomeSel != null) {
                  viewDocs =
                      viewDocs.where((d) {
                        final m = d.data();
                        final catKey =
                            (m[kCatKeyField] ?? '').toString().trim();
                        final catNome =
                            (m[kCatNomeField] ?? '').toString().trim();

                        if (_categoriaKeySel != null &&
                            _categoriaKeySel!.isNotEmpty) {
                          if (catKey.isNotEmpty) {
                            return catKey == _categoriaKeySel;
                          }
                          if (_categoriaNomeSel != null &&
                              _categoriaNomeSel!.isNotEmpty) {
                            return catNome == _categoriaNomeSel;
                          }
                          return false;
                        } else if (_categoriaNomeSel != null &&
                            _categoriaNomeSel!.isNotEmpty) {
                          return catNome == _categoriaNomeSel;
                        }
                        return true;
                      }).toList();
                }

                if (viewDocs.isEmpty) {
                  return _EmptyState(
                    title: 'Nada para exibir com o filtro atual.',
                    subtitle:
                        '${_status == null ? "Todos" : _labelStatus(_status!)} • ${_fmtData(_ini)} a ${_fmtData(_fim)}',
                    onSet30: () => _setPreset(30),
                    onSet90: () => _setPreset(90),
                    onCustom: _pickCustomRange,
                  );
                }

                double totalTitulo = 0.0;
                double totalRecebido = 0.0;
                double totalAberto = 0.0;
                double totalAtrasado = 0.0;
                final int qtdTitulos = viewDocs.length;

                final byStatus = <String, int>{};
                final byCliente = <String, double>{};
                final byVencValor = <DateTime, double>{};
                final byPgPago = <DateTime, double>{};

                final hoje = _at00(DateTime.now());
                int qtdAtrasados = 0;

                for (final d in viewDocs) {
                  final m = d.data();
                  final valor = _asNum(m[kValorField]);
                  final pago = _asNum(m[kValorPagoField]);
                  final status = (m[kStatusField] ?? '').toString();
                  final dtVenc = (m[kDateField] as Timestamp?)?.toDate();
                  final dtPg = (m['dataPagamento'] as Timestamp?)?.toDate();
                  final cliente = (m[kClienteField] ?? '—').toString();

                  totalTitulo += valor;
                  totalRecebido += pago;

                  final saldo = max(0.0, valor - pago);
                  totalAberto += saldo;

                  final isAtrasado =
                      status != 'pago' &&
                      dtVenc != null &&
                      _at00(dtVenc).isBefore(hoje) &&
                      saldo > 0;

                  if (isAtrasado) {
                    totalAtrasado += saldo;
                    qtdAtrasados++;
                  }

                  if (dtVenc != null) {
                    final k = _at00(dtVenc);
                    byVencValor.update(
                      k,
                      (v) => v + valor,
                      ifAbsent: () => valor,
                    );
                  }

                  if (dtPg != null && pago > 0) {
                    final k = _at00(dtPg);
                    byPgPago.update(k, (v) => v + pago, ifAbsent: () => pago);
                  }

                  byStatus.update(
                    status.isEmpty ? '—' : status,
                    (v) => v + 1,
                    ifAbsent: () => 1,
                  );

                  byCliente.update(
                    cliente.isEmpty ? '—' : cliente,
                    (v) => v + saldo,
                    ifAbsent: () => saldo,
                  );
                }

                if (qtdAtrasados > 0) {
                  byStatus['atrasado'] = qtdAtrasados;
                }

                final percRecebido =
                    totalTitulo == 0 ? 0 : (totalRecebido / totalTitulo) * 100;

                final allDays =
                    <DateTime>{
                        ...byVencValor.keys.map(_at00),
                        ...byPgPago.keys.map(_at00),
                      }.toList()
                      ..sort();

                final barGroups = <BarChartGroupData>[
                  for (int i = 0; i < allDays.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 6,
                      barRods: [
                        BarChartRodData(
                          toY: byVencValor[allDays[i]] ?? 0.0,
                          width: 10,
                          borderRadius: BorderRadius.circular(4),
                          color: ContasReceberDashboardStyle.primary,
                        ),
                        BarChartRodData(
                          toY: byPgPago[allDays[i]] ?? 0.0,
                          width: 10,
                          borderRadius: BorderRadius.circular(4),
                          color: ContasReceberDashboardStyle.teal,
                        ),
                      ],
                    ),
                ];

                final categoriaOpts = _collectCategoriaOpts(docs);

                final top =
                    byCliente.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value));
                final top5 = top.take(5).toList();

                final periodoStr =
                    _preset == -1
                        ? ' • ${_fmtData(_ini)} a ${_fmtData(_fim)}'
                        : '';

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: ContasReceberDashboardStyle.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      _buildFilters(categoriaOpts),
                      const SizedBox(height: 14),

                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _KpiCard(
                            icon: Icons.request_quote_outlined,
                            label: 'A receber',
                            value: _fmtMoeda(totalAberto),
                            color: ContasReceberDashboardStyle.primary,
                          ),
                          _KpiCard(
                            icon: Icons.payments_outlined,
                            label: 'Recebido',
                            value: _fmtMoeda(totalRecebido),
                            color: ContasReceberDashboardStyle.teal,
                          ),
                          _KpiCard(
                            icon: Icons.warning_amber_outlined,
                            label: 'Em atraso',
                            value: _fmtMoeda(totalAtrasado),
                            color: ContasReceberDashboardStyle.red,
                          ),
                          _KpiCard(
                            icon: Icons.receipt_long_outlined,
                            label: 'Títulos',
                            value: '$qtdTitulos',
                            color: ContasReceberDashboardStyle.indigo,
                          ),
                          _KpiCard(
                            icon: Icons.verified_outlined,
                            label: '% Recebido',
                            value: '${percRecebido.toStringAsFixed(1)}%',
                            color: ContasReceberDashboardStyle.orange,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      if (barGroups.isNotEmpty)
                        _SectionCard(
                          icon: Icons.bar_chart_outlined,
                          title: 'Valor × Recebido por dia',
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(
                                  bottom: 10,
                                  left: 4,
                                  right: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _LegendDot(
                                      color:
                                          ContasReceberDashboardStyle.primary,
                                      label: 'Valor',
                                    ),
                                    SizedBox(width: 12),
                                    _LegendDot(
                                      color: ContasReceberDashboardStyle.teal,
                                      label: 'Recebido',
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 240,
                                child: BarChart(
                                  BarChartData(
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      getDrawingHorizontalLine:
                                          (value) => FlLine(
                                            color: const Color(0xFFEDEAF5),
                                            strokeWidth: 1,
                                          ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    barGroups: barGroups,
                                    titlesData: FlTitlesData(
                                      topTitles: const AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      rightTitles: const AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: false,
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 48,
                                          getTitlesWidget: (v, meta) {
                                            if (v <= 0) {
                                              return const SizedBox.shrink();
                                            }
                                            return Text(
                                              _formatCompact(v.toDouble()),
                                              style: const TextStyle(
                                                color:
                                                    ContasReceberDashboardStyle
                                                        .muted,
                                                fontSize: 10,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval:
                                              max(
                                                1,
                                                (allDays.length / 6).floor(),
                                              ).toDouble(),
                                          getTitlesWidget: (v, meta) {
                                            final i = v.toInt();
                                            if (i < 0 || i >= allDays.length) {
                                              return const SizedBox.shrink();
                                            }
                                            final d = allDays[i];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              child: Text(
                                                '${d.day}/${d.month}',
                                                style: const TextStyle(
                                                  color:
                                                      ContasReceberDashboardStyle
                                                          .muted,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    barTouchData: BarTouchData(
                                      enabled: true,
                                      touchTooltipData: BarTouchTooltipData(
                                        tooltipBgColor: Colors.black87,
                                        tooltipRoundedRadius: 8,
                                        fitInsideHorizontally: true,
                                        fitInsideVertically: true,
                                        getTooltipItem: (
                                          group,
                                          groupIndex,
                                          rod,
                                          rodIndex,
                                        ) {
                                          return BarTooltipItem(
                                            _formatCompact(rod.toY),
                                            const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 16),

                      _SectionCard(
                        icon: Icons.flag_outlined,
                        title: 'Títulos por status',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final e in byStatus.entries)
                              if (e.key == 'aberto' ||
                                  e.key == 'pago' ||
                                  e.key == 'atrasado')
                                ChoiceChip(
                                  label: Text(
                                    '${_labelStatus(e.key)}: ${e.value}',
                                  ),
                                  selected: _status == e.key,
                                  selectedColor:
                                      e.key == 'pago'
                                          ? ContasReceberDashboardStyle.teal
                                          : e.key == 'atrasado'
                                          ? ContasReceberDashboardStyle.red
                                          : ContasReceberDashboardStyle.primary,
                                  labelStyle: TextStyle(
                                    color:
                                        _status == e.key
                                            ? Colors.white
                                            : ContasReceberDashboardStyle.text,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  showCheckmark: false,
                                  onSelected:
                                      (sel) => setState(
                                        () => _status = sel ? e.key : null,
                                      ),
                                )
                              else
                                Chip(
                                  label: Text(
                                    '${_labelStatus(e.key)}: ${e.value}',
                                  ),
                                ),
                            if (_status != null ||
                                _categoriaKeySel != null ||
                                _categoriaNomeSel != null)
                              ActionChip(
                                avatar: const Icon(Icons.clear, size: 18),
                                label: const Text('Limpar filtros'),
                                onPressed:
                                    () => setState(() {
                                      _status = null;
                                      _categoriaKeySel = null;
                                      _categoriaNomeSel = null;
                                    }),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      _SectionCard(
                        icon: Icons.star_outline_rounded,
                        title: 'Top clientes por saldo',
                        child:
                            top5.isEmpty
                                ? const Text('Sem dados no período.')
                                : Column(
                                  children: [
                                    for (int i = 0; i < top5.length; i++)
                                      _ClienteRank(
                                        posicao: i + 1,
                                        nome:
                                            top5[i].key.isEmpty
                                                ? '—'
                                                : top5[i].key,
                                        valor: _fmtMoeda(top5[i].value),
                                      ),
                                  ],
                                ),
                      ),

                      const SizedBox(height: 16),

                      _SectionCard(
                        icon: Icons.list_alt_outlined,
                        title: 'Títulos (${viewDocs.length}$periodoStr)',
                        child: ListView.separated(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: viewDocs.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final d = viewDocs[i];
                            final m = d.data();
                            final valor = _asNum(m[kValorField]);
                            final pago = _asNum(m[kValorPagoField]);
                            final saldo = max(0.0, valor - pago);
                            final dt = (m[kDateField] as Timestamp?)?.toDate();
                            final status = (m[kStatusField] ?? '').toString();
                            final cliente = (m[kClienteField] ?? '').toString();

                            final color =
                                status == 'pago'
                                    ? ContasReceberDashboardStyle.teal
                                    : ContasReceberDashboardStyle.primary;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: ContasReceberDashboardStyle.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(.10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      status == 'pago'
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.request_quote_outlined,
                                      color: color,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cliente.isEmpty
                                              ? 'Sem cliente'
                                              : cliente,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color:
                                                ContasReceberDashboardStyle
                                                    .text,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            if (dt != null)
                                              'Venc. ${_fmtData(dt)}',
                                            'Saldo ${_fmtMoeda(saldo)}',
                                            _labelStatus(status),
                                          ].join(' • '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color:
                                                ContasReceberDashboardStyle
                                                    .muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _fmtMoeda(valor),
                                    style: const TextStyle(
                                      color: ContasReceberDashboardStyle.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: ContasReceberDashboardStyle.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.white.withOpacity(.16),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.maybePop(context),
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contas a Receber',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Dashboard financeiro',
                  style: TextStyle(color: Color(0xFFD9D4F5), fontSize: 12),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withOpacity(.16),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => setState(() {}),
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(List<({String? key, String? nome})> categoriaOpts) {
    final statusLabel =
        _status == null ? 'Status: Todos' : 'Status: ${_labelStatus(_status!)}';

    final periodoLabel =
        _preset == -1
            ? '${_fmtData(_ini)} • ${_fmtData(_fim)}'
            : (_preset == 0 ? 'Hoje' : 'Últimos $_preset dias');

    final categoriaLabel =
        (_categoriaKeySel == null && _categoriaNomeSel == null)
            ? 'Categoria'
            : 'Categoria: ${_categoriaNomeSel ?? '—'}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ContasReceberDashboardStyle.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: ContasReceberDashboardStyle.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Filtros',
                style: TextStyle(
                  color: ContasReceberDashboardStyle.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  icon: Icons.filter_alt_outlined,
                  child: PopupMenuButton<String>(
                    tooltip: 'Filtrar status',
                    initialValue: _status ?? _kAllStatus,
                    onSelected:
                        (v) => setState(
                          () => _status = (v == _kAllStatus) ? null : v,
                        ),
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem<String>(
                            value: _kAllStatus,
                            child: Text('Todos'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'aberto',
                            child: Text('Em aberto'),
                          ),
                          PopupMenuItem<String>(
                            value: 'pago',
                            child: Text('Pago'),
                          ),
                          PopupMenuItem<String>(
                            value: 'atrasado',
                            child: Text('Atrasado'),
                          ),
                        ],
                    child: _FilterLabel(text: statusLabel),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  icon: Icons.date_range_outlined,
                  child: PopupMenuButton<int>(
                    tooltip: 'Período',
                    onSelected:
                        (v) => v == -1 ? _pickCustomRange() : _setPreset(v),
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem(value: 0, child: Text('Hoje')),
                          PopupMenuItem(
                            value: 7,
                            child: Text('Últimos 7 dias'),
                          ),
                          PopupMenuItem(
                            value: 30,
                            child: Text('Últimos 30 dias'),
                          ),
                          PopupMenuItem(
                            value: 90,
                            child: Text('Últimos 90 dias'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: -1,
                            child: Text('Personalizado…'),
                          ),
                        ],
                    child: _FilterLabel(text: periodoLabel),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  icon: Icons.category_outlined,
                  child: PopupMenuButton<String>(
                    tooltip: 'Filtrar categoria',
                    onSelected: (v) {
                      if (v == _kAllCats) {
                        setState(() {
                          _categoriaKeySel = null;
                          _categoriaNomeSel = null;
                        });
                      } else {
                        final opt = categoriaOpts.firstWhere(
                          (e) => (e.key ?? e.nome ?? '') == v,
                          orElse: () => (key: null, nome: null),
                        );
                        setState(() {
                          _categoriaKeySel = opt.key ?? v;
                          _categoriaNomeSel = opt.nome;
                        });
                      }
                    },
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem<String>(
                            value: _kAllCats,
                            child: Text('Todas as categorias'),
                          ),
                          const PopupMenuDivider(),
                          if (categoriaOpts.isEmpty)
                            const PopupMenuItem<String>(
                              enabled: false,
                              child: Text('Sem categorias no período'),
                            )
                          else
                            ...categoriaOpts.map(
                              (e) => PopupMenuItem<String>(
                                value: e.key ?? e.nome ?? '',
                                child: Text(e.nome ?? e.key ?? '—'),
                              ),
                            ),
                        ],
                    child: _FilterLabel(text: categoriaLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== util =====
  static double _asNum(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0.0;
  }

  static String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtMoeda(num v) {
    final n = v.toDouble();
    final s = n.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  static String _formatCompact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  static String _labelStatus(String s) {
    switch (s) {
      case 'aberto':
        return 'Em aberto';
      case 'pago':
        return 'Pago';
      case 'atrasado':
        return 'Atrasado';
      // 'cancelado' não é usado aqui, mas mantemos fallback:
      case 'cancelado':
        return 'Cancelado';
      default:
        return s;
    }
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'pago':
        return Colors.teal;
      case 'aberto':
      default:
        return Colors.indigo;
    }
  }
}

/* ============================== Widgets ============================== */

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const _FilterPill({required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ContasReceberDashboardStyle.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: ContasReceberDashboardStyle.primary),
          const SizedBox(width: 7),
          child,
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String text;

  const _FilterLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ContasReceberDashboardStyle.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: ContasReceberDashboardStyle.muted,
          ),
        ],
      ),
    );
  }
}

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
      width: min(MediaQuery.of(context).size.width / 2 - 22, 220),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ContasReceberDashboardStyle.border),
          boxShadow: ContasReceberDashboardStyle.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: ContasReceberDashboardStyle.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: ContasReceberDashboardStyle.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ContasReceberDashboardStyle.border),
        boxShadow: ContasReceberDashboardStyle.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ContasReceberDashboardStyle.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: ContasReceberDashboardStyle.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: ContasReceberDashboardStyle.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ClienteRank extends StatelessWidget {
  final int posicao;
  final String nome;
  final String valor;

  const _ClienteRank({
    required this.posicao,
    required this.nome,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ContasReceberDashboardStyle.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ContasReceberDashboardStyle.primary.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$posicao',
              style: const TextStyle(
                color: ContasReceberDashboardStyle.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ContasReceberDashboardStyle.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            valor,
            style: const TextStyle(
              color: ContasReceberDashboardStyle.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
            const Icon(
              Icons.search_off_rounded,
              size: 52,
              color: ContasReceberDashboardStyle.primary,
            ),
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

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
