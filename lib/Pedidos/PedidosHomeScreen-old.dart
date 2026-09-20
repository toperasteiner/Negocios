// lib/Pedidos/PedidosHomeScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Pedidos/CadastroPedidoScreen.dart';
import 'comprovante_pdf.dart';

enum PedidoStatus {
  pendente,
  aguardando_aprovacao,
  aguardando_aprovacao_web,
  aprovado,
  em_andamento,
  aguardando_pagamento,
  enviado,
  concluido,
  garantia,
  cancelado,
}

const _statusLabel = {
  PedidoStatus.pendente: 'Pendente',
  PedidoStatus.aguardando_aprovacao: 'Aguardando aprovação',
  PedidoStatus.aprovado: 'Aprovado',
  PedidoStatus.em_andamento: 'Em andamento',
  PedidoStatus.aguardando_pagamento: 'Aguardando pagamento',
  PedidoStatus.enviado: 'Enviado',
  PedidoStatus.concluido: 'Concluído',
  PedidoStatus.garantia: 'Garantia',
  PedidoStatus.cancelado: 'Cancelado',
  PedidoStatus.aguardando_aprovacao_web: 'Aguardando Aprovação - WEB',
};

const _statusDot = {
  PedidoStatus.aguardando_aprovacao_web: Colors.orange,
  PedidoStatus.pendente: Colors.orange,
  PedidoStatus.aguardando_aprovacao: Colors.orange,
  PedidoStatus.aprovado: Colors.blue,
  PedidoStatus.em_andamento: Colors.blue,
  PedidoStatus.aguardando_pagamento: Colors.blue,
  PedidoStatus.enviado: Colors.blue,
  PedidoStatus.concluido: Colors.green,
  PedidoStatus.garantia: Colors.green,
  PedidoStatus.cancelado: Colors.red,
};

class PedidosHomeScreen extends StatefulWidget {
  const PedidosHomeScreen({super.key});

  @override
  State<PedidosHomeScreen> createState() => _PedidosHomeScreenState();
}

class _PedidosHomeScreenState extends State<PedidosHomeScreen>
    with SingleTickerProviderStateMixin {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== Escopo multiempresa =====
  String? _companyId; // users.companyId (opcional)
  String? _scopeUserId; // companyId ?? uid (legado)
  bool _loadingScope = true;
  String? _scopeError;

  bool get _useCompany => _companyId != null && _companyId!.trim().isNotEmpty;
  String? get _uid => _auth.currentUser?.uid;

  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _search = '';

  static const _pageSize = 20;
  DocumentSnapshot? _lastDoc;
  bool _loadingMore = false;
  bool _hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  final Map<PedidoStatus, int> _counts = {
    for (final s in PedidoStatus.values) s: 0,
  };
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _initScope();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Faça login para continuar.';
      });
      return;
    }
    try {
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();
      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isEmpty ? u.uid : companyId;
        _loadingScope = false;
      });
      await _loadFirstPage();
      await _refreshCounts();
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao definir escopo: $e';
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return (byUid.data() ?? {}) as Map<String, dynamic>;
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

  Query<Map<String, dynamic>> _baseQuery() {
    final col = _fs.collection('pedidos');
    if (_useCompany) {
      return col.where('companyId', isEqualTo: _companyId);
    }
    return col.where('userId', isEqualTo: _uid);
  }

  Future<void> _cancelarTitulosDoPedido(String pedidoId) async {
    Query<Map<String, dynamic>> q = _fs
        .collection('contas_receber')
        .where('origem', isEqualTo: 'pedido')
        .where('pedidoId', isEqualTo: pedidoId)
        .where('status', isEqualTo: 'aberto');

    q =
        _useCompany
            ? q.where('companyId', isEqualTo: _companyId)
            : q.where('userId', isEqualTo: _uid);

    final snap = await q.get();
    if (snap.docs.isEmpty) return;

    final batch = _fs.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {
        'status': 'cancelado',
        'updatedAt': FieldValue.serverTimestamp(),
        'canceladoPor': 'pedido',
        'canceladoEm': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _reativarTitulosDoPedido(String pedidoId) async {
    Query<Map<String, dynamic>> q = _fs
        .collection('contas_receber')
        .where('origem', isEqualTo: 'pedido')
        .where('pedidoId', isEqualTo: pedidoId)
        .where('status', isEqualTo: 'cancelado');

    q =
        _useCompany
            ? q.where('companyId', isEqualTo: _companyId)
            : q.where('userId', isEqualTo: _uid);

    final snap = await q.get();
    if (snap.docs.isEmpty) return;

    final batch = _fs.batch();
    for (final d in snap.docs) {
      final m = d.data();
      final valor = (m['valor'] as num?)?.toDouble() ?? 0.0;
      final valorPago = (m['valorPago'] as num?)?.toDouble() ?? 0.0;
      final temSaldo = valorPago < valor;
      if (temSaldo) {
        batch.update(d.reference, {
          'status': 'aberto',
          'updatedAt': FieldValue.serverTimestamp(),
          'reativadoEm': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Future<void> _emitirComprovante(String pedidoId) async {
    await ComprovanteScreen.open(context, pedidoId);
  }

  Future<void> _loadFirstPage() async {
    if (!_useCompany && _uid == null) return;
    setState(() {
      _docs = [];
      _lastDoc = null;
      _hasMore = true;
      _loadingMore = true;
    });

    var q = _baseQuery()
    // .orderBy('data', descending: true)
    // .orderBy('numero', descending: true)
    .limit(_pageSize);

    final snap = await q.get();
    if (!mounted) return;
    setState(() {
      _docs = snap.docs;
      _lastDoc = snap.docs.isEmpty ? null : snap.docs.last;
      _hasMore = snap.docs.length == _pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || (!_useCompany && _uid == null)) return;
    setState(() => _loadingMore = true);
    var q = _baseQuery().limit(_pageSize);
    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
    final snap = await q.get();
    if (!mounted) return;
    setState(() {
      _docs.addAll(snap.docs);
      if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
      _hasMore = snap.docs.length == _pageSize;
      _loadingMore = false;
    });
  }

  /// Conta quantos títulos em aberto existem para este pedido
  Future<int> _contarTitulosAbertos(String pedidoId) async {
    Query<Map<String, dynamic>> q = _fs
        .collection('contas_receber')
        .where('origem', isEqualTo: 'pedido')
        .where('pedidoId', isEqualTo: pedidoId)
        .where('status', isEqualTo: 'aberto');

    q =
        _useCompany
            ? q.where('companyId', isEqualTo: _companyId)
            : q.where('userId', isEqualTo: _uid);

    final snap = await q.count().get();
    return snap.count ?? 0;
  }

  /// Mostra o diálogo perguntando se deve cancelar os títulos
  Future<bool> _confirmarCancelamentoTitulos(int qtd) async {
    final r = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Cancelar títulos?'),
            content: Text(
              'Este pedido possui $qtd título(s) em Contas a Receber com status "aberto". '
              'Você deseja cancelá-los agora?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Manter títulos'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancelar títulos'),
              ),
            ],
          ),
    );
    return r ?? false;
  }

  Future<void> _refreshCounts() async {
    if (!_useCompany && _uid == null) return;
    setState(() => _loadingCounts = true);

    final futures = <Future<void>>[];
    for (final s in PedidoStatus.values) {
      futures.add(() async {
        Query<Map<String, dynamic>> q = _fs.collection('pedidos');
        q =
            _useCompany
                ? q.where('companyId', isEqualTo: _companyId)
                : q.where('userId', isEqualTo: _uid);

        final aggr = await q.where('status', isEqualTo: s.name).count().get();
        _counts[s] = aggr.count ?? 0;
      }());
    }

    await Future.wait(futures);
    if (mounted) setState(() => _loadingCounts = false);
  }

  Future<bool> _confirmarCriarContasReceber() async {
    final r = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Criar contas a receber?'),
            content: const Text(
              'Este pedido veio do Catálogo Online. Deseja criar o título em Contas a Receber agora?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não criar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Criar título'),
              ),
            ],
          ),
    );

    return r ?? false;
  }

  Future<void> _criarContaReceberDoPedido(String pedidoId) async {
    final pedidoSnap = await _fs.collection('pedidos').doc(pedidoId).get();
    if (!pedidoSnap.exists) return;

    final pedido = pedidoSnap.data() ?? {};

    final jaExiste =
        await _fs
            .collection('contas_receber')
            .where('origem', isEqualTo: 'pedido')
            .where('pedidoId', isEqualTo: pedidoId)
            .limit(1)
            .get();

    if (jaExiste.docs.isNotEmpty) return;

    final numero = (pedido['numero'] as num?)?.toInt() ?? 0;
    final ano = (pedido['ano'] as num?)?.toInt() ?? DateTime.now().year;
    final total = (pedido['total'] as num?)?.toDouble() ?? 0.0;

    await _fs.collection('contas_receber').add({
      'companyId': pedido['companyId'],
      'userId': pedido['userId'],
      'createdByUid': pedido['createdByUid'],

      'clienteNome': pedido['clienteNome'] ?? pedido['cliente'] ?? '',
      'origem': 'pedido',

      'pedidoId': pedidoId,
      'pedidoNumero': numero,
      'pedidoAno': ano,
      'pedidoCodigo': '$numero-$ano',

      'categoriaKey': 'vendas_produtos_servicos',
      'categoriaNome': 'Vendas de produtos/serviços',

      'valor': total,
      'vencimento': pedido['data'] ?? Timestamp.now(),

      'parcelaNumero': 1,
      'parcelasTotal': 1,
      'status': 'aberto',

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateStatus(String docId, PedidoStatus novo) async {
    bool foiParaCancelado = false;
    bool saiuDeCancelado = false;

    bool veioDoCatalogoWeb = false;
    bool deveCriarContasReceber = false;

    final pedidoAntesSnap = await _fs.collection('pedidos').doc(docId).get();
    final pedidoAntes = pedidoAntesSnap.data();

    if (pedidoAntes != null) {
      final statusAtual = (pedidoAntes['status'] ?? '').toString();

      veioDoCatalogoWeb =
          statusAtual == 'aguardando_aprovacao_web' &&
          novo != PedidoStatus.cancelado;

      if (veioDoCatalogoWeb) {
        deveCriarContasReceber = await _confirmarCriarContasReceber();
      }
    }

    // 👉 Se o novo status for "cancelado", veja se há títulos e pergunte
    bool deveCancelarTitulos = false;
    if (novo == PedidoStatus.cancelado) {
      final qtd = await _contarTitulosAbertos(docId);
      if (qtd > 0) {
        deveCancelarTitulos = await _confirmarCancelamentoTitulos(qtd);
      }
    }

    await _fs.runTransaction((tx) async {
      final pedidoRef = _fs.collection('pedidos').doc(docId);
      final pedidoSnap = await tx.get(pedidoRef);
      if (!pedidoSnap.exists) return;

      final data = pedidoSnap.data() as Map<String, dynamic>;
      final String prevStatusStr = (data['status'] ?? 'pendente').toString();
      final bool prevCancelado =
          prevStatusStr.toLowerCase() == PedidoStatus.cancelado.name;
      final bool newCancelado = novo == PedidoStatus.cancelado;

      bool estoqueReposto = data['estoqueReposto'] == true;

      Future<void> ajustarEstoque(num fator) async {
        final itens = (data['itensProdutos'] as List?) ?? const [];
        for (final raw in itens) {
          final m = Map<String, dynamic>.from(raw as Map);
          final String? refId = m['refId'] as String?;
          if (refId == null || refId.isEmpty) continue;

          final double qtd =
              (m['quantidade'] is num)
                  ? (m['quantidade'] as num).toDouble()
                  : double.tryParse('${m['quantidade']}') ?? 0.0;
          if (qtd <= 0) continue;

          final prodRef = _fs.collection('produtos').doc(refId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) continue;

          final pm = prodSnap.data() as Map<String, dynamic>;
          final bool controla = pm['controlaEstoque'] == true;
          if (!controla) continue;

          tx.update(prodRef, {'estoque': FieldValue.increment(qtd * fator)});
        }
      }

      final statusStr = novo.name;
      final bool prevWeb = prevStatusStr == 'aguardando_aprovacao_web';

      if (prevWeb && !newCancelado) {
        await ajustarEstoque(-1);

        tx.update(pedidoRef, {
          'status': statusStr,
          'statusLabel': _statusLabel[novo],
          'estoqueBaixado': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (!prevCancelado && newCancelado && !estoqueReposto) {
        await ajustarEstoque(1);
        tx.update(pedidoRef, {
          'status': statusStr,
          'estoqueReposto': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        foiParaCancelado = true;
      } else if (prevCancelado && !newCancelado && estoqueReposto) {
        await ajustarEstoque(-1);
        tx.update(pedidoRef, {
          'status': statusStr,
          'estoqueReposto': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        saiuDeCancelado = true;
      } else {
        tx.update(pedidoRef, {
          'status': statusStr,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    // 👉 Só cancela títulos se o usuário confirmou
    if (foiParaCancelado && deveCancelarTitulos) {
      await _cancelarTitulosDoPedido(docId);
    } else if (saiuDeCancelado) {
      await _reativarTitulosDoPedido(docId);
    }

    if (veioDoCatalogoWeb && deveCriarContasReceber) {
      await _criarContaReceberDoPedido(docId);
    }

    await _refreshCounts();
    await _loadFirstPage();
  }

  Future<void> _alterarPedido(String pedidoId) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CadastroPedidoScreen(pedidoId: pedidoId),
      ),
    );
    if (ok == true) {
      await _loadFirstPage();
      await _refreshCounts();
    }
  }

  Future<void> _duplicarPedido(String pedidoId) async {
    final srcRef = _fs.collection('pedidos').doc(pedidoId);
    final srcSnap = await srcRef.get();
    if (!srcSnap.exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido original não encontrado.')),
      );
      return;
    }
    final src = srcSnap.data() as Map<String, dynamic>;

    final Map<String, dynamic> initialData =
        Map<String, dynamic>.from(src)
          ..remove('numero')
          ..remove('ano')
          ..remove('status')
          ..remove('createdAt')
          ..remove('updatedAt')
          ..remove('userId')
          ..remove('companyId')
          ..remove('createdByUid');

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => CadastroPedidoScreen(
              initialData: initialData,
              isDuplicate: true,
            ),
      ),
    );

    if (ok == true) {
      await _loadFirstPage();
      await _refreshCounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_scopeError != null || (!_useCompany && _uid == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedidos')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_scopeError ?? 'Não foi possível determinar o escopo.'),
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Todos os pedidos'),
            Tab(text: 'Pedidos por status'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'novo pedido',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _newPedido,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // --------- Aba 1 ----------
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por cliente, referência ou número...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    _search = _searchCtrl.text.trim();
                    _loadFirstPage();
                  },
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _loadFirstPage();
                    await _refreshCounts();
                  },
                  child:
                      _docs.isEmpty && !_loadingMore
                          ? _EmptyState(
                            title: 'Comece salvando um pedido',
                            subtitle: 'Organize seu negócio aqui!',
                            onNew: _newPedido,
                          )
                          : NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n.metrics.pixels >=
                                      n.metrics.maxScrollExtent - 120 &&
                                  !_loadingMore) {
                                _loadMore();
                              }
                              return false;
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: _docs.length + (_hasMore ? 1 : 0),
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                if (i >= _docs.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Center(
                                      child:
                                          _loadingMore
                                              ? const CircularProgressIndicator()
                                              : TextButton(
                                                onPressed: _loadMore,
                                                child: const Text(
                                                  'carregar mais',
                                                ),
                                              ),
                                    ),
                                  );
                                }

                                final doc = _docs[i];
                                final m = doc.data();

                                if (_search.isNotEmpty) {
                                  final t =
                                      ('${m['clienteNome'] ?? ''} ${m['referencia'] ?? ''} ${m['numero'] ?? ''}')
                                          .toLowerCase();
                                  if (!t.contains(_search.toLowerCase())) {
                                    return const SizedBox.shrink();
                                  }
                                }

                                return _PedidoTile(
                                  id: doc.id,
                                  numero: (m['numero'] ?? 0) as int,
                                  ano: (m['ano'] ?? DateTime.now().year) as int,
                                  data: (m['data'] as Timestamp?)?.toDate(),
                                  cliente: (m['clienteNome'] ?? '').toString(),
                                  referencia:
                                      (m['referencia'] ?? '').toString(),
                                  total:
                                      (m['total'] is num)
                                          ? (m['total'] + 0.0)
                                          : 0,
                                  statusStr:
                                      (m['status'] ?? 'pendente').toString(),
                                  onAlterarPedido: () => _alterarPedido(doc.id),
                                  onChangeStatus: (novo) async {
                                    await _updateStatus(doc.id, novo);
                                  },
                                  onEmitirComprovante:
                                      () => _emitirComprovante(doc.id),
                                  onDuplicarPedido:
                                      () => _duplicarPedido(doc.id),
                                );
                              },
                            ),
                          ),
                ),
              ),
            ],
          ),

          // --------- Aba 2 ----------
          _StatusList(
            counts: _counts,
            loading: _loadingCounts,
            onOpen: (status) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => _PedidosPorStatusScreen(
                        status: status,
                        companyId: _companyId,
                        uidFallback: _uid,
                        onAlterarPedido: _alterarPedido,
                        onDuplicarPedido: _duplicarPedido,
                        onEmitirComprovante: _emitirComprovante,
                        onChangeStatus: _updateStatus,
                      ),
                ),
              ).then((_) {
                _loadFirstPage();
                _refreshCounts();
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('novo pedido'),
            onPressed: _newPedido,
          ),
        ),
      ),
    );
  }

  Future<void> _newPedido() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CadastroPedidoScreen()),
    );
    if (ok == true) {
      await _loadFirstPage();
      await _refreshCounts();
    }
  }
}

// ------------------ Widgets auxiliares ------------------

class _PedidoTile extends StatelessWidget {
  final String id;
  final int numero;
  final int ano;
  final DateTime? data;
  final String cliente;
  final String referencia;
  final double total;
  final String statusStr;

  final VoidCallback onAlterarPedido;
  final Future<void> Function(PedidoStatus) onChangeStatus;
  final VoidCallback onEmitirComprovante;
  final VoidCallback onDuplicarPedido;

  const _PedidoTile({
    required this.id,
    required this.numero,
    required this.ano,
    required this.data,
    required this.cliente,
    required this.referencia,
    required this.total,
    required this.statusStr,
    required this.onAlterarPedido,
    required this.onChangeStatus,
    required this.onEmitirComprovante,
    required this.onDuplicarPedido,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = PedidoStatus.values.firstWhere(
      (s) => s.name == statusStr.toLowerCase(),
      orElse: () => PedidoStatus.pendente,
    );

    final dataStr =
        data == null
            ? '--/--/----'
            : '${data!.day.toString().padLeft(2, '0')}/${data!.month.toString().padLeft(2, '0')}/${data!.year}';

    return ListTile(
      onTap: () => _abrirMenu(context, status),
      contentPadding: EdgeInsets.zero,
      leading: _Dot(color: _statusDot[status] ?? cs.primary),
      title: Text(
        'Pedido ${numero.toString().padLeft(3, '0')}-$ano • $dataStr',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${cliente.isEmpty ? '—' : cliente}'
        '${referencia.isEmpty ? '' : ' • Ref.: $referencia'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: InkWell(
        onTap: () => _abrirMenu(context, status),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _fmtMoeda(total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(_statusLabel[status]!, style: TextStyle(color: cs.primary)),
          ],
        ),
      ),
    );
  }

  void _abrirMenu(BuildContext context, PedidoStatus statusAtual) async {
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz_outlined),
                title: const Text('Alterar status do pedido'),
                onTap: () async {
                  final novo = await _escolherStatus(ctx, statusAtual);
                  Navigator.pop(ctx, 'status:${novo?.name}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Emitir comprovante'),
                onTap: () => Navigator.pop(ctx, 'comprovante'),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: const Text('Duplicar pedido'),
                onTap: () => Navigator.pop(ctx, 'duplicar'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Alterar pedido'),
                onTap: () => Navigator.pop(ctx, 'alterar'),
              ),
            ],
          ),
        );
      },
    );

    if (op == null) return;

    if (op.startsWith('status:')) {
      final name = op.split(':').last;
      final novo = PedidoStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => statusAtual,
      );
      if (novo != statusAtual) {
        // 👇 aguarde fechar a sheet completamente e então chame a ação
        await onChangeStatus(novo);
      }
      return;
    }

    switch (op) {
      case 'comprovante':
        onEmitirComprovante();
        break;
      case 'duplicar':
        onDuplicarPedido();
        break;
      case 'alterar':
        onAlterarPedido();
        break;
    }
  }

  static Future<PedidoStatus?> _escolherStatus(
    BuildContext context,
    PedidoStatus atual,
  ) async {
    return showDialog<PedidoStatus>(
      context: context,
      builder: (ctx) {
        PedidoStatus selecionado = atual;

        return StatefulBuilder(
          builder: (ctx, setState) {
            final cs = Theme.of(ctx).colorScheme;
            final statusDisponiveis =
                PedidoStatus.values
                    .where((s) => s != PedidoStatus.aguardando_aprovacao_web)
                    .toList();

            return AlertDialog(
              title: const Text('Alterar status'),
              content: SizedBox(
                width: double.maxFinite,

                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: statusDisponiveis.length,
                  itemBuilder: (ctx, i) {
                    final s = statusDisponiveis[i];
                    final label = _statusLabel[s]!;
                    final dot = _statusDot[s] ?? cs.primary;

                    return InkWell(
                      // 👉 agora tocar na linha marca o radio também
                      onTap: () => setState(() => selecionado = s),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Radio<PedidoStatus>(
                              value: s,
                              groupValue: selecionado,
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => selecionado = v);
                                }
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: dot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selecionado),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
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
}

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

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onNew;
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 72, color: cs.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: const Text('novo pedido'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusList extends StatelessWidget {
  final Map<PedidoStatus, int> counts;
  final bool loading;
  final ValueChanged<PedidoStatus> onOpen;
  const _StatusList({
    required this.counts,
    required this.loading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: PedidoStatus.values.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = PedidoStatus.values[i];
        return ListTile(
          onTap: () => onOpen(s),
          leading: _Dot(color: _statusDot[s] ?? cs.primary),
          title: Text(_statusLabel[s]!),
          trailing:
              loading
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text('${counts[s] ?? 0}'),
        );
      },
    );
  }
}

class _PedidosPorStatusScreen extends StatelessWidget {
  final PedidoStatus status;
  final String? companyId;
  final String? uidFallback;

  final Future<void> Function(String pedidoId) onAlterarPedido;
  final Future<void> Function(String pedidoId) onDuplicarPedido;
  final Future<void> Function(String pedidoId) onEmitirComprovante;
  final Future<void> Function(String pedidoId, PedidoStatus novo)
  onChangeStatus;

  const _PedidosPorStatusScreen({
    required this.status,
    required this.companyId,
    required this.uidFallback,
    required this.onAlterarPedido,
    required this.onDuplicarPedido,
    required this.onEmitirComprovante,
    required this.onChangeStatus,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    Query<Map<String, dynamic>> q = fs.collection('pedidos');
    if (companyId != null && companyId!.isNotEmpty) {
      q = q.where('companyId', isEqualTo: companyId);
    } else {
      q = q.where('userId', isEqualTo: uidFallback);
    }

    q = q.where('status', isEqualTo: status.name);

    return Scaffold(
      appBar: AppBar(title: Text(_statusLabel[status]!)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const _EmptyState(
              title: 'Nada aqui ainda',
              subtitle: 'Crie um pedido para este status.',
              onNew: _noop,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final d = docs[i];
              final m = d.data();
              return _PedidoTile(
                id: d.id,
                numero: (m['numero'] ?? 0) as int,
                ano: (m['ano'] ?? DateTime.now().year) as int,
                data: (m['data'] as Timestamp?)?.toDate(),
                cliente: (m['clienteNome'] ?? '').toString(),
                referencia: (m['referencia'] ?? '').toString(),
                total: (m['total'] is num) ? (m['total'] + 0.0) : 0,
                statusStr: (m['status'] ?? 'pendente').toString(),
                onAlterarPedido: () => onAlterarPedido(d.id),
                onChangeStatus: (novo) async => onChangeStatus(d.id, novo),
                onEmitirComprovante: () => onEmitirComprovante(d.id),
                onDuplicarPedido: () => onDuplicarPedido(d.id),
              );
            },
          );
        },
      ),
    );
  }

  static void _noop() {}
}
