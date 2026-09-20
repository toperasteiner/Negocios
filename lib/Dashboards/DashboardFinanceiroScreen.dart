import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardFinanceiroScreen extends StatefulWidget {
  const DashboardFinanceiroScreen({super.key});

  @override
  State<DashboardFinanceiroScreen> createState() =>
      _DashboardFinanceiroScreenState();
}

enum PeriodoDashboard { hoje, seteDias, trintaDias, mesAtual }

class _DashboardFinanceiroScreenState extends State<DashboardFinanceiroScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? _uid;
  String? _companyId;
  String? _scopeUserId;
  bool _loadingScope = true;
  String? _scopeError;

  static const String kScopeField = 'companyId';
  PeriodoDashboard _periodo = PeriodoDashboard.mesAtual;

  DateTimeRange _getRange() {
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);

    switch (_periodo) {
      case PeriodoDashboard.hoje:
        return DateTimeRange(
          start: hoje,
          end: hoje.add(const Duration(days: 1)),
        );
      case PeriodoDashboard.seteDias:
        return DateTimeRange(
          start: hoje.subtract(const Duration(days: 6)),
          end: hoje.add(const Duration(days: 1)),
        );
      case PeriodoDashboard.trintaDias:
        return DateTimeRange(
          start: hoje.subtract(const Duration(days: 29)),
          end: hoje.add(const Duration(days: 1)),
        );
      case PeriodoDashboard.mesAtual:
        final inicio = DateTime(now.year, now.month, 1);
        final fim = DateTime(now.year, now.month + 1, 1);
        return DateTimeRange(start: inicio, end: fim);
    }
  }

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

  Future<_Resumo> _loadData() async {
    final range = _getRange();

    final snap =
        await _fs
            .collection('pedidos')
            .where('userId', isEqualTo: _uid ?? '__')
            .where(
              'data',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
            )
            .where('data', isLessThan: Timestamp.fromDate(range.end))
            .get();

    double faturamento = 0;
    double custo = 0;
    double lucro = 0;
    int pedidos = 0;

    final Map<String, _TopItem> produtos = {};
    final Map<String, _TopItem> servicos = {};

    for (var doc in snap.docs) {
      final m = doc.data();

      faturamento += _toDouble(m['subtotal']);
      custo += _toDouble(m['custoTotal']);
      lucro += _toDouble(m['lucroLiquido']);
      pedidos++;

      // Produtos
      final itensProdutos = (m['itensProdutos'] as List?) ?? [];
      for (var item in itensProdutos) {
        final x = Map<String, dynamic>.from(item);
        final nome = x['nome'] ?? '';
        final qtd = _toDouble(x['quantidade']);
        final lucroItem = _toDouble(x['lucroItem']);

        final atual = produtos[nome];
        produtos[nome] = _TopItem(
          nome: nome,
          quantidade: (atual?.quantidade ?? 0) + qtd,
          valor: (atual?.valor ?? 0) + lucroItem,
        );
      }

      // Serviços
      final itensServicos = (m['itensServicos'] as List?) ?? [];
      for (var item in itensServicos) {
        final x = Map<String, dynamic>.from(item);
        final nome = x['nome'] ?? '';
        final qtd = _toDouble(x['quantidade']);
        final lucroItem = _toDouble(x['lucroItem']);

        final atual = servicos[nome];
        servicos[nome] = _TopItem(
          nome: nome,
          quantidade: (atual?.quantidade ?? 0) + qtd,
          valor: (atual?.valor ?? 0) + lucroItem,
        );
      }
    }

    final margem = faturamento == 0 ? 0.0 : (lucro / faturamento) * 100.0;

    final ticket = pedidos == 0 ? 0.0 : faturamento / pedidos;

    return _Resumo(
      faturamento: faturamento,
      custo: custo,
      lucro: lucro,
      pedidos: pedidos,
      margem: margem,
      ticket: ticket,
      topProdutos:
          produtos.values.toList()..sort((a, b) => b.valor.compareTo(a.valor)),
      topServicos:
          servicos.values.toList()..sort((a, b) => b.valor.compareTo(a.valor)),
    );
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String _fmt(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Financeiro')),
      body: FutureBuilder<_Resumo>(
        future: _loadData(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final r = snap.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _filtro(),
              const SizedBox(height: 16),
              _cards(r),
              const SizedBox(height: 16),
              _top('Top Produtos', r.topProdutos),
              const SizedBox(height: 16),
              _top('Top Serviços', r.topServicos),
            ],
          );
        },
      ),
    );
  }

  Widget _filtro() {
    return DropdownButton<PeriodoDashboard>(
      value: _periodo,
      isExpanded: true,
      onChanged: (v) => setState(() => _periodo = v!),
      items: const [
        DropdownMenuItem(value: PeriodoDashboard.hoje, child: Text('Hoje')),
        DropdownMenuItem(
          value: PeriodoDashboard.seteDias,
          child: Text('Últimos 7 dias'),
        ),
        DropdownMenuItem(
          value: PeriodoDashboard.trintaDias,
          child: Text('Últimos 30 dias'),
        ),
        DropdownMenuItem(
          value: PeriodoDashboard.mesAtual,
          child: Text('Mês atual'),
        ),
      ],
    );
  }

  Widget _cards(_Resumo r) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _card('Faturamento', _fmt(r.faturamento)),
        _card('Custo', _fmt(r.custo)),
        _card('Lucro', _fmt(r.lucro)),
        _card('Pedidos', '${r.pedidos}'),
        _card('Ticket Médio', _fmt(r.ticket)),
        _card('Margem', '${r.margem.toStringAsFixed(2)}%'),
      ],
    );
  }

  Widget _card(String t, String v) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(t),
          const SizedBox(height: 6),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _top(String titulo, List<_TopItem> itens) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...itens
                .take(5)
                .map(
                  (e) => ListTile(
                    title: Text(e.nome),
                    subtitle: Text('Qtd: ${e.quantidade}'),
                    trailing: Text(_fmt(e.valor)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Resumo {
  final double faturamento;
  final double custo;
  final double lucro;
  final int pedidos;
  final double margem;
  final double ticket;
  final List<_TopItem> topProdutos;
  final List<_TopItem> topServicos;

  _Resumo({
    required this.faturamento,
    required this.custo,
    required this.lucro,
    required this.pedidos,
    required this.margem,
    required this.ticket,
    required this.topProdutos,
    required this.topServicos,
  });
}

class _TopItem {
  final String nome;
  final double quantidade;
  final double valor;

  _TopItem({required this.nome, required this.quantidade, required this.valor});
}
