import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async'; // <- necessário para StreamSubscription

enum _Periodo { hoje, semana, mes, personalizado }

enum _TipoTitulo { ambos, entrada, saida }

class DashboardFluxoCaixaScreen extends StatefulWidget {
  const DashboardFluxoCaixaScreen({super.key});

  @override
  State<DashboardFluxoCaixaScreen> createState() =>
      _DashboardFluxoCaixaScreenState();
}

class _DashboardFluxoCaixaScreenState extends State<DashboardFluxoCaixaScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== escopo multiempresa =====
  String? _companyId; // users.companyId (se existir)
  String? _scopeUserId; // companyId ?? uid (valor para filtro)
  bool _loadingScope = true;
  String? _scopeError;

  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';

  // ===== filtros =====
  _Periodo _periodo = _Periodo.mes;
  DateTime _ini = _at00(DateTime.now());
  DateTime _fim = _at2359(DateTime.now());
  _TipoTitulo _tipo = _TipoTitulo.ambos;

  // "Categoria" aqui = pessoa (cliente p/ entrada, fornecedor p/ saída)
  String? _categoriaKeySel; // null => todas
  String? _categoriaNomeSel;
  final Set<String> _todasCategoriasKeys = {};
  final Map<String, String> _todasCategoriasNomes = {};

  // ===== dados =====
  bool _loading = false;
  double _totalEntradas = 0; // soma de valorAbs onde tipo=entrada
  double _totalSaidas = 0; // soma de valorAbs onde tipo=saida
  Map<String, double> _porCategoria = {}; // +entrada, -saida
  List<_ItemLinha> _itens = [];

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  StreamSubscription<User?>? _authSub;
  bool _scopeInitialized = false;
  int _loadStamp = 0;

  @override
  void initState() {
    super.initState();
    _aplicarPeriodo(_periodo);
    _initScope(); // primeira carga

    // Evita reinicializações múltiplas; só roda se logar depois
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
      // Carrega o registro do usuário para descobrir companyId e permissões (se precisar)
      final meSnap = await _fs.collection('users').doc(u.uid).get();
      final companyId = (meSnap.data()?['companyId'] ?? '').toString().trim();

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
          final dow = now.weekday; // 1=Mon..7=Sun
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
          // Mantém datas atuais até o usuário escolher no date range
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

    final int myStamp = ++_loadStamp; // token desta execução
    setState(() => _loading = true);

    // ---- acumuladores locais ----
    double totalEntradas = 0.0;
    double totalSaidas = 0.0;
    final Map<String, double> porCategoria = {};
    final List<_ItemLinha> itens = [];
    final Set<String> todasCategoriasKeys = {};
    final Map<String, String> todasCategoriasNomes = {};

    try {
      final iniTs = Timestamp.fromDate(_ini);
      final fimExc = DateTime(
        _fim.year,
        _fim.month,
        _fim.day,
      ).add(const Duration(days: 1)); // [ini, fim+1dia)
      final fimTs = Timestamp.fromDate(fimExc);

      // >>>> AQUI ESTÁ O AJUSTE MULTIEMPRESA (usa _scopeField dinâmico)
      Query<Map<String, dynamic>> q = _fs
          .collection('fluxo_caixa')
          .where(_scopeField, isEqualTo: scope)
          .where('data', isGreaterThanOrEqualTo: iniTs)
          .where('data', isLessThan: fimTs)
          .orderBy('data');

      final snap = await q.get();

      for (final d in snap.docs) {
        final m = d.data();
        final tipo = (m['tipo'] ?? '').toString().toLowerCase();
        final num? vAbsN = m['valorAbs'] as num?;
        final num? vN = m['valor'] as num?;
        final double valorAbs = (vAbsN ?? (vN ?? 0).abs()).toDouble();

        // filtro de tipo
        final passaTipo =
            _tipo == _TipoTitulo.ambos ||
            (_tipo == _TipoTitulo.entrada && tipo == 'entrada') ||
            (_tipo == _TipoTitulo.saida && tipo == 'saida');
        if (!passaTipo) continue;

        final pessoa =
            tipo == 'entrada'
                ? (m['clienteNome'] ?? '').toString()
                : (m['fornecedorNome'] ?? '').toString();

        // filtro de "categoria" (pessoa)
        if (_categoriaKeySel != null && _categoriaKeySel!.isNotEmpty) {
          if (pessoa != _categoriaKeySel) continue;
        }

        if (tipo == 'entrada') {
          totalEntradas += valorAbs;
        } else if (tipo == 'saida') {
          totalSaidas += valorAbs;
        }

        final label = pessoa.isEmpty ? '—' : pessoa;
        todasCategoriasKeys.add(pessoa);
        todasCategoriasNomes[pessoa] = label;

        final delta = tipo == 'entrada' ? valorAbs : -valorAbs;
        porCategoria[label] = (porCategoria[label] ?? 0) + delta;

        itens.add(
          _ItemLinha(
            tipo: tipo == 'entrada' ? _TipoTitulo.entrada : _TipoTitulo.saida,
            data: (m['data'] as Timestamp?)?.toDate(),
            pessoa: label,
            categoriaNome: label,
            valor: delta,
            observacao: (m['observacao'] ?? '').toString(),
          ),
        );
      }

      itens.sort(
        (a, b) => (a.data?.millisecondsSinceEpoch ?? 0).compareTo(
          b.data?.millisecondsSinceEpoch ?? 0,
        ),
      );

      // ⚠️ Só aplica se ninguém iniciou outra carga depois desta
      if (!mounted || myStamp != _loadStamp) return;

      setState(() {
        _totalEntradas = totalEntradas;
        _totalSaidas = totalSaidas;
        _porCategoria = porCategoria;
        _itens = itens;
        _todasCategoriasKeys
          ..clear()
          ..addAll(todasCategoriasKeys);
        _todasCategoriasNomes
          ..clear()
          ..addAll(todasCategoriasNomes);
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

  // ====================== UI ======================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fluxo de Caixa')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    // Saldo = entradas - saídas
    final saldo = _totalEntradas - _totalSaidas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard • Fluxo de Caixa'),
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
              tipo: _tipo,
              onTipoChanged: (t) {
                setState(() => _tipo = t);
                _carregar();
              },
              // sem status
              categoriaKey: _categoriaKeySel,
              categoriaNome: _categoriaNomeSel,
              categoriasDisponiveis:
                  _todasCategoriasKeys
                      .map(
                        (k) => _CategoriaKV(k, _todasCategoriasNomes[k] ?? '—'),
                      )
                      .toList()
                    ..sort((a, b) => a.label.compareTo(b.label)),
              onCategoriaChanged: (key, label) {
                setState(() {
                  _categoriaKeySel = key;
                  _categoriaNomeSel = label;
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
                    title: 'Entradas',
                    value: _fmtMoeda(_totalEntradas),
                    icon: Icons.arrow_downward_rounded,
                    color: Colors.green,
                  ),
                  _TotalCard(
                    title: 'Saídas',
                    value: _fmtMoeda(_totalSaidas),
                    icon: Icons.arrow_upward_rounded,
                    color: Colors.red,
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
              title: 'Saldo (Entradas - Saídas)',
              value: _fmtMoeda(saldo),
              icon: Icons.account_balance_wallet_outlined,
              color: saldo >= 0 ? cs.primary : Colors.red,
              big: true,
            ),
            const SizedBox(height: 16),

            if (_porCategoria.isNotEmpty) ...[
              Text(
                'Por Cliente/Fornecedor',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _BarChart(categories: _porCategoria),
              const SizedBox(height: 16),
            ],

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Resumo por categoria (pessoa)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final e
                        in _porCategoria.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: SizedBox(
                          width: 110,
                          child: Text(
                            _fmtMoeda(e.value),
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Itens no período'),
                    subtitle: Text('${_fmtData(_ini)} a ${_fmtData(_fim)}'),
                  ),
                  const Divider(height: 1),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_itens.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Nenhum lançamento para os filtros atuais.'),
                    )
                  else
                    ..._itens.map((i) {
                      final color =
                          i.tipo == _TipoTitulo.entrada
                              ? Colors.green
                              : Colors.red;
                      return Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              i.tipo == _TipoTitulo.entrada
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: color,
                            ),
                            title: Text(
                              i.pessoa.isEmpty
                                  ? (i.tipo == _TipoTitulo.entrada
                                      ? 'Cliente'
                                      : 'Fornecedor')
                                  : i.pessoa,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (i.data != null)
                                  'Data: ${_fmtData(i.data!)}',
                                if (i.observacao.isNotEmpty) i.observacao,
                              ].join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: SizedBox(
                              width: 110,
                              child: Text(
                                _fmtMoeda(i.valor),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: color,
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

  // ===== utils =====
  static String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtMoeda(num v) {
    // aceita negativos (para saídas na lista/por categoria)
    final sinal = v < 0 ? '-' : '';
    final vv = v.abs();
    final s = vv.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return '${sinal}R\$ $inteiro,${p[1]}';
  }
}

// ===== modelos/auxiliares =====
class _ItemLinha {
  final _TipoTitulo tipo;
  final DateTime? data;
  final String pessoa;
  final String categoriaNome;
  final double valor; // +entrada / -saida
  final String observacao; // de fluxo_caixa
  _ItemLinha({
    required this.tipo,
    required this.data,
    required this.pessoa,
    required this.categoriaNome,
    required this.valor,
    required this.observacao,
  });
}

class _CategoriaKV {
  final String key;
  final String label;
  _CategoriaKV(this.key, this.label);
}

// ===== widgets =====
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

  final _TipoTitulo tipo;
  final void Function(_TipoTitulo) onTipoChanged;

  final String? categoriaKey;
  final String? categoriaNome;
  final List<_CategoriaKV> categoriasDisponiveis;
  final void Function(String? key, String? label) onCategoriaChanged;

  const _Filtros({
    required this.periodo,
    required this.onPeriodoTap,
    required this.onPersonalizado,
    required this.ini,
    required this.fim,
    required this.tipo,
    required this.onTipoChanged,
    required this.categoriaKey,
    required this.categoriaNome,
    required this.categoriasDisponiveis,
    required this.onCategoriaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String _fmtData(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    // valor seguro do dropdown (evita value inválido quando lista muda)
    final Set<String> availableValues = {
      for (final c in categoriasDisponiveis) c.key,
    };
    final String? dropdownCategoriaValue =
        (categoriaKey != null && availableValues.contains(categoriaKey))
            ? categoriaKey
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
                    '${_fmtData(ini)} • ${_fmtData(fim)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Linha: Tipo e Categoria (pessoa)
            Row(
              children: [
                // Tipo
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<_TipoTitulo>(
                        value: tipo,
                        isDense: true,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: _TipoTitulo.ambos,
                            child: Text('Ambos'),
                          ),
                          DropdownMenuItem(
                            value: _TipoTitulo.entrada,
                            child: Text('Entrada'),
                          ),
                          DropdownMenuItem(
                            value: _TipoTitulo.saida,
                            child: Text('Saída'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) onTipoChanged(v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Categoria (pessoa)
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Cliente/Fornecedor',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: dropdownCategoriaValue,
                        isDense: true,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todas'),
                          ),
                          ...categoriasDisponiveis.map(
                            (c) => DropdownMenuItem<String?>(
                              value: c.key,
                              child: Text(
                                c.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null || v.isEmpty) {
                            onCategoriaChanged(null, null);
                          } else {
                            final label =
                                categoriasDisponiveis
                                    .firstWhere(
                                      (e) => e.key == v,
                                      orElse: () => _CategoriaKV(v, '—'),
                                    )
                                    .label;
                            onCategoriaChanged(v, label);
                          }
                        },
                      ),
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

class _BarChart extends StatelessWidget {
  final Map<String, double> categories;
  const _BarChart({required this.categories});

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final maxAbs = categories.values
        .map((v) => v.abs())
        .fold<double>(0, max)
        .clamp(1, double.infinity);
    final sorted =
        categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            for (final e in sorted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Stack(
                        children: [
                          Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          FractionallySizedBox(
                            alignment:
                                e.value >= 0
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                            widthFactor: (e.value.abs() / maxAbs).clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: e.value >= 0 ? Colors.green : Colors.red,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: Text(
                        _DashboardFluxoCaixaScreenState._fmtMoeda(e.value),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
