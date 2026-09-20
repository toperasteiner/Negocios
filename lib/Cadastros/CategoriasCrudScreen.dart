import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CategoriasCrudScreen extends StatefulWidget {
  const CategoriasCrudScreen({super.key});

  @override
  State<CategoriasCrudScreen> createState() => _CategoriasCrudScreenState();
}

class _CategoriasCrudScreenState extends State<CategoriasCrudScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _filtroTipo = 'todos';

  bool _loading = true;
  String? _companyId;
  String? _scopeUserId;
  String? _erro;

  CollectionReference<Map<String, dynamic>> get _categoriasRef =>
      _firestore.collection('categorias');

  @override
  void initState() {
    super.initState();
    _carregarEscopo();
  }

  Future<void> _carregarEscopo() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _erro = 'Usuário não autenticado.';
        });
        return;
      }

      Map<String, dynamic>? userData;

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        userData = doc.data();
      } else {
        final emailKey = (user.email ?? '').trim().toLowerCase();

        if (emailKey.isNotEmpty) {
          final query =
              await _firestore
                  .collection('users')
                  .where('emailKey', isEqualTo: emailKey)
                  .limit(1)
                  .get();

          if (query.docs.isNotEmpty) {
            userData = query.docs.first.data();
          }
        }
      }

      final companyId = (userData?['companyId'] ?? '').toString().trim();

      if (!mounted) return;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : user.uid;
        _loading = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _erro = 'Erro ao carregar empresa/escopo: $e';
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamCategorias() {
    Query<Map<String, dynamic>> query = _categoriasRef
        .where('companyId', isEqualTo: _scopeUserId)
        .where('ativo', isEqualTo: true);

    if (_filtroTipo != 'todos') {
      query = query.where('tipo', isEqualTo: _filtroTipo);
    }

    return query.snapshots();
  }

  Future<void> _abrirFormulario({
    String? categoriaId,
    Map<String, dynamic>? dados,
  }) async {
    if (_scopeUserId == null || _scopeUserId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    final nomeController = TextEditingController(
      text: dados?['nome']?.toString() ?? '',
    );

    final descricaoController = TextEditingController(
      text: dados?['descricao']?.toString() ?? '',
    );

    String tipoSelecionado = dados?['tipo']?.toString() ?? 'produto';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: CategoriaStyle.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final padding =
            MediaQuery.of(sheetContext).viewInsets +
            const EdgeInsets.fromLTRB(16, 8, 16, 16);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Padding(
              padding: padding,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Row(
                      children: [
                        const _IconBadge(
                          icon: Icons.category_outlined,
                          color: CategoriaStyle.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            categoriaId == null
                                ? 'Nova categoria'
                                : 'Editar categoria',
                            style: const TextStyle(
                              color: CategoriaStyle.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nomeController,
                      decoration: _inputDecoration(
                        label: 'Nome da categoria',
                        icon: Icons.label_outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descricaoController,
                      maxLines: 3,
                      decoration: _inputDecoration(
                        label: 'Descrição',
                        icon: Icons.description_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: tipoSelecionado,
                      decoration: _inputDecoration(
                        label: 'Tipo',
                        icon: Icons.tune_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'produto',
                          child: Text('Produto'),
                        ),
                        DropdownMenuItem(
                          value: 'servico',
                          child: Text('Serviço'),
                        ),
                        DropdownMenuItem(
                          value: 'ambos',
                          child: Text('Produto e Serviço'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          tipoSelecionado = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: CategoriaStyle.primary,
                              side: BorderSide(
                                color: CategoriaStyle.primary.withOpacity(0.25),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.pop(sheetContext, false),
                            icon: const Icon(Icons.close),
                            label: const Text(
                              'Cancelar',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: CategoriaStyle.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              final nome = nomeController.text.trim();

                              if (nome.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Informe o nome da categoria.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              await _salvarCategoria(
                                categoriaId: categoriaId,
                                nome: nome,
                                descricao: descricaoController.text.trim(),
                                tipo: tipoSelecionado,
                              );

                              if (!mounted) return;
                              Navigator.pop(sheetContext, true);
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text(
                              'Salvar',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            categoriaId == null
                ? 'Categoria cadastrada com sucesso.'
                : 'Categoria atualizada com sucesso.',
          ),
        ),
      );
    }
  }

  Future<void> _salvarCategoria({
    required String? categoriaId,
    required String nome,
    required String descricao,
    required String tipo,
  }) async {
    final uid = _auth.currentUser?.uid;

    if (_scopeUserId == null || _scopeUserId!.isEmpty) {
      throw Exception('Empresa não identificada.');
    }

    final dados = {
      'nome': nome,
      'nomeLower': nome.toLowerCase(),
      'descricao': descricao,
      'tipo': tipo,
      'companyId': _scopeUserId,
      'userId': uid,
      'ativo': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (categoriaId == null) {
      await _categoriasRef.add({
        ...dados,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _categoriasRef.doc(categoriaId).update(dados);
    }
  }

  Future<void> _excluirCategoria(String categoriaId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Excluir categoria?'),
          content: const Text(
            'A categoria será desativada e não aparecerá mais nos cadastros.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: CategoriaStyle.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    await _categoriasRef.doc(categoriaId).update({
      'ativo': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Categoria excluída.')));
    }
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'produto':
        return 'Produto';
      case 'servico':
        return 'Serviço';
      case 'ambos':
        return 'Produto e Serviço';
      default:
        return tipo;
    }
  }

  IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'produto':
        return Icons.inventory_2_outlined;
      case 'servico':
        return Icons.miscellaneous_services_outlined;
      case 'ambos':
        return Icons.category_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: CategoriaStyle.bg,
        body: Center(
          child: CircularProgressIndicator(color: CategoriaStyle.primary),
        ),
      );
    }

    if (_erro != null) {
      return Scaffold(
        backgroundColor: CategoriaStyle.bg,
        body: Column(
          children: [
            CategoriasHeader(
              onBack: () => Navigator.of(context).maybePop(),
              onNew: () => _abrirFormulario(),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _erro!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CategoriaStyle.text,
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

    return Scaffold(
      backgroundColor: CategoriaStyle.bg,
      body: Column(
        children: [
          CategoriasHeader(
            onBack: () => Navigator.of(context).maybePop(),
            onNew: () => _abrirFormulario(),
          ),
          _FilterCard(
            value: _filtroTipo,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _filtroTipo = value;
              });
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamCategorias(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: CategoriaStyle.primary,
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Erro ao carregar categorias: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: CategoriaStyle.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const _EmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final dados = doc.data();

                    final nome = dados['nome']?.toString() ?? 'Sem nome';
                    final descricao = dados['descricao']?.toString() ?? '';
                    final tipo = dados['tipo']?.toString() ?? 'produto';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CategoriaCard(
                        nome: nome,
                        descricao: descricao,
                        tipo: tipo,
                        tipoLabel: _tipoLabel(tipo),
                        tipoIcon: _tipoIcon(tipo),
                        onTap:
                            () => _abrirFormulario(
                              categoriaId: doc.id,
                              dados: dados,
                            ),
                        onEdit:
                            () => _abrirFormulario(
                              categoriaId: doc.id,
                              dados: dados,
                            ),
                        onDelete: () => _excluirCategoria(doc.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: CategoriaStyle.orange,
        foregroundColor: Colors.white,
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text(
          'Categoria',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? label, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon:
          icon == null ? null : Icon(icon, color: CategoriaStyle.primary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: CategoriaStyle.primary, width: 1.4),
      ),
      isDense: true,
    );
  }
}

/* ====================== WIDGETS VISUAIS ====================== */

class CategoriasHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onNew;

  const CategoriasHeader({
    super.key,
    required this.onBack,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: CategoriaStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 6,
        16,
        16,
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
              _HeaderIconButton(icon: Icons.add, onTap: onNew),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Organize categorias usadas em produtos e serviços.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  const _FilterCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Filtrar por tipo',
          prefixIcon: const Icon(Icons.filter_alt_outlined),
          prefixIconColor: CategoriaStyle.primary,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(value: 'todos', child: Text('Todos')),
          DropdownMenuItem(value: 'produto', child: Text('Produto')),
          DropdownMenuItem(value: 'servico', child: Text('Serviço')),
          DropdownMenuItem(value: 'ambos', child: Text('Produto e Serviço')),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _CategoriaCard extends StatelessWidget {
  final String nome;
  final String descricao;
  final String tipo;
  final String tipoLabel;
  final IconData tipoIcon;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoriaCard({
    required this.nome,
    required this.descricao,
    required this.tipo,
    required this.tipoLabel,
    required this.tipoIcon,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
              _IconBadge(icon: tipoIcon, color: CategoriaStyle.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CategoriaStyle.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoChip(label: tipoLabel, icon: Icons.sell_outlined),
                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CategoriaStyle.muted,
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
                onSelected: (value) {
                  if (value == 'editar') onEdit();
                  if (value == 'excluir') onDelete();
                },
                itemBuilder: (context) {
                  return const [
                    PopupMenuItem(value: 'editar', child: Text('Editar')),
                    PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                  ];
                },
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

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CategoriaStyle.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: CategoriaStyle.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CategoriaStyle.text,
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 44),
        Column(
          children: [
            _IconBadge(
              icon: Icons.category_outlined,
              color: CategoriaStyle.orange,
            ),
            SizedBox(height: 14),
            Text(
              'Nenhuma categoria cadastrada.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CategoriaStyle.text,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Toque em “Categoria” para começar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CategoriaStyle.muted,
                fontWeight: FontWeight.w600,
              ),
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

class CategoriaStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
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
