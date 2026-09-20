import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ComprasAprovacaoScreen extends StatefulWidget {
  const ComprasAprovacaoScreen({super.key});

  @override
  State<ComprasAprovacaoScreen> createState() => _ComprasAprovacaoScreenState();
}

class _ItemProdutoCompra {
  final String produtoId;
  final String nome;
  final double quantidade;
  final double valorUnitario;

  const _ItemProdutoCompra({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.valorUnitario,
  });
}

class _ComprasAprovacaoScreenState extends State<ComprasAprovacaoScreen> {
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
      final data = userDoc.data() ?? {};

      final companyId = (data['companyId'] ?? user.uid).toString().trim();

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

  Stream<QuerySnapshot<Map<String, dynamic>>> _comprasPendentesStream() {
    return _fs
        .collection('compras')
        .where('companyId', isEqualTo: _companyId)
        .where('status', whereIn: ['aberta', 'entrega_parcial'])
        .snapshots();
  }

  Future<void> _marcarComoEntregue(String compraId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('Marcar como entregue?'),
              ],
            ),
            content: const Text(
              'Ao confirmar, a compra será marcada como entregue, '
              'o estoque dos produtos será atualizado e o preço médio será recalculado.',
              style: TextStyle(color: Color(0xFF475569)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Confirmar Entrega'),
              ),
            ],
          ),
    );

    if (confirmar != true) return;

    try {
      await _atualizarStatusCompraComEstoque(
        compraId: compraId,
        novoStatus: 'entregue',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Compra marcada como entregue, estoque atualizado e preço médio recalculado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao marcar compra como entregue: $e')),
      );
    }
  }

  Future<void> _atualizarStatusCompraComEstoque({
    required String compraId,
    required String novoStatus,
  }) async {
    final compraRef = _fs.collection('compras').doc(compraId);

    await _fs.runTransaction((transaction) async {
      final compraSnap = await transaction.get(compraRef);

      if (!compraSnap.exists) {
        throw Exception('Compra não encontrada.');
      }

      final compraData = compraSnap.data() ?? {};

      final statusAtual = _normalizarStatus(
        (compraData['status'] ?? 'aberta').toString(),
      );

      final statusNovo = _normalizarStatus(novoStatus);

      if (statusAtual == statusNovo) return;

      final estavaEntregue = statusAtual == 'entregue';
      final vaiSerEntregue = statusNovo == 'entregue';

      if (!estavaEntregue && vaiSerEntregue) {
        await _ajustarEstoqueProdutosDaCompra(
          transaction: transaction,
          compraData: compraData,
          fator: 1,
        );
      }

      if (estavaEntregue && !vaiSerEntregue) {
        await _ajustarEstoqueProdutosDaCompra(
          transaction: transaction,
          compraData: compraData,
          fator: -1,
        );
      }

      transaction.update(compraRef, {
        'status': statusNovo,
        'statusAprovacao': statusNovo == 'entregue' ? 'aprovada' : null,
        'entregueEm':
            statusNovo == 'entregue' ? FieldValue.serverTimestamp() : null,
        'entreguePorUid':
            statusNovo == 'entregue' ? _auth.currentUser?.uid : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _ajustarEstoqueProdutosDaCompra({
    required Transaction transaction,
    required Map<String, dynamic> compraData,
    required int fator,
  }) async {
    final itens = _extrairItensProdutoDaCompra(compraData);

    final snaps =
        <_ItemProdutoCompra, DocumentSnapshot<Map<String, dynamic>>>{};

    for (final item in itens) {
      if (item.produtoId.isEmpty || item.quantidade <= 0) continue;

      final produtoRef = _fs.collection('produtos').doc(item.produtoId);
      final produtoSnap = await transaction.get(produtoRef);

      if (!produtoSnap.exists) {
        throw Exception('Produto não encontrado no estoque: ${item.nome}');
      }

      snaps[item] = produtoSnap;
    }

    for (final entry in snaps.entries) {
      final item = entry.key;
      final produtoSnap = entry.value;

      final produtoRef = _fs.collection('produtos').doc(item.produtoId);
      final produtoData = produtoSnap.data() ?? {};

      final estoqueAtual = _toDouble(produtoData['estoque']);
      final quantidadeComprada = item.quantidade;
      final valorCompra = item.valorUnitario;

      final novoEstoque = estoqueAtual + (quantidadeComprada * fator);

      final updates = <String, dynamic>{
        'estoque': novoEstoque,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (fator > 0) {
        double precoMedioAtual = _toDouble(
          produtoData['precoMedio'] ?? produtoData['preco-medio'],
        );

        if (precoMedioAtual <= 0) {
          precoMedioAtual = valorCompra;
        }

        final estoqueFinal = estoqueAtual + quantidadeComprada;

        final novoPrecoMedio =
            estoqueFinal <= 0
                ? valorCompra
                : ((estoqueAtual * precoMedioAtual) +
                        (quantidadeComprada * valorCompra)) /
                    estoqueFinal;

        updates['precoMedio'] = novoPrecoMedio;
      }

      transaction.update(produtoRef, updates);
    }
  }

  List<_ItemProdutoCompra> _extrairItensProdutoDaCompra(
    Map<String, dynamic> compraData,
  ) {
    final itensProduto = <_ItemProdutoCompra>[];

    final itensRaw = compraData['itens'] ?? compraData['itensProdutos'];

    if (itensRaw is List) {
      for (final raw in itensRaw) {
        if (raw is! Map) continue;

        final item = Map<String, dynamic>.from(raw);

        final tipo =
            (item['tipo'] ?? item['tipoItem'] ?? 'produto')
                .toString()
                .toLowerCase()
                .trim();

        if (tipo != 'produto') continue;

        final produtoId =
            (item['refId'] ??
                    item['itemId'] ??
                    item['produtoId'] ??
                    item['idProduto'] ??
                    item['id'] ??
                    '')
                .toString()
                .trim();

        final nome =
            (item['nome'] ?? item['itemNome'] ?? item['produtoNome'] ?? '')
                .toString();

        final quantidade = _toDouble(item['quantidade']);
        final valorUnitario = _toDouble(item['valorUnitario']);

        if (produtoId.isEmpty || quantidade <= 0) continue;

        itensProduto.add(
          _ItemProdutoCompra(
            produtoId: produtoId,
            nome: nome,
            quantidade: quantidade,
            valorUnitario: valorUnitario,
          ),
        );
      }
    }

    return itensProduto;
  }

  String _normalizarStatus(String status) {
    final s = status.toLowerCase().trim();

    if (s == 'recebida') return 'entregue';
    if (s == 'parcial') return 'entrega_parcial';
    if (s == 'entregue') return 'entregue';
    if (s == 'entrega_parcial') return 'entrega_parcial';
    if (s == 'cancelada') return 'cancelada';

    return 'aberta';
  }

  Future<void> _rejeitarCompra(String compraId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text('Rejeitar compra?'),
              ],
            ),
            content: const Text(
              'Esta compra será marcada como cancelada.\n\n'
              'Deseja realmente continuar?',
              style: TextStyle(color: Color(0xFF475569)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Sim, rejeitar'),
              ),
            ],
          ),
    );

    if (confirmar != true) return;

    await _fs.collection('compras').doc(compraId).update({
      'status': 'cancelada',
      'statusAprovacao': 'rejeitada',
      'rejeitadoEm': FieldValue.serverTimestamp(),
      'rejeitadoPorUid': _auth.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Compra rejeitada.')));
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(
          value
              .toString()
              .replaceAll('R\$', '')
              .replaceAll('.', '')
              .replaceAll(',', '.')
              .trim(),
        ) ??
        0.0;
  }

  String _fmtMoeda(dynamic value) {
    final v = _toDouble(value);
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );

    return 'R\$ $inteiro,${p[1]}';
  }

  String _fmtData(dynamic value) {
    DateTime? d;

    if (value is Timestamp) {
      d = value.toDate();
    } else if (value is DateTime) {
      d = value;
    }

    if (d == null) return 'Sem data';

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  int _qtdItens(Map<String, dynamic> data) {
    final itens = data['itens'] ?? data['itensProdutos'];

    if (itens is List) return itens.length;

    return 0;
  }

  Widget _buildHeader(int count) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF3B0CA3), // primaryDark
            Color(0xFF5B21B6), // primary
            Color(0xFFF97316), // orange
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              if (Navigator.canPop(context)) ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    tooltip: 'Voltar',
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Entrega de Compras',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 1
                          ? '1 compra aguardando entrega'
                          : '$count compras aguardando entrega',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Estoque',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

  Widget _compraCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final numeroCompra = (data['numeroCompra'] ?? '').toString().trim();
    final fornecedorNome =
        (data['fornecedorNome'] ?? 'Fornecedor não informado').toString();

    final valorTotal = data['valorTotal'] ?? data['total'] ?? 0;
    final dataCompra = data['createdAt'] ?? data['dataCompra'];
    final dataEntrega = data['dataEntrega'];
    final condicaoPagamento =
        (data['condicaoPagamento'] ?? 'Não informada').toString();
    final status = (data['status'] ?? 'aberta').toString();
    final isParcial = status == 'entrega_parcial';

    final titulo =
        numeroCompra.isEmpty ? 'Compra sem número' : 'Compra #$numeroCompra';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isParcial
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                        : const Color(0xFFF97316).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isParcial ? Icons.inventory_outlined : Icons.pending_actions_rounded,
                    color: isParcial ? const Color(0xFF3B82F6) : const Color(0xFFF97316),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.business_rounded, size: 14, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              fornecedorNome,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isParcial
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                        : const Color(0xFFF97316).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isParcial ? 'Parcial' : 'Pendente',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isParcial ? const Color(0xFF1D4ED8) : const Color(0xFFC2410C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Chips informativos
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(
                  icon: Icons.attach_money_rounded,
                  label: _fmtMoeda(valorTotal),
                  isBold: true,
                  color: const Color(0xFF10B981),
                ),
                _infoChip(
                  icon: Icons.shopping_bag_outlined,
                  label: '${_qtdItens(data)} item(ns)',
                ),
                _infoChip(
                  icon: Icons.calendar_today_rounded,
                  label: 'Criada: ${_fmtData(dataCompra)}',
                ),
                if (dataEntrega != null)
                  _infoChip(
                    icon: Icons.local_shipping_outlined,
                    label: 'Entrega: ${_fmtData(dataEntrega)}',
                  ),
                if (condicaoPagamento.isNotEmpty && condicaoPagamento != 'Não informada')
                  _infoChip(
                    icon: Icons.payment_rounded,
                    label: condicaoPagamento,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // Ações
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejeitarCompra(doc.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text(
                      'Rejeitar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _marcarComoEntregue(doc.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size.fromHeight(46),
                      elevation: 2,
                      shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'Marcar Entregue',
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

  Widget _infoChip({
    required IconData icon,
    required String label,
    bool isBold = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color != null
            ? color.withValues(alpha: 0.1)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color != null
              ? color.withValues(alpha: 0.25)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color ?? const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
        ),
      );
    }

    if (_erro != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            _buildHeader(0),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _erro!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFEF4444)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _comprasPendentesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
            );
          }

          if (snap.hasError) {
            return Column(
              children: [
                _buildHeader(0),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Erro ao carregar compras: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFEF4444)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final docs = snap.data?.docs ?? [];

          docs.sort((a, b) {
            final da = a.data()['createdAt'];
            final db = b.data()['createdAt'];

            final ta = da is Timestamp ? da.toDate() : DateTime(1900);
            final tb = db is Timestamp ? db.toDate() : DateTime(1900);

            return tb.compareTo(ta);
          });

          return Column(
            children: [
              _buildHeader(docs.length),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 38,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Tudo em dia!',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Nenhuma compra aguardando recebimento no momento.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: docs.map(_compraCard).toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
