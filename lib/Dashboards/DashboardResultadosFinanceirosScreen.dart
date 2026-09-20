import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum _Periodo { hoje, semana, mes, personalizado }

class DashboardResultadosFinanceirosScreen extends StatefulWidget {
  const DashboardResultadosFinanceirosScreen({super.key});

  @override
  State<DashboardResultadosFinanceirosScreen> createState() =>
      _DashboardResultadosFinanceirosScreenState();
}

class _DashboardResultadosFinanceirosScreenState
    extends State<DashboardResultadosFinanceirosScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  String? _scopeUserId;
  bool _loadingScope = true;
  String? _scopeError;

  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';

  _Periodo _periodo = _Periodo.mes;
  DateTime _ini = _at00(DateTime.now());
  DateTime _fim = _at2359(DateTime.now());

  String? _clienteKeySel;
  String? _clienteNomeSel;
  final Set<String> _todosClientesKeys = {};
  final Map<String, String> _todosClientesNomes = {};

  bool _loading = false;

  double _faturamento = 0.0;
  double _custo = 0.0;
  double _lucro = 0.0;

  List<_PedidoItem> _pedidos = [];

  StreamSubscription<User?>? _authSub;
  bool _scopeInitialized = false;
  int _loadStamp = 0;

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _aplicarPeriodo(_periodo);
    _initScope();

    _authSub = _auth.authStateChanges().listen((u) {
      if (u != null && !_scopeInitialized) {
        _initScope();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
      });
      return;
    }

    try {
      final doc = await _fs.collection('users').doc(u.uid).get();
      final companyId = (doc.data()?['companyId'] ?? '').toString().trim();

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid;
        _loadingScope = false;
        _scopeError = null;
        _scopeInitialized = true;
      });

      await _carregar();
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao iniciar escopo: $e';
      });
    }
  }

  void _aplicarPeriodo(_Periodo p) {
    final now = DateTime.now();
    setState(() {
      _periodo = p;
      switch (p) {
        case _Periodo.hoje:
          _ini = _at00(now);
          _fim = _at2359(now);
          break;
        case _Periodo.semana:
          final dow = now.weekday;
          final ini = now.subtract(Duration(days: dow - 1));
          final fim = ini.add(const Duration(days: 6));
          _ini = _at00(ini);
          _fim = _at2359(fim);
          break;
        case _Periodo.mes:
          final ini = DateTime(now.year, now.month, 1);
          final fim = DateTime(now.year, now.month + 1, 0);
          _ini = _at00(ini);
          _fim = _at2359(fim);
          break;
        case _Periodo.personalizado:
          break;
      }
    });
  }

  Future<void> _pickPeriodoPersonalizado() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _ini, end: _fim),
      helpText: 'Período personalizado',
    );
    if (range != null) {
      setState(() {
        _periodo = _Periodo.personalizado;
        _ini = _at00(range.start);
        _fim = _at2359(range.end);
      });
      _carregar();
    }
  }

  Future<void> _carregar() async {
    final scope = _scopeUserId;
    if (scope == null) return;

    final int myStamp = ++_loadStamp;
    setState(() => _loading = true);

    double fat = 0.0;
    double cus = 0.0;
    double luc = 0.0;
    final List<_PedidoItem> lista = [];
    final Set<String> todosClientesKeys = {};
    final Map<String, String> todosClientesNomes = {};

    try {
      final iniTs = Timestamp.fromDate(_ini);
      final fimExc = DateTime(
        _fim.year,
        _fim.month,
        _fim.day,
      ).add(const Duration(days: 1));
      final fimTs = Timestamp.fromDate(fimExc);

      final snap =
          await _fs
              .collection('pedidos')
              .where(_scopeField, isEqualTo: scope)
              .where('data', isGreaterThanOrEqualTo: iniTs)
              .where('data', isLessThan: fimTs)
              .orderBy('data')
              .get();

      for (final d in snap.docs) {
        final m = d.data();

        final status = (m['status'] ?? '').toString().trim().toLowerCase();

        if (status == 'cancelado') {
          continue;
        }

        final cliente =
            (m['clienteNome'] ?? m['cliente'] ?? '').toString().trim();
        final clienteLabel = cliente.isEmpty ? '—' : cliente;

        todosClientesKeys.add(cliente);
        todosClientesNomes[cliente] = clienteLabel;

        if (_clienteKeySel != null && _clienteKeySel!.isNotEmpty) {
          if (cliente != _clienteKeySel) continue;
        }

        final subtotal = _toDouble(m['subtotal']);
        final custo = _toDouble(m['custoTotal']);
        final lucro = _toDouble(m['lucroLiquido']);
        final total = _toDouble(m['total']);
        final data = (m['data'] as Timestamp?)?.toDate();
        final numero = (m['numero'] is num) ? (m['numero'] as num).toInt() : 0;
        final ano =
            (m['ano'] is num) ? (m['ano'] as num).toInt() : DateTime.now().year;

        fat += subtotal;
        cus += custo;
        luc += lucro;

        lista.add(
          _PedidoItem(
            nome: clienteLabel,
            valor: lucro,
            faturamento: total,
            custo: custo,
            data: data,
            numero: numero,
            ano: ano,
          ),
        );
      }

      if (!mounted || myStamp != _loadStamp) return;

      setState(() {
        _faturamento = fat;
        _custo = cus;
        _lucro = luc;
        _pedidos = lista;
        _todosClientesKeys
          ..clear()
          ..addAll(todosClientesKeys);
        _todosClientesNomes
          ..clear()
          ..addAll(todosClientesNomes);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || myStamp != _loadStamp) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar dashboard: $e')));
    }
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _fmt(num v) {
    final sinal = v < 0 ? '-' : '';
    final vv = v.abs().toDouble();
    final s = vv.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return '${sinal}R\$ $inteiro,${p[1]}';
  }

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard Financeiro')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Financeiro'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _carregar(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _Filtros(
              periodo: _periodo,
              onPeriodoTap: (p) {
                _aplicarPeriodo(p);
                if (p != _Periodo.personalizado) _carregar();
              },
              onPersonalizado: _pickPeriodoPersonalizado,
              ini: _ini,
              fim: _fim,
              clienteKey: _clienteKeySel,
              clienteNome: _clienteNomeSel,
              clientesDisponiveis:
                  _todosClientesKeys
                      .map((k) => _ClienteKV(k, _todosClientesNomes[k] ?? '—'))
                      .toList()
                    ..sort((a, b) => a.label.compareTo(b.label)),
              onClienteChanged: (key, label) {
                setState(() {
                  _clienteKeySel = key;
                  _clienteNomeSel = label;
                });
                _carregar();
              },
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 560;
                final cards = [
                  _TotalCard(
                    title: 'Faturamento',
                    value: _fmt(_faturamento),
                    icon: Icons.payments_outlined,
                    color: Colors.blue,
                  ),
                  _TotalCard(
                    title: 'Custo',
                    value: _fmt(_custo),
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.orange,
                  ),
                ];
                if (stacked) {
                  return Column(
                    children: [cards[0], const SizedBox(height: 8), cards[1]],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 8),
                    Expanded(child: cards[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            _TotalCard(
              title: 'Lucro',
              value: _fmt(_lucro),
              icon: Icons.trending_up_outlined,
              color: _lucro >= 0 ? Colors.green : Colors.red,
              big: true,
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Pedidos no período'),
                    subtitle: Text('${_fmtData(_ini)} a ${_fmtData(_fim)}'),
                  ),
                  const Divider(height: 1),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_pedidos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nenhum pedido para os filtros atuais.'),
                    )
                  else
                    ..._pedidos.map((e) {
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(
                              'Pedido ${e.numero.toString().padLeft(3, '0')}-${e.ano} • ${e.nome}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (e.data != null)
                                  'Data: ${_fmtData(e.data!)}',
                                'Faturamento: ${_fmt(e.faturamento)}',
                                'Custo: ${_fmt(e.custo)}',
                              ].join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: SizedBox(
                              width: 110,
                              child: Text(
                                _fmt(e.valor),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color:
                                      e.valor >= 0 ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PedidoItem {
  final String nome;
  final double valor;
  final double faturamento;
  final double custo;
  final DateTime? data;
  final int numero;
  final int ano;

  _PedidoItem({
    required this.nome,
    required this.valor,
    required this.faturamento,
    required this.custo,
    required this.data,
    required this.numero,
    required this.ano,
  });
}

class _ClienteKV {
  final String key;
  final String label;
  _ClienteKV(this.key, this.label);
}

class _TotalCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool big;

  const _TotalCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: big ? 24 : null,
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

class _Filtros extends StatelessWidget {
  final _Periodo periodo;
  final void Function(_Periodo) onPeriodoTap;
  final VoidCallback onPersonalizado;
  final DateTime ini;
  final DateTime fim;

  final String? clienteKey;
  final String? clienteNome;
  final List<_ClienteKV> clientesDisponiveis;
  final void Function(String? key, String? label) onClienteChanged;

  const _Filtros({
    required this.periodo,
    required this.onPeriodoTap,
    required this.onPersonalizado,
    required this.ini,
    required this.fim,
    required this.clienteKey,
    required this.clienteNome,
    required this.clientesDisponiveis,
    required this.onClienteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String fmtData(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final Set<String> availableValues = {
      for (final c in clientesDisponiveis) c.key,
    };

    final String? dropdownClienteValue =
        (clienteKey != null && availableValues.contains(clienteKey))
            ? clienteKey
            : null;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in _Periodo.values)
                  ChoiceChip(
                    label: Text(
                      {
                        _Periodo.hoje: 'Hoje',
                        _Periodo.semana: 'Semana',
                        _Periodo.mes: 'Mês',
                        _Periodo.personalizado: 'Personalizado',
                      }[p]!,
                    ),
                    selected: periodo == p,
                    onSelected: (_) {
                      if (p == _Periodo.personalizado) {
                        onPeriodoTap(p);
                        onPersonalizado();
                      } else {
                        onPeriodoTap(p);
                      }
                    },
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: cs.surfaceVariant,
                  ),
                  child: Text(
                    '${fmtData(ini)} • ${fmtData(fim)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Cliente',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: dropdownClienteValue,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...clientesDisponiveis.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.key,
                        child: Text(c.label, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onClienteChanged(null, null);
                    } else {
                      final label =
                          clientesDisponiveis
                              .firstWhere(
                                (e) => e.key == v,
                                orElse: () => _ClienteKV(v, '—'),
                              )
                              .label;
                      onClienteChanged(v, label);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
