// lib/Listagens/ProdutoScreen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../Planos/PlanService.dart';

import '../Cadastros/CadastroProdutoScreen.dart';
import '../Planos/PlanosScreen.dart';

class ProdutoStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get headerGradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

class ProdutoScreen extends StatefulWidget {
  const ProdutoScreen({super.key});

  @override
  State<ProdutoScreen> createState() => _ProdutoScreenState();
}

class _ProdutoScreenState extends State<ProdutoScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // -------- Estado de empresa/escopo/perm ----------
  String? _companyId;
  bool _loadingCompany = true;
  String? _loadError;

  bool _canManageProducts = false;

  // -------- Busca ----------
  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _q = '';

  // -------- Plano ----------
  bool _loadingPlan = true;
  String? _planError;
  int _productsUsed = 0;
  int _productsLimit = -1; // -1 = ilimitado
  bool _canCreateByPlan = true;

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _productsLimit = service.getLimit('maxProducts');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan =
            (service.companyId ?? '').isNotEmpty &&
            (_productsLimit == -1 || _productsUsed < _productsLimit);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _buscaCtrl.addListener(_onSearchChange);
    _loadCompanyScopeAndPerms();
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _debounce?.cancel();
    _buscaCtrl.removeListener(_onSearchChange);
    _buscaCtrl.dispose();
    super.dispose();
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
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
    );
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

      final usados = await PlanService.instance.getCurrentProductsCount();
      final limite = PlanService.instance.getLimit('maxProducts');
      final canCreate = await PlanService.instance.canCreateProduct();

      if (!mounted) return;

      setState(() {
        _productsUsed = usados;
        _productsLimit = limite;
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

  // -------- Carregar companyId + permissões ----------
  Future<void> _loadCompanyScopeAndPerms() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingCompany = false;
        _loadError = 'Usuário não autenticado.';
      });
      return;
    }

    try {
      Map<String, dynamic>? me;

      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) {
        me = Map<String, dynamic>.from(byUid.data() ?? {});
      } else {
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

      if (me == null) {
        setState(() {
          _loadingCompany = false;
          _loadError = 'Registro do usuário não encontrado em "users".';
        });
        return;
      }

      final companyId = (me['companyId'] ?? '').toString().trim();
      final perms = Map<String, dynamic>.from(me['permissions'] ?? {});
      final canMP = (perms['canManageProducts'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _canManageProducts = canMP;
        _loadingCompany = false;
        _loadError = null;
      });

      await _refreshPlanRules();
    } catch (e) {
      setState(() {
        _loadingCompany = false;
        _loadError = 'Erro ao carregar empresa/permissões: $e';
      });
    }
  }

  void _onSearchChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final v = _buscaCtrl.text.trim();
      if (v != _q) setState(() => _q = v);
    });
  }

  // -------- Gate de permissão centralizado ----------
  bool _requirePerm() {
    if (_canManageProducts) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissão. É necessário "Cadastrar/Alterar produtos".',
        ),
      ),
    );
    return false;
  }

  Future<bool> _requirePlanSlot() async {
    try {
      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final canCreate = await PlanService.instance.canCreateProduct();
      final usados = await PlanService.instance.getCurrentProductsCount();
      final limite = PlanService.instance.getLimit('maxProducts');

      if (!mounted) return false;

      setState(() {
        _productsUsed = usados;
        _productsLimit = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de produtos atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de produtos do seu plano atual.\n\n'
                    'Produtos usados: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando produtos.',
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

  // -------- Navegação ----------
  Future<void> _novo() async {
    if (!_requirePerm()) return;

    //final ok = await _requirePlanSlot();
    //if (!ok) return;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CadastroProdutoScreen()),
    );

    await _refreshPlanRules();
  }

  Future<void> _editar(String id) async {
    if (!_requirePerm()) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CadastroProdutoScreen(produtoId: id)),
    );

    await _refreshPlanRules();
  }

  Future<void> _deleteStorageFile(String raw) async {
    try {
      if (raw.trim().isEmpty) return;

      final ref =
          raw.startsWith('http://') || raw.startsWith('https://')
              ? FirebaseStorage.instance.refFromURL(raw)
              : raw.startsWith('gs://')
              ? FirebaseStorage.instance.refFromURL(raw)
              : FirebaseStorage.instance.ref(raw);

      await ref.delete();
    } catch (e) {
      debugPrint('Erro ao excluir imagem do Storage: $raw -> $e');
    }
  }

  Future<void> _deleteProductImages(Map<String, dynamic> data) async {
    final paths = <String>{};

    void addList(dynamic value) {
      if (value is List) {
        for (final item in value) {
          final s = item?.toString().trim() ?? '';
          if (s.isNotEmpty) paths.add(s);
        }
      }
    }

    addList(data['fotos']);
    addList(data['fotosPendentes']);
    addList(data['fotosRecusadas']);

    final fotoUrl = (data['fotoUrl'] ?? '').toString().trim();
    if (fotoUrl.isNotEmpty) paths.add(fotoUrl);

    for (final path in paths) {
      await _deleteStorageFile(path);
    }
  }

  Future<void> _excluir(String id, String nome) async {
    if (!_requirePerm()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Excluir produto'),
            content: Text(
              'Deseja excluir "${nome.isEmpty ? 'produto' : nome}"?\n\n'
              'As fotos relacionadas também serão removidas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir'),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      final produtoRef = _fs.collection('produtos').doc(id);
      final produtoSnap = await produtoRef.get();

      if (produtoSnap.exists) {
        final data = produtoSnap.data() ?? {};
        await _deleteProductImages(data);
      }

      await produtoRef.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto e fotos excluídos com sucesso.'),
          ),
        );
      }

      await _refreshPlanRules();
    } catch (e, st) {
      debugPrint('❌ Erro ao excluir produto ($id): $e');
      debugPrint('$st');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
  }

  // -------- Queries por empresa ----------
  Query<Map<String, dynamic>> _baseQuery(String companyId) {
    return _fs
        .collection('produtos')
        .where('companyId', isEqualTo: companyId)
        .orderBy('nomeLower');
  }

  Query<Map<String, dynamic>> _query(String companyId) {
    final bq = _baseQuery(companyId);
    if (_q.isEmpty) return bq;
    final qLower = _q.toLowerCase();
    return bq.startAt([qLower]).endAt(['$qLower\uf8ff']);
  }

  // -------- Helpers: thumb --------
  Future<String?> _resolveThumb(Map<String, dynamic> m) async {
    // usa somente imagens aprovadas
    final fotos =
        (m['fotos'] as List?)
            ?.cast<dynamic>()
            .map((e) => e.toString())
            .where(
              (e) =>
                  e.contains('produtos/') ||
                  e.startsWith('http://') ||
                  e.startsWith('https://'),
            )
            .toList() ??
        const [];

    final raw =
        fotos.isNotEmpty ? fotos.first : (m['fotoUrl'] ?? '').toString();

    if (raw.isEmpty) return null;

    // url já pronta
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    try {
      final ref =
          raw.startsWith('gs://')
              ? FirebaseStorage.instance.refFromURL(raw)
              : FirebaseStorage.instance.ref(raw);

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Erro ao carregar thumb: $e');
      return null;
    }
  }

  Widget _buildPlanWarningCard(BuildContext context) {
    final planoAtual = PlanService.instance.planId.toUpperCase();
    final ilimitado = _productsLimit == -1;
    final restantes = ilimitado ? 999999 : (_productsLimit - _productsUsed);
    final atingiuLimite = !ilimitado && _productsUsed >= _productsLimit;
    final mostrarAviso = !ilimitado && restantes <= 5;

    if (!mostrarAviso) {
      return const SizedBox.shrink();
    }

    final accent = atingiuLimite ? ProdutoStyle.red : ProdutoStyle.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.20)),
        boxShadow: ProdutoStyle.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.workspace_premium_outlined, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Plano: $planoAtual',
                  style: const TextStyle(
                    color: ProdutoStyle.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_productsUsed / $_productsLimit',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            atingiuLimite
                ? 'Você atingiu o limite do seu plano para produtos.'
                : 'Faltam apenas $restantes produto(s) para atingir o limite do seu plano.',
            style: const TextStyle(
              color: ProdutoStyle.muted,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanosScreen()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: ProdutoStyle.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Fazer upgrade'),
          ),
          if (_planError != null) ...[
            const SizedBox(height: 8),
            Text(
              _planError!,
              style: const TextStyle(
                color: ProdutoStyle.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_loadingCompany) {
      return const Scaffold(
        backgroundColor: ProdutoStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: ProdutoStyle.bg,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_uid == null) {
      return Scaffold(
        backgroundColor: ProdutoStyle.bg,
        body: Column(
          children: [
            _buildHeader(),
            const Expanded(
              child: Center(child: Text('Faça login para ver seus produtos.')),
            ),
          ],
        ),
      );
    }

    if (_companyId == null) {
      return Scaffold(
        backgroundColor: ProdutoStyle.bg,
        body: Column(
          children: [
            _buildHeader(),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Seu usuário não possui uma empresa vinculada.\n'
                    'Configure o companyId no cadastro do usuário.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _requirePerm,
          backgroundColor: Colors.white,
          foregroundColor: ProdutoStyle.muted,
          icon: const Icon(Icons.add),
          label: const Text('Novo produto'),
        ),
      );
    }

    final fabEnabled =
        _canManageProducts &&
        !_loadingPlan &&
        (_canCreateByPlan || _productsLimit == -1);

    return Scaffold(
      backgroundColor: ProdutoStyle.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            _loadingPlan
                ? null
                : (fabEnabled
                    ? _novo
                    : () async {
                      if (!_requirePerm()) return;
                      await _requirePlanSlot();
                    }),
        backgroundColor: fabEnabled ? ProdutoStyle.primary : Colors.white,
        foregroundColor: fabEnabled ? Colors.white : ProdutoStyle.muted,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.add_rounded),
        label: Text(_loadingPlan ? 'Validando...' : 'Novo produto'),
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (_loadingPlan)
            const LinearProgressIndicator(
              color: ProdutoStyle.orange,
              backgroundColor: Color(0xFFEDE9FE),
            ),
          if (!_loadingPlan) _buildPlanWarningCard(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query(_companyId!).snapshots().handleError((e, st) {
                debugPrint('❌ Firestore stream error (produtos): $e');
                debugPrint('$st');
              }),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  debugPrint('❌ snap.hasError em produtos: ${snap.error}');
                  if (snap.stackTrace != null) debugPrint('${snap.stackTrace}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Erro ao carregar: ${snap.error}'),
                    ),
                  );
                }

                var docs = snap.data?.docs ?? [];

                if (_q.isNotEmpty) {
                  final qLower = _q.toLowerCase();
                  docs =
                      docs.where((d) {
                        final m = d.data();
                        final nome =
                            (m['nomeLower'] ?? m['nome'] ?? '')
                                .toString()
                                .toLowerCase();
                        return nome.contains(qLower);
                      }).toList();
                }

                if (docs.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshPlanRules,
                    color: ProdutoStyle.primary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: ProdutoStyle.softShadow,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: ProdutoStyle.primary
                                              .withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 36,
                                          color: ProdutoStyle.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        _q.isEmpty
                                            ? 'Nenhum produto cadastrado'
                                            : 'Nenhum resultado para “$_q”.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: ProdutoStyle.text,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Cadastre seus produtos para controlar estoque, preços e vendas.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: ProdutoStyle.muted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      FilledButton.icon(
                                        onPressed:
                                            _loadingPlan
                                                ? null
                                                : (fabEnabled
                                                    ? _novo
                                                    : () async {
                                                      if (!_requirePerm())
                                                        return;
                                                      await _requirePlanSlot();
                                                    }),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: ProdutoStyle.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: const Text(
                                          'Cadastrar primeiro produto',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshPlanRules,
                  color: ProdutoStyle.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final m = doc.data();
                      final nome = (m['nome'] ?? '').toString();
                      final estoqueStr = (m['estoque'] ?? 0).toString();
                      final preco =
                          (m['precoUnitario'] ?? m['valorVenda'] ?? 0);

                      return _buildProdutoCard(
                        docId: doc.id,
                        data: m,
                        nome: nome,
                        estoqueStr: estoqueStr,
                        preco: preco,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: ProdutoStyle.headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Produtos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: Icons.refresh_rounded,
                onTap: _refreshPlanRules,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: ProdutoStyle.softShadow,
            ),
            child: TextField(
              controller: _buscaCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar produto por nome',
                hintStyle: const TextStyle(color: ProdutoStyle.muted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: ProdutoStyle.primary,
                ),
                suffixIcon:
                    _q.isEmpty
                        ? null
                        : IconButton(
                          onPressed: () {
                            _buscaCtrl.clear();
                            FocusScope.of(context).unfocus();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProdutoCard({
    required String docId,
    required Map<String, dynamic> data,
    required String nome,
    required String estoqueStr,
    required dynamic preco,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ProdutoStyle.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _canManageProducts ? _editar(docId) : _requirePerm(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: FutureBuilder<String?>(
                      future: _resolveThumb(data),
                      builder: (ctx, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return Container(
                            color: const Color(0xFFF1F5F9),
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ProdutoStyle.primary,
                              ),
                            ),
                          );
                        }

                        final url = snap.data;
                        if (url == null || url.isEmpty) {
                          return Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: ProdutoStyle.muted,
                            ),
                          );
                        }

                        return Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => Container(
                                color: const Color(0xFFF1F5F9),
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: ProdutoStyle.muted,
                                ),
                              ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome.isNotEmpty ? nome : 'Sem nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ProdutoStyle.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _InfoPill(
                            icon: Icons.inventory_2_outlined,
                            text: 'Estoque: $estoqueStr',
                            color: ProdutoStyle.primary,
                          ),
                          _InfoPill(
                            icon: Icons.sell_outlined,
                            text: _fmtMoeda(preco),
                            color: ProdutoStyle.orange,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opções',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: ProdutoStyle.muted,
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'editar':
                        _editar(docId);
                        break;
                      case 'excluir':
                        _excluir(docId, nome);
                        break;
                    }
                  },
                  itemBuilder:
                      (_) => [
                        PopupMenuItem(
                          value: 'editar',
                          enabled: _canManageProducts,
                          child: const Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('Alterar'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'excluir',
                          enabled: _canManageProducts,
                          child: const Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: ProdutoStyle.red,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Excluir',
                                style: TextStyle(color: ProdutoStyle.red),
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

  String _fmtMoeda(dynamic v) {
    final n =
        (v is num) ? v : num.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
    return 'R\$ ${n.toStringAsFixed(2)}';
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
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: ProdutoStyle.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
