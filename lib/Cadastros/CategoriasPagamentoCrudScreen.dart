// lib/Financeiro/CategoriasPagamentoCrudScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'CadastroCategoriaPagamentoScreen.dart';
import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

class CategoriasPagamentoCrudScreen extends StatefulWidget {
  const CategoriasPagamentoCrudScreen({super.key});

  @override
  State<CategoriasPagamentoCrudScreen> createState() =>
      _CategoriasPagamentoCrudScreenState();
}

class _CategoriasPagamentoCrudScreenState
    extends State<CategoriasPagamentoCrudScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String _limitKey = 'maxPaymentCategories';

  String? _companyId;
  String? _scopeUserId;
  bool _loadingScope = true;
  String? _scopeError;

  bool _loadingPlan = true;
  String? _planError;
  int _usedCount = 0;
  int _limitCount = -1;
  bool _canCreateByPlan = true;

  bool _mostrarInativos = false;

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _limitCount = service.getLimit('maxPaymentCategories');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan = (_limitCount == -1 || _usedCount < _limitCount);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _initScope();
    _auth.authStateChanges().listen((_) => _initScope());
  }

  Future<int> _getCurrentCategoriasCount() async {
    final scope = _scopeUserId;
    if (scope == null || scope.isEmpty) return 0;

    final snap =
        await _fs
            .collection('categorias_pagamento')
            .where('companyId', isEqualTo: scope)
            .count()
            .get();

    return snap.count ?? 0;
  }

  Future<void> _refreshPlanRules() async {
    try {
      setState(() {
        _loadingPlan = true;
        _planError = null;
      });

      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await _getCurrentCategoriasCount();
      final limite = PlanService.instance.getLimit(_limitKey);
      final canCreate = limite == -1 ? true : usados < limite;

      if (!mounted) return;

      setState(() {
        _usedCount = usados;
        _limitCount = limite;
        _canCreateByPlan = canCreate;
        _loadingPlan = false;
        _planError = null;
      });
      // A plan notification may have arrived while the count was loading.
      _onPlanChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _planError = 'Erro ao validar plano: $e';
      });
    }
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
        _companyId = null;
        _scopeUserId = null;
      });
      return;
    }

    setState(() {
      _loadingScope = true;
      _scopeError = null;
    });

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      Map<String, dynamic>? me = byUid.data();

      if (me == null) {
        final email = (u.email ?? '').toLowerCase().trim();
        if (email.isNotEmpty) {
          final q =
              await _fs
                  .collection('users')
                  .where('emailKey', isEqualTo: email)
                  .limit(1)
                  .get();
          if (q.docs.isNotEmpty) me = q.docs.first.data();
        }
      }

      final companyId = (me?['companyId'] ?? '').toString().trim();

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid;
        _loadingScope = false;
      });

      await _refreshPlanRules();
    } catch (e, st) {
      debugPrint('[CategoriasPagamento] _initScope erro: $e\n$st');
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar escopo: $e';
        _companyId = null;
        _scopeUserId = null;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamCategorias() {
    final scope = _scopeUserId ?? '__';
    final col = _fs.collection('categorias_pagamento');

    if (!_mostrarInativos) {
      return col
          .where('companyId', isEqualTo: scope)
          .where('ativa', isEqualTo: true)
          .orderBy('nome')
          .snapshots();
    }

    return col.where('companyId', isEqualTo: scope).orderBy('nome').snapshots();
  }

  void _showPlanLimitDialog({
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: CategoriaPagamentoStyle.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<bool> _requirePlanSlot() async {
    try {
      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await _getCurrentCategoriasCount();
      final limite = PlanService.instance.getLimit(_limitKey);
      final canCreate = limite == -1 ? true : usados < limite;

      if (!mounted) return false;

      setState(() {
        _usedCount = usados;
        _limitCount = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de categorias atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de categorias de pagamento do seu plano atual.\n\n'
                    'Categorias usadas: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando.',
      );

      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao validar plano: $e')));
      return false;
    }
  }

  Widget _buildPlanWarningCard() {
    final planoAtual = PlanService.instance.planId.toUpperCase();
    final ilimitado = _limitCount == -1;
    final restantes = ilimitado ? 999999 : (_limitCount - _usedCount);
    final atingiuLimite = !ilimitado && _usedCount >= _limitCount;
    final mostrarAviso = !ilimitado && restantes <= 5;

    if (!mostrarAviso && _planError == null) {
      return const SizedBox.shrink();
    }

    final color =
        atingiuLimite
            ? CategoriaPagamentoStyle.red
            : CategoriaPagamentoStyle.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(
            icon:
                atingiuLimite
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plano: $planoAtual',
                  style: const TextStyle(
                    color: CategoriaPagamentoStyle.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  atingiuLimite
                      ? 'Você atingiu o limite do seu plano para categorias de pagamento.'
                      : 'Faltam apenas $restantes categoria(s) para atingir o limite do seu plano.',
                  style: const TextStyle(
                    color: CategoriaPagamentoStyle.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_planError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _planError!,
                    style: const TextStyle(
                      color: CategoriaPagamentoStyle.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CategoriaPagamentoStyle.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlanosScreen()),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Fazer upgrade'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirCadastroNova() async {
    final ok = await _requirePlanSlot();
    if (!ok) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CadastroCategoriaPagamentoScreen(companyId: _scopeUserId!),
      ),
    );

    await _refreshPlanRules();
  }

  Future<void> _abrirEdicao(String categoriaId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CadastroCategoriaPagamentoScreen(
              companyId: _scopeUserId!,
              categoriaId: categoriaId,
            ),
      ),
    );

    await _refreshPlanRules();
  }

  Future<void> _toggleAtiva(
    BuildContext context, {
    required String id,
    required bool ativaAtual,
  }) async {
    final u = _auth.currentUser;
    final novoStatus = !ativaAtual;

    try {
      await _fs.collection('categorias_pagamento').doc(id).update({
        'ativa': novoStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        if (u != null) 'updatedBy': u.uid,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              novoStatus ? 'Categoria ativada.' : 'Categoria inativada.',
            ),
          ),
        );
      }

      await _refreshPlanRules();
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[CategoriasPagamento] _toggleAtiva FirebaseException: '
        '${e.code} ${e.message}\n$st',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao alterar status: ${e.message}')),
        );
      }
    } catch (e, st) {
      debugPrint('[CategoriasPagamento] _toggleAtiva erro: $e\n$st');

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao alterar status: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: CategoriaPagamentoStyle.bg,
        body: Center(
          child: CircularProgressIndicator(
            color: CategoriaPagamentoStyle.primary,
          ),
        ),
      );
    }

    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: CategoriaPagamentoStyle.bg,
        body: Column(
          children: [
            CategoriasPagamentoHeader(
              mostrarInativos: _mostrarInativos,
              onBack: () => Navigator.of(context).maybePop(),
              onNew: _abrirCadastroNova,
              onToggleInativos: (v) => setState(() => _mostrarInativos = v),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _scopeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CategoriaPagamentoStyle.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_scopeUserId == null) {
      return const Scaffold(
        backgroundColor: CategoriaPagamentoStyle.bg,
        body: Center(child: Text('Faça login para continuar.')),
      );
    }

    final fabEnabled = !_loadingPlan && (_canCreateByPlan || _limitCount == -1);

    return Scaffold(
      backgroundColor: CategoriaPagamentoStyle.bg,
      body: Column(
        children: [
          CategoriasPagamentoHeader(
            mostrarInativos: _mostrarInativos,
            onBack: () => Navigator.of(context).maybePop(),
            onNew:
                _loadingPlan
                    ? null
                    : (fabEnabled
                        ? _abrirCadastroNova
                        : () async {
                          await _requirePlanSlot();
                        }),
            onToggleInativos: (v) => setState(() => _mostrarInativos = v),
          ),
          if (_loadingPlan)
            const LinearProgressIndicator(
              minHeight: 3,
              color: CategoriaPagamentoStyle.primary,
            ),
          if (!_loadingPlan) _buildPlanWarningCard(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamCategorias(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  debugPrint(
                    '[CategoriasPagamento] StreamBuilder erro: ${snap.error}',
                  );
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro: ${snap.error}'),
                  );
                }

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: CategoriaPagamentoStyle.primary,
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return RefreshIndicator(
                    color: CategoriaPagamentoStyle.primary,
                    onRefresh: _refreshPlanRules,
                    child: _EmptyState(
                      mostrarInativos: _mostrarInativos,
                      onNew:
                          _loadingPlan
                              ? null
                              : (fabEnabled
                                  ? _abrirCadastroNova
                                  : () async {
                                    await _requirePlanSlot();
                                  }),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: CategoriaPagamentoStyle.primary,
                  onRefresh: _refreshPlanRules,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();

                      final nome = (m['nome'] ?? '').toString();
                      final tipo = (m['tipo'] ?? 'ambos').toString();
                      final ativa = (m['ativa'] ?? true) == true;
                      final desc = (m['descricao'] ?? '').toString();

                      String tipoLabel;
                      switch (tipo) {
                        case 'pagar':
                          tipoLabel = 'Pagar';
                          break;
                        case 'receber':
                          tipoLabel = 'Receber';
                          break;
                        default:
                          tipoLabel = 'Ambos';
                      }

                      return _CategoriaCard(
                        nome: nome,
                        tipoLabel: tipoLabel,
                        descricao: desc,
                        ativa: ativa,
                        onTap: () async => _abrirEdicao(d.id),
                        onEdit: () async => _abrirEdicao(d.id),
                        onToggle: () async {
                          await _toggleAtiva(
                            context,
                            id: d.id,
                            ativaAtual: ativa,
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:
            fabEnabled ? CategoriaPagamentoStyle.orange : Colors.grey.shade300,
        foregroundColor: fabEnabled ? Colors.white : Colors.grey.shade700,
        onPressed:
            _loadingPlan
                ? null
                : (fabEnabled
                    ? _abrirCadastroNova
                    : () async {
                      await _requirePlanSlot();
                    }),
        icon: const Icon(Icons.add),
        label: Text(_loadingPlan ? 'Validando...' : 'Nova categoria'),
      ),
    );
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }
}

/* ====================== WIDGETS VISUAIS ====================== */

class CategoriasPagamentoHeader extends StatelessWidget {
  final bool mostrarInativos;
  final VoidCallback onBack;
  final VoidCallback? onNew;
  final ValueChanged<bool> onToggleInativos;

  const CategoriasPagamentoHeader({
    super.key,
    required this.mostrarInativos,
    required this.onBack,
    required this.onNew,
    required this.onToggleInativos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: CategoriaPagamentoStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 6,
        16,
        14,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Expanded(
                child: Center(
                  child: Text(
                    'Categorias',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(icon: Icons.add, onTap: onNew ?? () {}),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Organize categorias usadas em contas a pagar e a receber.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 7),
                const Text(
                  'Mostrar inativas',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Switch.adaptive(
                  value: mostrarInativos,
                  activeColor: Colors.white,
                  onChanged: onToggleInativos,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriaCard extends StatelessWidget {
  final String nome;
  final String tipoLabel;
  final String descricao;
  final bool ativa;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _CategoriaCard({
    required this.nome,
    required this.tipoLabel,
    required this.descricao,
    required this.ativa,
    required this.onTap,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        ativa ? CategoriaPagamentoStyle.primary : CategoriaPagamentoStyle.muted;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBadge(icon: Icons.label, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Sem nome' : nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            ativa
                                ? CategoriaPagamentoStyle.text
                                : CategoriaPagamentoStyle.muted,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        decoration: ativa ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          label: 'Tipo: $tipoLabel',
                          icon: Icons.swap_horiz_outlined,
                        ),
                        if (!ativa)
                          const _InfoChip(
                            label: 'Inativa',
                            icon: Icons.block_outlined,
                            color: CategoriaPagamentoStyle.red,
                          ),
                      ],
                    ),
                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CategoriaPagamentoStyle.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'toggle') onToggle();
                },
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(ativa ? 'Inativar' : 'Ativar'),
                      ),
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _InfoChip({
    required this.label,
    required this.icon,
    this.color = CategoriaPagamentoStyle.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CategoriaPagamentoStyle.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CategoriaPagamentoStyle.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool mostrarInativos;
  final VoidCallback? onNew;

  const _EmptyState({required this.mostrarInativos, required this.onNew});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 44),
        Column(
          children: [
            const _IconBadge(
              icon: Icons.label_off,
              color: CategoriaPagamentoStyle.orange,
            ),
            const SizedBox(height: 14),
            Text(
              mostrarInativos
                  ? 'Nenhuma categoria cadastrada.'
                  : 'Nenhuma categoria ativa cadastrada.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CategoriaPagamentoStyle.text,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Toque em “Nova categoria” para começar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CategoriaPagamentoStyle.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: const Text('Nova categoria'),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

/* ====================== STYLE ====================== */

class CategoriaPagamentoStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
