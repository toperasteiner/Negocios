import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class VendasDashboardScreen extends StatefulWidget {
  const VendasDashboardScreen({super.key});

  @override
  State<VendasDashboardScreen> createState() => _VendasDashboardScreenState();
}

class _VendasDashboardScreenState extends State<VendasDashboardScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== Escopo multiempresa =====
  String? _uid;
  String? _companyId;
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;
  String? _statusFilter; // null = todos os status

  // Campo usado para ESCOPAR as consultas.
  // Se já migrou sua base, use 'companyId'.
  // Se ainda estiver em legado, pode apontar para 'userId' temporariamente.
  static const String kScopeField = 'companyId';

  // ===== filtro de período =====
  DateTime _ini = _at00(DateTime.now().subtract(const Duration(days: 29)));
  DateTime _fim = _at2359(DateTime.now());
  int _preset = 30; // 0=hoje, 7, 30, 90, -1=custom

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid;
    _initScope();
    // Ouve alterações de autenticação e atualiza a tela
    _auth.authStateChanges().listen((u) async {
      _uid = u?.uid;
      await _initScope();
      if (mounted) setState(() {});
    });
  }

  // Carrega escopo: scopeUserId = companyId ?? uid
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
        '[VendasDash] escopo: scopeUserId=$_scopeUserId (companyId=$_companyId uid=${u.uid})',
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

    // 1) users/{uid}
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid.data();
    } catch (_) {}

    // 2) fallback por emailKey (se usar esse campo)
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
    if (days == 0) {
      setState(() {
        _preset = 0;
        _ini = _at00(now);
        _fim = _at2359(now);
      });
    } else {
      setState(() {
        _preset = days;
        _ini = _at00(now.subtract(Duration(days: days - 1)));
        _fim = _at2359(now);
      });
    }
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

  Query<Map<String, dynamic>> _query() {
    // Índices recomendados:
    // 1) companyId (ou userId) ASC, data ASC
    // 2) companyId (ou userId) ASC, status ASC, data ASC  (quando _statusFilter != null)

    final iniTs = Timestamp.fromDate(_ini);
    final fimExclusive = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExclusive);

    var q = _fs
        .collection('pedidos')
        .where(
          kScopeField,
          isEqualTo: _scopeUserId ?? '__',
        ) // <-- multiempresa!
        .where('data', isGreaterThanOrEqualTo: iniTs)
        .where('data', isLessThan: fimTs);

    if (_statusFilter != null && _statusFilter!.isNotEmpty) {
      q = q.where('status', isEqualTo: _statusFilter);
    }

    return q.orderBy('data', descending: false);
  }

  String _fmtMoeda(num v) {
    final n = (v is double) ? v : v.toDouble();
    final s = n.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendas')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_scopeUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Faça login para visualizar.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Período rápido',
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
                  PopupMenuDivider(),
                  PopupMenuItem(value: -1, child: Text('Personalizado…')),
                ],
            child: Row(
              children: [
                const Icon(Icons.date_range),
                const SizedBox(width: 8),
                Text(
                  _preset == -1
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query().snapshots(),
        builder: (ctx, snap) {
          if (snap.hasError) {
            final err = snap.error;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                'Erro ao carregar (provável índice faltando): $err',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];

          // Estado vazio diagnosticável
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      'Sem pedidos no período selecionado.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Período: ${_fmtData(_ini)} a ${_fmtData(_fim)}\n'
                      'Escopo: ${_scopeUserId ?? '—'}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _setPreset(30),
                          child: const Text('Últimos 30 dias'),
                        ),
                        OutlinedButton(
                          onPressed: () => _setPreset(90),
                          child: const Text('Últimos 90 dias'),
                        ),
                        OutlinedButton(
                          onPressed: _pickCustomRange,
                          child: const Text('Personalizar…'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          // === métricas e agrupamentos ===
          double faturamento = 0.0;
          int pedidos = docs.length;
          final byStatus = <String, int>{};
          final byMonth = <String, double>{}; // "2025-01" -> valor
          final byCliente = <String, double>{};

          for (final d in docs) {
            final m = d.data();
            final total = (m['total'] is num) ? (m['total'] + 0.0) : 0.0;
            final status = (m['status'] ?? 'pendente').toString();
            final cliente = (m['clienteNome'] ?? '—').toString();
            final data = (m['data'] as Timestamp?)?.toDate();

            faturamento += total;
            byStatus.update(status, (v) => v + 1, ifAbsent: () => 1);
            byCliente.update(cliente, (v) => v + total, ifAbsent: () => total);

            if (data != null) {
              final key =
                  '${data.year}-${data.month.toString().padLeft(2, '0')}';
              byMonth.update(key, (v) => v + total, ifAbsent: () => total);
            }
          }

          final ticketMedio = pedidos == 0 ? 0.0 : (faturamento / pedidos);

          // ordenar top clientes
          final topClientes =
              byCliente.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
          final top5 = topClientes.take(5).toList();

          // ordenar meses (chave YYYY-MM)
          final mesesOrdenados = byMonth.keys.toList()..sort();
          final bars = [
            for (int i = 0; i < mesesOrdenados.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (byMonth[mesesOrdenados[i]] ?? 0.0),
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ];

          // string do período para o título da lista
          final periodoStr =
              _preset == -1 ? ' • ${_fmtData(_ini)} a ${_fmtData(_fim)}' : '';
          final statusStr =
              _statusFilter == null ? '' : ' • ${_labelStatus(_statusFilter!)}';

          title:
          'Pedidos (${docs.length}$periodoStr$statusStr)';

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                // KPIs
                // === KPIs (grid responsivo, alinhado) ===
                // === KPIs (grid responsivo e alinhado) ===
                LayoutBuilder(
                  builder: (context, cts) {
                    final w = cts.maxWidth;
                    final cols = w < 360 ? 1 : 2;

                    return GridView(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: cols == 1 ? 3.4 : 2.8,
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _KpiCard(
                          icon: Icons.payments_outlined,
                          label: 'Faturamento',
                          value: _fmtMoeda(faturamento),
                          color: cs.primary,
                        ),
                        _KpiCard(
                          icon: Icons.receipt_long_outlined,
                          label: 'Pedidos',
                          value: '$pedidos',
                          color: Colors.indigo,
                        ),
                        _KpiCard(
                          icon: Icons.stacked_line_chart_outlined,
                          label: 'Ticket médio',
                          value: _fmtMoeda(ticketMedio),
                          color: Colors.teal,
                        ),
                        _KpiCard(
                          icon: Icons.verified_outlined,
                          label: 'Aprovados',
                          value: '${byStatus['aprovado'] ?? 0}',
                          color: Colors.blue,
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // GRÁFICO: Faturamento por mês
                if (mesesOrdenados.isNotEmpty)
                  _SectionCard(
                    icon: Icons.bar_chart_outlined,
                    title: 'Faturamento por mês',
                    child: SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          gridData: FlGridData(show: true),
                          borderData: FlBorderData(show: false),
                          barGroups: bars,
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 42,
                                getTitlesWidget: (v, meta) {
                                  if (v <= 0) return const SizedBox.shrink();
                                  return Text(
                                    _formatCompact(v.toDouble()),
                                    style: const TextStyle(fontSize: 11),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, meta) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= mesesOrdenados.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final key = mesesOrdenados[i];
                                  final parts = key.split('-');
                                  final mes = int.tryParse(parts[1]) ?? 0;
                                  final lbl =
                                      '${_mesAbrev(mes)}/${parts[0].substring(2)}';
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      lbl,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  );
                                },
                              ),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // STATUS: chips com contagem
                _SectionCard(
                  icon: Icons.flag_outlined,
                  title: 'Pedidos por status',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Chip "Todos"
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: _statusFilter == null,
                        onSelected: (_) => setState(() => _statusFilter = null),
                      ),
                      // Demais chips (baseado nas contagens do período já carregado)
                      for (final e in byStatus.entries)
                        ChoiceChip(
                          label: Text('${_labelStatus(e.key)}: ${e.value}'),
                          selected: _statusFilter == e.key,
                          onSelected: (sel) {
                            setState(() {
                              _statusFilter = sel ? e.key : null;
                            });
                          },
                        ),
                      if (_statusFilter != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 18),
                          label: const Text('Limpar filtro'),
                          onPressed: () => setState(() => _statusFilter = null),
                        ),
                      if (byStatus.isEmpty)
                        const Text('Sem pedidos no período.'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // TOP CLIENTES
                _SectionCard(
                  icon: Icons.star_outline,
                  title: 'Top clientes (por faturamento)',
                  child:
                      top5.isEmpty
                          ? const Text('Sem dados no período.')
                          : Column(
                            children: [
                              for (final e in top5)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    e.key.isEmpty ? '—' : e.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(_fmtMoeda(e.value)),
                                ),
                            ],
                          ),
                ),

                const SizedBox(height: 16),

                // LISTA de pedidos
                _SectionCard(
                  icon: Icons.list_alt_outlined,
                  title: 'Pedidos (${docs.length}$periodoStr)',
                  child:
                      docs.isEmpty
                          ? const Text('Sem pedidos neste período.')
                          : ListView.separated(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: docs.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = docs[i];
                              final m = d.data();
                              final total =
                                  (m['total'] is num)
                                      ? (m['total'] + 0.0)
                                      : 0.0;
                              final data = (m['data'] as Timestamp?)?.toDate();
                              final numero = (m['numero'] ?? 0) as int? ?? 0;
                              final ano =
                                  (m['ano'] ?? DateTime.now().year) as int? ??
                                  0;
                              final cliente =
                                  (m['clienteNome'] ?? '').toString();
                              final status =
                                  (m['status'] ?? 'pendente').toString();

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.receipt_outlined),
                                title: Text(
                                  'Pedido ${numero.toString().padLeft(3, '0')}-$ano • ${_fmtMoeda(total)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (data != null) _fmtData(data),
                                    if (cliente.isNotEmpty) cliente,
                                    _labelStatus(status),
                                  ].join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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

  static String _mesAbrev(int m) {
    const mm = [
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    if (m < 1 || m > 12) return '';
    return mm[m];
  }

  static String _labelStatus(String s) {
    switch (s) {
      case 'pendente':
        return 'Pendente';
      case 'aguardando_aprovacao':
        return 'Aguard. aprovação';
      case 'aprovado':
        return 'Aprovado';
      case 'em_andamento':
        return 'Em andamento';
      case 'aguardando_pagamento':
        return 'Aguard. pagamento';
      case 'enviado':
        return 'Enviado';
      case 'concluido':
        return 'Concluído';
      case 'garantia':
        return 'Garantia';
      case 'cancelado':
        return 'Cancelado';
      default:
        return s;
    }
  }

  static String _formatCompact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

/* ============================== Widgets ============================== */

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
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.black54,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
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
