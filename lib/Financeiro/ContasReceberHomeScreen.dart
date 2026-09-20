// lib/Financeiro/ContasReceberHomeScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Seletores/SelecionarClienteSheet.dart';
// 👇 novo import do seletor de categoria (pagamentos)
import '../Seletores/SelecionarCategoriaPagamentoSheet.dart';

class ContasReceberStyle {
  static const Color primary = Color(0xFF6A2BFF);
  static const Color primaryDark = Color(0xFF32106C);
  static const Color orange = Color(0xFFFF9800);
  static const Color green = Color(0xFF16A34A);
  static const Color background = Color(0xFFF7F7FB);
  static const Color surface = Colors.white;
  static const Color text = Color(0xFF17152B);
  static const Color muted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE7E5EF);

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

enum CRStatus { todos, aberto, pago, cancelado }

const _statusLabel = {
  CRStatus.todos: 'Todos',
  CRStatus.aberto: 'Em aberto',
  CRStatus.pago: 'Pago',
  CRStatus.cancelado: 'Cancelado',
};

const _statusColor = {
  CRStatus.aberto: Colors.orange,
  CRStatus.pago: Colors.green,
  CRStatus.cancelado: Colors.red,
};

class ContasReceberHomeScreen extends StatefulWidget {
  const ContasReceberHomeScreen({super.key});

  @override
  State<ContasReceberHomeScreen> createState() =>
      _ContasReceberHomeScreenState();
}

class _ContasReceberHomeScreenState extends State<ContasReceberHomeScreen>
    with SingleTickerProviderStateMixin {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final ScrollController _listCtrl = ScrollController();
  String? get _uid => _auth.currentUser?.uid;

  // ===== ESCOPO MULTIEMPRESA =====
  String? _companyId; // users.companyId
  String? _scopeUserId; // companyId ?? uid (usar nas queries)
  bool _loadingScope = true;
  String? _scopeError;

  // 👉 Helpers de escopo
  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';

  // 🔐 Permissões (financeiro - receber)
  bool _canAccountsReceivable = false;
  bool _canAR_EditOpen = false; // canAccountsReceivableEditOpen
  bool _canAR_MarkPaid = false; // canAccountsReceivableMarkPaid
  bool _canAR_Cancel = false; // canAccountsReceivableCancel

  // filtros
  CRStatus _status = CRStatus.aberto;
  final _clienteCtrl = TextEditingController();
  String _clienteFiltro = '';

  // ordenação
  bool _ordemAsc = true; // por vencimento crescente

  // contadores por status
  final Map<CRStatus, int> _counts = {
    CRStatus.aberto: 0,
    CRStatus.pago: 0,
    CRStatus.cancelado: 0,
  };
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _initScope();
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  String _mkObsFluxo({
    required Map<String, dynamic> cr,
    required double valor,
    required String crId,
  }) {
    final cliente = (cr['clienteNome'] ?? '').toString().trim();
    final numero = (cr['pedidoNumero'] as int?) ?? 0;
    final ano = (cr['pedidoAno'] as int?) ?? 0;
    final temPedido = numero > 0 && ano > 0;

    final valorFmt = _fmtMoeda(valor);

    final partes = <String>[
      if (temPedido) 'Pedido: ${numero.toString().padLeft(3, '0')}-$ano',
      if (cliente.isNotEmpty) 'Cliente: $cliente',
      'Valor: $valorFmt',
    ];

    return partes.join(' ');
  }

  // ================== RESOLUÇÃO DE ESCOPO ==================

  Future<void> _showAcoesTitulo({
    required String id,
    required Map<String, dynamic> m,
    required CRStatus crStatus,
    required double valor,
    required DateTime? venc,
    required double? valorPago,
    required DateTime? dataPg,
    required String cliente,
  }) async {
    final itens = <Widget>[];

    // Duplicar (sempre que tiver permissão de Receber)
    itens.add(
      ListTile(
        leading: const Icon(Icons.copy_outlined),
        title: const Text('Duplicar'),
        enabled: _canAccountsReceivable,
        onTap: () async {
          Navigator.pop(context);
          await _duplicarTitulo(originalId: id, m: m);
        },
      ),
    );

    if (crStatus == CRStatus.aberto) {
      itens.addAll([
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Editar valor/vencimento'),
          enabled: _canAccountsReceivable && _canAR_EditOpen,
          onTap: () async {
            Navigator.pop(context);
            await _editarAberto(
              id: id,
              valorAtual: valor,
              vencAtual: venc,
              clienteNome: cliente,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: const Text('Marcar como pago'),
          enabled: _canAccountsReceivable && _canAR_MarkPaid,
          onTap: () async {
            Navigator.pop(context);
            await _marcarPago(id);
          },
        ),
      ]);
    }

    if (crStatus == CRStatus.pago) {
      itens.addAll([
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Editar pagamento'),
          enabled: _canAccountsReceivable && _canAR_MarkPaid,
          onTap: () async {
            Navigator.pop(context);
            await _editarPago(
              id: id,
              valorPagoAtual: valorPago,
              dataPagamentoAtual: dataPg,
              clienteNome: cliente,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Reabrir (em aberto)'),
          enabled: _canAccountsReceivable && _canAR_EditOpen,
          onTap: () async {
            Navigator.pop(context);
            await _reabrir(id);
          },
        ),
      ]);
    }

    if (crStatus == CRStatus.cancelado) {
      itens.add(
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Reabrir (em aberto)'),
          enabled: _canAccountsReceivable && _canAR_EditOpen,
          onTap: () async {
            Navigator.pop(context);
            await _reabrir(id);
          },
        ),
      );
    }

    if (crStatus != CRStatus.cancelado) {
      itens.add(
        ListTile(
          leading: const Icon(Icons.cancel_outlined, color: Colors.red),
          title: const Text('Cancelar'),
          enabled: _canAccountsReceivable && _canAR_Cancel,
          onTap: () async {
            Navigator.pop(context);
            await _cancelar(id);
          },
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    cliente.isEmpty ? 'Título' : cliente,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  subtitle: Row(
                    children: [
                      if (venc != null) Text('Venc.: ${_fmtData(venc)}'),
                      if (valorPago != null) ...[
                        const SizedBox(width: 8),
                        Text('Pago: ${_fmtMoeda(valorPago)}'),
                      ] else ...[
                        const SizedBox(width: 8),
                        Text('Valor: ${_fmtMoeda(valor)}'),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...itens,
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
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
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();

      // 🔐 carrega permissões de contas a receber
      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      bool p(String k) => (perms[k] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid; // escopo

        _canAccountsReceivable = p('canAccountsReceivable');
        _canAR_EditOpen = p('canAccountsReceivableEditOpen');
        _canAR_MarkPaid = p('canAccountsReceivableMarkPaid');
        _canAR_Cancel = p('canAccountsReceivableCancel');

        _loadingScope = false;
        _scopeError = null;
      });

      await _refreshCounts();
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
        final data = (byUid.data() ?? {}) as Map<String, dynamic>;
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

  // ----------------- helpers Firestore -----------------

  Query<Map<String, dynamic>> _queryBase() {
    final col = _fs.collection('contas_receber');
    final scope = _scopeUserId ?? '__';

    Query<Map<String, dynamic>> q = col.where(_scopeField, isEqualTo: scope);

    if (_status != CRStatus.todos) {
      q = q.where('status', isEqualTo: _status.name);
    }
    // se quiser ordenar no servidor, crie índice e descomente:
    // q = q.orderBy('vencimento', descending: !_ordemAsc);
    return q;
  }

  Future<void> _refreshCounts() async {
    final scope = _scopeUserId;
    if (scope == null) return;
    setState(() => _loadingCounts = true);

    Future<int> _count(String status) async {
      final a =
          await _fs
              .collection('contas_receber')
              .where(_scopeField, isEqualTo: scope)
              .where('status', isEqualTo: status)
              .count()
              .get();
      return a.count ?? 0;
    }

    final aberto = await _count('aberto');
    final pago = await _count('pago');
    final cancelado = await _count('cancelado');

    if (!mounted) return;
    setState(() {
      _counts[CRStatus.aberto] = aberto;
      _counts[CRStatus.pago] = pago;
      _counts[CRStatus.cancelado] = cancelado;
      _loadingCounts = false;
    });
  }

  // 🔐 Helpers de permissão
  bool _require(bool ok, String msg) {
    if (ok) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }

  bool _requireAR() =>
      _require(_canAccountsReceivable, 'Sem permissão para Contas a Receber.');

  bool _requireEditOpen() => _require(
    _canAccountsReceivable && _canAR_EditOpen,
    'Sem permissão para editar valor/vencimento.',
  );

  bool _requireMarkPaid() => _require(
    _canAccountsReceivable && _canAR_MarkPaid,
    'Sem permissão para marcar/editar pagamento.',
  );

  bool _requireCancel() => _require(
    _canAccountsReceivable && _canAR_Cancel,
    'Sem permissão para cancelar título.',
  );

  // ----------------- ações de item -----------------
  Future<void> _marcarPago(String id) async {
    if (!_requireMarkPaid()) return;

    try {
      final uid = _uid;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Faça login para continuar.')),
          );
        }
        return;
      }

      // Busca o título
      final ref = _fs.collection('contas_receber').doc(id);
      final snap = await ref.get();
      final m = snap.data();

      if (m == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Título não encontrado.')),
          );
        }
        return;
      }

      final statusAtual = (m['status'] ?? 'aberto').toString();
      if (statusAtual == 'pago') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este título já está como pago.')),
          );
        }
        return;
      }

      final valorTitulo = (m['valor'] as num?)?.toDouble() ?? 0.0;
      final clienteNome = (m['clienteNome'] ?? '').toString();
      final pedidoId = (m['pedidoId'] ?? '').toString().trim();

      final agora = DateTime.now();
      final dataPg = DateTime(agora.year, agora.month, agora.day);

      final batch = _fs.batch();

      // 2) Cria o lançamento no fluxo_caixa (somente se companyId está resolvido)
      String? fluxoId;
      if (_companyId != null && _companyId!.isNotEmpty) {
        final fluxoRef = _fs.collection('fluxo_caixa').doc();
        fluxoId = fluxoRef.id;

        batch.set(fluxoRef, {
          'userId': uid, // quem marcou pago
          'companyId': _companyId, // companyId do users.{uid}
          'createdByUid': uid,

          'data': Timestamp.fromDate(dataPg),
          'tipo': 'entrada',
          'valorAbs': valorTitulo,
          'valor': valorTitulo, // positivo (entrada)
          'observacao': _mkObsFluxo(cr: m, valor: valorTitulo, crId: snap.id),

          'clienteNome': clienteNome.isEmpty ? null : clienteNome,
          'fornecedorNome': null,

          // vínculo com pedido e CR
          'pedidoId': pedidoId.isEmpty ? null : pedidoId,
          'contasReceberId': snap.id,

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

      // 1) Atualiza o título como pago (e referencia o fluxoCaixaId se criado)
      batch.update(ref, {
        'status': 'pago',
        'valorPago': valorTitulo,
        'dataPagamento': Timestamp.fromDate(dataPg),
        if (fluxoId != null) 'fluxoCaixaId': fluxoId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pagamento registrado: ${_fmtMoeda(valorTitulo)}'),
          ),
        );
      }

      await _refreshCounts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao marcar como pago: $e')));
      }
    }
  }

  Future<void> _reabrir(String id) async {
    if (!_requireEditOpen()) return;
    try {
      final ref = _fs.collection('contas_receber').doc(id);
      final snap = await ref.get();
      final m = snap.data();

      final batch = _fs.batch();
      batch.update(ref, {
        'status': 'aberto',
        'dataPagamento': null,
        'valorPago': null,
        'fluxoCaixaId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final fluxoId = (m?['fluxoCaixaId'] ?? '').toString().trim();
      if (fluxoId.isNotEmpty) {
        batch.delete(_fs.collection('fluxo_caixa').doc(fluxoId));
      } else {
        if (_isCompanyScope) {
          final q =
              await _fs
                  .collection('fluxo_caixa')
                  .where('companyId', isEqualTo: _companyId)
                  .where('contasReceberId', isEqualTo: id)
                  .get();
          for (final doc in q.docs) {
            batch.delete(doc.reference);
          }
        }
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Título reaberto e fluxo removido.')),
        );
      }
      await _refreshCounts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao reabrir: $e')));
      }
    }
  }

  Future<void> _cancelar(String id) async {
    if (!_requireCancel()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Cancelar título?'),
            content: const Text(
              'Isto marcará este título como cancelado e removerá o lançamento no Fluxo de Caixa.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não'),
              ),
              FilledButton(
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
      batch.update(ref, {
        'status': 'cancelado',
        'dataPagamento': null,
        'valorPago': null,
        'fluxoCaixaId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final fluxoId = (m?['fluxoCaixaId'] ?? '').toString().trim();
      if (fluxoId.isNotEmpty) {
        batch.delete(_fs.collection('fluxo_caixa').doc(fluxoId));
      } else {
        if (_isCompanyScope) {
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
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Título cancelado e fluxo removido.')),
        );
      }
      await _refreshCounts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
      }
    }
  }

  Future<void> _editarAberto({
    required String id,
    required double valorAtual,
    required DateTime? vencAtual,
    String? clienteNome,
  }) async {
    if (!_requireEditOpen()) return;
    final valorCtrl = TextEditingController(
      text: valorAtual.toStringAsFixed(2).replaceAll('.', ','),
    );
    DateTime venc = vencAtual ?? DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSt) => AlertDialog(
                  title: Text(
                    clienteNome?.isNotEmpty == true
                        ? clienteNome!
                        : 'Editar título',
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: valorCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Valor',
                          prefixText: 'R\$ ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text('Venc.: ${_fmtData(venc)}')),
                          TextButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: venc,
                                firstDate: DateTime(venc.year - 5),
                                lastDate: DateTime(venc.year + 5),
                                helpText: 'Escolha o vencimento',
                              );
                              if (d != null) setSt(() => venc = d);
                            },
                            icon: const Icon(Icons.event),
                            label: const Text('Trocar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
          ),
    );

    if (ok == true) {
      final v = _parseMoeda(valorCtrl.text);
      await _fs.collection('contas_receber').doc(id).update({
        'valor': v,
        'vencimento': Timestamp.fromDate(
          DateTime(venc.year, venc.month, venc.day),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Título atualizado.')));
      }
    }
  }

  Future<void> _editarPago({
    required String id,
    required double? valorPagoAtual,
    required DateTime? dataPagamentoAtual,
    String? clienteNome,
  }) async {
    if (!_requireMarkPaid()) return;

    final valorCtrl = TextEditingController(
      text: (valorPagoAtual ?? 0.0).toStringAsFixed(2).replaceAll('.', ','),
    );
    DateTime dataPg = dataPagamentoAtual ?? DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSt) => AlertDialog(
                  title: Text(
                    clienteNome?.isNotEmpty == true
                        ? clienteNome!
                        : 'Ajustar pagamento',
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: valorCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Valor pago',
                          prefixText: 'R\$ ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text('Pago em: ${_fmtData(dataPg)}')),
                          TextButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: dataPg,
                                firstDate: DateTime(dataPg.year - 5),
                                lastDate: DateTime(dataPg.year + 5),
                                helpText: 'Data do pagamento',
                              );
                              if (d != null) setSt(() => dataPg = d);
                            },
                            icon: const Icon(Icons.event_available_outlined),
                            label: const Text('Trocar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true) return;

    try {
      final v = _parseMoeda(valorCtrl.text);
      final refCR = _fs.collection('contas_receber').doc(id);
      final snapCR = await refCR.get();
      final m = snapCR.data() ?? {};

      final uid = _uid;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Faça login para continuar.')),
          );
        }
        return;
      }

      final nomeCliente = (m['clienteNome'] ?? '').toString();
      final pedidoId = (m['pedidoId'] ?? '').toString().trim();

      final tsDataPg = Timestamp.fromDate(
        DateTime(dataPg.year, dataPg.month, dataPg.day),
      );

      final batch = _fs.batch();

      // 1) Atualiza o título (CR)
      batch.update(refCR, {
        'valorPago': v,
        'dataPagamento': tsDataPg,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2) Atualiza (ou cria) o lançamento em fluxo_caixa
      String? fluxoId = (m['fluxoCaixaId'] ?? '').toString().trim();
      DocumentReference<Map<String, dynamic>>? fluxoRef;

      if (fluxoId.isNotEmpty) {
        fluxoRef = _fs.collection('fluxo_caixa').doc(fluxoId);
        batch.update(fluxoRef, {
          'data': tsDataPg,
          'valorAbs': v,
          'valor': v, // entrada
          'updatedAt': FieldValue.serverTimestamp(),
          if (nomeCliente.isNotEmpty) 'clienteNome': nomeCliente,
          if (pedidoId.isNotEmpty) 'pedidoId': pedidoId,
          'contasReceberId': id,
          'observacao': _mkObsFluxo(cr: m, valor: v, crId: id),
        });
      } else {
        if (_isCompanyScope) {
          final q =
              await _fs
                  .collection('fluxo_caixa')
                  .where('companyId', isEqualTo: _companyId)
                  .where('contasReceberId', isEqualTo: id)
                  .limit(1)
                  .get();
          if (q.docs.isNotEmpty) {
            fluxoRef = q.docs.first.reference;
            fluxoId = fluxoRef.id;
            batch.update(fluxoRef, {
              'data': tsDataPg,
              'valorAbs': v,
              'valor': v,
              'updatedAt': FieldValue.serverTimestamp(),
              if (nomeCliente.isNotEmpty) 'clienteNome': nomeCliente,
              if (pedidoId.isNotEmpty) 'pedidoId': pedidoId,
            });
            batch.update(refCR, {'fluxoCaixaId': fluxoId});
          } else {
            fluxoRef = _fs.collection('fluxo_caixa').doc();
            fluxoId = fluxoRef.id;
            batch.set(fluxoRef, {
              'userId': uid,
              'companyId': _companyId,
              'createdByUid': uid,
              'data': tsDataPg,
              'tipo': 'entrada',
              'valorAbs': v,
              'valor': v,
              'observacao': _mkObsFluxo(cr: m, valor: v, crId: id),
              'clienteNome': nomeCliente.isEmpty ? null : nomeCliente,
              'fornecedorNome': null,
              'pedidoId': pedidoId.isEmpty ? null : pedidoId,
              'contasReceberId': id,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            batch.update(refCR, {'fluxoCaixaId': fluxoId});
          }
        }
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pagamento atualizado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar pagamento: $e')),
        );
      }
    }
  }

  // ----------------- DUPLICAR TÍTULO (replica categoria) -----------------
  Future<void> _duplicarTitulo({
    required String originalId,
    required Map<String, dynamic> m,
  }) async {
    if (!_requireAR()) return;
    final uid = _uid;
    final scope = _scopeUserId;
    if (uid == null || scope == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login.')));
      return;
    }

    final clienteId = (m['clienteId'] ?? '').toString();
    final clienteNome = (m['clienteNome'] ?? '').toString();
    final descricao = (m['descricao'] ?? '').toString();
    final valorOriginal = (m['valor'] as num?)?.toDouble() ?? 0.0;
    final vencOriginal =
        (m['vencimento'] as Timestamp?)?.toDate() ?? DateTime.now();

    // >>> categoria do original (se houver)
    final String? catKeyOrig =
        (m['categoriaKey'] ?? '').toString().trim().isEmpty
            ? null
            : (m['categoriaKey'] as String);
    final String? catNomeOrig =
        (m['categoriaNome'] ?? '').toString().trim().isEmpty
            ? null
            : (m['categoriaNome'] as String);

    final valorCtrl = TextEditingController(
      text: valorOriginal.toStringAsFixed(2).replaceAll('.', ','),
    );
    DateTime venc = vencOriginal;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSt) => AlertDialog(
                  title: const Text('Duplicar título'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          clienteNome.isEmpty ? '—' : clienteNome,
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: valorCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Valor',
                          prefixText: 'R\$ ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Vencimento: ${_fmtData(venc)}'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: venc,
                                firstDate: DateTime(venc.year - 5),
                                lastDate: DateTime(venc.year + 5),
                                helpText: 'Escolha o vencimento',
                              );
                              if (d != null) setSt(() => venc = d);
                            },
                            icon: const Icon(Icons.event),
                            label: const Text('Trocar'),
                          ),
                        ],
                      ),
                      if (catNomeOrig != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Categoria: $catNomeOrig',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Duplicar'),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true) return;

    final novoValor = _parseMoeda(valorCtrl.text);
    if (novoValor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um valor válido.')));
      return;
    }

    try {
      await _fs.collection('contas_receber').add({
        // >>> Correção: SEMPRE UID aqui:
        'userId': uid,
        // >>> E companyId quando existir:
        if (_isCompanyScope) 'companyId': _companyId,
        'createdByUid': uid,
        'origem': 'duplicado',
        'fromId': originalId,
        'clienteId': clienteId.isEmpty ? null : clienteId,
        'clienteNome': clienteNome.isEmpty ? null : clienteNome,
        'descricao': descricao.isEmpty ? null : descricao,
        'valor': novoValor,
        'vencimento': Timestamp.fromDate(
          DateTime(venc.year, venc.month, venc.day),
        ),
        'status': 'aberto',
        'valorPago': null,
        'dataPagamento': null,
        // >>> replica categoria
        'categoriaKey': catKeyOrig,
        'categoriaNome': catNomeOrig,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Título duplicado.')));
      }
      await _refreshCounts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao duplicar: $e')));
      }
    }
  }

  // ----------------- criar novo título (manual) -----------------
  double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickCliente(
    BuildContext ctx,
    void Function(void Function()) setSt,
    void Function(ClienteSelecionado) onSel,
  ) async {
    final c = await showModalBottomSheet<ClienteSelecionado>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SelecionarClienteSheet(),
    );
    if (c != null) {
      setSt(() => onSel(c));
    }
  }

  // ========= NOVO: abrir seletor de categorias de pagamento (Receber) =========
  Future<CategoriaSelecionada?> _pickCategoriaPagamento(BuildContext ctx) {
    return showModalBottomSheet<CategoriaSelecionada>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => const SelecionarCategoriaPagamentoSheet(
            filtroTipo: 'receber', // mostra apenas categorias do tipo Receber
          ),
    );
  }

  Future<void> _novoTitulo() async {
    if (!_requireAR()) return;
    final uid = _uid;
    final scope = _scopeUserId;
    if (uid == null || scope == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login.')));
      return;
    }

    ClienteSelecionado? clienteSel;
    final descCtrl = TextEditingController();
    final valorCtrl = TextEditingController(text: '0,00');
    DateTime venc = DateTime.now();
    bool salvando = false;

    // >>> usando o novo seletor
    CategoriaSelecionada? categoriaSel;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSt) => AlertDialog(
                  title: const Text('Novo contas a receber'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Cliente
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Cliente',
                            style: Theme.of(ctx).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(ctx).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  clienteSel?.nome ?? 'Selecione um cliente',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        clienteSel == null
                                            ? Colors.black54
                                            : null,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed:
                                    salvando
                                        ? null
                                        : () => _pickCliente(
                                          ctx,
                                          setSt,
                                          (c) => clienteSel = c,
                                        ),
                                icon: const Icon(Icons.person_search_outlined),
                                label: Text(
                                  clienteSel == null ? 'Selecionar' : 'Trocar',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Categoria (novo seletor)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Categoria',
                            style: Theme.of(ctx).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(ctx).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.category_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  categoriaSel?.nome ??
                                      'Selecione uma categoria',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        categoriaSel == null
                                            ? Colors.black54
                                            : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed:
                                    salvando
                                        ? null
                                        : () async {
                                          final sel =
                                              await _pickCategoriaPagamento(
                                                ctx,
                                              );
                                          if (sel != null)
                                            setSt(() => categoriaSel = sel);
                                        },
                                icon: const Icon(Icons.search),
                                label: Text(
                                  categoriaSel == null
                                      ? 'Selecionar'
                                      : 'Trocar',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Descrição
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Descrição (opcional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Valor
                        TextField(
                          controller: valorCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d\., ]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Valor',
                            prefixText: 'R\$ ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Vencimento
                        Row(
                          children: [
                            Expanded(
                              child: Text('Vencimento: ${_fmtData(venc)}'),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: venc,
                                  firstDate: DateTime(venc.year - 5),
                                  lastDate: DateTime(venc.year + 5),
                                  helpText: 'Escolha o vencimento',
                                );
                                if (d != null) setSt(() => venc = d);
                              },
                              icon: const Icon(Icons.event),
                              label: const Text('Trocar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          salvando ? null : () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          salvando
                              ? null
                              : () async {
                                if (clienteSel == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Selecione um cliente.'),
                                    ),
                                  );
                                  return;
                                }
                                if (categoriaSel == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Selecione uma categoria.'),
                                    ),
                                  );
                                  return;
                                }
                                final v = _parseMoeda(valorCtrl.text);
                                if (v <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Informe um valor válido.'),
                                    ),
                                  );
                                  return;
                                }
                                setSt(() => salvando = true);
                                try {
                                  await _fs.collection('contas_receber').add({
                                    // >>> Correção multiempresa:
                                    'userId': uid, // UID sempre
                                    if (_isCompanyScope)
                                      'companyId': _companyId,
                                    'createdByUid': uid,
                                    'origem': 'manual',
                                    'clienteId': clienteSel!.id,
                                    'clienteNome': clienteSel!.nome,
                                    'descricao':
                                        descCtrl.text.trim().isEmpty
                                            ? null
                                            : descCtrl.text.trim(),

                                    // >>> categoria (novo seletor)
                                    'categoriaKey':
                                        categoriaSel!.id, // docId da categoria
                                    'categoriaNome': categoriaSel!.nome,

                                    'valor': v,
                                    'vencimento': Timestamp.fromDate(
                                      DateTime(venc.year, venc.month, venc.day),
                                    ),
                                    'status': 'aberto',
                                    'createdAt': FieldValue.serverTimestamp(),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Título criado.'),
                                      ),
                                    );
                                  }
                                  if (mounted) Navigator.pop(ctx, true);
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro ao salvar: $e'),
                                      ),
                                    );
                                  }
                                  setSt(() => salvando = false);
                                }
                              },
                      icon:
                          salvando
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.save_outlined),
                      label: const Text('Salvar'),
                    ),
                  ],
                ),
          ),
    );

    if (ok == true) {
      await _refreshCounts();
      setState(() {}); // reflete na lista
    }
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final double fabReserve = 84.0 + MediaQuery.of(context).padding.bottom;

    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: ContasReceberStyle.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: ContasReceberStyle.background,
        body: Column(
          children: [
            _cabecalho(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _scopeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ContasReceberStyle.text),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: ContasReceberStyle.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _canAccountsReceivable ? _novoTitulo : () => _requireAR(),
        backgroundColor:
            _canAccountsReceivable
                ? ContasReceberStyle.primary
                : const Color(0xFFE5E7EB),
        foregroundColor:
            _canAccountsReceivable ? Colors.white : ContasReceberStyle.muted,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Novo título',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _cabecalho(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _queryBase().snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Erro ao carregar: ${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];

                final filtered =
                    docs.where((d) {
                      if (_clienteFiltro.isEmpty) return true;
                      final nome =
                          (d.data()['clienteNome'] ?? '')
                              .toString()
                              .toLowerCase();
                      return nome.contains(_clienteFiltro);
                    }).toList();

                filtered.sort((a, b) {
                  final va = (a.data()['vencimento'] as Timestamp?)?.toDate();
                  final vb = (b.data()['vencimento'] as Timestamp?)?.toDate();
                  final ca = va == null ? 0 : va.millisecondsSinceEpoch;
                  final cb = vb == null ? 0 : vb.millisecondsSinceEpoch;
                  return _ordemAsc ? ca.compareTo(cb) : cb.compareTo(ca);
                });

                final total = filtered.fold<double>(0.0, (acc, doc) {
                  final m = doc.data();
                  final valor = (m['valor'] is num) ? (m['valor'] + 0.0) : 0.0;
                  final valorPago =
                      (m['valorPago'] is num) ? (m['valorPago'] + 0.0) : null;
                  return acc + (valorPago ?? valor);
                });

                return CustomScrollView(
                  controller: _listCtrl,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _painelFiltros(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _resumoLista(
                          quantidade: filtered.length,
                          total: total,
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(
                          title: 'Nada encontrado',
                          subtitle:
                              'Ajuste os filtros para ver seus recebíveis.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          16 + fabReserve,
                        ),
                        sliver: SliverList.separated(
                          itemCount: filtered.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            final m = d.data();

                            final statusStr =
                                (m['status'] ?? 'aberto').toString();
                            final crStatus = () {
                              switch (statusStr) {
                                case 'pago':
                                  return CRStatus.pago;
                                case 'cancelado':
                                  return CRStatus.cancelado;
                                default:
                                  return CRStatus.aberto;
                              }
                            }();

                            final venc =
                                (m['vencimento'] as Timestamp?)?.toDate();
                            final cliente = (m['clienteNome'] ?? '').toString();
                            final valor =
                                (m['valor'] is num) ? (m['valor'] + 0.0) : 0.0;
                            final numero =
                                (m['pedidoNumero'] ?? 0) as int? ?? 0;
                            final ano = (m['pedidoAno'] ?? 0) as int? ?? 0;
                            final dataPg =
                                (m['dataPagamento'] as Timestamp?)?.toDate();
                            final valorPago =
                                (m['valorPago'] is num)
                                    ? (m['valorPago'] + 0.0)
                                    : null;
                            final double valorMostrar = valorPago ?? valor;
                            final categoriaNome =
                                (m['categoriaNome'] ?? '').toString();

                            final hoje = DateTime.now();
                            final isVencido =
                                crStatus == CRStatus.aberto &&
                                venc != null &&
                                DateTime(
                                  venc.year,
                                  venc.month,
                                  venc.day,
                                ).isBefore(
                                  DateTime(hoje.year, hoje.month, hoje.day),
                                );

                            return _cardTitulo(
                              cliente: cliente,
                              pedidoNumero: numero,
                              pedidoAno: ano,
                              categoriaNome: categoriaNome,
                              crStatus: crStatus,
                              venc: venc,
                              dataPg: dataPg,
                              valorMostrar: valorMostrar,
                              isVencido: isVencido,
                              onTap: () {
                                _showAcoesTitulo(
                                  id: d.id,
                                  m: m,
                                  crStatus: crStatus,
                                  valor: valor,
                                  venc: venc,
                                  valorPago: valorPago,
                                  dataPg: dataPg,
                                  cliente: cliente,
                                );
                              },
                              onLongPress: () {
                                _showAcoesTitulo(
                                  id: d.id,
                                  m: m,
                                  crStatus: crStatus,
                                  valor: valor,
                                  venc: venc,
                                  valorPago: valorPago,
                                  dataPg: dataPg,
                                  cliente: cliente,
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: ContasReceberStyle.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.white.withOpacity(.16),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.maybePop(context),
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contas a Receber',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Acompanhe vencimentos e recebimentos',
                  style: TextStyle(color: Color(0xFFD9D4F5), fontSize: 12),
                ),
              ],
            ),
          ),
          _headerAction(
            tooltip:
                _ordemAsc
                    ? 'Ordenar por vencimento (desc)'
                    : 'Ordenar por vencimento (asc)',
            icon:
                _ordemAsc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
            onTap: () => setState(() => _ordemAsc = !_ordemAsc),
          ),
          const SizedBox(width: 8),
          _headerAction(
            tooltip: 'Atualizar',
            icon: Icons.refresh_rounded,
            onTap: _refreshCounts,
          ),
        ],
      ),
    );
  }

  Widget _headerAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(.16),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }

  Widget _painelFiltros() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                color: ContasReceberStyle.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Filtros',
                style: TextStyle(
                  color: ContasReceberStyle.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in CRStatus.values) ...[
                  _statusChip(s),
                  if (s != CRStatus.values.last) const SizedBox(width: 7),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clienteCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: ContasReceberStyle.primary,
              ),
              suffixIcon:
                  _clienteCtrl.text.isEmpty
                      ? null
                      : IconButton(
                        tooltip: 'Limpar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _clienteCtrl.clear();
                          setState(() => _clienteFiltro = '');
                        },
                      ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: ContasReceberStyle.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(
                  color: ContasReceberStyle.primary,
                  width: 1.5,
                ),
              ),
            ),
            onChanged:
                (t) => setState(() => _clienteFiltro = t.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          _contadores(),
        ],
      ),
    );
  }

  Widget _statusChip(CRStatus s) {
    final selected = _status == s;
    final color =
        s == CRStatus.todos
            ? ContasReceberStyle.primary
            : (_statusColor[s] ?? ContasReceberStyle.primary);

    return ChoiceChip(
      label: Text(_statusLabel[s]!),
      selected: selected,
      showCheckmark: false,
      avatar:
          s == CRStatus.todos
              ? null
              : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : color,
                  shape: BoxShape.circle,
                ),
              ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : ContasReceberStyle.text,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      selectedColor: color,
      backgroundColor: const Color(0xFFF8FAFC),
      side: BorderSide(color: selected ? color : ContasReceberStyle.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => setState(() => _status = s),
    );
  }

  Widget _contadores() {
    if (_loadingCounts) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _contadorMini(
            label: 'Abertos',
            valor: _counts[CRStatus.aberto] ?? 0,
            color: _statusColor[CRStatus.aberto]!,
            onTap: () => setState(() => _status = CRStatus.aberto),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _contadorMini(
            label: 'Pagos',
            valor: _counts[CRStatus.pago] ?? 0,
            color: _statusColor[CRStatus.pago]!,
            onTap: () => setState(() => _status = CRStatus.pago),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _contadorMini(
            label: 'Cancelados',
            valor: _counts[CRStatus.cancelado] ?? 0,
            color: _statusColor[CRStatus.cancelado]!,
            onTap: () => setState(() => _status = CRStatus.cancelado),
          ),
        ),
      ],
    );
  }

  Widget _contadorMini({
    required String label,
    required int valor,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Text(
                '$valor',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ContasReceberStyle.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumoLista({required int quantidade, required double total}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ContasReceberStyle.primary.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ContasReceberStyle.primary.withOpacity(.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$quantidade ${quantidade == 1 ? 'título' : 'títulos'}',
              style: const TextStyle(
                color: ContasReceberStyle.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(
            'Total ',
            style: TextStyle(color: ContasReceberStyle.muted, fontSize: 12),
          ),
          Text(
            _fmtMoeda(total),
            style: const TextStyle(
              color: ContasReceberStyle.primaryDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTitulo({
    required String cliente,
    required int pedidoNumero,
    required int pedidoAno,
    required String categoriaNome,
    required CRStatus crStatus,
    required DateTime? venc,
    required DateTime? dataPg,
    required double valorMostrar,
    required bool isVencido,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final statusColor = _statusColor[crStatus] ?? ContasReceberStyle.primary;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ContasReceberStyle.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.035),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  crStatus == CRStatus.pago
                      ? Icons.check_circle_outline_rounded
                      : crStatus == CRStatus.cancelado
                      ? Icons.cancel_outlined
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
                      cliente.isEmpty ? '—' : cliente,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ContasReceberStyle.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if (pedidoNumero > 0 && pedidoAno > 0)
                          _infoPill(
                            icon: Icons.receipt_long_outlined,
                            text:
                                'Pedido ${pedidoNumero.toString().padLeft(3, '0')}-$pedidoAno',
                          ),
                        if (venc != null)
                          _infoPill(
                            icon: Icons.event_outlined,
                            text: 'Venc. ${_fmtData(venc)}',
                          ),
                        if (isVencido)
                          _infoPill(
                            icon: Icons.warning_amber_rounded,
                            text: 'Vencido',
                            color: Colors.red,
                          ),
                        if (crStatus == CRStatus.pago && dataPg != null)
                          _infoPill(
                            icon: Icons.event_available_outlined,
                            text: 'Pago ${_fmtData(dataPg)}',
                            color: Colors.green,
                          ),
                        if (categoriaNome.isNotEmpty)
                          _infoPill(
                            icon: Icons.category_outlined,
                            text: categoriaNome,
                            color: ContasReceberStyle.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtMoeda(valorMostrar),
                    style: const TextStyle(
                      color: ContasReceberStyle.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel[crStatus]!,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.more_horiz_rounded,
                    color: ContasReceberStyle.muted,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoPill({
    required IconData icon,
    required String text,
    Color color = ContasReceberStyle.muted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- widgets auxiliares -----------------

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  const _Dot({required this.color, this.size = 12});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CountChip extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _CountChip({
    required this.color,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = selected ? cs.primaryContainer.withOpacity(0.45) : cs.surface;
    final border = selected ? cs.primary : theme.dividerColor;

    final textStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: selected ? cs.onPrimaryContainer : null,
    );

    final chip = Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      labelPadding: const EdgeInsets.only(left: 4, right: 6),
      side: BorderSide(color: border),
      backgroundColor: bg,
      avatar: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      label: Text(
        label,
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    );

    return onTap == null
        ? chip
        : InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: chip,
        );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 72, color: cs.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
