import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'CadastroCompraScreen.dart';
import '../Planos/PlanosScreen.dart';
import 'compras_controller.dart';
import 'compras_widgets.dart';

class ComprasCrudScreen extends StatefulWidget {
  const ComprasCrudScreen({super.key});

  @override
  State<ComprasCrudScreen> createState() => _ComprasCrudScreenState();
}

class _ComprasCrudScreenState extends State<ComprasCrudScreen> {
  late final ComprasController _controller;

  @override
  void initState() {
    super.initState();

    _controller = ComprasController(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    _controller.initScope();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _abrirTelaPlanos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlanosScreen()),
    ).then((_) async {
      await _controller.refreshPurchasesLimit();
    });
  }

  void _showPlanLimitDialog({
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _abrirTelaPlanos();
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Fazer upgrade'),
              ),
            ],
          ),
    );
  }

  Future<void> _novaCompra() async {
    if (_controller.loadingPurchaseLimit) return;

    final allowed = await _controller.requirePurchaseSlot();

    if (!mounted) return;

    if (!allowed) {
      _showPlanLimitDialog(
        titulo: 'Limite de compras atingido',
        mensagem:
            'Você já atingiu o limite de compras do seu plano atual.\n\n'
            'Compras usadas neste mês: ${_controller.monthlyPurchasesCount}\n'
            'Limite do plano: ${_controller.monthlyPurchasesLimit}\n\n'
            'Faça upgrade para continuar cadastrando compras.',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Você atingiu o limite de ${_controller.monthlyPurchasesLimit} compras por mês do seu plano.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CadastroCompraScreen()));

    await _controller.refreshPurchasesLimit();
  }

  Future<void> _editarCompra(String compraId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CadastroCompraScreen(compraId: compraId),
      ),
    );
  }

  Future<void> _alterarStatusCompra({
    required String compraId,
    required String statusAtual,
  }) async {
    if (_controller.normalizarStatusFiltro(statusAtual) == 'cancelada') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compra cancelada não pode ter o status alterado.'),
        ),
      );
      return;
    }

    final novoStatus = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Alterar situação da compra',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                StatusOptionTile(
                  status: 'aberta',
                  statusAtual: statusAtual,
                  label: 'Aberta',
                  icon: Icons.shopping_cart_outlined,
                  color: ComprasStyle.orange,
                ),
                StatusOptionTile(
                  status: 'entrega_parcial',
                  statusAtual: statusAtual,
                  label: 'Entrega Parcial',
                  icon: Icons.inventory_outlined,
                  color: ComprasStyle.blue,
                ),
                StatusOptionTile(
                  status: 'cancelada',
                  statusAtual: statusAtual,
                  label: 'Cancelada',
                  icon: Icons.cancel_outlined,
                  color: ComprasStyle.red,
                ),
                StatusOptionTile(
                  status: 'entregue',
                  statusAtual: statusAtual,
                  label: 'Entregue',
                  icon: Icons.inventory_2_outlined,
                  color: ComprasStyle.green,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (novoStatus == null || novoStatus == statusAtual) return;

    try {
      await _controller.atualizarStatusCompraComEstoque(
        compraId: compraId,
        novoStatus: novoStatus,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Situação alterada para ${_controller.statusLabel(novoStatus)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao alterar situação: $e')));
    }
  }

  Future<void> _cancelarCompra(String compraId) async {
    try {
      await _controller.cancelarCompra(compraId);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Compra cancelada.')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao cancelar compra: $e')));
    }
  }

  double _totalCompras(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.fold<double>(0, (total, doc) {
      final data = doc.data();
      return total + _controller.toDouble(data['valorTotal'] ?? data['total']);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_controller.erro != null) {
      return Scaffold(
        backgroundColor: ComprasStyle.bg,
        appBar: AppBar(title: const Text('Compras')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_controller.erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ComprasStyle.bg,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        onPressed:
            _controller.loadingPurchaseLimit || _controller.purchaseLimitReached
                ? null
                : () async {
                  await _novaCompra();
                },
        label: Text(
          _controller.loadingPurchaseLimit
              ? 'Validando...'
              : _controller.purchaseLimitReached
              ? 'Limite atingido'
              : 'Nova compra',
        ),
        backgroundColor:
            _controller.purchaseLimitReached
                ? const Color(0xFFE2E8F0)
                : ComprasStyle.orange,
        foregroundColor:
            _controller.purchaseLimitReached
                ? ComprasStyle.muted
                : Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _controller.comprasStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erro ao listar compras: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          final fornecedores = _controller.montarFornecedoresFiltro(docs);
          if (_controller.filtroFornecedorId != 'todos' &&
              !fornecedores.containsKey(_controller.filtroFornecedorId)) {
            _controller.setFiltroFornecedor('todos');
          }

          final docsFiltrados = _controller.aplicarFiltros(docs);
          final total = _totalCompras(docsFiltrados);

          return Column(
            children: [
              ComprasHeader(
                onBack: () => Navigator.pop(context),
                onRefresh: () async => _controller.refreshPurchasesLimit(),
              ),
              if (_controller.purchasePlanError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _controller.purchasePlanError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (_controller.loadingPurchaseLimit)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              /*if (!_controller.loadingPurchaseLimit)
                PurchasePlanWarningCard(
                  currentPlan: _controller.currentPlan,
                  monthlyPurchasesCount: _controller.monthlyPurchasesCount,
                  monthlyPurchasesLimit: _controller.monthlyPurchasesLimit,
                  purchasePlanError: _controller.purchasePlanError,
                  onUpgrade: _abrirTelaPlanos,
                ),*/
              ComprasFiltrosCard(
                statusOptions: _controller.statusOptions,
                filtroStatus: _controller.filtroStatus,
                filtroFornecedorId: _controller.filtroFornecedorId,
                fornecedores: fornecedores,
                statusLabel: _controller.statusLabel,
                onStatusChanged: _controller.setFiltroStatus,
                onFornecedorChanged: _controller.setFiltroFornecedor,
                onLimpar: _controller.limparFiltros,
              ),
              ComprasResumoSection(
                loadingPurchaseLimit: _controller.loadingPurchaseLimit,
                monthlyPurchasesCount: _controller.monthlyPurchasesCount,
                monthlyPurchasesLimit: _controller.monthlyPurchasesLimit,
                totalText: _controller.fmtMoeda(total),
              ),
              Expanded(
                child:
                    docsFiltrados.isEmpty
                        ? ComprasEmptyState(possuiCompras: docs.isNotEmpty)
                        : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: docsFiltrados.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return CompraCard(
                              doc: docsFiltrados[index],
                              fmtMoeda: _controller.fmtMoeda,
                              fmtData: _controller.fmtData,
                              toDouble: _controller.toDouble,
                              normalizarStatusFiltro:
                                  _controller.normalizarStatusFiltro,
                              statusLabel: _controller.statusLabel,
                              statusColor: _controller.statusColor,
                              statusIcon: _controller.statusIcon,
                              onEditar: _editarCompra,
                              onCancelar: _cancelarCompra,
                              onAlterarStatus: (compraId, statusAtual) {
                                _alterarStatusCompra(
                                  compraId: compraId,
                                  statusAtual: statusAtual,
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
    );
  }
}
