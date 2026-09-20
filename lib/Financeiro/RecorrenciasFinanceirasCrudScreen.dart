import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'CadastroRecorrenciaFinanceiraScreen.dart';

class RecorrenciasFinanceirasCrudScreen extends StatefulWidget {
  final TipoRecorrenciaFinanceira tipo;

  const RecorrenciasFinanceirasCrudScreen({super.key, required this.tipo});

  @override
  State<RecorrenciasFinanceirasCrudScreen> createState() =>
      _RecorrenciasFinanceirasCrudScreenState();
}

class _RecorrenciasFinanceirasCrudScreenState
    extends State<RecorrenciasFinanceirasCrudScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  String? _companyId;
  String? _erro;

  bool get _isPagar => widget.tipo == TipoRecorrenciaFinanceira.pagar;

  String get _collectionName =>
      _isPagar ? 'recorrencias_pagar' : 'recorrencias_receber';

  String get _titulo =>
      _isPagar ? 'Pagamentos Recorrentes' : 'Recebimentos Recorrentes';

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
        _erro = null;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar empresa: $e';
        _loading = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamRecorrencias() {
    return _fs
        .collection(_collectionName)
        .where('companyId', isEqualTo: _companyId)
        .snapshots();
  }

  Future<void> _abrirCadastro({String? recorrenciaId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => CadastroRecorrenciaFinanceiraScreen(
              tipo: widget.tipo,
              recorrenciaId: recorrenciaId,
            ),
      ),
    );
  }

  Future<void> _excluir(String id) async {
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
                Text('Excluir Recorrência?',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            content: const Text(
              'Esta recorrência será excluída.\n\nAs contas já geradas anteriormente não serão apagadas.',
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
                label: const Text('Sim, excluir'),
              ),
            ],
          ),
    );

    if (confirmar != true) return;

    await _fs.collection(_collectionName).doc(id).delete();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recorrência excluída com sucesso.')));
  }

  String _fmtMoeda(dynamic value) {
    final v = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isPagar
                          ? 'Gestão de despesas mensais programadas'
                          : 'Gestão de receitas mensais programadas',
                      style: const TextStyle(
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
                      Icon(
                        _isPagar ? Icons.upload_rounded : Icons.download_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
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

  Widget _buildRecorrenciaCard(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    final descricao = (data['descricao'] ?? 'Sem descrição').toString();
    final pessoa = _isPagar
        ? (data['fornecedorNome'] ?? 'Fornecedor não informado').toString()
        : (data['clienteNome'] ?? 'Cliente não informado').toString();

    final categoria = (data['categoriaNome'] ?? 'Sem categoria').toString();
    final dia = (data['diaVencimento'] ?? '-').toString();
    final ativo = (data['ativo'] ?? true) == true;
    final valor = data['valor'];

    final statusColor = _isPagar ? const Color(0xFFDC2626) : const Color(0xFF059669);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _abrirCadastro(recorrenciaId: doc.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topo: Ícone + Descrição + Valor
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
                        _isPagar
                            ? Icons.receipt_long_outlined
                            : Icons.savings_outlined,
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
                            descricao,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _isPagar
                                    ? Icons.store_outlined
                                    : Icons.person_outline,
                                size: 14,
                                color: const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  pessoa,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Opções',
                      onSelected: (value) {
                        if (value == 'editar') {
                          _abrirCadastro(recorrenciaId: doc.id);
                        }
                        if (value == 'excluir') {
                          _excluir(doc.id);
                        }
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'editar',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined,
                                  size: 18, color: Color(0xFF475569)),
                              SizedBox(width: 8),
                              Text('Editar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'excluir',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Excluir',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.more_vert,
                          color: Color(0xFF475569),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Painel interno: Categoria, Dia e Valor
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
                            Text(
                              categoria.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 13,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Dia $dia de cada mês',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        color: const Color(0xFFE2E8F0),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'VALOR MENSAL',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _fmtMoeda(valor),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Tags de status ativo/inativo
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ativo
                            ? const Color(0xFF059669).withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: ativo
                                  ? const Color(0xFF059669)
                                  : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            ativo ? 'Ativo' : 'Inativo',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ativo
                                  ? const Color(0xFF059669)
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Toque para editar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
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
                Icons.repeat_rounded,
                size: 54,
                color: Color(0xFF3B0CA3),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isPagar
                  ? 'Nenhum pagamento recorrente'
                  : 'Nenhum recebimento recorrente',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isPagar
                  ? 'Cadastre contas recorrentes (aluguel, internet, salários) para automação financeira.'
                  : 'Cadastre receitas recorrentes (mensalidades, assinaturas) para automação financeira.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _abrirCadastro(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B0CA3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Criar Primeira Recorrência',
                style: TextStyle(fontWeight: FontWeight.w700),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirCadastro(),
        backgroundColor: const Color(0xFF3B0CA3),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: const Icon(Icons.add),
        label: const Text(
          'Nova Recorrência',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _streamRecorrencias(),
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

                      final sortedDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
                      sortedDocs.sort((a, b) {
                        final da = a.data()['createdAt'];
                        final db = b.data()['createdAt'];

                        final ta = da is Timestamp ? da.toDate() : DateTime(1900);
                        final tb = db is Timestamp ? db.toDate() : DateTime(1900);

                        return tb.compareTo(ta);
                      });

                      if (sortedDocs.isEmpty) {
                        return _buildEmptyState();
                      }

                      return RefreshIndicator(
                        color: const Color(0xFF3B0CA3),
                        onRefresh: () async => setState(() {}),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: sortedDocs.length,
                          itemBuilder: (context, index) {
                            return _buildRecorrenciaCard(context, sortedDocs[index]);
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
