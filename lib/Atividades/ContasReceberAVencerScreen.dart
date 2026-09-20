// lib/Financeiro/ContasReceberAVencerScreen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ContasReceberAVencerScreen extends StatefulWidget {
  const ContasReceberAVencerScreen({super.key});

  @override
  State<ContasReceberAVencerScreen> createState() =>
      _ContasReceberAVencerScreenState();
}

class _ContasReceberAVencerScreenState
    extends State<ContasReceberAVencerScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== ESCOPO MULTIEMPRESA =====
  String? _companyId; // users.companyId
  String? _scopeUserId; // companyId ?? uid (usar nas queries)
  bool _loadingScope = true;
  String? _scopeError;

  // Helpers de escopo: se tiver companyId, filtra por companyId; senão por userId (legado)
  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';

  // 🔐 Permissões (financeiro - receber)
  bool _canAR = false; // canAccountsReceivable
  bool _canAR_EditOpen = false; // canAccountsReceivableEditOpen
  bool _canAR_MarkPaid = false; // canAccountsReceivableMarkPaid
  bool _canAR_Cancel = false; // canAccountsReceivableCancel

  // Filtros (inicia em VENCIDOS)
  _Filtro _filtro = _Filtro.vencidos;
  DateTime _ini = _at00(DateTime.now());
  DateTime _fim = _at2359(DateTime.now());

  static DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _at2359(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  @override
  void initState() {
    super.initState();
    _aplicarFiltro(_Filtro.vencidos);
    _initScope();
    _auth.authStateChanges().listen((_) {
      if (mounted) _initScope();
    });
  }

  // ================== ESCOPO + PERMISSÕES ==================
  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
        _canAR = false;
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
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid; // ⟵ ESCOPO

        _canAR = p('canAccountsReceivable');
        _canAR_EditOpen = p('canAccountsReceivableEditOpen');
        _canAR_MarkPaid = p('canAccountsReceivableMarkPaid');
        _canAR_Cancel = p('canAccountsReceivableCancel');

        _loadingScope = false;
        _scopeError = null;
      });
      debugPrint(
        '[CR A Vencer] escopo: $_scopeField=$_scopeUserId (companyId=$_companyId uid=${u.uid})',
      );
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
    final col = _fs.collection('contas_receber');
    final scope = _scopeUserId ?? '__';

    // Sempre restringe ao escopo e a títulos em aberto
    var q = col
        .where(_scopeField, isEqualTo: scope)
        .where('status', isEqualTo: 'aberto');

    final hoje00 = _at00(DateTime.now());

    if (_filtro == _Filtro.vencidos) {
      q = q.where('vencimento', isLessThan: Timestamp.fromDate(hoje00));
      return q.orderBy(
        'vencimento',
      ); // exige índice composto com escopo + status
    } else {
      final iniTs = Timestamp.fromDate(_ini);
      final fimExc = _at00(_fim.add(const Duration(days: 1))); // fim exclusivo
      final fimTs = Timestamp.fromDate(fimExc);

      q = q
          .where('vencimento', isGreaterThanOrEqualTo: iniTs)
          .where('vencimento', isLessThan: fimTs);

      return q.orderBy(
        'vencimento',
      ); // exige índice composto com escopo + status
    }
  }

  // ================== GATES DE PERMISSÃO ==================
  bool _require(bool ok, String msg) {
    if (ok) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }

  bool _requireEditOpen() => _require(
    _canAR && _canAR_EditOpen,
    'Sem permissão para editar valor/vencimento.',
  );
  bool _requireMarkPaid() => _require(
    _canAR && _canAR_MarkPaid,
    'Sem permissão para marcar/editar recebimento.',
  );
  bool _requireCancel() =>
      _require(_canAR && _canAR_Cancel, 'Sem permissão para cancelar título.');

  // ---------- Ações (integram com fluxo_caixa) ----------
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
      await _fs.collection('contas_receber').doc(id).update(updates);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Título atualizado.')));
      }
    }
  }

  Future<void> _marcarRecebido(String id, Map<String, dynamic> m) async {
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
    final clienteNome = (m['clienteNome'] ?? '').toString();

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
                Text('Marcar como Recebido', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            content: Text('Confirmar recebimento de ${_fmtMoeda(valor)}?'),
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
      final ref = _fs.collection('contas_receber').doc(id);
      final snap = await ref.get();
      final atual = snap.data() ?? {};
      final statusAtual = (atual['status'] ?? 'aberto').toString();

      if (statusAtual == 'pago') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este título já está como recebido.')),
          );
        }
        return;
      }

      final hoje = DateTime.now();
      final dataPg = DateTime(hoje.year, hoje.month, hoje.day);

      final batch = _fs.batch();
      String? fluxoId;

      // Lança no fluxo_caixa (entrada) com companyId quando houver
      if (_isCompanyScope) {
        final fluxoRef = _fs.collection('fluxo_caixa').doc();
        fluxoId = fluxoRef.id;

        batch.set(fluxoRef, {
          'userId': uid,
          'companyId': _companyId, // ⟵ importante
          'createdByUid': uid,

          'data': Timestamp.fromDate(dataPg),
          'tipo': 'entrada',
          'valorAbs': valor,
          'valor': valor,

          'observacao': [
            'Recebimento CR $id',
            if (clienteNome.isNotEmpty) '• $clienteNome',
          ].join(' '),

          'clienteNome': clienteNome.isNotEmpty ? clienteNome : null,
          'fornecedorNome': null,

          'contasReceberId': id,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recebimento marcado, mas não foi possível lançar no Fluxo de Caixa '
                '(companyId ausente em users.{uid}.companyId).',
              ),
            ),
          );
        }
      }

      // Atualiza CR como pago (+ vínculo com fluxo, se criado)
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
          SnackBar(
            content: Text('Recebimento registrado: ${_fmtMoeda(valor)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao marcar como recebido: $e')),
        );
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
      final ref = _fs.collection('contas_receber').doc(id);
      final snap = await ref.get();
      final m = snap.data();

      final batch = _fs.batch();

      // Atualiza CR e limpa pagamento + vínculo
      batch.update(ref, {
        'status': 'cancelado',
        'dataPagamento': null,
        'valorPago': null,
        'fluxoCaixaId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Remove lançamentos no fluxo_caixa (por vínculo direto ou busca por companyId)
      final fluxoId = (m?['fluxoCaixaId'] ?? '').toString().trim();
      if (fluxoId.isNotEmpty) {
        batch.delete(_fs.collection('fluxo_caixa').doc(fluxoId));
      } else if (_isCompanyScope) {
        final q =
            await _fs
                .collection('fluxo_caixa')
                .where('companyId', isEqualTo: _companyId)
                .where('contasReceberId', isEqualTo: id)
                .get();
        for (final d in q.docs) {
          batch.delete(d.reference);
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
    if (!_canAR) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sem permissão para Contas a Receber.',
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
                    // Filtro defensivo na UI
                    final m = d.data();
                    final valor = _asNum(m['valor']);
                    final pago = _asNum(m['valorPago']);
                    final saldo = max(0.0, valor - pago);
                    if (saldo <= 0) return false;
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
                          'Contas a Receber',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Gestão de recebimentos e clientes',
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
              color: const Color(0xFF059669).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.savings_outlined,
              color: Color(0xFF059669),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalTitulos ${totalTitulos == 1 ? 'título a receber' : 'títulos a receber'}',
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
    final cliente = (m['clienteNome'] ?? '').toString();
    final desc = (m['descricao'] ?? '').toString();
    final dt = (m['vencimento'] as Timestamp?)?.toDate();
    final valor = _asNum(m['valor']);
    final pago = _asNum(m['valorPago']);
    final saldo = max(0.0, valor - pago);

    final atrasado = dt != null && _at00(dt).isBefore(_at00(DateTime.now()));
    final statusColor = atrasado ? const Color(0xFFDC2626) : const Color(0xFF059669);

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
              _canAR && _canAR_EditOpen ? () => _abrirEditar(id, m) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha superior: cliente/desc + status badge + popup menu
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
                            : Icons.arrow_downward_rounded,
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
                            cliente.isEmpty
                                ? (desc.isEmpty ? 'Sem identificação' : desc)
                                : cliente,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (cliente.isNotEmpty && desc.isNotEmpty) ...[
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
                // Linha de dados: Vencimento + Saldo a Receber
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
                            'SALDO A RECEBER',
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
                if (_canAR_MarkPaid) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _marcarRecebido(id, m),
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
                        'Confirmar Recebimento',
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
        } else if (k == 'recebido') {
          await _marcarRecebido(id, m);
        } else if (k == 'cancelar') {
          await _cancelar(id);
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'editar',
          enabled: _canAR && _canAR_EditOpen,
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
          value: 'recebido',
          enabled: _canAR && _canAR_MarkPaid,
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: Color(0xFF059669)),
              SizedBox(width: 10),
              Text(
                'Marcar como recebido',
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
          enabled: _canAR && _canAR_Cancel,
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
                  ? 'Excelente! Não há contas vencidas para receber.'
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
