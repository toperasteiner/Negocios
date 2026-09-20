// lib/Dashboard/PedidosDashboardScreen.dart
// Dashboard de Pedidos — MULTIEMPRESA
//
// Escopo: scopeUserId = (users.companyId ?? auth.uid)
// Índices sugeridos no Firestore (recomendado):
// 1) companyId ASC, data ASC
// 2) companyId ASC, clienteId ASC, data ASC
// 3) companyId ASC, status ASC, data ASC   // >>> STATUS (caso filtrar por status)

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class PedidosDashboardScreen extends StatefulWidget {
  const PedidosDashboardScreen({super.key});

  @override
  State<PedidosDashboardScreen> createState() => _PedidosDashboardScreenState();
}

class _PedidosDashboardScreenState extends State<PedidosDashboardScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ======= Escopo (multiempresa) =======
  String? _uid;
  String? _companyId; // lido de users.companyId
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  // ======= Config =======
  static const String kCollection = 'pedidos';
  static const String kScopeField = 'companyId';

  static const String kDate = 'data';
  static const String kClienteId = 'clienteId';
  static const String kClienteNome = 'clienteNome';
  static const String kTotal = 'total';
  static const String kSubtotal = 'subtotal';
  static const String kDescontoValor = 'descontoValor';
  static const String kDescontoAplicado = 'descontoAplicado';
  static const String kTaxaEntrega = 'taxaEntrega';
  static const String kStatus = 'status';
  static const String kNumero = 'numero';

  // Sentinela para "Todos os status" / limpar
  static const String _kAllStatus = '__ALL__';

  // ======= Filtros =======
  DateTime _ini = _at00(DateTime.now().subtract(const Duration(days: 29)));
  DateTime _fim = _at2359(DateTime.now());
  int _preset = 30; // 0=Hoje, 7, 30, 90, -1=custom

  String? _clienteIdFilter; // null = todos
  String? _clienteNomeFilter; // exibição

  // >>> STATUS NO APPBAR
  String? _statusFilter; // null = todos
  static const Map<String, String> kStatusLabels = {
    'pendente': 'Pendente',
    'aguardando_aprovacao': 'Aguardando aprovação',
    'aprovado': 'Aprovado',
    'em_andamento': 'Em andamento',
    'aguardando_pagamento': 'Aguardando pagamento',
    'enviado': 'Enviado',
    'concluido': 'Concluído',
    'garantia': 'Garantia',
    'cancelado': 'Cancelado',
  };

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
        '[PedidosDash] escopo: scopeUserId=$_scopeUserId (companyId=$_companyId uid=${u.uid})',
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

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid.data();
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

  Query<Map<String, dynamic>> _query() {
    final iniTs = Timestamp.fromDate(_ini);
    final fimExc = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExc);

    var q = _fs
        .collection(kCollection)
        .where(kScopeField, isEqualTo: _scopeUserId ?? '__')
        .where(kDate, isGreaterThanOrEqualTo: iniTs)
        .where(kDate, isLessThan: fimTs);

    if (_clienteIdFilter != null && _clienteIdFilter!.isNotEmpty) {
      q = q.where(kClienteId, isEqualTo: _clienteIdFilter);
    }
    if (_statusFilter != null && _statusFilter!.isNotEmpty) {
      q = q.where(kStatus, isEqualTo: _statusFilter);
    }

    debugPrint(
      '[PedidosDash] query escopo=${_scopeUserId} cliente=${_clienteIdFilter} status=${_statusFilter} ini=$_ini fim=$_fim',
    );
    return q.orderBy(kDate);
  }

  void _clearCliente() {
    setState(() {
      _clienteIdFilter = null;
      _clienteNomeFilter = null;
    });
  }

  void _clearStatus() => setState(() => _statusFilter = null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_scopeError != null) {
      return Scaffold(
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

    // Opções de status ordenadas alfabeticamente pelo rótulo
    final statusOptions =
        kStatusLabels.keys.toList()..sort(
          (a, b) => (kStatusLabels[a] ?? a).toLowerCase().compareTo(
            (kStatusLabels[b] ?? b).toLowerCase(),
          ),
        );

    final statusAtualLabel =
        _statusFilter == null
            ? 'Todos os status'
            : (kStatusLabels[_statusFilter] ?? _statusFilter!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard • Pedidos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // ======= Pílula: STATUS =======
                _FilterPill(
                  icon: Icons.flag_outlined,
                  child: PopupMenuButton<String>(
                    tooltip: 'Filtrar por status',
                    onSelected:
                        (v) => setState(
                          () => _statusFilter = (v == _kAllStatus) ? null : v,
                        ),
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem<String>(
                            value: _kAllStatus,
                            child: Text('Todos os status'),
                          ),
                          const PopupMenuDivider(),
                          // opções de status (ordenadas pelo rótulo amigável)
                          ...([...kStatusLabels.keys]..sort(
                                (a, b) => (kStatusLabels[a] ?? a)
                                    .toLowerCase()
                                    .compareTo(
                                      (kStatusLabels[b] ?? b).toLowerCase(),
                                    ),
                              ))
                              .map(
                                (s) => PopupMenuItem<String>(
                                  value: s,
                                  child: Text(kStatusLabels[s] ?? s),
                                ),
                              )
                              .toList(),
                          if (_statusFilter != null) const PopupMenuDivider(),
                          if (_statusFilter != null)
                            const PopupMenuItem<String>(
                              value: _kAllStatus,
                              child: Text('Limpar filtro'),
                            ),
                        ],
                    child: _FilterLabel(
                      text:
                          _statusFilter == null
                              ? 'Todos os status'
                              : (kStatusLabels[_statusFilter] ??
                                  _statusFilter!),
                    ),
                  ),
                ),

                // ======= Pílula: PERÍODO =======
                _FilterPill(
                  icon: Icons.date_range,
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
                    child: _FilterLabel(
                      text:
                          _preset == -1
                              ? '${_fmtData(_ini)} • ${_fmtData(_fim)}'
                              : _preset == 0
                              ? 'Hoje'
                              : 'Últimos $_preset dias',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
              title: 'Sem pedidos no período selecionado.',
              subtitle:
                  'Período: ${_fmtData(_ini)} a ${_fmtData(_fim)}'
                  '${_clienteNomeFilter == null ? '' : '\nCliente: ${_clienteNomeFilter!}'}'
                  '${_statusFilter == null ? '' : '\nStatus: ${kStatusLabels[_statusFilter] ?? _statusFilter}'}',
              onSet30: () => _setPreset(30),
              onSet90: () => _setPreset(90),
              onCustom: _pickCustomRange,
            );
          }

          double total = 0;
          double descontos = 0;
          double entrega = 0;
          int qtd = docs.length;

          final byDia = <DateTime, double>{};
          final byClienteValor = <String, double>{};
          final byClienteIdNome = <String, String>{};

          for (final d in docs) {
            final m = d.data();

            final val = _asNum(m[kTotal]);
            final deliv = _asNum(m[kTaxaEntrega]);

            double desc = _asNum(m[kDescontoAplicado]);
            if (desc == 0) desc = _asNum(m[kDescontoValor]);

            final subtotal = _asNum(m[kSubtotal]);
            if (desc == 0 && subtotal > 0) {
              final derivado = (subtotal + deliv) - val;
              if (derivado > 0) desc = derivado;
            }

            final dt = (m[kDate] as Timestamp?)?.toDate();
            final clienteId = (m[kClienteId] ?? '').toString();
            final clienteNm = (m[kClienteNome] ?? '—').toString();

            total += val;
            descontos += desc;
            entrega += deliv;

            if (dt != null) {
              final k = _at00(dt);
              byDia.update(k, (v) => v + val, ifAbsent: () => val);
            }

            final nome = clienteNm.isEmpty ? '—' : clienteNm;
            byClienteValor.update(nome, (v) => v + val, ifAbsent: () => val);
            if (clienteId.isNotEmpty) byClienteIdNome[clienteId] = nome;
          }

          final ticketMedio = qtd == 0 ? 0 : total / qtd;

          final dias = byDia.keys.toList()..sort();
          final barGroups = <BarChartGroupData>[
            for (int i = 0; i < dias.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: byDia[dias[i]] ?? 0,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                    color: cs.primary,
                  ),
                ],
              ),
          ];

          final clientesOrdenados =
              byClienteValor.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
          final top5 = clientesOrdenados.take(5).toList();

          final periodoStr =
              _preset == -1 ? ' • ${_fmtData(_ini)} a ${_fmtData(_fim)}' : '';
          final clienteStr =
              _clienteNomeFilter == null ? '' : ' • ${_clienteNomeFilter!}';
          final statusStr =
              _statusFilter == null
                  ? ''
                  : ' • ${kStatusLabels[_statusFilter] ?? _statusFilter!}';

          final availableIds = byClienteIdNome.keys.toSet();
          final String? dropdownClienteValue =
              (_clienteIdFilter != null &&
                      availableIds.contains(_clienteIdFilter))
                  ? _clienteIdFilter
                  : null;

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                // === Filtro por cliente (permanece abaixo do cabeçalho) ===
                _SectionCard(
                  icon: Icons.people_alt_outlined,
                  title: 'Cliente',
                  trailing:
                      dropdownClienteValue == null
                          ? null
                          : TextButton.icon(
                            onPressed: _clearCliente,
                            icon: const Icon(Icons.clear),
                            label: const Text('Limpar'),
                          ),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por cliente',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: dropdownClienteValue,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos os clientes'),
                          ),
                          ...byClienteIdNome.entries
                              .map(
                                (e) => DropdownMenuItem<String?>(
                                  value: e.key,
                                  child: Text(
                                    e.value.isEmpty ? '—' : e.value,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                              .toList()
                            ..sort(
                              (a, b) => (a.child as Text).data!
                                  .toLowerCase()
                                  .compareTo(
                                    (b.child as Text).data!.toLowerCase(),
                                  ),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _clienteIdFilter = v;
                            _clienteNomeFilter =
                                v == null ? null : byClienteIdNome[v];
                          });
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // === KPIs ===
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool oneCol = constraints.maxWidth < 420;
                    final int cols = oneCol ? 1 : 2;

                    return GridView.count(
                      crossAxisCount: cols,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 4.8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _KpiCard.compact(
                          icon: Icons.request_quote_outlined,
                          label: 'Total',
                          value: _fmtMoeda(total),
                          color: cs.primary,
                        ),
                        _KpiCard.compact(
                          icon: Icons.receipt_long_outlined,
                          label: 'Pedidos',
                          value: '$qtd',
                          color: Colors.indigo,
                        ),
                        _KpiCard.compact(
                          icon: Icons.analytics_outlined,
                          label: 'Ticket médio',
                          value: _fmtMoeda(ticketMedio),
                          color: Colors.teal,
                        ),
                        _KpiCard.compact(
                          icon: Icons.local_offer_outlined,
                          label: 'Descontos',
                          value: _fmtMoeda(descontos),
                          color: Colors.orange,
                        ),
                        _KpiCard.compact(
                          icon: Icons.delivery_dining_outlined,
                          label: 'Entrega',
                          value: _fmtMoeda(entrega),
                          color: Colors.brown,
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // === Gráfico: Total por dia ===
                if (barGroups.isNotEmpty)
                  _SectionCard(
                    icon: Icons.bar_chart_outlined,
                    title: 'Total por dia$periodoStr$clienteStr$statusStr',
                    child: SizedBox(
                      height: 240,
                      child: BarChart(
                        BarChartData(
                          gridData: FlGridData(show: true),
                          borderData: FlBorderData(show: false),
                          barGroups: barGroups,
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 48,
                                getTitlesWidget: (v, meta) {
                                  if (v <= 0) return const SizedBox.shrink();
                                  return Text(_formatCompact(v.toDouble()));
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval:
                                    max(
                                      1,
                                      (dias.length / 6).floor(),
                                    ).toDouble(),
                                getTitlesWidget: (v, meta) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= dias.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = dias[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text('${d.day}/${d.month}'),
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
                              getTooltipItem: (group, gi, rod, ri) {
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
                  ),

                const SizedBox(height: 16),

                // === Top clientes por valor ===
                _SectionCard(
                  icon: Icons.star_outline,
                  title: 'Top clientes por valor',
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
                                  onTap: () {
                                    String? id;
                                    byClienteIdNome.forEach((cid, nome) {
                                      if (nome == e.key) id = cid;
                                    });
                                    setState(() {
                                      _clienteIdFilter = id;
                                      _clienteNomeFilter = e.key;
                                    });
                                  },
                                ),
                            ],
                          ),
                ),

                const SizedBox(height: 16),

                // === Lista de pedidos ===
                _SectionCard(
                  icon: Icons.list_alt_outlined,
                  title:
                      'Pedidos (${docs.length}$periodoStr$clienteStr$statusStr)',
                  child: ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();
                      final tot = _asNum(m[kTotal]);
                      final dt = (m[kDate] as Timestamp?)?.toDate();
                      final cliente = (m[kClienteNome] ?? '').toString();
                      final numero = (m[kNumero] as int?) ?? 0;
                      final status = (m[kStatus] ?? '').toString();

                      final color = _statusColor(status);

                      double descItem = _asNum(m[kDescontoAplicado]);
                      if (descItem == 0) descItem = _asNum(m[kDescontoValor]);
                      final subItem = _asNum(m[kSubtotal]);
                      final taxaItem = _asNum(m[kTaxaEntrega]);
                      if (descItem == 0 && subItem > 0) {
                        final derivado = (subItem + taxaItem) - tot;
                        if (derivado > 0) descItem = derivado;
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.12),
                          child: Icon(Icons.receipt_long, color: color),
                        ),
                        title: Text(
                          '${cliente.isEmpty ? "Sem cliente" : cliente} • ${_fmtMoeda(tot)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (numero > 0)
                              'Nº ${numero.toString().padLeft(3, '0')}',
                            if (dt != null) _fmtData(dt),
                            if (descItem > 0) 'Desc ${_fmtMoeda(descItem)}',
                            status.isEmpty
                                ? '—'
                                : (kStatusLabels[status] ?? status),
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

  // ===== Util =====
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

  static Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'pago':
      case 'finalizado':
      case 'concluido':
        return Colors.teal;
      case 'cancelado':
        return Colors.red;
      case 'pendente':
      case 'aguardando_aprovacao':
      case 'aguardando_pagamento':
      case 'aprovado':
      case 'em_andamento':
      case 'enviado':
      case 'garantia':
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          child, // o PopupMenuButton vem aqui
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
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  final EdgeInsets padding;
  final double iconSize;
  final double minHeight;
  final double valueFontSize;
  final double labelFontSize;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.iconSize = 28,
    this.minHeight = 60,
    this.valueFontSize = 16,
    this.labelFontSize = 11,
  });

  factory _KpiCard.compact({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return _KpiCard(
      icon: icon,
      label: label,
      value: value,
      color: color,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      iconSize: 26,
      minHeight: 54,
      valueFontSize: 15,
      labelFontSize: 10.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              Container(
                width: iconSize + 8,
                height: iconSize + 8,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: labelFontSize,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: valueFontSize,
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
  final Widget? trailing;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
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
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (trailing != null) trailing!,
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
