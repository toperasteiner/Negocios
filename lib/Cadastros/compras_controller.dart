import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Planos/PlanService.dart';

class ComprasController {
  ComprasController({required this.onChanged}) {
    PlanService.instance.addListener(_onPlanChanged);
  }

  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
  }

  void _onPlanChanged() {
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    currentPlan = service.planId;
    monthlyPurchasesLimit = service.getLimit('maxCompras');
    _notify();
  }

  final VoidCallback onChanged;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? companyId;
  String? scopeUserId;
  bool loadingScope = true;
  String? erro;

  String filtroStatus = 'todos';
  String filtroFornecedorId = 'todos';

  String currentPlan = 'free';
  int monthlyPurchasesCount = 0;
  int monthlyPurchasesLimit = -1;
  bool loadingPurchaseLimit = true;
  String? purchasePlanError;

  bool get isCompanyScope => companyId != null && companyId!.isNotEmpty;
  String get scopeField => isCompanyScope ? 'companyId' : 'userId';

  bool get purchaseLimitReached =>
      !loadingPurchaseLimit &&
      monthlyPurchasesLimit != -1 &&
      monthlyPurchasesCount >= monthlyPurchasesLimit;

  List<String> get statusOptions => const [
    'todos',
    'aberta',
    'entrega_parcial',
    'cancelada',
    'entregue',
  ];

  void _notify() => onChanged();

  Future<void> initScope() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        loadingScope = false;
        erro = 'Usuário não autenticado.';
        _notify();
        return;
      }

      final userDoc = await _fs.collection('users').doc(user.uid).get();
      final data = userDoc.data() ?? {};
      final loadedCompanyId = (data['companyId'] ?? '').toString().trim();
      final planId = (data['planId'] ?? 'free').toString().trim().toLowerCase();

      companyId = loadedCompanyId.isEmpty ? null : loadedCompanyId;
      scopeUserId = loadedCompanyId.isNotEmpty ? loadedCompanyId : user.uid;
      loadingScope = false;
      currentPlan =
          PlanService.instance.isLoaded
              ? PlanService.instance.planId
              : (planId.isEmpty ? 'free' : planId);
      erro = null;
      _notify();

      await refreshPurchasesLimit();
    } catch (e) {
      loadingScope = false;
      erro = 'Erro ao carregar compras: $e';
      _notify();
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> comprasStream() {
    return _fs
        .collection('compras')
        .where(scopeField, isEqualTo: scopeUserId)
        .snapshots();
  }

  Future<bool> requirePurchaseSlot() async {
    await refreshPurchasesLimit();

    // Se houve erro na validação do plano,
    // não permite cadastrar uma nova compra.
    if (purchasePlanError != null) {
      return false;
    }

    // -1 significa plano ilimitado.
    if (monthlyPurchasesLimit == -1) {
      return true;
    }

    // Só permite quando ainda existe saldo disponível.
    return monthlyPurchasesCount < monthlyPurchasesLimit;
  }

  Future<int> loadMonthlyPurchasesCount() async {
    final user = _auth.currentUser;
    if (user == null || scopeUserId == null) return 0;

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth =
        now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);

    final snap =
        await _fs
            .collection('compras')
            .where(scopeField, isEqualTo: scopeUserId)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
            )
            .where(
              'createdAt',
              isLessThan: Timestamp.fromDate(startOfNextMonth),
            )
            .get();

    return snap.docs.length;
  }

  Future<void> refreshPurchasesLimit() async {
    try {
      loadingPurchaseLimit = true;
      purchasePlanError = null;
      _notify();

      await PlanService.instance.reload();
      final count = await loadMonthlyPurchasesCount();
      final limite = PlanService.instance.getLimit('maxCompras');

      debugPrint('COMPRAS PLAN ID: ${PlanService.instance.planId}');
      debugPrint('COMPRAS LIMIT maxCompras: $limite');
      debugPrint('COMPRAS USER DATA: ${PlanService.instance.userData}');
      debugPrint('COMPRAS PLAN DATA: ${PlanService.instance.planId}');

      monthlyPurchasesCount = count;
      monthlyPurchasesLimit = limite;
      currentPlan = PlanService.instance.planId;
      loadingPurchaseLimit = false;
      purchasePlanError = null;
      _notify();
    } catch (e) {
      loadingPurchaseLimit = false;
      purchasePlanError = 'Erro ao validar limite de compras: $e';
      _notify();
    }
  }

  Future<void> atualizarStatusCompraComEstoque({
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

      final statusAtual = normalizarStatusFiltro(
        (compraData['status'] ?? 'aberta').toString(),
      );

      final statusNovo = normalizarStatusFiltro(novoStatus);

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
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelarCompra(String compraId) async {
    await atualizarStatusCompraComEstoque(
      compraId: compraId,
      novoStatus: 'cancelada',
    );
  }

  Future<void> _ajustarEstoqueProdutosDaCompra({
    required Transaction transaction,
    required Map<String, dynamic> compraData,
    required int fator,
  }) async {
    final itens = extrairItensProdutoDaCompra(compraData);

    final snaps = <ItemProdutoCompra, DocumentSnapshot<Map<String, dynamic>>>{};

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

      final estoqueAtual = toDouble(produtoData['estoque']);
      final quantidadeComprada = item.quantidade;
      final valorCompra = item.valorUnitario;

      final novoEstoque = estoqueAtual + (quantidadeComprada * fator);

      final updates = <String, dynamic>{
        'estoque': novoEstoque,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (fator > 0) {
        double precoMedioAtual = toDouble(
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

  List<ItemProdutoCompra> extrairItensProdutoDaCompra(
    Map<String, dynamic> compraData,
  ) {
    final itensProduto = <ItemProdutoCompra>[];

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

        final quantidade = toDouble(item['quantidade']);
        final valorUnitario = toDouble(item['valorUnitario']);

        if (produtoId.isEmpty || quantidade <= 0) continue;

        itensProduto.add(
          ItemProdutoCompra(
            produtoId: produtoId,
            nome: nome,
            quantidade: quantidade,
            valorUnitario: valorUnitario,
          ),
        );
      }

      return itensProduto;
    }

    final tipoItem =
        (compraData['tipoItem'] ?? 'produto').toString().toLowerCase().trim();

    if (tipoItem == 'produto') {
      final produtoId =
          (compraData['itemId'] ?? compraData['produtoId'] ?? '')
              .toString()
              .trim();

      final nome =
          (compraData['itemNome'] ?? compraData['produtoNome'] ?? '')
              .toString();

      final quantidade = toDouble(compraData['quantidade']);
      final valorUnitario = toDouble(compraData['valorUnitario']);

      if (produtoId.isNotEmpty && quantidade > 0) {
        itensProduto.add(
          ItemProdutoCompra(
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

  double toDouble(dynamic v) {
    if (v is num) return v.toDouble();

    final text = v
        .toString()
        .trim()
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(text) ?? 0.0;
  }

  String fmtMoeda(num v) {
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

  String fmtData(dynamic value) {
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

  Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'entregue':
      case 'recebida':
        return Colors.green;
      case 'entrega_parcial':
      case 'parcial':
        return Colors.blue;
      case 'cancelada':
        return Colors.red;
      case 'aberta':
      default:
        return Colors.orange;
    }
  }

  IconData statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'entregue':
      case 'recebida':
        return Icons.inventory_2_outlined;
      case 'entrega_parcial':
      case 'parcial':
        return Icons.inventory_outlined;
      case 'cancelada':
        return Icons.cancel_outlined;
      case 'aberta':
      default:
        return Icons.shopping_cart_outlined;
    }
  }

  String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'entregue':
      case 'recebida':
        return 'Entregue';
      case 'entrega_parcial':
      case 'parcial':
        return 'Entrega Parcial';
      case 'cancelada':
        return 'Cancelada';
      case 'aberta':
      default:
        return 'Aberta';
    }
  }

  String normalizarStatusFiltro(String status) {
    final s = status.toLowerCase().trim();

    if (s == 'recebida') return 'entregue';
    if (s == 'parcial') return 'entrega_parcial';

    if (s == 'cancelada') return 'cancelada';
    if (s == 'entregue') return 'entregue';
    if (s == 'entrega_parcial') return 'entrega_parcial';

    return 'aberta';
  }

  Map<String, String> montarFornecedoresFiltro(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final fornecedores = <String, String>{};

    for (final doc in docs) {
      final data = doc.data();

      final fornecedorId = (data['fornecedorId'] ?? '').toString().trim();
      final fornecedorNome = (data['fornecedorNome'] ?? '').toString().trim();

      if (fornecedorId.isNotEmpty) {
        fornecedores[fornecedorId] =
            fornecedorNome.isEmpty ? 'Fornecedor sem nome' : fornecedorNome;
      }
    }

    final ordenado =
        fornecedores.entries.toList()..sort(
          (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
        );

    return Map.fromEntries(ordenado);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> aplicarFiltros(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();

      final status = normalizarStatusFiltro(
        (data['status'] ?? 'aberta').toString(),
      );

      final fornecedorId = (data['fornecedorId'] ?? '').toString().trim();

      final passaStatus =
          filtroStatus == 'todos'
              ? status != 'cancelada'
              : status == filtroStatus;

      final passaFornecedor =
          filtroFornecedorId == 'todos' || fornecedorId == filtroFornecedorId;

      return passaStatus && passaFornecedor;
    }).toList();
  }

  void setFiltroStatus(String value) {
    filtroStatus = value;
    _notify();
  }

  void setFiltroFornecedor(String value) {
    filtroFornecedorId = value;
    _notify();
  }

  void limparFiltros() {
    filtroStatus = 'todos';
    filtroFornecedorId = 'todos';
    _notify();
  }
}

class ItemProdutoCompra {
  final String produtoId;
  final String nome;
  final double quantidade;
  final double valorUnitario;

  const ItemProdutoCompra({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.valorUnitario,
  });
}
