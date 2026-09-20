// lib/Pedidos/SelecionarProdutosSheet.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';

/* ------------------------------------------------------------------ */
/*  Modelo local                                                       */
/* ------------------------------------------------------------------ */

enum TipoPrecoProduto { venda, compra }

class LinhaItemPedido {
  final String? refId;
  final String nome;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final double custo;

  const LinhaItemPedido({
    required this.refId,
    required this.nome,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.custo,
  });

  double get total => quantidade * valorUnitario;
}

class _ProdutoCatalogo {
  final String id;
  final String nome;
  final String unidade;
  final double valorVenda;
  final double custo;
  final String? fotoUrl;
  final String? descricao;

  const _ProdutoCatalogo({
    required this.id,
    required this.nome,
    required this.unidade,
    required this.valorVenda,
    required this.custo,
    this.fotoUrl,
    this.descricao,
  });
}

class _NovoItemPedido {
  final String refId;
  final String nome;
  final String unidade;
  final double valorUnitario;
  final double custo;

  const _NovoItemPedido({
    required this.refId,
    required this.nome,
    required this.unidade,
    required this.valorUnitario,
    required this.custo,
  });
}

/* ------------------------------------------------------------------ */
/*  SHEET                                                              */
/* ------------------------------------------------------------------ */

class SelecionarProdutosSheet extends StatefulWidget {
  final TipoPrecoProduto tipoPreco;

  const SelecionarProdutosSheet({
    super.key,
    this.tipoPreco = TipoPrecoProduto.venda,
  });

  @override
  State<SelecionarProdutosSheet> createState() =>
      _SelecionarProdutosSheetState();
}

class _SelecionarProdutosSheetState extends State<SelecionarProdutosSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final _selecionados = <String, _ProdutoCatalogo>{};
  final _qtd = <String, double>{};

  final _cadKey = GlobalKey<_CadastrarProdutoTabState>();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  bool _loadingScope = true;
  String? _scopeError;

  bool _podeCadastrar = false;
  String? _motivoCadastroBloqueado;

  // ----- plano -----
  bool _loadingPlan = true;
  String? _planError;
  int _productsUsed = 0;
  int _productsLimit = -1;
  bool _canCreateByPlan = true;

  String? get _uid => _auth.currentUser?.uid;

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
    _tab = TabController(length: 2, vsync: this);

    _tab.addListener(() async {
      if (!_tab.indexIsChanging) {
        if (mounted) setState(() {});
        return;
      }

      final indoParaCadastrar = _tab.index == 1;
      if (!indoParaCadastrar) {
        if (mounted) setState(() {});
        return;
      }

      if (!_podeCadastrar) {
        _tab.index = 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sem permissão para cadastrar produtos.'),
            ),
          );
          setState(() {});
        }
        return;
      }

      if (_loadingPlan) {
        _tab.index = 0;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Validando plano...')));
          setState(() {});
        }
        return;
      }

      final ok = await _requirePlanSlot();
      if (!mounted) return;

      if (!ok) {
        _tab.index = 0;
      }

      setState(() {});
    });

    _initScope();
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Faça login para continuar.';
      });
      return;
    }

    try {
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();
      final perms = Map<String, dynamic>.from(me?['permissions'] ?? {});
      final canManageProducts = (perms['canManageProducts'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _podeCadastrar = canManageProducts;
        _motivoCadastroBloqueado =
            canManageProducts
                ? null
                : 'Você não tem permissão para cadastrar produtos.';
        _loadingScope = false;
        _scopeError =
            _companyId == null
                ? 'Usuário sem companyId vinculado. Associe uma empresa ao usuário.'
                : null;
      });

      await _refreshPlanRules();
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao resolver escopo: $e';
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) {
        return Map<String, dynamic>.from(byUid.data() ?? {});
      }
    } catch (_) {}

    final email = (u.email ?? '').toLowerCase().trim();
    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) {
          return Map<String, dynamic>.from(q.docs.first.data());
        }
      } catch (_) {}
    }

    return null;
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

  void _fecharComSelecionados() {
    final itens =
        _selecionados.values.map((p) {
          final q = _qtd[p.id] ?? 1;

          final valorUnitario =
              widget.tipoPreco == TipoPrecoProduto.compra
                  ? p.custo
                  : p.valorVenda;

          return LinhaItemPedido(
            refId: p.id,
            nome: p.nome,
            unidade: p.unidade,
            quantidade: q,
            valorUnitario: valorUnitario,
            custo: p.custo,
          );
        }).toList();

    Navigator.pop(context, itens);
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _tab.dispose();
    super.dispose();
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
            title: Text(
              widget.tipoPreco == TipoPrecoProduto.compra
                  ? 'Adicionar produto à compra'
                  : 'Adicionar produto ao pedido',
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _scopeError ?? 'Não foi possível determinar o escopo.',
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
          title: Text(
            widget.tipoPreco == TipoPrecoProduto.compra
                ? 'Adicionar produto à compra'
                : 'Adicionar produto ao pedido',
          ),
          bottom: TabBar(
            controller: _tab,
            tabs: [
              const Tab(icon: Icon(Icons.sell_outlined), text: 'Catálogo'),
              Tab(
                icon: Icon(
                  !_podeCadastrar || (!_loadingPlan && !_canCreateByPlan)
                      ? Icons.lock_outline
                      : Icons.add_circle_outline,
                ),
                text:
                    !_podeCadastrar
                        ? 'Cadastrar (bloqueado)'
                        : (!_loadingPlan && !_canCreateByPlan)
                        ? 'Cadastrar (limite)'
                        : 'Cadastrar produto',
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child:
                _tab.index == 0
                    ? FilledButton.icon(
                      onPressed:
                          _selecionados.isEmpty ? null : _fecharComSelecionados,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        _selecionados.isEmpty
                            ? 'Adicionar selecionados'
                            : 'Adicionar selecionados (${_selecionados.length})',
                      ),
                    )
                    : FilledButton.icon(
                      onPressed:
                          !_podeCadastrar
                              ? null
                              : (_loadingPlan
                                  ? null
                                  : ((_canCreateByPlan || _productsLimit == -1)
                                      ? () {
                                        final st = _cadKey.currentState;
                                        if (st == null || st._carregando)
                                          return;
                                        st._salvar();
                                      }
                                      : () async {
                                        await _requirePlanSlot();
                                      })),
                      icon:
                          (_cadKey.currentState?._carregando ?? false)
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.check_rounded),
                      label: Text(
                        !_podeCadastrar
                            ? 'Sem permissão para cadastrar'
                            : _loadingPlan
                            ? 'Validando plano...'
                            : (_canCreateByPlan || _productsLimit == -1)
                            ? 'Adicionar este produto'
                            : 'Limite do plano atingido',
                      ),
                    ),
          ),
        ),
        body: Column(
          children: [
            if (_loadingPlan) const LinearProgressIndicator(),
            if (_planError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _planError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _CatalogoProdutosTab(
                    companyId: companyId,
                    tipoPreco: widget.tipoPreco,
                    selecionados: _selecionados,
                    qtd: _qtd,
                    onChanged: () => setState(() {}),
                  ),
                  !_podeCadastrar
                      ? _AbaBloqueada(
                        motivo:
                            _motivoCadastroBloqueado ??
                            'Você não tem permissão para cadastrar produtos.',
                      )
                      : _CadastrarProdutoTab(
                        key: _cadKey,
                        companyId: companyId,
                        createdByUid: _uid,
                        requirePlanSlot: _requirePlanSlot,
                        onPlanRefreshed: _refreshPlanRules,
                        onCadastrado: (novo) {
                          Navigator.pop(context, [
                            LinhaItemPedido(
                              refId: novo.refId,
                              nome: novo.nome,
                              unidade: novo.unidade,
                              quantidade: 1,
                              valorUnitario: novo.valorUnitario,
                              custo: novo.custo,
                            ),
                          ]);
                        },
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  CATÁLOGO                                                           */
/* ------------------------------------------------------------------ */

class _CatalogoProdutosTab extends StatefulWidget {
  final String companyId;
  final TipoPrecoProduto tipoPreco;
  final Map<String, _ProdutoCatalogo> selecionados;
  final Map<String, double> qtd;
  final VoidCallback onChanged;

  const _CatalogoProdutosTab({
    required this.companyId,
    required this.tipoPreco,
    required this.selecionados,
    required this.qtd,
    required this.onChanged,
  });

  @override
  State<_CatalogoProdutosTab> createState() => _CatalogoProdutosTabState();
}

class _CatalogoProdutosTabState extends State<_CatalogoProdutosTab> {
  final _fs = FirebaseFirestore.instance;
  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _buscaCtrl.addListener(_onSearchChange);
  }

  void _onSearchChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final v = _buscaCtrl.text.trim().toLowerCase();
      if (mounted && v != _q) setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.removeListener(_onSearchChange);
    _buscaCtrl.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _query() {
    return _fs
        .collection('produtos')
        .where('companyId', isEqualTo: widget.companyId)
        .orderBy('nomeLower');
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar produto',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              filled: true,
              suffixIcon:
                  _q.isEmpty
                      ? null
                      : IconButton(
                        onPressed: () {
                          _buscaCtrl.clear();
                          FocusScope.of(context).unfocus();
                        },
                        icon: const Icon(Icons.close),
                      ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query().snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }

              var docs = snap.data?.docs ?? [];

              if (_q.isNotEmpty) {
                docs =
                    docs.where((d) {
                      final m = d.data();
                      final nome =
                          (m['nomeLower'] ?? m['nome'] ?? '')
                              .toString()
                              .toLowerCase();
                      final desc =
                          (m['descricao'] ?? '').toString().toLowerCase();
                      return nome.contains(_q) || desc.contains(_q);
                    }).toList();
              }

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum produto encontrado.'),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data();

                  final item = _ProdutoCatalogo(
                    id: d.id,
                    nome: (m['nome'] ?? '').toString(),
                    unidade: ((m['unidade'] ?? 'UN').toString()).trim(),
                    valorVenda: _toDouble(m['valorVenda'] ?? m['precoVenda']),
                    custo: _toDouble(m['custo'] ?? m['valorCusto']),
                    fotoUrl:
                        (m['fotoUrl'] ?? '').toString().trim().isEmpty
                            ? null
                            : (m['fotoUrl'] ?? '').toString().trim(),
                    descricao: (m['descricao'] ?? '').toString(),
                  );

                  final selecionado = widget.selecionados.containsKey(item.id);
                  final qtdAtual = widget.qtd[item.id] ?? 1;

                  final valorExibido =
                      widget.tipoPreco == TipoPrecoProduto.compra
                          ? item.custo
                          : item.valorVenda;

                  final labelValor =
                      widget.tipoPreco == TipoPrecoProduto.compra
                          ? 'Compra: ${_fmtMoeda(valorExibido)}'
                          : 'Venda: ${_fmtMoeda(valorExibido)}';

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ProdutoThumb(url: item.fotoUrl),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.nome.isEmpty ? 'Sem nome' : item.nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if ((item.descricao ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.descricao!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _chip(
                                      context,
                                      'Unidade: ${item.unidade}',
                                      Icons.straighten_outlined,
                                    ),
                                    _chip(
                                      context,
                                      labelValor,
                                      widget.tipoPreco ==
                                              TipoPrecoProduto.compra
                                          ? Icons
                                              .shopping_cart_checkout_outlined
                                          : Icons.sell_outlined,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity: const VisualDensity(
                                              horizontal: -4,
                                              vertical: -4,
                                            ),
                                            value: selecionado,
                                            onChanged: (v) {
                                              if (v == true) {
                                                widget.selecionados[item.id] =
                                                    item;
                                                widget.qtd[item.id] ??= 1;
                                              } else {
                                                widget.selecionados.remove(
                                                  item.id,
                                                );
                                                widget.qtd.remove(item.id);
                                              }
                                              widget.onChanged();
                                              setState(() {});
                                            },
                                          ),
                                          const SizedBox(width: 4),
                                          const Text('Selecionar'),
                                        ],
                                      ),
                                      _QtdStepper(
                                        value: qtdAtual,
                                        enabled: selecionado,
                                        onChanged: (v) {
                                          widget.qtd[item.id] = v;
                                          widget.onChanged();
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _chip(BuildContext ctx, String label, IconData icon) {
    final cs = Theme.of(ctx).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final inteiro = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${parts[1]}';
  }
}

/* ------------------------------------------------------------------ */
/*  CADASTRO                                                           */
/* ------------------------------------------------------------------ */

class _CadastrarProdutoTab extends StatefulWidget {
  final String companyId;
  final String? createdByUid;
  final Future<bool> Function() requirePlanSlot;
  final Future<void> Function() onPlanRefreshed;
  final void Function(_NovoItemPedido novo) onCadastrado;

  const _CadastrarProdutoTab({
    super.key,
    required this.companyId,
    required this.createdByUid,
    required this.requirePlanSlot,
    required this.onPlanRefreshed,
    required this.onCadastrado,
  });

  @override
  State<_CadastrarProdutoTab> createState() => _CadastrarProdutoTabState();
}

class _CadastrarProdutoTabState extends State<_CadastrarProdutoTab> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final _nomeCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _custoCtrl = TextEditingController();
  final _vendaCtrl = TextEditingController();
  final _estoqueCtrl = TextEditingController();

  String _unidade = 'UN';
  bool _ativo = true;
  bool _carregando = false;

  final List<_ArquivoLocal> _novasImagens = [];
  final ImagePicker _picker = ImagePicker();

  static const List<String> _unidades = [
    'UN',
    'CX',
    'PÇ',
    'KG',
    'G',
    'L',
    'ML',
    'M',
    'M²',
    'M³',
    'H',
    'KIT',
    'PAR',
    'DZ',
  ];

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descricaoCtrl.dispose();
    _codigoCtrl.dispose();
    _custoCtrl.dispose();
    _vendaCtrl.dispose();
    _estoqueCtrl.dispose();
    super.dispose();
  }

  double _parseNumero(String texto) {
    var s = texto.trim();
    s = s.replaceAll('.', '');
    s = s.replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }

  String? _validaObrigatorio(String? v, String label) {
    if ((v ?? '').trim().isEmpty) return 'Informe $label';
    return null;
  }

  Future<void> _adicionarImagemGaleria() async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;

        setState(() {
          for (final f in result.files) {
            if (f.bytes == null) continue;
            _novasImagens.add(
              _ArquivoLocal(
                nome: f.name,
                bytes: f.bytes!,
                mimeType: lookupMimeType(f.name) ?? 'image/jpeg',
              ),
            );
          }
        });
        return;
      }

      final imagens = await _picker.pickMultiImage(imageQuality: 85);
      if (imagens.isEmpty) return;

      final lista = <_ArquivoLocal>[];
      for (final x in imagens) {
        final file = File(x.path);
        final nome = x.name;
        final mime = lookupMimeType(x.path) ?? 'image/jpeg';
        lista.add(_ArquivoLocal(nome: nome, file: file, mimeType: mime));
      }

      if (!mounted) return;
      setState(() => _novasImagens.addAll(lista));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao selecionar imagem: $e')));
    }
  }

  Future<List<String>> _uploadImagens(String docId) async {
    final urls = <String>[];

    for (final arq in _novasImagens) {
      final ext = _extensaoPorMime(arq.mimeType);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_sanitize(arq.nome)}$ext';

      final ref = _storage
          .ref()
          .child('companies')
          .child(widget.companyId)
          .child('produtos')
          .child(docId)
          .child(fileName);

      final metadata = SettableMetadata(contentType: arq.mimeType);

      if (kIsWeb && arq.bytes != null) {
        await ref.putData(arq.bytes!, metadata);
      } else if (arq.file != null) {
        await ref.putFile(arq.file!, metadata);
      } else {
        continue;
      }

      final url = await ref.getDownloadURL();
      urls.add(url);
    }

    return urls;
  }

  String _sanitize(String nome) {
    return nome.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
  }

  String _extensaoPorMime(String mime) {
    if (mime.contains('png')) return '.png';
    if (mime.contains('webp')) return '.webp';
    return '.jpg';
  }

  Future<void> _salvar() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifique os campos obrigatórios.')),
      );
      return;
    }

    final okPlano = await widget.requirePlanSlot();
    if (!okPlano) return;

    setState(() => _carregando = true);

    try {
      final nome = _nomeCtrl.text.trim();
      final descricao = _descricaoCtrl.text.trim();
      final codigo = _codigoCtrl.text.trim();
      final custo = _parseNumero(_custoCtrl.text);
      final venda = _parseNumero(_vendaCtrl.text);
      final estoque = _parseNumero(_estoqueCtrl.text);

      final dados = <String, dynamic>{
        'companyId': widget.companyId,
        'userId': widget.companyId,
        'createdByUid': widget.createdByUid,
        'nome': nome,
        'nomeLower': nome.toLowerCase(),
        'descricao': descricao.isEmpty ? null : descricao,
        'codigo': codigo.isEmpty ? null : codigo,
        'unidade': _unidade,
        'ativo': _ativo,
        'custo': custo,
        'valorCusto': custo,
        'valorVenda': venda,
        'estoque': estoque,
        'estoqueAtual': estoque,
        'fotos': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final ref = await _fs.collection('produtos').add(dados);
      final docId = ref.id;

      String? fotoPrincipal;
      List<String> fotos = [];

      if (_novasImagens.isNotEmpty) {
        fotos = await _uploadImagens(docId);
        fotoPrincipal = fotos.isNotEmpty ? fotos.first : null;

        await _fs.collection('produtos').doc(docId).update({
          'fotos': fotos,
          'fotoUrl': fotoPrincipal,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await widget.onPlanRefreshed();

      widget.onCadastrado(
        _NovoItemPedido(
          refId: docId,
          nome: nome,
          unidade: _unidade,
          valorUnitario: venda,
          custo: custo,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar produto: $e')));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _carregando,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionCard(
            icon: Icons.inventory_2_outlined,
            title: 'Dados do produto',
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _field(
                    controller: _nomeCtrl,
                    label: 'Nome *',
                    validator: (v) => _validaObrigatorio(v, 'o nome'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _descricaoCtrl,
                    label: 'Descrição',
                    maxLines: 3,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _codigoCtrl,
                    label: 'Código',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _unidade,
                    items:
                        _unidades
                            .map(
                              (u) => DropdownMenuItem<String>(
                                value: u,
                                child: Text(u),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _unidade = v);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Unidade',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _ativo,
                    onChanged: (v) => setState(() => _ativo = v),
                    title: const Text('Produto ativo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.attach_money_outlined,
            title: 'Valores e estoque',
            child: Column(
              children: [
                _field(
                  controller: _custoCtrl,
                  label: 'Valor de custo',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
                  ],
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _vendaCtrl,
                  label: 'Valor de venda *',
                  validator: (v) => _validaObrigatorio(v, 'o valor de venda'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
                  ],
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _estoqueCtrl,
                  label: 'Estoque inicial',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.photo_library_outlined,
            title: 'Imagens',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _adicionarImagemGaleria,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Adicionar imagens'),
                    ),
                  ],
                ),
                if (_novasImagens.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _novasImagens.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final item = _novasImagens[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 92,
                                height: 92,
                                color: Colors.black12,
                                child: _ArquivoPreview(item: item),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: InkWell(
                                onTap: () {
                                  setState(() => _novasImagens.removeAt(i));
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  HELPERS UI                                                         */
/* ------------------------------------------------------------------ */

class _ProdutoThumb extends StatelessWidget {
  final String? url;

  const _ProdutoThumb({this.url});

  @override
  Widget build(BuildContext context) {
    final has = (url ?? '').trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 68,
        height: 68,
        color: Colors.black12,
        child:
            has
                ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2),
                )
                : const Icon(Icons.inventory_2),
      ),
    );
  }
}

class _QtdStepper extends StatelessWidget {
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _QtdStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String fmt(double v) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toStringAsFixed(2).replaceAll('.', ',');
    }

    Widget btn({required IconData icon, required VoidCallback? onTap}) {
      return SizedBox(
        width: 28,
        height: 28,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? Colors.black26 : null,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(
          icon: Icons.remove_circle_outline,
          onTap:
              !enabled
                  ? null
                  : () {
                    final double novo = value > 1.0 ? value - 1.0 : 1.0;
                    onChanged(novo);
                  },
        ),
        const SizedBox(width: 6),
        Text(fmt(value), style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        btn(
          icon: Icons.add_circle_outline,
          onTap: !enabled ? null : () => onChanged(value + 1.0),
        ),
      ],
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
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

/* ------------------------------------------------------------------ */
/*  ARQUIVOS                                                           */
/* ------------------------------------------------------------------ */

class _ArquivoLocal {
  final String nome;
  final File? file;
  final Uint8List? bytes;
  final String mimeType;

  const _ArquivoLocal({
    required this.nome,
    this.file,
    this.bytes,
    required this.mimeType,
  });
}

class _ArquivoPreview extends StatelessWidget {
  final _ArquivoLocal item;

  const _ArquivoPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && item.bytes != null) {
      return Image.memory(
        item.bytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
      );
    }

    if (item.file != null) {
      return Image.file(
        item.file!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
      );
    }

    return const Icon(Icons.image_not_supported);
  }
}
