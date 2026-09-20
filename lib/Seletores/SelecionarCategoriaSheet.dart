import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CategoriaSelecionada {
  final String id;
  final String nome;

  const CategoriaSelecionada({required this.id, required this.nome});
}

class SelecionarCategoriaSheet extends StatefulWidget {
  final String tipo; // produto, servico ou ambos

  const SelecionarCategoriaSheet({super.key, this.tipo = 'servico'});

  @override
  State<SelecionarCategoriaSheet> createState() =>
      _SelecionarCategoriaSheetState();
}

class _SelecionarCategoriaSheetState extends State<SelecionarCategoriaSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CategoriaSelecionada? _selecionada;

  String? _companyId;
  bool _loadingScope = true;
  String? _scopeError;
  bool _podeCadastrar = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _initScope();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _initScope() async {
    final user = _auth.currentUser;

    if (user == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Faça login para continuar.';
      });
      return;
    }

    try {
      Map<String, dynamic>? me;

      final byUid = await _fs.collection('users').doc(user.uid).get();

      if (byUid.exists) {
        me = byUid.data();
      } else {
        final emailKey = (user.email ?? '').trim().toLowerCase();

        if (emailKey.isNotEmpty) {
          final q =
              await _fs
                  .collection('users')
                  .where('emailKey', isEqualTo: emailKey)
                  .limit(1)
                  .get();

          if (q.docs.isNotEmpty) {
            me = q.docs.first.data();
          }
        }
      }

      final companyId = (me?['companyId'] ?? '').toString().trim();

      final permissionsRaw = me?['permissions'];
      final permissions =
          permissionsRaw is Map<String, dynamic> ? permissionsRaw : {};

      final role = (me?['role'] ?? '').toString().toLowerCase();
      final isAdmin = role == 'admin';

      final canManageCategories =
          isAdmin || (permissions['canManageCategories'] ?? false) == true;

      if (!mounted) return;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _podeCadastrar = canManageCategories;
        _loadingScope = false;
        _scopeError =
            companyId.isEmpty ? 'Usuário sem empresa vinculada.' : null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar empresa: $e';
      });
    }
  }

  void _concluirSelecao() {
    if (_selecionada == null) return;
    Navigator.pop(context, _selecionada);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const SafeArea(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_scopeError != null || _companyId == null) {
      return SafeArea(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: 'Voltar',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Selecionar categoria'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _scopeError ?? 'Não foi possível determinar a empresa.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final companyId = _companyId!;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Selecionar categoria'),
          bottom: TabBar(
            controller: _tab,
            tabs: [
              const Tab(icon: Icon(Icons.category_outlined), text: 'Catálogo'),
              Tab(
                icon: Icon(
                  _podeCadastrar
                      ? Icons.add_circle_outline
                      : Icons.lock_outline,
                ),
                text: 'Cadastrar',
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child:
                _tab.index == 0
                    ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context, null);
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Sem categoria'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _selecionada == null ? null : _concluirSelecao,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Adicionar categoria'),
                          ),
                        ),
                      ],
                    )
                    : FilledButton.icon(
                      onPressed:
                          !_podeCadastrar
                              ? null
                              : () {
                                final state =
                                    context
                                        .findAncestorStateOfType<
                                          _SelecionarCategoriaSheetState
                                        >();
                                state?.setState(() {});
                              },
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        _podeCadastrar
                            ? 'Salvar categoria'
                            : 'Sem permissão para cadastrar',
                      ),
                    ),
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            _CatalogoCategoriasTab(
              companyId: companyId,
              tipo: widget.tipo,
              selecionada: _selecionada,
              onEscolhida: (categoria) {
                setState(() {
                  _selecionada = categoria;
                });
              },
            ),
            !_podeCadastrar
                ? const _AbaBloqueada(
                  motivo: 'Você não tem permissão para cadastrar categorias.',
                )
                : _CadastrarCategoriaTab(
                  companyId: companyId,
                  tipo: widget.tipo,
                  onSalvo: (categoria) {
                    Navigator.pop(context, categoria);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _CatalogoCategoriasTab extends StatefulWidget {
  final String companyId;
  final String tipo;
  final CategoriaSelecionada? selecionada;
  final void Function(CategoriaSelecionada categoria) onEscolhida;

  const _CatalogoCategoriasTab({
    required this.companyId,
    required this.tipo,
    required this.selecionada,
    required this.onEscolhida,
  });

  @override
  State<_CatalogoCategoriasTab> createState() => _CatalogoCategoriasTabState();
}

class _CatalogoCategoriasTabState extends State<_CatalogoCategoriasTab> {
  final _fs = FirebaseFirestore.instance;
  final _buscaCtrl = TextEditingController();

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  bool _tipoCompativel(Map<String, dynamic> data) {
    final tipo = (data['tipo'] ?? '').toString();

    if (widget.tipo == 'produto') {
      return tipo == 'produto' || tipo == 'ambos';
    }

    if (widget.tipo == 'servico') {
      return tipo == 'servico' || tipo == 'ambos';
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final query = _fs
        .collection('categorias')
        .where('companyId', isEqualTo: widget.companyId)
        .where('ativo', isEqualTo: true)
    //.orderBy('nomeLower')
    ;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar categoria',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Erro ao carregar categorias: ${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final filtro = _buscaCtrl.text.trim().toLowerCase();

              final docs =
                  (snap.data?.docs ?? []).where((doc) {
                    final data = doc.data();

                    if (!_tipoCompativel(data)) return false;

                    final nome = (data['nome'] ?? '').toString().toLowerCase();
                    final descricao =
                        (data['descricao'] ?? '').toString().toLowerCase();

                    return filtro.isEmpty ||
                        nome.contains(filtro) ||
                        descricao.contains(filtro);
                  }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma categoria encontrada.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final doc = docs[index];
                  final data = doc.data();

                  final id = doc.id;
                  final nome = (data['nome'] ?? 'Sem nome').toString();
                  final descricao = (data['descricao'] ?? '').toString();
                  final tipo = (data['tipo'] ?? '').toString();

                  final selecionada = widget.selecionada?.id == id;

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RadioListTile<bool>(
                      value: true,
                      groupValue: selecionada ? true : null,
                      onChanged: (_) {
                        widget.onEscolhida(
                          CategoriaSelecionada(id: id, nome: nome),
                        );
                      },
                      title: Text(
                        nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        descricao.isNotEmpty ? descricao : _tipoLabel(tipo),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondary: const Icon(Icons.category_outlined),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
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
        return 'Categoria';
    }
  }
}

class _CadastrarCategoriaTab extends StatefulWidget {
  final String companyId;
  final String tipo;
  final void Function(CategoriaSelecionada categoria) onSalvo;

  const _CadastrarCategoriaTab({
    required this.companyId,
    required this.tipo,
    required this.onSalvo,
  });

  @override
  State<_CadastrarCategoriaTab> createState() => _CadastrarCategoriaTabState();
}

class _CadastrarCategoriaTabState extends State<_CadastrarCategoriaTab> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _salvando = false;
  late String _tipoCategoria;

  @override
  void initState() {
    super.initState();

    if (widget.tipo == 'produto') {
      _tipoCategoria = 'produto';
    } else if (widget.tipo == 'servico') {
      _tipoCategoria = 'servico';
    } else {
      _tipoCategoria = 'ambos';
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String? _validaNome(String? value) {
    final nome = (value ?? '').trim();

    if (nome.isEmpty) return 'Informe o nome da categoria.';
    if (nome.length < 2) return 'Nome muito curto.';

    return null;
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;

    final uid = _auth.currentUser?.uid;
    final nome = _nomeCtrl.text.trim();

    setState(() {
      _salvando = true;
    });

    try {
      final ref = await _fs.collection('categorias').add({
        'companyId': widget.companyId,
        'userId': uid,
        'createdByUid': uid,
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'descricao':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'tipo': _tipoCategoria,
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      widget.onSalvo(CategoriaSelecionada(id: ref.id, nome: nome));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar categoria: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _salvando,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionCard(
            icon: Icons.category_outlined,
            title: 'Informações da Categoria',
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nomeCtrl,
                    validator: _validaNome,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nome da categoria *',
                      border: OutlineInputBorder(),
                      filled: true,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      border: OutlineInputBorder(),
                      filled: true,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _tipoCategoria,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                      filled: true,
                      isDense: true,
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
                      setState(() {
                        _tipoCategoria = value;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon:
                        _salvando
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.check_rounded),
                    label: Text(_salvando ? 'Salvando...' : 'Salvar categoria'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbaBloqueada extends StatelessWidget {
  final String motivo;

  const _AbaBloqueada({required this.motivo});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Cadastro bloqueado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(motivo, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
