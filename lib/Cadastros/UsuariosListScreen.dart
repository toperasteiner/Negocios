import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ajuste o import conforme seu projeto
import 'UsuarioFormScreen.dart';

class UsuariosListScreen extends StatefulWidget {
  const UsuariosListScreen({super.key});

  @override
  State<UsuariosListScreen> createState() => _UsuariosListScreenState();
}

class _UsuariosListScreenState extends State<UsuariosListScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _uid; // UID do usuário logado (Auth)
  String _myEmailKey = '';
  bool _loadingScope = true; // carregando UID
  String? _scopeError; // erro ao obter UID

  String _busca = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hydrateAuth();
    _auth.authStateChanges().listen((_) => _hydrateAuth());
    _searchCtrl.addListener(
      () => setState(() => _busca = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  void _hydrateAuth() {
    final u = _auth.currentUser;
    _uid = u?.uid;
    _myEmailKey = (u?.email ?? '').trim().toLowerCase();
    _loadingScope = false;
    _scopeError = (_uid == null) ? 'Faça login para visualizar.' : null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------- Query ----------------
  /// Retorna todos `users` cujo `companyId` == UID do logado.
  Query<Map<String, dynamic>> _query() {
    final filterUid = _uid ?? '__NO_UID__';
    final q = _fs.collection('users').where('companyId', isEqualTo: filterUid);
    debugPrint('[UsuariosList] filter companyId == $filterUid');
    return q; // ordenação client-side p/ evitar índice composto
  }

  // ---------------- Navegação ----------------
  Future<void> _abrirNovo() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const UsuarioFormScreen()),
    );
    if (ok == true && mounted) setState(() {}); // refresh
  }

  Future<void> _editarUsuarioAbrirForm(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UsuarioFormScreen(userDocId: doc.id)),
    );
    if (ok == true && mounted) setState(() {}); // refresh
  }

  Future<void> _excluirUsuario(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};
    final nome = (data['displayName'] ?? data['email'] ?? doc.id).toString();

    final confirma = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text('Excluir usuário?'),
              ],
            ),
            content: Text(
              'Esta ação removerá o acesso e os registros deste usuário no sistema.\n\nUsuário: $nome',
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
    );
    if (confirma != true) return;

    try {
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Usuário excluído.')));
      }
    } catch (e, st) {
      debugPrint('[UsuariosList][excluirUsuario] $e');
      debugPrint('[UsuariosList][excluirUsuario] $st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                          'Usuários e Equipe',
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
                              ? '1 usuário cadastrado'
                              : '$count usuários cadastrados',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      tooltip: 'Novo usuário',
                      onPressed: _abrirNovo,
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Campo de busca integrado
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome ou e-mail...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    suffixIcon:
                        _busca.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(
                                  Icons.clear_rounded,
                                  size: 18,
                                  color: Color(0xFF94A3B8),
                                ),
                                onPressed: () => _searchCtrl.clear(),
                              ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    final nome = (m['displayName'] ?? '').toString();
    final email = (m['email'] ?? '').toString();
    final active = (m['active'] ?? true) == true;
    final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
    final updatedAt = (m['updatedAt'] as Timestamp?)?.toDate();

    final initialLetter =
        (nome.isNotEmpty
                ? nome[0]
                : (email.isNotEmpty ? email[0] : '?'))
            .toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _editarUsuarioAbrirForm(doc),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF5B21B6).withValues(alpha: 0.15),
                        const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF5B21B6).withValues(alpha: 0.2),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initialLetter,
                    style: const TextStyle(
                      color: Color(0xFF5B21B6),
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Informações
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nome.isEmpty ? email : nome,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Badge Ativo / Inativo
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  active
                                      ? const Color(0xFF10B981).withValues(
                                        alpha: 0.12,
                                      )
                                      : const Color(0xFFEF4444).withValues(
                                        alpha: 0.12,
                                      ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color:
                                        active
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  active ? 'Ativo' : 'Inativo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        active
                                            ? const Color(0xFF047857)
                                            : const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (email.isNotEmpty)
                        Row(
                          children: [
                            const Icon(
                              Icons.alternate_email_rounded,
                              size: 13,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                email,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            updatedAt != null
                                ? 'Atualizado em ${_fmtData(updatedAt)}'
                                : (createdAt != null
                                    ? 'Criado em ${_fmtData(createdAt)}'
                                    : 'Cadastrado'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Menu de Ações
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') _editarUsuarioAbrirForm(doc);
                    if (v == 'delete') _excluirUsuario(doc);
                  },
                  itemBuilder:
                      (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Color(0xFF5B21B6),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Editar usuário',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Color(0xFFEF4444),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Excluir',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
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

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
        ),
      );
    }
    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            _buildHeader(0),
            Expanded(child: Center(child: Text(_scopeError!))),
          ],
        ),
      );
    }
    if (_uid == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            _buildHeader(0),
            const Expanded(
              child: Center(child: Text('Faça login para visualizar.')),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query().snapshots(),
      builder: (ctx, snap) {
        final isWaiting = snap.connectionState == ConnectionState.waiting;
        var docs = snap.data?.docs ?? [];

        // 1) EXCLUI O PRÓPRIO USUÁRIO (por docId == uid OU por email/emailKey)
        docs =
            docs.where((d) {
              final m = d.data();
              final emailKeyDoc =
                  (m['emailKey'] ?? (m['email'] ?? ''))
                      .toString()
                      .trim()
                      .toLowerCase();
              final notSelfById = d.id != _uid;
              final notSelfByEmail =
                  _myEmailKey.isEmpty ? true : (emailKeyDoc != _myEmailKey);
              return notSelfById && notSelfByEmail;
            }).toList();

        // 2) Ordena client-side por nome lower (se houver) ou email
        docs.sort((a, b) {
          final am = a.data();
          final bm = b.data();
          final an =
              (am['displayNameLower'] ?? am['displayName'] ?? '')
                  .toString()
                  .toLowerCase();
          final bn =
              (bm['displayNameLower'] ?? bm['displayName'] ?? '')
                  .toString()
                  .toLowerCase();
          if (an.isEmpty && bn.isEmpty) {
            return (am['email'] ?? '').toString().toLowerCase().compareTo(
              (bm['email'] ?? '').toString().toLowerCase(),
            );
          }
          return an.compareTo(bn);
        });

        // 3) Filtro por busca
        if (_busca.isNotEmpty) {
          docs =
              docs.where((d) {
                final m = d.data();
                final nome = (m['displayName'] ?? '').toString().toLowerCase();
                final email = (m['email'] ?? '').toString().toLowerCase();
                return nome.contains(_busca) || email.contains(_busca);
              }).toList();
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _abrirNovo,
            backgroundColor: const Color(0xFF5B21B6),
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text(
              'Novo Usuário',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: Column(
            children: [
              _buildHeader(docs.length),
              Expanded(
                child:
                    snap.hasError
                        ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(
                              'Erro: ${snap.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        )
                        : (isWaiting && (snap.data == null))
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF5B21B6),
                          ),
                        )
                        : (docs.isEmpty)
                        ? _EmptyState(
                          onNew: _abrirNovo,
                          hint:
                              _busca.isEmpty
                                  ? 'Nenhum usuário (da sua empresa) para listar.\nObs.: seu próprio usuário não é exibido aqui.'
                                  : 'Sem resultados para "$_busca"',
                        )
                        : RefreshIndicator(
                          color: const Color(0xFF5B21B6),
                          onRefresh: () async => setState(() {}),
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                            itemCount: docs.length,
                            itemBuilder: (_, i) => _buildUserCard(docs[i]),
                          ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  final String? hint;
  const _EmptyState({required this.onNew, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF5B21B6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 36,
                color: Color(0xFF5B21B6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hint ?? 'Nenhum usuário encontrado.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onNew,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5B21B6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text(
                'Adicionar Usuário',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
