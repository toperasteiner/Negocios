// lib/Dashboard/TopProdutosDashboardScreen.dart
// Dashboard: Top Produtos Vendidos — MULTIEMPRESA
// Escopo: scopeUserId = (users.companyId ?? auth.uid)
//
// Firestore (coleção "pedidos"):
// companyId (ou userId), data (timestamp), status (string),
// itensProdutos ([{refId, nome, unidade, quantidade, valorUnitario, total}])
//
// Índice recomendado: (companyId ASC, data ASC)

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TopProdutosDashboardScreen extends StatefulWidget {
  const TopProdutosDashboardScreen({super.key});

  @override
  State<TopProdutosDashboardScreen> createState() =>
      _TopProdutosDashboardScreenState();
}

class _TopProdutosDashboardScreenState
    extends State<TopProdutosDashboardScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== Escopo (multiempresa) =====
  String? _uid;
  String? _companyId;
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  // ===== Config =====
  static const String kCollection = 'pedidos';
  static const String kScopeField = 'companyId'; // ou 'userId' em legado
  static const String kDate = 'data';
  static const String kItensProdutos = 'itensProdutos';
  static const String kStatus = 'status';

  // ===== Filtros =====
  DateTime _ini = _at00(DateTime.now().subtract(const Duration(days: 29)));
  DateTime _fim = _at2359(DateTime.now());
  int _preset = 30; // 0=Hoje, 7, 30, 90, -1=custom

  // ranking por valor (true) ou por quantidade (false)
  bool _rankByValue = true;
  // quantos produtos mostrar no ranking/gráfico
  int _topN = 3;

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

  // ===== Carrega escopo (companyId ?? uid) =====
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
        '[TopProdutosDash] escopo: scopeUserId=$_scopeUserId (companyId=$_companyId uid=${u.uid})',
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

    // 1) doc por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid.data();
    } catch (_) {}

    // 2) fallback por emailKey (se existir na sua base)
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
    // Índice recomendado:
    // (companyId ASC, data ASC)  — ou (userId ASC, data ASC) se usar userId
    final iniTs = Timestamp.fromDate(_ini);
    final fimExc = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExc);

    return _fs
        .collection(kCollection)
        .where(kScopeField, isEqualTo: _scopeUserId ?? '__') // ESCOPO
        .where(kDate, isGreaterThanOrEqualTo: iniTs)
        .where(kDate, isLessThan: fimTs)
        .orderBy(kDate);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard • Top Produtos')),
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
        title: const Text('Dashboard • Top Produtos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
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

                // ======= Pílula: RANKING (Valor x Quantidade) =======
                _FilterPill(
                  icon: Icons.tune,
                  child: PopupMenuButton<String>(
                    tooltip: 'Ordenar por',
                    onSelected:
                        (v) => setState(() => _rankByValue = (v == 'valor')),
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem(
                            value: 'valor',
                            child: Text('Top por Valor (R\$)'),
                          ),
                          PopupMenuItem(
                            value: 'quant',
                            child: Text('Top por Quantidade'),
                          ),
                        ],
                    child: _FilterLabel(
                      text:
                          _rankByValue
                              ? 'Ranking: Valor'
                              : 'Ranking: Quantidade',
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

          // --------- IGNORAR CANCELADOS (filtro no cliente) ---------
          final all = snap.data?.docs ?? [];
          final docs =
              all.where((d) {
                final s = (d.data()[kStatus] ?? '').toString().toLowerCase();
                return s != 'cancelado';
              }).toList();

          if (docs.isEmpty) {
            return _EmptyState(
              title: 'Sem vendas de produtos no período selecionado.',
              subtitle:
                  'Período: ${_fmtData(_ini)} a ${_fmtData(_fim)}\n(ignora pedidos cancelados)',
              onSet30: () => _setPreset(30),
              onSet90: () => _setPreset(90),
              onCustom: _pickCustomRange,
            );
          }

          // ======= Agregação =======
          final Map<String, _ProdutoAgg> produtos = {};
          final Set<String> pedidosComProdutos = {};

          for (final d in docs) {
            final m = d.data();
            final itens = (m[kItensProdutos] as List?)?.cast<dynamic>() ?? [];
            if (itens.isEmpty) continue;

            bool teveProduto = false;
            for (final it in itens) {
              if (it is! Map) continue;
              final refId = (it['refId'] ?? '').toString();
              final nome = (it['nome'] ?? '').toString();
              final unidade = (it['unidade'] ?? '').toString();
              final qtd = _asNum(it['quantidade']);
              final total = _asNum(it['total']);
              final vu = _asNum(it['valorUnitario']);
              if (qtd == 0 && total == 0) continue;

              final key =
                  refId.isNotEmpty ? refId : (nome.isEmpty ? '—' : nome);
              final p = produtos.putIfAbsent(
                key,
                () => _ProdutoAgg(key: key, nome: nome, unidade: unidade),
              );
              if (p.nome.isEmpty && nome.isNotEmpty) p.nome = nome;
              if (p.unidade.isEmpty && unidade.isNotEmpty) p.unidade = unidade;

              p.qtd += qtd;
              p.valor += total;
              p.vuAcum += vu > 0 ? vu * qtd : 0;
              p.vuQtd += vu > 0 ? qtd : 0;
              teveProduto = true;
            }
            if (teveProduto) pedidosComProdutos.add(d.id);
          }

          // KPIs
          final itensVendidos = produtos.values.fold<double>(
            0,
            (a, e) => a + e.qtd,
          );
          final faturamento = produtos.values.fold<double>(
            0,
            (a, e) => a + e.valor,
          );
          final pedidosQtd = pedidosComProdutos.length;
          final ticketItem =
              itensVendidos > 0 ? (faturamento / itensVendidos) : 0.0;

          // Ordenações
          final lista = produtos.values.toList();
          if (_rankByValue) {
            lista.sort((a, b) => b.valor.compareTo(a.valor));
          } else {
            lista.sort((a, b) => b.qtd.compareTo(a.qtd));
          }
          final top = lista.take(_topN).toList();

          // Gráfico barras Top N
          final barGroups = <BarChartGroupData>[
            for (int i = 0; i < top.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: _rankByValue ? top[i].valor : top[i].qtd,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                    color:
                        _rankByValue
                            ? Theme.of(context).colorScheme.primary
                            : Colors.teal,
                  ),
                ],
              ),
          ];

          // Rótulos completos para o eixo X (com quebra em até 2 linhas)
          final labels = <String>[
            for (final p in top) (p.nome.isEmpty ? p.key : p.nome),
          ];

          final periodoStr =
              _preset == -1 ? ' • ${_fmtData(_ini)} a ${_fmtData(_fim)}' : '';

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                // KPIs (grid responsivo, alturas iguais)
                LayoutBuilder(
                  builder: (context, cts) {
                    final w = cts.maxWidth;
                    final cols = w < 360 ? 1 : 2;

                    final kpis = [
                      (
                        icon: Icons.shopping_bag_outlined,
                        label: 'Itens vendidos',
                        value: _formatCompact(itensVendidos),
                        color: Colors.indigo,
                      ),
                      (
                        icon: Icons.request_quote_outlined,
                        label: 'Faturamento (prod.)',
                        value: _fmtMoeda(faturamento),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      (
                        icon: Icons.stacked_line_chart_outlined,
                        label: 'Ticket por item',
                        value: _fmtMoeda(ticketItem),
                        color: Colors.teal,
                      ),
                      (
                        icon: Icons.receipt_long_outlined,
                        label: 'Pedidos c/ produtos',
                        value: '$pedidosQtd',
                        color: Colors.deepPurple,
                      ),
                    ];

                    return GridView.count(
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: cols == 1 ? 3.4 : 2.8,
                      children: [
                        for (final k in kpis)
                          _KpiCard(
                            icon: k.icon,
                            label: k.label,
                            value: k.value,
                            color: k.color,
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Ranking / Gráfico Top N
                _SectionCard(
                  icon: Icons.bar_chart_outlined,
                  title:
                      'Top $_topN produtos ${_rankByValue ? "(por Valor)" : "(por Quantidade)"}$periodoStr',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Diminuir Top N',
                        onPressed:
                            _topN > 3 ? () => setState(() => _topN--) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$_topN'),
                      IconButton(
                        tooltip: 'Aumentar Top N',
                        onPressed:
                            _topN < 12 ? () => setState(() => _topN++) : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: _LegendDot(
                          color:
                              _rankByValue
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.teal,
                          label: _rankByValue ? 'Valor (R\$)' : 'Quantidade',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (barGroups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('Sem dados para o ranking.'),
                        )
                      else
                        SizedBox(
                          height: 300,
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
                                      if (v <= 0) {
                                        return const SizedBox.shrink();
                                      }
                                      return Text(
                                        _rankByValue
                                            ? _formatCompact(v.toDouble())
                                            : v.toStringAsFixed(0),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 1,
                                    reservedSize: 64,
                                    getTitlesWidget: (v, meta) {
                                      final i = v.toInt();
                                      if (i < 0 || i >= labels.length) {
                                        return const SizedBox.shrink();
                                      }
                                      final nome = labels[i];
                                      return SideTitleWidget(
                                        axisSide: meta.axisSide,
                                        space: 8,
                                        child: SizedBox(
                                          width: 90,
                                          child: Text(
                                            nome,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
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
                                  getTooltipItem: (group, groupIndex, rod, ri) {
                                    final idx = group.x.toInt();
                                    final nome =
                                        (idx >= 0 && idx < labels.length)
                                            ? labels[idx]
                                            : '';
                                    final valor = rod.toY;
                                    final txt =
                                        _rankByValue
                                            ? _fmtMoeda(valor)
                                            : _formatNumber(valor);
                                    return BarTooltipItem(
                                      '$nome\n$txt',
                                      const TextStyle(
                                        fontWeight: FontWeight.w600,
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

                // Lista completa (ordenada pelo ranking atual)
                _SectionCard(
                  icon: Icons.list_alt_outlined,
                  title:
                      'Produtos (${lista.length}${_rankByValue ? " • ordenado por Valor" : " • ordenado por Quantidade"})',
                  child: ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = lista[i];
                      final ticketUnit =
                          p.vuQtd > 0 ? (p.vuAcum / p.vuQtd) : 0.0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: cs.primary.withOpacity(0.12),
                          child: const Icon(
                            Icons.inventory_2,
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          p.nome.isEmpty ? p.key : p.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            'Qtd ${_formatNumber(p.qtd)}${p.unidade.isEmpty ? "" : " ${p.unidade}"}',
                            'Total ${_fmtMoeda(p.valor)}',
                            'VU ~ ${_fmtMoeda(ticketUnit)}',
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          _rankByValue
                              ? _fmtMoeda(p.valor)
                              : _formatNumber(p.qtd),
                          style: const TextStyle(fontWeight: FontWeight.w800),
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

  static String _formatNumber(double v) {
    if (v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

/* ============================== Apoio ============================== */
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

class _ProdutoAgg {
  final String key; // refId ou nome
  String nome;
  String unidade;
  double qtd;
  double valor;
  double vuAcum; // soma de (valorUnitario * qtd) para base do VU médio
  double vuQtd; // soma de qtds consideradas para VU
  _ProdutoAgg({
    required this.key,
    this.nome = '',
    this.unidade = '',
    this.qtd = 0.0,
    this.valor = 0.0,
    this.vuAcum = 0.0,
    this.vuQtd = 0.0,
  });
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
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        height: 86,
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
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.black54),
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
