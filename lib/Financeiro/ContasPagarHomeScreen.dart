// lib/Financeiro/ContasPagarHomeScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Seletores/SelecionarFornecedorSheet.dart';
import '../Seletores/SelecionarCategoriaPagamentoSheet.dart';

class ContasPagarStyle {
  static const primary = Color(0xFF6A2BFF);
  static const primaryDark = Color(0xFF32106C);
  static const orange = Color(0xFFFF9800);
  static const background = Color(0xFFF7F7FB);
  static const text = Color(0xFF17152B);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE7E5EF);
  static const headerGradient = LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

enum CPStatus { todos, aberto, pago, cancelado }

const _statusLabel = {
  CPStatus.todos: 'Todos',
  CPStatus.aberto: 'Em aberto',
  CPStatus.pago: 'Pago',
  CPStatus.cancelado: 'Cancelado',
};

const _statusColor = {
  CPStatus.aberto: Colors.orange,
  CPStatus.pago: Colors.green,
  CPStatus.cancelado: Colors.red,
};

class ContasPagarHomeScreen extends StatefulWidget {
  const ContasPagarHomeScreen({super.key});

  @override
  State<ContasPagarHomeScreen> createState() => _ContasPagarHomeScreenState();
}

class _ContasPagarHomeScreenState extends State<ContasPagarHomeScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _listCtrl = ScrollController();

  String? get _uid => _auth.currentUser?.uid;

  // ===== ESCOPO MULTIEMPRESA =====
  String? _companyId; // users.companyId do usuário
  String? _scopeUserId; // companyId ?? uid  -> usado nas queries
  bool _loadingScope = true; // loading enquanto resolve escopo
  String? _scopeError;

  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';

  String _mkObsFornecedorValor(String fornecedorNome, double valor) {
    final nome = fornecedorNome.trim();
    return 'Fornecedor: ${nome.isEmpty ? "—" : nome} Valor: ${_fmtMoeda(valor)}';
  }

  // 🔐 Permissões (financeiro - pagar)
  bool _canAccountsPayable = false;
  bool _canAP_EditOpen = false; // canAccountsPayableEditOpen
  bool _canAP_MarkPaid = false; // canAccountsPayableMarkPaid
  bool _canAP_Cancel = false; // canAccountsPayableCancel

  // filtros
  CPStatus _status = CPStatus.aberto;
  final _fornCtrl = TextEditingController();
  String _fornFiltro = '';

  // ordenação
  bool _ordemAsc = true;

  // contadores
  final Map<CPStatus, int> _counts = {
    CPStatus.aberto: 0,
    CPStatus.pago: 0,
    CPStatus.cancelado: 0,
  };
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _initScope(); // resolve escopo e só então carrega contadores
  }

  @override
  void dispose() {
    _fornCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  // ================== RESOLUÇÃO DE ESCOPO ==================
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

      // 🔐 carrega permissões
      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      bool p(String k) => (perms[k] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid; // escopo

        _canAccountsPayable = p('canAccountsPayable');
        _canAP_EditOpen = p('canAccountsPayableEditOpen');
        _canAP_MarkPaid = p('canAccountsPayableMarkPaid');
        _canAP_Cancel = p('canAccountsPayableCancel');

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

  // ================== helpers Firestore ==================
  Query<Map<String, dynamic>> _queryBase() {
    final col = _fs.collection('contas_pagar');
    final scope = _scopeUserId ?? '__';

    Query<Map<String, dynamic>> q = col.where(_scopeField, isEqualTo: scope);

    if (_status != CPStatus.todos) {
      q = q.where('status', isEqualTo: _status.name);
    }
    // se quiser ordenar por vencimento depois que criar índice:
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
              .collection('contas_pagar')
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
      _counts[CPStatus.aberto] = aberto;
      _counts[CPStatus.pago] = pago;
      _counts[CPStatus.cancelado] = cancelado;
      _loadingCounts = false;
    });
  }

  // ================== formatações ==================
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

  // ================== GATES DE PERMISSÃO ==================
  bool _require(bool ok, String msg) {
    if (ok) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }

  bool _requireAP() =>
      _require(_canAccountsPayable, 'Sem permissão para Contas a Pagar.');

  bool _requireEditOpen() => _require(
    _canAccountsPayable && _canAP_EditOpen,
    'Sem permissão para editar valor/vencimento.',
  );

  bool _requireMarkPaid() => _require(
    _canAccountsPayable && _canAP_MarkPaid,
    'Sem permissão para marcar/editar pagamento.',
  );

  bool _requireCancel() => _require(
    _canAccountsPayable && _canAP_Cancel,
    'Sem permissão para cancelar título.',
  );

  // ================== AÇÕES (com integração a fluxo_caixa) ==================

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

      final ref = _fs.collection('contas_pagar').doc(id);
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
      final fornecedorNome = (m['fornecedorNome'] ?? '').toString();

      final agora = DateTime.now();
      final dataPg = DateTime(agora.year, agora.month, agora.day);

      final batch = _fs.batch();

      // 2) Cria o lançamento no fluxo_caixa (somente se companyId está resolvido)
      String? fluxoId;
      if (_companyId != null && _companyId!.isNotEmpty) {
        final fluxoRef = _fs.collection('fluxo_caixa').doc();
        fluxoId = fluxoRef.id;

        batch.set(fluxoRef, {
          'userId': uid, // quem executou
          'companyId': _companyId, // escopo
          'createdByUid': uid,

          'data': Timestamp.fromDate(dataPg),
          'tipo': 'saida',
          'valorAbs': valorTitulo,
          'valor': -valorTitulo, // saída => negativo

          'observacao': [
            'Pagamento CP ${snap.id}',
            if (fornecedorNome.isNotEmpty) '• $fornecedorNome',
          ].join(' '),

          'clienteNome': null,
          'fornecedorNome': fornecedorNome.isNotEmpty ? fornecedorNome : null,

          'contasPagarId': snap.id,

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

      // 1) Atualiza o CP como pago (e referencia fluxoCaixaId se criado)
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
      final ref = _fs.collection('contas_pagar').doc(id);
      final snap = await ref.get();
      final m = snap.data();

      final batch = _fs.batch();

      // volta CP para aberto e remove vínculo/pagamento
      batch.update(ref, {
        'status': 'aberto',
        'dataPagamento': null,
        'valorPago': null,
        'fluxoCaixaId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // apaga o(s) lançamentos no fluxo_caixa vinculados
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
    String? fornecedorNome,
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
                    fornecedorNome?.isNotEmpty == true
                        ? fornecedorNome!
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
      await _fs.collection('contas_pagar').doc(id).update({
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
    String? fornecedorNome,
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
                    fornecedorNome?.isNotEmpty == true
                        ? fornecedorNome!
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
      final uid = _uid;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Faça login para continuar.')),
          );
        }
        return;
      }

      final v = _parseMoeda(valorCtrl.text);
      final refCP = _fs.collection('contas_pagar').doc(id);
      final snapCP = await refCP.get();
      final m = snapCP.data() ?? {};

      final nomeFornecedor = (m['fornecedorNome'] ?? '').toString();

      final tsDataPg = Timestamp.fromDate(
        DateTime(dataPg.year, dataPg.month, dataPg.day),
      );

      final batch = _fs.batch();

      // 1) Atualiza o título (CP)
      batch.update(refCP, {
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
          'valor': -v, // saída => negativo
          'updatedAt': FieldValue.serverTimestamp(),
          if (nomeFornecedor.isNotEmpty) 'fornecedorNome': nomeFornecedor,
          'contasPagarId': id,
        });
      } else {
        // tentar localizar pelo vínculo (contasPagarId)
        if (_companyId != null && _companyId!.isNotEmpty) {
          final q =
              await _fs
                  .collection('fluxo_caixa')
                  .where('companyId', isEqualTo: _companyId)
                  .where('contasPagarId', isEqualTo: id)
                  .limit(1)
                  .get();

          if (q.docs.isNotEmpty) {
            fluxoRef = q.docs.first.reference;
            fluxoId = fluxoRef.id;
            batch.update(fluxoRef, {
              'data': tsDataPg,
              'valorAbs': v,
              'valor': -v,
              'updatedAt': FieldValue.serverTimestamp(),
              if (nomeFornecedor.isNotEmpty) 'fornecedorNome': nomeFornecedor,
            });
            // grava o id encontrado no CP
            batch.update(refCP, {'fluxoCaixaId': fluxoId});
          } else {
            // não existe fluxo → cria novo
            if (_companyId != null && _companyId!.isNotEmpty) {
              fluxoRef = _fs.collection('fluxo_caixa').doc();
              fluxoId = fluxoRef.id;

              batch.set(fluxoRef, {
                'userId': uid,
                'companyId': _companyId,
                'createdByUid': uid,

                'data': tsDataPg,
                'tipo': 'saida',
                'valorAbs': v,
                'valor': -v,

                'observacao': [
                  'Pagamento CP $id',
                  if (nomeFornecedor.isNotEmpty) '• $nomeFornecedor',
                ].join(' '),

                'clienteNome': null,
                'fornecedorNome':
                    nomeFornecedor.isNotEmpty ? nomeFornecedor : null,

                'contasPagarId': id,

                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });

              batch.update(refCP, {'fluxoCaixaId': fluxoId});
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Pagamento ajustado, mas não foi possível lançar no Fluxo de Caixa '
                      '(companyId ausente em users.{uid}.companyId).',
                    ),
                  ),
                );
              }
            }
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

  // ================== DUPLICAR ==================
  Future<void> _duplicarTitulo({
    required String originalId,
    required Map<String, dynamic> m,
  }) async {
    if (!_requireAP()) return;
    final uid = _uid;
    final scope = _scopeUserId;
    if (uid == null || scope == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login.')));
      return;
    }

    final fornecedorId = (m['fornecedorId'] ?? '').toString();
    final fornecedorNome = (m['fornecedorNome'] ?? '').toString();
    final descricao = (m['descricao'] ?? '').toString();
    final valorOriginal = (m['valor'] as num?)?.toDouble() ?? 0.0;
    final vencOriginal =
        (m['vencimento'] as Timestamp?)?.toDate() ?? DateTime.now();

    // Mantém compatibilidade: se o original tiver categoria salva no modelo antigo,
    // copiamos o que houver.
    final String? catIdOrig =
        (m['categoriaId'] ?? '').toString().trim().isEmpty
            ? null
            : (m['categoriaId'] as String);
    final String? catNomeOrig =
        (m['categoriaNome'] ?? '').toString().trim().isEmpty
            ? null
            : (m['categoriaNome'] as String);
    final String? catTipoOrig =
        (m['categoriaTipo'] ?? '').toString().trim().isEmpty
            ? null
            : (m['categoriaTipo'] as String);

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
                          fornecedorNome.isEmpty ? '—' : fornecedorNome,
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
                      const SizedBox(height: 8),
                      if (catNomeOrig != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Categoria: $catNomeOrig',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
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
      await _fs.collection('contas_pagar').add({
        'userId': uid,
        'companyId': _companyId, // escopo
        'createdByUid': uid,
        'origem': 'duplicado',
        'fromId': originalId,
        'fornecedorId': fornecedorId.isEmpty ? null : fornecedorId,
        'fornecedorNome': fornecedorNome.isNotEmpty ? fornecedorNome : null,
        'descricao': descricao.isNotEmpty ? descricao : null,
        'valor': novoValor,
        'vencimento': Timestamp.fromDate(
          DateTime(venc.year, venc.month, venc.day),
        ),
        'status': 'aberto',
        'valorPago': null,
        'dataPagamento': null,

        // Mantém campos de categoria se existirem no original
        if (catIdOrig != null) 'categoriaId': catIdOrig,
        if (catNomeOrig != null) 'categoriaNome': catNomeOrig,
        if (catTipoOrig != null) 'categoriaTipo': catTipoOrig,

        'observacao': _mkObsFornecedorValor(fornecedorNome, novoValor),
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

  // ================== NOVO (com seletor de categoria) ==================
  Future<void> _novoTitulo() async {
    if (!_requireAP()) return;
    final uid = _uid;
    final scope = _scopeUserId;
    if (uid == null || scope == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login.')));
      return;
    }

    FornecedorSelecionado? fornecedorSel;
    final descCtrl = TextEditingController();
    final valorCtrl = TextEditingController(text: '0,00');
    DateTime venc = DateTime.now();
    bool salvando = false;

    CategoriaSelecionada? categoriaSel;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSt) => AlertDialog(
                  title: const Text('Novo contas a pagar'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // -------- Fornecedor --------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Fornecedor',
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
                                  fornecedorSel?.nome ??
                                      'Selecione um fornecedor',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        fornecedorSel == null
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
                                        : () async {
                                          final sel = await showModalBottomSheet<
                                            FornecedorSelecionado
                                          >(
                                            context: ctx,
                                            isScrollControlled: true,
                                            useSafeArea: true,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(26),
                                                  ),
                                            ),
                                            builder:
                                                (_) =>
                                                    const SelecionarFornecedorSheet(),
                                          );
                                          if (sel != null)
                                            setSt(() => fornecedorSel = sel);
                                        },
                                icon: const Icon(
                                  Icons.store_mall_directory_outlined,
                                ),
                                label: Text(
                                  fornecedorSel == null
                                      ? 'Selecionar'
                                      : 'Trocar',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // -------- Categoria (novo seletor) --------
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
                                          final sel = await showModalBottomSheet<
                                            CategoriaSelecionada
                                          >(
                                            context: ctx,
                                            isScrollControlled: true,
                                            useSafeArea: true,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(26),
                                                  ),
                                            ),
                                            builder:
                                                (
                                                  _,
                                                ) => const SelecionarCategoriaPagamentoSheet(
                                                  filtroTipo:
                                                      'pagar', // IMPORTANT: contexto CP
                                                ),
                                          );
                                          if (sel != null)
                                            setSt(() => categoriaSel = sel);
                                        },
                                icon: const Icon(Icons.category),
                                label: Text(
                                  categoriaSel == null ? 'Escolher' : 'Trocar',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Descrição (opcional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

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
                                if (fornecedorSel == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Selecione um fornecedor.'),
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
                                  await _fs.collection('contas_pagar').add({
                                    'userId': uid,
                                    'companyId': _companyId, // escopo
                                    'createdByUid': uid,
                                    'origem': 'manual',

                                    'fornecedorId': fornecedorSel!.id,
                                    'fornecedorNome': fornecedorSel!.nome,
                                    'descricao':
                                        descCtrl.text.trim().isEmpty
                                            ? null
                                            : descCtrl.text.trim(),

                                    // >>> campos vindos do novo seletor de categoria
                                    'categoriaId': categoriaSel!.id,
                                    'categoriaNome': categoriaSel!.nome,
                                    'categoriaTipo':
                                        categoriaSel!.tipo, // pagar|ambos

                                    'valor': v,
                                    'vencimento': Timestamp.fromDate(
                                      DateTime(venc.year, venc.month, venc.day),
                                    ),

                                    'observacao': _mkObsFornecedorValor(
                                      fornecedorSel!.nome,
                                      v,
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

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fabSpace = MediaQuery.of(context).padding.bottom + 88.0;

    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: ContasPagarStyle.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contas a Pagar')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_scopeError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ContasPagarStyle.background,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Contas a Pagar',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: ContasPagarStyle.headerGradient,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Novo título',
            icon: const Icon(Icons.add_card_outlined),
            onPressed: _canAccountsPayable ? _novoTitulo : () => _requireAP(),
            color: _canAccountsPayable ? null : cs.onSurfaceVariant,
          ),
          IconButton(
            tooltip:
                _ordemAsc
                    ? 'Ordenar por vencimento (desc)'
                    : 'Ordenar por vencimento (asc)',
            icon: Icon(_ordemAsc ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: () => setState(() => _ordemAsc = !_ordemAsc),
          ),
          IconButton(
            tooltip: 'Atualizar contadores',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCounts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _canAccountsPayable ? _novoTitulo : () => _requireAP(),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
        backgroundColor:
            _canAccountsPayable ? ContasPagarStyle.primary : cs.surfaceVariant,
        foregroundColor:
            _canAccountsPayable ? Colors.white : cs.onSurfaceVariant,
      ),
      body: Column(
        children: [
          // filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in CPStatus.values)
                        ChoiceChip(
                          label: Text(_statusLabel[s]!),
                          selectedColor: ContasPagarStyle.primary.withOpacity(
                            0.16,
                          ),
                          side: const BorderSide(
                            color: ContasPagarStyle.border,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                          selected: _status == s,
                          onSelected: (_) => setState(() => _status = s),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _fornCtrl,
              decoration: InputDecoration(
                hintText: 'Filtrar por fornecedor...',
                prefixIcon: const Icon(Icons.store_mall_directory_outlined),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                suffixIcon:
                    _fornCtrl.text.isEmpty
                        ? null
                        : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _fornCtrl.clear();
                            setState(() => _fornFiltro = '');
                          },
                        ),
              ),
              onChanged:
                  (t) => setState(() => _fornFiltro = t.trim().toLowerCase()),
            ),
          ),

          // chips de contagem
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child:
                _loadingCounts
                    ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _CountChip(
                            color: _statusColor[CPStatus.aberto]!,
                            label: 'Abertos: ${_counts[CPStatus.aberto] ?? 0}',
                            selected: _status == CPStatus.aberto,
                            onTap: () {
                              setState(() => _status = CPStatus.aberto);
                              _listCtrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          _CountChip(
                            color: _statusColor[CPStatus.pago]!,
                            label: 'Pagos: ${_counts[CPStatus.pago] ?? 0}',
                            selected: _status == CPStatus.pago,
                            onTap: () {
                              setState(() => _status = CPStatus.pago);
                              _listCtrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          _CountChip(
                            color: _statusColor[CPStatus.cancelado]!,
                            label:
                                'Cancel.: ${_counts[CPStatus.cancelado] ?? 0}',
                            selected: _status == CPStatus.cancelado,
                            onTap: () {
                              setState(() => _status = CPStatus.cancelado);
                              _listCtrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
          ),

          const Divider(height: 1),

          // lista
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _queryBase().snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];

                // filtro por fornecedor (contains em memória)
                final filtered =
                    docs.where((d) {
                      if (_fornFiltro.isEmpty) return true;
                      final nome =
                          (d.data()['fornecedorNome'] ?? '')
                              .toString()
                              .toLowerCase();
                      return nome.contains(_fornFiltro);
                    }).toList();

                // ordenação local (por vencimento)
                filtered.sort((a, b) {
                  final va = (a.data()['vencimento'] as Timestamp?)?.toDate();
                  final vb = (b.data()['vencimento'] as Timestamp?)?.toDate();
                  final ca = va == null ? 0 : va.millisecondsSinceEpoch;
                  final cb = vb == null ? 0 : vb.millisecondsSinceEpoch;
                  return _ordemAsc ? ca.compareTo(cb) : cb.compareTo(ca);
                });

                if (filtered.isEmpty) {
                  return const _EmptyState(
                    title: 'Nada encontrado',
                    subtitle: 'Ajuste os filtros para ver seus pagamentos.',
                  );
                }

                // total exibe valorPago (ou valor se ainda aberto)
                final total = filtered.fold<double>(0.0, (acc, doc) {
                  final m = doc.data();
                  final valor = (m['valor'] is num) ? (m['valor'] + 0.0) : 0.0;
                  final valorPago =
                      (m['valorPago'] is num) ? (m['valorPago'] + 0.0) : null;
                  return acc + (valorPago ?? valor);
                });

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: ContasPagarStyle.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: ContasPagarStyle.primary.withOpacity(0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Exibindo ${filtered.length} ${filtered.length == 1 ? 'título' : 'títulos'}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            'Total: ${_fmtMoeda(total)}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.separated(
                        controller: _listCtrl,
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + fabSpace),
                        itemBuilder: (_, i) {
                          final d = filtered[i];
                          final m = d.data();

                          final statusStr =
                              (m['status'] ?? 'aberto').toString();
                          final cpStatus = () {
                            switch (statusStr) {
                              case 'pago':
                                return CPStatus.pago;
                              case 'cancelado':
                                return CPStatus.cancelado;
                              default:
                                return CPStatus.aberto;
                            }
                          }();

                          final venc =
                              (m['vencimento'] as Timestamp?)?.toDate();
                          final fornecedor =
                              (m['fornecedorNome'] ?? '').toString();
                          final valor =
                              (m['valor'] is num) ? (m['valor'] + 0.0) : 0.0;

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
                              cpStatus == CPStatus.aberto &&
                              venc != null &&
                              DateTime(
                                venc.year,
                                venc.month,
                                venc.day,
                              ).isBefore(
                                DateTime(hoje.year, hoje.month, hoje.day),
                              );
                          final descricao = (m['descricao'] ?? '').toString();

                          return Card(
                            elevation: 0,
                            color: Colors.white,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                color: ContasPagarStyle.border,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: _Dot(
                                color:
                                    _statusColor[cpStatus] ??
                                    (Theme.of(context).colorScheme.primary),
                              ),
                              title: Text(
                                fornecedor.isEmpty ? '—' : fornecedor,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (descricao.isNotEmpty) ...[
                                    Text(
                                      descricao,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    [
                                      if (venc != null)
                                        'Venc.: ${_fmtData(venc)}',
                                      if (isVencido) 'VENCIDO',
                                      if (cpStatus == CPStatus.pago &&
                                          dataPg != null)
                                        ' • Pago em: ${_fmtData(dataPg)}',
                                    ].where((s) => s.isNotEmpty).join(' • '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (categoriaNome.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        color: ContasPagarStyle.primary
                                            .withOpacity(0.08),
                                      ),
                                      child: Text(
                                        categoriaNome,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _fmtMoeda(valorMostrar),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _statusLabel[cpStatus]!,
                                    style: TextStyle(
                                      color:
                                          _statusColor[cpStatus] ?? cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                _showAcoesTitulo(
                                  id: d.id,
                                  m: m,
                                  cpStatus: cpStatus,
                                  valor: valor,
                                  venc: venc,
                                  valorPago: valorPago,
                                  dataPg: dataPg,
                                  fornecedor: fornecedor,
                                );
                              },
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: filtered.length,
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

  // ================== Bottom sheet de AÇÕES ==================
  Future<void> _showAcoesTitulo({
    required String id,
    required Map<String, dynamic> m,
    required CPStatus cpStatus,
    required double valor,
    required DateTime? venc,
    required double? valorPago,
    required DateTime? dataPg,
    required String fornecedor,
  }) async {
    final itens = <Widget>[];

    itens.add(
      ListTile(
        leading: const Icon(Icons.copy_outlined),
        title: const Text('Duplicar'),
        enabled: _canAccountsPayable,
        onTap: () async {
          Navigator.pop(context);
          await _duplicarTitulo(originalId: id, m: m);
        },
      ),
    );

    if (cpStatus == CPStatus.aberto) {
      itens.addAll([
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Editar valor/vencimento'),
          enabled: _canAccountsPayable && _canAP_EditOpen,
          onTap: () async {
            Navigator.pop(context);
            await _editarAberto(
              id: id,
              valorAtual: valor,
              vencAtual: venc,
              fornecedorNome: fornecedor,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: const Text('Marcar como pago'),
          enabled: _canAccountsPayable && _canAP_MarkPaid,
          onTap: () async {
            Navigator.pop(context);
            await _marcarPago(id);
          },
        ),
      ]);
    }

    if (cpStatus == CPStatus.pago) {
      itens.addAll([
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Editar pagamento'),
          enabled: _canAccountsPayable && _canAP_MarkPaid,
          onTap: () async {
            Navigator.pop(context);
            await _editarPago(
              id: id,
              valorPagoAtual: valorPago,
              dataPagamentoAtual: dataPg,
              fornecedorNome: fornecedor,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Reabrir (em aberto)'),
          enabled: _canAccountsPayable && _canAP_EditOpen,
          onTap: () async {
            Navigator.pop(context);
            await _reabrir(id);
          },
        ),
      ]);
    }

    if (cpStatus == CPStatus.cancelado) {
      itens.add(
        ListTile(
          leading: const Icon(Icons.undo),
          title: const Text('Reabrir (em aberto)'),
          enabled: _canAccountsPayable && _canAP_EditOpen,
          onTap: () async {
            Navigator.pop(context);
            await _reabrir(id);
          },
        ),
      );
    }

    if (cpStatus != CPStatus.cancelado) {
      itens.add(
        ListTile(
          leading: const Icon(Icons.cancel_outlined, color: Colors.red),
          title: const Text('Cancelar'),
          enabled: _canAccountsPayable && _canAP_Cancel,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    fornecedor.isEmpty ? 'Título' : fornecedor,
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
            Icon(
              Icons.payments_outlined,
              size: 72,
              color: ContasPagarStyle.primary.withOpacity(0.45),
            ),
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
