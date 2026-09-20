// lib/Financeiro/ContasPagarAVencerScreen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ContasPagarAVencerScreen extends StatefulWidget {
  const ContasPagarAVencerScreen({super.key});

  @override
  State<ContasPagarAVencerScreen> createState() =>
      _ContasPagarAVencerScreenState();
}

class _ContasPagarAVencerScreenState extends State<ContasPagarAVencerScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== ESCOPO MULTIEMPRESA =====
  String? _companyId; // users.companyId
  String? _scopeUserId; // companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  // Campo usado para ESCOPAR todas as consultas desta tela.
  // Se ainda estiver em legado, mude para 'userId'.
  static const String kScopeField = 'companyId';

  // 🔐 Permissões (financeiro - pagar)
  bool _canAP = false; // canAccountsPayable
  bool _canAP_EditOpen = false; // canAccountsPayableEditOpen
  bool _canAP_MarkPaid = false; // canAccountsPayableMarkPaid
  bool _canAP_Cancel = false; // canAccountsPayableCancel

  // filtros
  _Filtro _filtro = _Filtro.vencidos; // começa em "vencidos"
  DateTime _ini = _at00(DateTime.now());
  DateTime _fim = _at2359(DateTime.now());

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _aplicarFiltro(_filtro);
    _initScope();
    // re-resolve escopo ao trocar auth (logout/login)
    _auth.authStateChanges().listen((_) {
      if (mounted) _initScope();
    });
  }

  // ================== RESOLUÇÃO DE ESCOPO + PERMISSÕES ==================
  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
        _canAP = false;
      });
      return;
    }
    try {
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();

      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      bool p(String k) => (perms[k] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid; // << aqui!

        _canAP = p('canAccountsPayable');
        _canAP_EditOpen = p('canAccountsPayableEditOpen');
        _canAP_MarkPaid = p('canAccountsPayableMarkPaid');
        _canAP_Cancel = p('canAccountsPayableCancel');

        _loadingScope = false;
        _scopeError = null;
      });
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar empresa/escopo: $e';
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    // 1) por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) {
        final data = byUid.data() ?? {};
        data['__docId'] = byUid.id;
        return data;
      }
    } catch (_) {}

    // 2) por emailKey (fallback)
    final email = (u.email ?? '').toLowerCase().trim();
    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          d['__docId'] = q.docs.first.id;
          return d;
        }
      } catch (_) {}
    }
    return null;
  }

  // ================== FILTRO ==================
  void _aplicarFiltro(_Filtro f) {
    final now = DateTime.now();
    setState(() {
      _filtro = f;
      switch (f) {
        case _Filtro.hoje:
          _ini = _at00(now);
          _fim = _at2359(now);
          break;
        case _Filtro.semana:
          final dow = now.weekday; // 1=seg..7=dom
          final ini = now.subtract(Duration(days: dow - 1));
          final fim = ini.add(const Duration(days: 6));
          _ini = _at00(ini);
          _fim = _at2359(fim);
          break;
        case _Filtro.mes:
          final ini = DateTime(now.year, now.month, 1);
          final fim = DateTime(now.year, now.month + 1, 0);
          _ini = _at00(ini);
          _fim = _at2359(fim);
          break;
        case _Filtro.vencidos:
          _ini = _at00(DateTime(2000, 1, 1));
          _fim = _at2359(now.subtract(const Duration(days: 1)));
          break;
      }
    });
  }

  // ================== QUERY (usa ESCOPO) ==================
  Query<Map<String, dynamic>> _query() {
    final col = _fs.collection('contas_pagar');
    final scope = _scopeUserId ?? '__';

    var q = col.where(kScopeField, isEqualTo: scope); // << multiempresa

    final hoje = _at00(DateTime.now());
    if (_filtro == _Filtro.vencidos) {
      q = q
          .where('vencimento', isLessThan: Timestamp.fromDate(hoje))
          .where('status', isNotEqualTo: 'pago');
      return q.orderBy('status').orderBy('vencimento'); // exige índice composto
    } else {
      final iniTs = Timestamp.fromDate(_ini);
      final fimExc = _at00(_fim.add(const Duration(days: 1)));
      final fimTs = Timestamp.fromDate(fimExc);
      q = q
          .where('vencimento', isGreaterThanOrEqualTo: iniTs)
          .where('vencimento', isLessThan: fimTs)
          .where('status', isNotEqualTo: 'pago');
      return q.orderBy('status').orderBy('vencimento'); // exige índice composto
    }
  }

  // ================== GATES DE PERMISSÃO ==================
  bool _require(bool ok, String msg) {
    if (ok) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }

  bool _requireEditOpen() => _require(
    _canAP && _canAP_EditOpen,
    'Sem permissão para editar valor/vencimento.',
  );

  bool _requireMarkPaid() => _require(
    _canAP && _canAP_MarkPaid,
    'Sem permissão para marcar/editar pagamento.',
  );

  bool _requireCancel() =>
      _require(_canAP && _canAP_Cancel, 'Sem permissão para cancelar título.');

  // ---------- Ações (com integração ao fluxo_caixa) ----------
  Future<void> _abrirEditar(String id, Map<String, dynamic> m) async {
    if (!_requireEditOpen()) return;

    final valorInicial = _asNum(m['valor']);
    final dtInicial = (m['vencimento'] as Timestamp?)?.toDate();

    final valorCtrl = TextEditingController(
      text: _fmtMoeda(valorInicial).replaceAll('R\$ ', ''),
    );
    DateTime? novoVenc = dtInicial ?? DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.edit_outlined, color: Color(0xFF3B0CA3), size: 22),
                SizedBox(width: 10),
                Text(
                  'Editar Título',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\., ]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Valor',
                    prefixText: 'R\$ ',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF3B0CA3), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: novoVenc ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      novoVenc = picked;
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_outlined, color: Color(0xFF3B0CA3), size: 20),
                        const SizedBox(width: 10),
                        Text(
                          novoVenc == null
                              ? 'Escolher vencimento'
                              : _fmtData(novoVenc!),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B0CA3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
    );

    if (ok == true) {
      final valorNovo = _parseMoeda(valorCtrl.text);
      final updates = <String, dynamic>{
        'valor': valorNovo,
        if (novoVenc != null)
          'vencimento': Timestamp.fromDate(_at00(novoVenc!)),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _fs.collection('contas_pagar').doc(id).update(updates);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Título atualizado.')));
      }
    }
  }

  Future<void> _marcarPago(String id, Map<String, dynamic> m) async {
    if (!_requireMarkPaid()) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faça login para continuar.')),
        );
      }
      return;
    }

    final valor = _asNum(m['valor']);
    final fornecedorNome = (m['fornecedorNome'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 22),
                SizedBox(width: 10),
                Text('Marcar como Pago', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            content: Text('Confirmar pagamento de ${_fmtMoeda(valor)}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não', style: TextStyle(color: Color(0xFF64748B))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sim, confirmar'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    try {
      final ref = _fs.collection('contas_pagar').doc(id);
      final snap = await ref.get();
      final atual = snap.data() ?? {};
      final statusAtual = (atual['status'] ?? 'aberto').toString();

      if (statusAtual == 'pago') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este título já está como pago.')),
          );
        }
        return;
      }

      final hoje = DateTime.now();
      final dataPg = DateTime(hoje.year, hoje.month, hoje.day);

      final batch = _fs.batch();
      String? fluxoId;

      // Cria fluxo_caixa (saída) se houver companyId
      if (_companyId != null && _companyId!.isNotEmpty) {
        final fluxoRef = _fs.collection('fluxo_caixa').doc();
        fluxoId = fluxoRef.id;

        batch.set(fluxoRef, {
          'userId': uid, // quem marcou pago
          'companyId': _companyId,
          'createdByUid': uid,

          'data': Timestamp.fromDate(dataPg),
          'tipo': 'saida',
          'valorAbs': valor,
          'valor': -valor, // saída => negativo

          'observacao': [
            'Pagamento CP $id',
            if (fornecedorNome.isNotEmpty) '• $fornecedorNome',
          ].join(' '),

          'clienteNome': null,
          'fornecedorNome': fornecedorNome.isEmpty ? null : fornecedorNome,

          // vínculo com CP
          'contasPagarId': id,

          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pagamento marcado, mas não foi possível lançar no Fluxo de Caixa '
                '(companyId ausente em users.{uid}.companyId).',
              ),
            ),
          );
        }
      }

      // Atualiza o título como pago (e referencia o fluxoCaixaId se criado)
      batch.update(ref, {
        'status': 'pago',
        'valorPago': valor,
        'dataPagamento': Timestamp.fromDate(dataPg),
        if (fluxoId != null) 'fluxoCaixaId': fluxoId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pagamento registrado: ${_fmtMoeda(valor)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao marcar como pago: $e')));
      }
    }
  }

  Future<void> _cancelar(String id) async {
    if (!_requireCancel()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.red, size: 22),
                SizedBox(width: 10),
                Text('Cancelar Título', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            content: const Text(
              'Deseja realmente cancelar este título? Se houver lançamento no Fluxo de Caixa, ele será removido.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não', style: TextStyle(color: Color(0xFF64748B))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sim, cancelar'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    try {
      final ref = _fs.collection('contas_pagar').doc(id);
      final snap = await ref.get();
      final m = snap.data();

      final batch = _fs.batch();

      // atualiza CP e limpa pagamento + vínculo
      batch.update(ref, {
        'status': 'cancelado',
        'dataPagamento': null,
        'valorPago': null,
        'fluxoCaixaId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // remove lançamentos no fluxo_caixa
      final fluxoId = (m?['fluxoCaixaId'] ?? '').toString().trim();
      if (fluxoId.isNotEmpty) {
        batch.delete(_fs.collection('fluxo_caixa').doc(fluxoId));
      } else {
        if (_companyId != null && _companyId!.isNotEmpty) {
          final q =
              await _fs
                  .collection('fluxo_caixa')
                  .where('companyId', isEqualTo: _companyId)
                  .where('contasPagarId', isEqualTo: id)
                  .get();
          for (final d in q.docs) {
            batch.delete(d.reference);
          }
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Título cancelado e fluxo removido.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
      }
    }
  }

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B0CA3)),
          ),
        ),
      );
    }
    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(_scopeError!, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }
    if (!_canAP) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sem permissão para Contas a Pagar.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _query().snapshots(),
                builder: (ctx, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.error_outline,
                                  color: Colors.red, size: 36),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Erro ao carregar dados',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${snap.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF3B0CA3)),
                      ),
                    );
                  }

                  final docs = (snap.data?.docs ?? []).where((d) {
                    // Filtra na UI:
                    final m = d.data();
                    final valor = _asNum(m['valor']);
                    final pago = _asNum(m['valorPago']);
                    final saldo = max(0.0, valor - pago);
                    if (saldo <= 0) return false; // totalmente pago

                    final status = (m['status'] ?? '').toString();
                    if (status == 'pago' || status == 'cancelado') return false;

                    if (_filtro == _Filtro.vencidos) {
                      final dt = (m['vencimento'] as Timestamp?)?.toDate();
                      return dt != null &&
                          _at00(dt).isBefore(_at00(DateTime.now()));
                    }
                    return true;
                  }).toList();

                  if (docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  // Totais
                  double totalSaldo = 0.0;
                  for (final d in docs) {
                    final m = d.data();
                    totalSaldo +=
                        max(0.0, _asNum(m['valor']) - _asNum(m['valorPago']));
                  }

                  return RefreshIndicator(
                    color: const Color(0xFF3B0CA3),
                    onRefresh: () async => setState(() {}),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: docs.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildTotalBanner(docs.length, totalSaldo);
                        }

                        final d = docs[index - 1];
                        final m = d.data();
                        return _buildContaCard(d.id, m);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3B0CA3),
            Color(0xFF5B21B6),
            Color(0xFFF97316),
          ],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).maybePop(),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contas a Pagar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Gestão de vencimentos e pagamentos',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_Filtro>(
                    tooltip: 'Filtrar período',
                    onSelected: _aplicarFiltro,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    itemBuilder: (_) => [
                      _buildPopupItem(_Filtro.hoje, 'Hoje', Icons.today_outlined),
                      _buildPopupItem(_Filtro.semana, 'Semana atual',
                          Icons.calendar_view_week_outlined),
                      _buildPopupItem(_Filtro.mes, 'Mês atual',
                          Icons.calendar_month_outlined),
                      const PopupMenuDivider(),
                      _buildPopupItem(_Filtro.vencidos, 'Vencidos',
                          Icons.warning_amber_rounded,
                          color: Colors.red),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_list_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _labelFiltro(_filtro),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down,
                              color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Chips de filtros rápidos
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _Filtro.values.map((f) {
                    final isSel = _filtro == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => _aplicarFiltro(f),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSel
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSel
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            _labelFiltro(f),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel
                                  ? const Color(0xFF3B0CA3)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_Filtro> _buildPopupItem(_Filtro val, String text, IconData icon,
      {Color? color}) {
    final isSel = _filtro == val;
    return PopupMenuItem<_Filtro>(
      value: val,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? const Color(0xFF475569)),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
              color: isSel ? const Color(0xFF3B0CA3) : const Color(0xFF1E293B),
            ),
          ),
          if (isSel) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: Color(0xFF3B0CA3)),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalBanner(int totalTitulos, double totalSaldo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3B0CA3).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Color(0xFF3B0CA3),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalTitulos ${totalTitulos == 1 ? 'título pendente' : 'títulos pendentes'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtMoeda(totalSaldo),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _filtro == _Filtro.vencidos
                  ? Colors.red.withValues(alpha: 0.1)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _filtro == _Filtro.vencidos ? 'Vencidos' : 'Em Aberto',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _filtro == _Filtro.vencidos
                    ? Colors.red.shade700
                    : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContaCard(String id, Map<String, dynamic> m) {
    final fornecedor = (m['fornecedorNome'] ?? '').toString();
    final desc = (m['descricao'] ?? '').toString();
    final dt = (m['vencimento'] as Timestamp?)?.toDate();
    final valor = _asNum(m['valor']);
    final pago = _asNum(m['valorPago']);
    final saldo = max(0.0, valor - pago);

    final atrasado = dt != null && _at00(dt).isBefore(_at00(DateTime.now()));
    final statusColor = atrasado ? const Color(0xFFDC2626) : const Color(0xFFEA580C);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: atrasado
              ? Colors.red.withValues(alpha: 0.25)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: atrasado
                ? Colors.red.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onLongPress:
              _canAP && _canAP_EditOpen ? () => _abrirEditar(id, m) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha superior: título + status badge + popup menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        atrasado
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                        color: statusColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fornecedor.isEmpty
                                ? (desc.isEmpty ? 'Sem fornecedor/descrição' : desc)
                                : fornecedor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (fornecedor.isNotEmpty && desc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildOptionsMenu(id, m),
                  ],
                ),
                const SizedBox(height: 14),
                // Linha de dados: Vencimento + Saldo/Valor
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDF2F7)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'VENCIMENTO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.event_outlined,
                                  size: 14,
                                  color: atrasado
                                      ? Colors.red
                                      : const Color(0xFF475569),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dt != null ? _fmtData(dt) : 'Sem data',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: atrasado
                                        ? Colors.red
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 30,
                        width: 1,
                        color: const Color(0xFFE2E8F0),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'SALDO A PAGAR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _fmtMoeda(saldo),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canAP_MarkPaid) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _marcarPago(id, m),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text(
                        'Confirmar Pagamento',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsMenu(String id, Map<String, dynamic> m) {
    return PopupMenuButton<String>(
      tooltip: 'Opções',
      onSelected: (k) async {
        if (k == 'editar') {
          await _abrirEditar(id, m);
        } else if (k == 'pago') {
          await _marcarPago(id, m);
        } else if (k == 'cancelar') {
          await _cancelar(id);
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'editar',
          enabled: _canAP && _canAP_EditOpen,
          child: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: Color(0xFF475569)),
              SizedBox(width: 10),
              Text(
                'Editar valor/vencimento',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'pago',
          enabled: _canAP && _canAP_MarkPaid,
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: Color(0xFF059669)),
              SizedBox(width: 10),
              Text(
                'Marcar como pago',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'cancelar',
          enabled: _canAP && _canAP_Cancel,
          child: const Row(
            children: [
              Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
              SizedBox(width: 10),
              Text(
                'Cancelar título',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.more_horiz,
          color: Color(0xFF475569),
          size: 18,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF3B0CA3).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 54,
                color: Color(0xFF3B0CA3),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _filtro == _Filtro.vencidos
                  ? 'Nenhum título vencido!'
                  : 'Nenhum título no período',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _filtro == _Filtro.vencidos
                  ? 'Excelente! Todas as contas estão em dia.'
                  : 'Período selecionado: ${_fmtData(_ini)} até ${_fmtData(_fim)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3B0CA3),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Atualizar lista'),
            ),
          ],
        ),
      ),
    );
  }

  static String _labelFiltro(_Filtro f) {
    switch (f) {
      case _Filtro.hoje:
        return 'Hoje';
      case _Filtro.semana:
        return 'Semana';
      case _Filtro.mes:
        return 'Mês';
      case _Filtro.vencidos:
        return 'Vencidos';
    }
  }

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

  static double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }
}

enum _Filtro { hoje, semana, mes, vencidos }
