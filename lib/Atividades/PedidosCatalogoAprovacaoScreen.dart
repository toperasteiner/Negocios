import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PedidosCatalogoAprovacaoScreen extends StatefulWidget {
  const PedidosCatalogoAprovacaoScreen({super.key});

  @override
  State<PedidosCatalogoAprovacaoScreen> createState() =>
      _PedidosCatalogoAprovacaoScreenState();
}

class _PedidosCatalogoAprovacaoScreenState
    extends State<PedidosCatalogoAprovacaoScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  String? _companyId;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarEmpresa();
  }

  Future<void> _carregarEmpresa() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _erro = 'Usuário não autenticado.';
          _loading = false;
        });
        return;
      }

      final userDoc = await _fs.collection('users').doc(user.uid).get();
      final data = userDoc.data();

      final companyId = (data?['companyId'] ?? user.uid).toString().trim();

      setState(() {
        _companyId = companyId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar empresa: $e';
        _loading = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamPedidos() {
    return _fs
        .collection('pedidos')
        .where('companyId', isEqualTo: _companyId)
        .where('origem', isEqualTo: 'catalogo_publico')
        .where('status', isEqualTo: 'aguardando_aprovacao_web')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  String _produtoIdDoItem(Map<String, dynamic> item) {
    return (item['produtoId'] ??
            item['idProduto'] ??
            item['refId'] ??
            item['id'] ??
            '')
        .toString()
        .trim();
  }

  double _quantidadeDoItem(Map<String, dynamic> item) {
    return _toDouble(item['quantidade'] ?? item['qtd'] ?? 0);
  }

  Future<void> _aprovarPedido(String pedidoId) async {
    final pedidoRef = _fs.collection('pedidos').doc(pedidoId);
    final pedidoSnap = await pedidoRef.get();

    if (!pedidoSnap.exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pedido não encontrado.')));
      return;
    }

    final pedido = pedidoSnap.data() ?? <String, dynamic>{};

    final total = _totalPedido(pedido);
    final clienteNome =
        (pedido['clienteNome'] ??
                pedido['cliente'] ??
                pedido['nomeCliente'] ??
                'Cliente não informado')
            .toString();

    final batch = _fs.batch();

    // 1. Aprova o pedido
    batch.update(pedidoRef, {
      'status': 'aprovado',
      'statusCatalogo': 'aprovado',
      'aprovadoEm': FieldValue.serverTimestamp(),
      'aprovadoPorUid': _auth.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Gera conta a receber
    final agora = DateTime.now();
    final ano = (pedido['ano'] as num?)?.toInt() ?? agora.year;

    final pedidoNumero =
        (pedido['numeroPedido'] ??
            pedido['numero'] ??
            pedido['pedidoNumero'] ??
            0);

    final pedidoNumeroInt =
        pedidoNumero is num
            ? pedidoNumero.toInt()
            : int.tryParse('$pedidoNumero') ?? 0;

    final pedidoCodigo =
        (pedido['pedidoCodigo'] ??
                pedido['codigo'] ??
                '${pedidoNumeroInt.toString().padLeft(3, '0')}-$ano')
            .toString();

    final contaReceberRef = _fs
        .collection('contas_receber')
        .doc('pedido_${pedidoId}_1');

    batch.set(contaReceberRef, {
      'categoriaKey': 'vendas_produtos_servicos',
      'categoriaNome': 'Vendas de produtos/serviços',
      'clienteNome': clienteNome,
      'companyId': pedido['companyId'] ?? _companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': _auth.currentUser?.uid,
      'origem': 'pedido',
      'parcelaNumero': 1,
      'parcelasTotal': 1,
      'pedidoAno': ano,
      'pedidoCodigo': pedidoCodigo,
      'pedidoId': pedidoId,
      'pedidoNumero': pedidoNumeroInt,
      'status': 'aberto',
      'updatedAt': FieldValue.serverTimestamp(),
      'userId': pedido['userId'] ?? _auth.currentUser?.uid,
      'valor': total,
      'vencimento': Timestamp.fromDate(
        DateTime(agora.year, agora.month, agora.day),
      ),
    });

    // 3. Reserva estoque dos produtos
    final itensProdutos = pedido['itensProdutos'];

    if (itensProdutos is List) {
      for (final raw in itensProdutos) {
        if (raw is! Map) continue;

        final item = Map<String, dynamic>.from(raw);
        final produtoId = _produtoIdDoItem(item);
        final quantidade = _quantidadeDoItem(item);

        if (produtoId.isEmpty || quantidade <= 0) continue;

        final produtoRef = _fs.collection('produtos').doc(produtoId);

        batch.update(produtoRef, {
          'estoque': FieldValue.increment(-quantidade),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pedido aprovado, conta a receber gerada e estoque reservado.',
        ),
      ),
    );
  }

  Future<void> _rejeitarPedido(String pedidoId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.red, size: 22),
                SizedBox(width: 10),
                Text(
                  'Eliminar Pedido?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ],
            ),
            content: const Text(
              'Este pedido será eliminado definitivamente da lista de pedidos do catálogo.\n\nDeseja continuar?',
              style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar',
                    style: TextStyle(color: Color(0xFF64748B))),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text('Sim, eliminar'),
              ),
            ],
          ),
    );

    if (confirmar != true) return;

    await _fs.collection('pedidos').doc(pedidoId).delete();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Pedido eliminado com sucesso.')));
  }

  String _fmtMoeda(num valor) {
    final s = valor.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  num _totalPedido(Map<String, dynamic> data) {
    final total = data['total'] ?? data['valorTotal'] ?? data['subtotal'] ?? 0;
    if (total is num) return total;
    return num.tryParse(total.toString()) ?? 0;
  }

  String _numeroPedido(Map<String, dynamic> data, String docId) {
    return (data['numeroPedido'] ??
            data['numero'] ??
            data['pedidoNumero'] ??
            data['codigo'] ??
            docId)
        .toString();
  }

  String _clientePedido(Map<String, dynamic> data) {
    return (data['clienteNome'] ??
            data['cliente'] ??
            data['nomeCliente'] ??
            'Cliente não informado')
        .toString();
  }

  String _telefonePedido(Map<String, dynamic> data) {
    return (data['clienteTelefone'] ??
            data['telefone'] ??
            data['celular'] ??
            '')
        .toString()
        .trim();
  }

  int _qtdItensPedido(Map<String, dynamic> data) {
    final itensProdutos = data['itensProdutos'];
    final itensServicos = data['itensServicos'];

    final qtdProdutos = itensProdutos is List ? itensProdutos.length : 0;
    final qtdServicos = itensServicos is List ? itensServicos.length : 0;

    return qtdProdutos + qtdServicos;
  }

  Widget _buildHeader(BuildContext context, int totalCount) {
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
          child: Row(
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
                      'Pedidos do Catálogo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Aprovação e reserva de pedidos web',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pending_actions,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '$totalCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
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

  Widget _infoItem({required IconData icon, required String text, Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor ?? const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pedidoCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final numeroPedido = _numeroPedido(data, doc.id);
    final cliente = _clientePedido(data);
    final telefone = _telefonePedido(data);
    final qtdItens = _qtdItensPedido(data);
    final total = _totalPedido(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topo do card: número do pedido + badge com valor total
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B0CA3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    color: Color(0xFF3B0CA3),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido Nº $numeroPedido',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Catálogo Público • Aguardando',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _fmtMoeda(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Painel com detalhes do cliente e itens
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEDF2F7)),
              ),
              child: Column(
                children: [
                  _infoItem(
                    icon: Icons.person_outline,
                    text: cliente,
                    iconColor: const Color(0xFF3B0CA3),
                  ),
                  const SizedBox(height: 8),
                  _infoItem(
                    icon: Icons.phone_outlined,
                    text: telefone.isNotEmpty
                        ? telefone
                        : 'Telefone não informado',
                  ),
                  const SizedBox(height: 8),
                  _infoItem(
                    icon: Icons.format_list_bulleted_rounded,
                    text: '$qtdItens item(ns) no pedido',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Botões de ação Rejeitar / Aprovar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejeitarPedido(doc.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text(
                      'Rejeitar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _aprovarPedido(doc.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text(
                      'Aprovar',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
                Icons.task_alt_rounded,
                size: 54,
                color: Color(0xFF3B0CA3),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tudo em dia!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nenhum pedido do catálogo público aguardando aprovação no momento.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B0CA3)),
          ),
        ),
      );
    }

    if (_erro != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _erro!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
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
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamPedidos(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            final totalCount = docs.length;

            return Column(
              children: [
                _buildHeader(context, totalCount),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Color(0xFF3B0CA3)),
                          ),
                        );
                      }

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
                                  'Erro ao carregar pedidos',
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

                      if (docs.isEmpty) {
                        return _buildEmptyState();
                      }

                      return RefreshIndicator(
                        color: const Color(0xFF3B0CA3),
                        onRefresh: () async => setState(() {}),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            return _pedidoCard(context, docs[index]);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
