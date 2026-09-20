import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'CotacaoFreteInternacionalScreen.dart';
import 'cotacoes_frete_orcamentos.dart';
import 'AprovarCotacoesFreteScreen.dart';

class CotacoesFreteInternacionalListScreen extends StatefulWidget {
  const CotacoesFreteInternacionalListScreen({super.key});

  @override
  State<CotacoesFreteInternacionalListScreen> createState() =>
      _CotacoesFreteInternacionalListScreenState();
}

class _CotacoesFreteInternacionalListScreenState
    extends State<CotacoesFreteInternacionalListScreen> {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color background = Color(0xFFFBFAFF);

  String _statusFiltro = 'Todos';

  final List<String> _statusList = [
    'Todos',
    'Rascunho',
    'Solicitada',
    'Cotando',
    'Recebida',
    'Em análise',
    'Aprovada',
    'Contratada',
    'Cancelada',
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamCotacoes() {
    final user = FirebaseAuth.instance.currentUser;

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('cotacoes_frete_internacional')
        .where('companyId', isEqualTo: user?.uid);

    if (_statusFiltro != 'Todos') {
      query = query.where('status', isEqualTo: _statusFiltro);
    }

    return query.snapshots();
  }

  Future<void> _abrirCadastro({String? cotacaoId}) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CotacaoFreteInternacionalScreen(cotacaoId: cotacaoId),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _abrirOrcamento({
    required String cotacaoId,
    required String referenciaCotacao,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => OrcamentoFreteInternacionalScreen(
              cotacaoId: cotacaoId,
              referenciaCotacao: referenciaCotacao,
            ),
      ),
    );
  }

  Future<void> _abrirAprovacao({required String cotacaoId}) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AprovarCotacoesFreteScreen(cotacaoId: cotacaoId),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _excluirCotacao(String cotacaoId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Excluir cotação'),
            content: const Text(
              'Deseja realmente excluir esta cotação de frete internacional?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
    );

    if (confirmar != true) return;

    await FirebaseFirestore.instance
        .collection('cotacoes_frete_internacional')
        .doc(cotacaoId)
        .delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cotação excluída com sucesso.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Rascunho':
        return textMuted;
      case 'Solicitada':
        return blue;
      case 'Cotando':
        return orange;
      case 'Recebida':
        return purple;
      case 'Em análise':
        return orange;
      case 'Aprovada':
        return green;
      case 'Contratada':
        return green;
      case 'Cancelada':
        return Colors.red;
      default:
        return purple;
    }
  }

  String _formatarData(dynamic value) {
    if (value == null) return '-';

    DateTime? data;

    if (value is Timestamp) {
      data = value.toDate();
    } else if (value is DateTime) {
      data = value;
    }

    if (data == null) return '-';

    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        onPressed: () => _abrirCadastro(),
        icon: const Icon(Icons.add),
        label: const Text(
          'Nova Cotação',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 170,
            pinned: true,
            elevation: 0,
            backgroundColor: purple,
            foregroundColor: Colors.white,
            centerTitle: true,
            title: const Text(
              'Cotações de Frete',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [purple, deepPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 68, 18, 18),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Frete Internacional',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Gerencie solicitações, orçamentos e contratações.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
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
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: _filtroStatus(),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _streamCotacoes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Erro ao carregar cotações:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return SliverFillRemaining(child: _emptyState());
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final doc = docs[index];
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      index == 0 ? 8 : 0,
                      18,
                      index == docs.length - 1 ? 90 : 14,
                    ),
                    child: _cotacaoCard(doc),
                  );
                }, childCount: docs.length),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filtroStatus() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: purple.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: _statusFiltro,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Filtrar por status',
          prefixIcon: const Icon(Icons.filter_list_rounded, color: purple),
          filled: true,
          fillColor: const Color(0xFFF8F6FF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: purple.withOpacity(0.10)),
          ),
        ),
        items:
            _statusList
                .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                .toList(),
        onChanged: (value) {
          setState(() => _statusFiltro = value ?? 'Todos');
        },
      ),
    );
  }

  Widget _cotacaoCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final referencia = data['referencia'] ?? 'Sem referência';
    final status = data['status'] ?? 'Rascunho';
    final modal = data['modal'] ?? '-';
    final incoterm = data['incoterm'] ?? '-';
    final tipoCarga = data['tipoCarga'] ?? '-';
    final localDestino = data['localDestino'] ?? '-';
    final createdAt = _formatarData(data['createdAt']);
    final statusColor = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _abrirCadastro(cotacaoId: doc.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            statusColor.withOpacity(0.95),
                            statusColor.withOpacity(0.70),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.local_shipping_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            referencia,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$modal • $incoterm • $tipoCarga',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Destino: $localDestino',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusChip(status, statusColor),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _infoChip(Icons.event_outlined, createdAt),
                    const SizedBox(width: 8),
                    Expanded(child: _infoChip(Icons.flag_outlined, status)),
                  ],
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 120,
                      child: OutlinedButton.icon(
                        onPressed: () => _abrirCadastro(cotacaoId: doc.id),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar'),
                      ),
                    ),
                    SizedBox(
                      width: 135,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          foregroundColor: Colors.white,
                        ),
                        onPressed:
                            () => _abrirOrcamento(
                              cotacaoId: doc.id,
                              referenciaCotacao: referencia,
                            ),
                        icon: const Icon(
                          Icons.request_quote_outlined,
                          size: 18,
                        ),
                        label: const Text('Orçamento'),
                      ),
                    ),
                    SizedBox(
                      width: 125,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _abrirAprovacao(cotacaoId: doc.id),
                        icon: const Icon(Icons.approval_outlined, size: 18),
                        label: const Text('Aprovar'),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        onPressed: () => _excluirCotacao(doc.id),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: purple),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 70,
              color: purple.withOpacity(0.35),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nenhuma cotação encontrada',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Crie uma nova cotação de frete internacional para iniciar o processo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: purple,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _abrirCadastro(),
              icon: const Icon(Icons.add),
              label: const Text('Nova Cotação'),
            ),
          ],
        ),
      ),
    );
  }
}
