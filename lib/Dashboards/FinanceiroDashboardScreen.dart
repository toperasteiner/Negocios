// lib/Financeiro/FinanceiroDashboardScreen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FinanceiroDashboardScreen extends StatefulWidget {
  const FinanceiroDashboardScreen({super.key});

  @override
  State<FinanceiroDashboardScreen> createState() =>
      _FinanceiroDashboardScreenState();
}

class _FinanceiroDashboardScreenState extends State<FinanceiroDashboardScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== AUTH/ESCOPO =====
  String? _uid;
  String? _companyId; // users.companyId
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  // campo de escopo nas coleções (mude para 'userId' se estiver em legado)
  static const String kScopeField = 'companyId';

  // Período
  DateTime _ini = _at00(DateTime.now());
  DateTime _fim = _at2359(DateTime.now());
  _Periodo _preset = _Periodo.mesAtual;

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid;
    _applyPreset(_preset);
    _initScope();
    _auth.authStateChanges().listen((u) async {
      _uid = u?.uid;
      await _initScope();
      if (mounted) setState(() {});
    });
  }

  // ====== Resolução de escopo (companyId ?? uid) ======
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
        '[FinanceiroDash] escopo: scopeUserId=$_scopeUserId (companyId=$_companyId, uid=${u.uid})',
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

  void _applyPreset(_Periodo p) {
    final now = DateTime.now();

    setState(() {
      _preset = p;
      switch (p) {
        case _Periodo.hoje:
          _ini = _at00(now);
          _fim = _at2359(now);
          break;
        case _Periodo.mesAtual:
          _ini = _at00(DateTime(now.year, now.month, 1));
          _fim = _at2359(DateTime(now.year, now.month + 1, 0));
          break;
        case _Periodo.mesPassado:
          final m0 = DateTime(now.year, now.month, 1);
          final ini = DateTime(m0.year, m0.month - 1, 1);
          final fim = DateTime(m0.year, m0.month, 0);
          _ini = _at00(ini);
          _fim = _at2359(fim);
          break;
        case _Periodo.ult30:
          _ini = _at00(now.subtract(const Duration(days: 29)));
          _fim = _at2359(now);
          break;
        case _Periodo.ult3m:
          final ini3 = DateTime(now.year, now.month - 2, 1);
          _ini = _at00(ini3);
          _fim = _at2359(now);
          break;
        case _Periodo.prox3m:
          final ini = _at00(now);
          final fim = DateTime(now.year, now.month + 3, 0);
          _ini = ini;
          _fim = _at2359(fim);
          break;
        case _Periodo.esteAno:
          _ini = _at00(DateTime(now.year, 1, 1));
          _fim = _at2359(DateTime(now.year, 12, 31));
          break;
        case _Periodo.anoPassado:
          _ini = _at00(DateTime(now.year - 1, 1, 1));
          _fim = _at2359(DateTime(now.year - 1, 12, 31));
          break;
        case _Periodo.mesEspecifico:
          break;
      }
    });
  }

  Future<void> _selectPeriodo() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FinanceiroStyle.bg,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    _IconBadge(
                      icon: Icons.calendar_month_outlined,
                      color: FinanceiroStyle.primary,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Escolha o período',
                        style: TextStyle(
                          color: FinanceiroStyle.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _pItem('Hoje', _Periodo.hoje),
                _pItem('Mês atual', _Periodo.mesAtual),
                _pItem('Mês passado', _Periodo.mesPassado),
                _pItem('Últimos 30 dias', _Periodo.ult30),
                _pItem('Últimos 3 meses', _Periodo.ult3m),
                _pItem('Próximos 3 meses', _Periodo.prox3m),
                _pItem('Este ano', _Periodo.esteAno),
                _pItem('Ano passado', _Periodo.anoPassado),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: const Icon(
                    Icons.edit_calendar_outlined,
                    color: FinanceiroStyle.primary,
                  ),
                  title: const Text(
                    'Selecionar mês específico',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _ini,
                      firstDate: DateTime(now.year - 5, 1, 1),
                      lastDate: DateTime(now.year + 1, 12, 31),
                      helpText: 'Escolha um dia do mês desejado',
                    );

                    if (picked != null && mounted) {
                      final ini = DateTime(picked.year, picked.month, 1);
                      final fim = DateTime(picked.year, picked.month + 1, 0);
                      Navigator.pop(context);
                      setState(() {
                        _preset = _Periodo.mesEspecifico;
                        _ini = _at00(ini);
                        _fim = _at2359(fim);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pItem(String label, _Periodo p) {
    final selected = _preset == p;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color:
            selected ? FinanceiroStyle.primary.withOpacity(0.10) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              selected
                  ? FinanceiroStyle.primary.withOpacity(0.35)
                  : const Color(0xFFE5E7EB),
        ),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(
          selected ? Icons.check_circle : Icons.calendar_today_outlined,
          color: selected ? FinanceiroStyle.primary : FinanceiroStyle.muted,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: FinanceiroStyle.text,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          _applyPreset(p);
        },
      ),
    );
  }

  // ===== QUERIES com ESCOPO (companyId ?? uid) =====
  // Índices recomendados:
  // contas_receber: (companyId ASC, status ASC, vencimento ASC)   [por whereIn+orderBy]
  // contas_pagar:   (companyId ASC, status ASC, vencimento ASC)
  //
  // ⚠️ Importante: usamos whereIn para incluir apenas 'aberto' e 'pago'
  //                (evita conflitos de múltiplas desigualdades e já exclui 'cancelado').
  Query<Map<String, dynamic>> _qReceber() {
    final scope = _scopeUserId ?? '__';
    final iniTs = Timestamp.fromDate(_ini);
    final fimExc = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExc);

    return _fs
        .collection('contas_receber')
        .where(kScopeField, isEqualTo: scope)
        .where('status', whereIn: ['aberto', 'pago'])
        .where('vencimento', isGreaterThanOrEqualTo: iniTs)
        .where('vencimento', isLessThan: fimTs)
        .orderBy('vencimento');
  }

  Query<Map<String, dynamic>> _qPagar() {
    final scope = _scopeUserId ?? '__';
    final iniTs = Timestamp.fromDate(_ini);
    final fimExc = _at00(_fim.add(const Duration(days: 1)));
    final fimTs = Timestamp.fromDate(fimExc);

    return _fs
        .collection('contas_pagar')
        .where(kScopeField, isEqualTo: scope)
        .where('status', whereIn: ['aberto', 'pago'])
        .where('vencimento', isGreaterThanOrEqualTo: iniTs)
        .where('vencimento', isLessThan: fimTs)
        .orderBy('vencimento');
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: FinanceiroStyle.bg,
        body: Center(
          child: CircularProgressIndicator(color: FinanceiroStyle.primary),
        ),
      );
    }

    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: FinanceiroStyle.bg,
        body: Column(
          children: [
            FinanceiroHeader(
              periodoLabel: _periodoLabel(),
              onBack: () => Navigator.of(context).maybePop(),
              onPeriodo: _selectPeriodo,
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _scopeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FinanceiroStyle.text,
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

    if (_scopeUserId == null) {
      return const Scaffold(
        backgroundColor: FinanceiroStyle.bg,
        body: Center(child: Text('Faça login para visualizar.')),
      );
    }

    return Scaffold(
      backgroundColor: FinanceiroStyle.bg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _qReceber().snapshots(),
        builder: (ctx, recSnap) {
          if (recSnap.hasError) return _err('Receita', recSnap.error);

          if (!recSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: FinanceiroStyle.primary),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _qPagar().snapshots(),
            builder: (ctx2, pagSnap) {
              if (pagSnap.hasError) return _err('Custos', pagSnap.error);

              if (!pagSnap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: FinanceiroStyle.primary,
                  ),
                );
              }

              // ======= Agrega RECEITA =======
              final hoje = _at00(DateTime.now());
              double recValorTotal = 0;
              double recRecebido = 0;
              double recAReceber = 0;
              double recEmAtraso = 0;

              for (final d in recSnap.data!.docs) {
                final m = d.data();
                final status = (m['status'] ?? '').toString();

                if (status == 'cancelado') continue;

                final valor = _asNum(m['valor']);
                final pago = max(
                  0.0,
                  min(valor, _asNum(m['valorPago'] ?? m['valorRecebido'])),
                );
                final saldo = max(0.0, valor - pago);
                final dtVenc = (m['vencimento'] as Timestamp?)?.toDate();

                recValorTotal += valor;
                recRecebido += pago;

                final atrasado =
                    (status != 'pago') &&
                    dtVenc != null &&
                    _at00(dtVenc).isBefore(hoje) &&
                    saldo > 0;

                if (atrasado) {
                  recEmAtraso += saldo;
                } else {
                  recAReceber += saldo;
                }
              }

              // ======= Agrega CUSTOS =======
              double cusValorTotal = 0;
              double cusPago = 0;
              double cusPrevisto = 0;
              double cusEmAtraso = 0;

              for (final d in pagSnap.data!.docs) {
                final m = d.data();
                final status = (m['status'] ?? '').toString();

                if (status == 'cancelado') continue;

                final valor = _asNum(m['valor']);
                final pago = max(0.0, min(valor, _asNum(m['valorPago'])));
                final saldo = max(0.0, valor - pago);
                final dtVenc = (m['vencimento'] as Timestamp?)?.toDate();

                cusValorTotal += valor;
                cusPago += pago;

                final atrasado =
                    (status != 'pago') &&
                    dtVenc != null &&
                    _at00(dtVenc).isBefore(hoje) &&
                    saldo > 0;

                if (atrasado) {
                  cusEmAtraso += saldo;
                } else {
                  cusPrevisto += saldo;
                }
              }

              final receitaTotalOperacional =
                  recRecebido + recAReceber + recEmAtraso;
              final custoTotalOperacional = cusPago + cusPrevisto + cusEmAtraso;
              final resultado = receitaTotalOperacional - custoTotalOperacional;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: FinanceiroHeader(
                      periodoLabel: _periodoLabel(),
                      onBack: () => Navigator.of(context).maybePop(),
                      onPeriodo: _selectPeriodo,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        ResultadoCard(
                          resultado: resultado,
                          receita: receitaTotalOperacional,
                          custos: custoTotalOperacional,
                          fmtMoeda: _fmtMoeda,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            /*Expanded(
                              child: FinanceiroResumoBox(
                                icon: Icons.trending_up_rounded,
                                label: 'Receita',
                                value: _fmtMoeda(receitaTotalOperacional),
                                color: FinanceiroStyle.green,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FinanceiroResumoBox(
                                icon: Icons.trending_down_rounded,
                                label: 'Custos',
                                value: _fmtMoeda(custoTotalOperacional),
                                color: FinanceiroStyle.orange,
                              ),
                            ),*/
                          ],
                        ),
                        const SizedBox(height: 14),
                        SectionCardModern(
                          title: 'Receita',
                          icon: Icons.attach_money_rounded,
                          color: FinanceiroStyle.green,
                          child: Column(
                            children: [
                              KpiRow(
                                color: FinanceiroStyle.green,
                                label: 'Recebido',
                                value: _fmtMoeda(recRecebido),
                              ),
                              KpiRow(
                                color: const Color(0xFF22C55E),
                                label: 'A receber',
                                value: _fmtMoeda(recAReceber),
                              ),
                              KpiRow(
                                color: FinanceiroStyle.orange,
                                label: 'Em atraso',
                                value: _fmtMoeda(recEmAtraso),
                              ),
                              const Divider(height: 20),
                              KpiBoldRow(
                                label: 'Receita total',
                                value: _fmtMoeda(recValorTotal),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SectionCardModern(
                          title: 'Custos',
                          icon: Icons.payments_outlined,
                          color: FinanceiroStyle.primary,
                          child: Column(
                            children: [
                              KpiRow(
                                color: FinanceiroStyle.primary,
                                label: 'Pago',
                                value: _fmtMoeda(cusPago),
                              ),
                              KpiRow(
                                color: FinanceiroStyle.blue,
                                label: 'Previsto',
                                value: _fmtMoeda(cusPrevisto),
                              ),
                              KpiRow(
                                color: FinanceiroStyle.red,
                                label: 'Em atraso',
                                value: _fmtMoeda(cusEmAtraso),
                              ),
                              const Divider(height: 20),
                              KpiBoldRow(
                                label: 'Custo total',
                                value: _fmtMoeda(cusValorTotal),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _periodoLabel() {
    switch (_preset) {
      case _Periodo.hoje:
        return 'Hoje';
      case _Periodo.mesAtual:
        return 'Mês atual';
      case _Periodo.mesPassado:
        return 'Mês passado';
      case _Periodo.ult30:
        return 'Últimos 30 dias';
      case _Periodo.ult3m:
        return 'Últimos 3 meses';
      case _Periodo.prox3m:
        return 'Próximos 3 meses';
      case _Periodo.esteAno:
        return 'Este ano';
      case _Periodo.anoPassado:
        return 'Ano passado';
      case _Periodo.mesEspecifico:
        return '${_mesNome(_ini.month)} de ${_ini.year}';
    }
  }

  static String _mesNome(int m) {
    const nomes = [
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
    return nomes[m];
  }

  static double _asNum(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0.0;
  }

  static Widget _err(String where, Object? e) => Scaffold(
    backgroundColor: FinanceiroStyle.bg,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          'Erro ao carregar $where: $e',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: FinanceiroStyle.red,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );

  static String _fmtMoeda(num v) {
    final n = v.toDouble();
    final sinal = n < 0 ? '-' : '';
    final s = n.abs().toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return '${sinal}R\$ $inteiro,${p[1]}';
  }
}

enum _Periodo {
  hoje,
  mesAtual,
  mesPassado,
  ult30,
  ult3m,
  prox3m,
  esteAno,
  anoPassado,
  mesEspecifico,
}

/* ====================== Identidade visual ====================== */

class FinanceiroStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get gradient => const LinearGradient(
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

/* ====================== Widgets visuais ====================== */

class FinanceiroHeader extends StatelessWidget {
  final String periodoLabel;
  final VoidCallback onBack;
  final VoidCallback onPeriodo;

  const FinanceiroHeader({
    super.key,
    required this.periodoLabel,
    required this.onBack,
    required this.onPeriodo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: FinanceiroStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        20,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Expanded(
                child: Center(
                  child: Text(
                    'Financeiro',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: Icons.calendar_month_outlined,
                onTap: onPeriodo,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Acompanhe receitas, custos e o resultado do negócio.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onPeriodo,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 17,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    periodoLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

class ResultadoCard extends StatelessWidget {
  final double resultado;
  final double receita;
  final double custos;
  final String Function(num value) fmtMoeda;

  const ResultadoCard({
    super.key,
    required this.resultado,
    required this.receita,
    required this.custos,
    required this.fmtMoeda,
  });

  @override
  Widget build(BuildContext context) {
    final positivo = resultado >= 0;
    final accent = positivo ? FinanceiroStyle.green : FinanceiroStyle.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: FinanceiroStyle.gradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: FinanceiroStyle.primary.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -26,
            top: -34,
            child: Container(
              width: 115,
              height: 115,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.09),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBadge(
                    icon:
                        positivo
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                    color: accent,
                    forceLight: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      positivo ? 'Resultado positivo' : 'Resultado negativo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                fmtMoeda(resultado),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 31,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Receitas menos custos no período selecionado.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MiniResultInfo(
                      label: 'Receitas',
                      value: fmtMoeda(receita),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniResultInfo(
                      label: 'Custos',
                      value: fmtMoeda(custos),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniResultInfo extends StatelessWidget {
  final String label;
  final String value;

  const _MiniResultInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceiroResumoBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const FinanceiroResumoBox({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: FinanceiroStyle.softShadow,
      ),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: FinanceiroStyle.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FinanceiroStyle.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCardModern extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  const SectionCardModern({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: FinanceiroStyle.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _IconBadge(icon: icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: FinanceiroStyle.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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

class KpiRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const KpiRow({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: FinanceiroStyle.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: FinanceiroStyle.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: FinanceiroStyle.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class KpiBoldRow extends StatelessWidget {
  final String label;
  final String value;

  const KpiBoldRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: FinanceiroStyle.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: FinanceiroStyle.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool forceLight;

  const _IconBadge({
    required this.icon,
    required this.color,
    this.forceLight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color:
            forceLight
                ? Colors.white.withOpacity(0.16)
                : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: forceLight ? Colors.white : color, size: 24),
    );
  }
}
