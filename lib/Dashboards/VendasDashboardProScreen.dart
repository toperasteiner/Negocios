// lib/Dashboard/VendasDashboardProScreenErrors.dart
// Dashboard de Vendas — versão com logs e tratamento de erros no terminal.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// =======================
/// 1) Hooks globais de erro
/// =======================
class AppErrorHooks {
  static void runAppWithHooks(Widget app) {
    // Widget de erro padrão (quando um build quebra)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // também loga no terminal
      _err('ErrorWidget.builder', details.exception, details.stack);
      return Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.4)),
            ),
            child: SelectableText(
              'Falha ao renderizar o widget.\n\n${details.exception}',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    // Erros de Flutter (síncronos durante o frame)
    FlutterError.onError = (FlutterErrorDetails d) {
      _err('FlutterError.onError', d.exception, d.stack);
      // encaminha para a zona atual (mantém comportamento nativo em debug)
      FlutterError.presentError(d);
    };

    // Erros de plataforma (assíncronos fora do FlutterError)
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _err('PlatformDispatcher.onError', error, stack);
      return true; // já tratamos/logamos
    };

    // Zona para capturar tudo que vazar (futures/streams/timers)
    runZonedGuarded(
      () {
        runApp(app);
      },
      (error, stack) {
        _err('runZonedGuarded', error, stack);
      },
    );
  }

  static void _err(String where, Object error, StackTrace? stack) {
    // Log no terminal/DevTools
    debugPrint('⛔ [$where] $error');
    if (stack != null) {
      debugPrint('└─ stack:\n$stack');
    }
    // Reporta no pipeline do Flutter (visível em ferramentas que escutam esse canal)
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'VendasDashboardPro',
        context: ErrorDescription(where),
      ),
    );
  }
}

/// =======================
/// 2) Tela principal
/// =======================
class VendasDashboardProScreenErrors extends StatefulWidget {
  const VendasDashboardProScreenErrors({super.key});

  @override
  State<VendasDashboardProScreenErrors> createState() =>
      _VendasDashboardProScreenErrorsState();
}

class _VendasDashboardProScreenErrorsState
    extends State<VendasDashboardProScreenErrors> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _uid;

  // período
  DateTime _ini = _at00(DateTime.now().subtract(const Duration(days: 29)));
  DateTime _fim = _at2359(DateTime.now());
  int _preset = 30; // 0=hoje, 7, 30, 90, -1=custom

  // status
  String? _status; // null => todos

  // logging minimalista
  bool _loggingEnabled = true;
  String? _lastLogKey;

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    try {
      _uid = _auth.currentUser?.uid;
      _log('initState: uid inicial=${_uid ?? "(null)"}');

      _auth.authStateChanges().listen((u) {
        _log('Auth change: uid=${u?.uid ?? "(null)"}');
        if (mounted) setState(() => _uid = u?.uid);
      });
    } catch (e, st) {
      _err('initState', e, st);
    }
  }

  void _setPreset(int days) {
    try {
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
      _log('Preset alterado: days=$days, ini=$_ini, fim=$_fim');
    } catch (e, st) {
      _err('_setPreset', e, st);
    }
  }

  Future<void> _pickCustomRange() async {
    try {
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
      _log('Período personalizado: ini=$_ini, fim=$_fim');
    } catch (e, st) {
      _err('_pickCustomRange', e, st);
    }
  }

  Query<Map<String, dynamic>> _baseQuery() {
    final iniTs = Timestamp.fromDate(_ini);
    final fimExclusive = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExclusive);

    var q = _fs
        .collection('pedidos')
        .where('userId', isEqualTo: _uid ?? '__')
        .where('data', isGreaterThanOrEqualTo: iniTs)
        .where('data', isLessThan: fimTs);

    if (_status != null && _status!.isNotEmpty) {
      q = q.where('status', isEqualTo: _status);
    }

    _log(
      'Query pronta: uid=${_uid ?? "(null)"} | ini=$_ini fim=$_fim | status=${_status ?? "Todos"}',
    );

    // ⚠️ IMPORTANTE: se faltar índice para (userId, data), o Firestore retornará erro com link.
    return q.orderBy('data');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // stream com handleError para registrar no terminal
    final stream = _baseQuery().snapshots().handleError((error, stack) {
      _err('Stream.handleError', error, stack);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard de Vendas — com erros no terminal'),
        actions: [
          // Forçar erro para teste
          IconButton(
            tooltip: 'Forçar erro',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () {
              // Exceção proposital — ver no terminal/DevTools
              throw StateError('Erro forçado pelo usuário (teste de pipeline)');
            },
          ),
          // filtro de status
          PopupMenuButton<String?>(
            tooltip: 'Filtrar status',
            initialValue: _status,
            onSelected:
                (v) => setState(() {
                  _status = v;
                  _log('Status alterado: ${_status ?? "Todos"}');
                }),
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: null, child: Text('Todos os status')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'pendente', child: Text('Pendente')),
                  PopupMenuItem(
                    value: 'aguardando_aprovacao',
                    child: Text('Aguard. aprovação'),
                  ),
                  PopupMenuItem(value: 'aprovado', child: Text('Aprovado')),
                  PopupMenuItem(
                    value: 'em_andamento',
                    child: Text('Em andamento'),
                  ),
                  PopupMenuItem(
                    value: 'aguardando_pagamento',
                    child: Text('Aguard. pagamento'),
                  ),
                  PopupMenuItem(value: 'enviado', child: Text('Enviado')),
                  PopupMenuItem(value: 'concluido', child: Text('Concluído')),
                  PopupMenuItem(value: 'garantia', child: Text('Garantia')),
                  PopupMenuItem(value: 'cancelado', child: Text('Cancelado')),
                ],
            child: Row(
              children: [
                const Icon(Icons.filter_alt_outlined),
                const SizedBox(width: 8),
                Text(
                  _status == null
                      ? 'Status: Todos'
                      : 'Status: ${_labelStatus(_status!)}',
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          // período rápido
          PopupMenuButton<int>(
            tooltip: 'Período',
            onSelected: (v) => v == -1 ? _pickCustomRange() : _setPreset(v),
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
      body:
          _uid == null
              ? const Center(child: Text('Faça login para visualizar.'))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (ctx, snap) {
                  try {
                    if (snap.connectionState == ConnectionState.waiting) {
                      _log('Stream: waiting…');
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snap.hasError) {
                      _err(
                        'StreamBuilder.hasError',
                        snap.error!,
                        snap.stackTrace,
                      );
                      return _ErrorPanel(error: snap.error);
                    }

                    final docs = snap.data?.docs ?? [];
                    final logKey =
                        '${docs.length}|${_ini.millisecondsSinceEpoch}|${_fim.millisecondsSinceEpoch}|${_status ?? "ALL"}';
                    if (_lastLogKey != logKey) {
                      _lastLogKey = logKey;
                      _log('Stream OK: ${docs.length} doc(s) recebidos');
                      if (docs.isNotEmpty) {
                        final ids = docs.take(3).map((d) => d.id).join(', ');
                        _log(
                          'Amostra de IDs: $ids${docs.length > 3 ? " …" : ""}',
                        );
                      }
                    }

                    if (docs.isEmpty) {
                      _log('Sem resultados no período/filtros atuais.');
                      return _EmptyState(
                        ini: _ini,
                        fim: _fim,
                        uid: _uid!,
                        onSet30: () => _setPreset(30),
                        onSet90: () => _setPreset(90),
                        onCustom: _pickCustomRange,
                      );
                    }

                    // ===== Processamento (com try/catch local) =====
                    double faturamento = 0;
                    int pedidos = docs.length;
                    final byStatus = <String, int>{};
                    final byDia = <DateTime, double>{};
                    final byCliente = <String, double>{};

                    for (final d in docs) {
                      try {
                        final m = d.data();
                        final total =
                            (m['total'] is num)
                                ? (m['total'] as num).toDouble()
                                : 0.0;
                        final status = (m['status'] ?? 'pendente').toString();
                        final cliente = (m['clienteNome'] ?? '—').toString();
                        final data = (m['data'] as Timestamp?)?.toDate();

                        faturamento += total;
                        byStatus.update(
                          status,
                          (v) => v + 1,
                          ifAbsent: () => 1,
                        );
                        byCliente.update(
                          cliente,
                          (v) => v + total,
                          ifAbsent: () => total,
                        );

                        if (data != null) {
                          final key = DateTime(data.year, data.month, data.day);
                          byDia.update(
                            key,
                            (v) => v + total,
                            ifAbsent: () => total,
                          );
                        }
                      } catch (e, st) {
                        _err('loop docs parse', e, st);
                      }
                    }

                    final aprovados = byStatus['aprovado'] ?? 0;
                    final conversao =
                        pedidos == 0 ? 0.0 : (aprovados / pedidos) * 100.0;
                    final ticketMedio =
                        pedidos == 0 ? 0.0 : faturamento / pedidos;

                    // preparar série diária
                    final dias = byDia.keys.toList()..sort();
                    final spots = <FlSpot>[];
                    for (var i = 0; i < dias.length; i++) {
                      final v = byDia[dias[i]] ?? 0.0;
                      spots.add(FlSpot(i.toDouble(), v));
                    }

                    // top clientes
                    final topClientes =
                        byCliente.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                    final top5 = topClientes.take(5).toList();

                    final periodoStr =
                        _preset == -1
                            ? ' • ${_fmtData(_ini)} a ${_fmtData(_fim)}'
                            : '';

                    _log(
                      'Métricas: faturamento=${_fmtMoeda(faturamento)}, '
                      'pedidos=$pedidos, aprovados=${byStatus['aprovado'] ?? 0}, '
                      'ticketMedio=${_fmtMoeda(ticketMedio)}',
                    );

                    return RefreshIndicator(
                      onRefresh: () async {
                        _log('Pull-to-refresh acionado');
                        setState(() {});
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        children: [
                          // KPIs
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
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
                                label: 'Conversão',
                                value: '${conversao.toStringAsFixed(1)}%',
                                color: Colors.blue,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // GRÁFICO
                          if (spots.isNotEmpty)
                            _SectionCard(
                              icon: Icons.show_chart,
                              title: 'Faturamento diário',
                              child: SizedBox(
                                height: 220,
                                child: LineChart(
                                  LineChartData(
                                    gridData: FlGridData(show: true),
                                    borderData: FlBorderData(show: false),
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
                                          reservedSize: 42,
                                          getTitlesWidget: (v, meta) {
                                            if (v <= 0) {
                                              return const SizedBox.shrink();
                                            }
                                            return Text(_formatCompact(v));
                                          },
                                        ),
                                      ),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval:
                                              max(
                                                1,
                                                (spots.length / 6).floor(),
                                              ).toDouble(),
                                          getTitlesWidget: (v, meta) {
                                            final i = v.toInt();
                                            if (i < 0 || i >= dias.length) {
                                              return const SizedBox.shrink();
                                            }
                                            final d = dias[i];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              child: Text(
                                                '${d.day}/${d.month}',
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    lineBarsData: [
                                      LineChartBarData(
                                        isCurved: true,
                                        barWidth: 3,
                                        dotData: const FlDotData(show: false),
                                        spots: spots,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),

                          // STATUS
                          _SectionCard(
                            icon: Icons.flag_outlined,
                            title: 'Pedidos por status',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  byStatus.isEmpty
                                      ? [const Text('Sem pedidos no período.')]
                                      : [
                                        for (final e in byStatus.entries)
                                          Chip(
                                            label: Text(
                                              '${_labelStatus(e.key)}: ${e.value}',
                                            ),
                                          ),
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

                          // LISTA
                          _SectionCard(
                            icon: Icons.list_alt_outlined,
                            title:
                                'Pedidos (${docs.length}$periodoStr${_status == null ? '' : ' • ${_labelStatus(_status!)}'})',
                            child: ListView.separated(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: docs.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                try {
                                  final d = docs[i];
                                  final m = d.data();
                                  final total =
                                      (m['total'] is num)
                                          ? (m['total'] as num).toDouble()
                                          : 0.0;
                                  final data =
                                      (m['data'] as Timestamp?)?.toDate();
                                  final numero =
                                      (m['numero'] ?? 0) as int? ?? 0;
                                  final ano =
                                      (m['ano'] ??
                                              (data?.year ??
                                                  DateTime.now().year))
                                          as int? ??
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
                                } catch (e, st) {
                                  _err('ListTile builder', e, st);
                                  // ainda renderiza algo pra não quebrar a lista
                                  return const ListTile(
                                    leading: Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                    ),
                                    title: Text('Erro ao exibir item'),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  } catch (e, st) {
                    _err('StreamBuilder.build', e, st);
                    return _ErrorPanel(error: e);
                  }
                },
              ),
    );
  }

  // ===== Utils & Log =====
  void _log(String msg) {
    if (!_loggingEnabled) return;
    debugPrint('📝 [VendasDashboardPro] $msg');
  }

  void _err(String where, Object error, StackTrace? stack) {
    debugPrint('⛔ [$where] $error');
    if (stack != null) {
      debugPrint('└─ stack:\n$stack');
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'VendasDashboardPro',
        context: ErrorDescription(where),
      ),
    );
  }

  static String _fmtMoeda(num v) =>
      NumberFormat.simpleCurrency(locale: 'pt_BR').format(v);

  static String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _formatCompact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
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
        return s.isEmpty ? '—' : s;
    }
  }
}

/// =======================
/// 3) Widgets auxiliares
/// =======================
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
      width: min(MediaQuery.of(context).size.width / 2 - 18, 220),
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
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
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
  final DateTime ini;
  final DateTime fim;
  final String uid;
  final VoidCallback onSet30;
  final VoidCallback onSet90;
  final VoidCallback onCustom;

  const _EmptyState({
    required this.ini,
    required this.fim,
    required this.uid,
    required this.onSet30,
    required this.onSet90,
    required this.onCustom,
  });

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
            Text(
              'Sem pedidos no período selecionado.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Período: ${_fmt(ini)} a ${_fmt(fim)}\nLogin: $uid',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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

class _ErrorPanel extends StatelessWidget {
  final Object? error;
  const _ErrorPanel({this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        color: Colors.red.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'Erro ao carregar dados:\n\n${error ?? "(sem mensagem)"}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// =======================
/// 4) Exemplo de main.dart
/// =======================
///
/// void main() {
///   AppErrorHooks.runAppWithHooks(const MyApp());
/// }
///
/// class MyApp extends StatelessWidget {
///   const MyApp({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       debugShowCheckedModeBanner: false,
///       home: const VendasDashboardProScreenErrors(),
///       theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
///     );
///   }
/// }
