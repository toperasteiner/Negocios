import '../Planos/PlanService.dart';
// lib/Cadastros/CadastroProdutoScreen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../Seletores/SelecionarCategoriaSheet.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

class CadastroProdutoScreen extends StatefulWidget {
  final String? produtoId;
  const CadastroProdutoScreen({super.key, this.produtoId});

  @override
  State<CadastroProdutoScreen> createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();

  // Campos
  final _nomeCtrl = TextEditingController();
  final _detalhesCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _codBarrasCtrl = TextEditingController();
  final _codInternoCtrl = TextEditingController();

  final _estoqueCtrl = TextEditingController(); // quantidade em estoque
  final _estoqueAlertaCtrl = TextEditingController(); // alerta
  final _custoCtrl = TextEditingController();
  final _valorVendaCtrl = TextEditingController();

  String _unidade = 'UN';
  bool _controlaEstoque = true; // flag
  String _currentPlan = 'free';

  int get _maxFotosProduto {
    return _currentPlan == 'premium' ? 3 : 1;
  }

  // Fotos
  final List<String> _fotoUrls = [];
  final List<XFile> _novasImagens = [];

  bool _carregando = false;
  bool _inicializando = true;
  bool _dirty = false;

  String? get _uid => _auth.currentUser?.uid;
  String? _categoriaId;
  String? _categoriaNome;

  static const Map<String, String> _unidadesDesc = {
    'UN': 'Unidade',
    'PÇ': 'Peça',
    'CX': 'Caixa',
    'DZ': 'Dúzia',
    'KIT': 'Kit / Conjunto',
    'PAR': 'Par',
    'KG': 'Quilograma',
    'G': 'Grama',
    'MG': 'Miligrama',
    'L': 'Litro',
    'ML': 'Mililitro',
    'M': 'Metro',
    'CM': 'Centímetro',
    'MM': 'Milímetro',
    'M²': 'Metro quadrado',
    'M³': 'Metro cúbico',
  };

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    setState(() {
      _currentPlan = service.isLoaded ? service.planId : 'free';
    });
  }

  Future<void> _loadPlanState() async {
    if (!mounted) return;
    try {
      if (!PlanService.instance.isLoaded) await PlanService.instance.load();
      _onPlanChanged();
    } catch (e) {
      debugPrint('Plan refresh failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlanState());
    _carregar();

    for (final c in [
      _nomeCtrl,
      _detalhesCtrl,
      _marcaCtrl,
      _codBarrasCtrl,
      _codInternoCtrl,
      _estoqueCtrl,
      _estoqueAlertaCtrl,
      _custoCtrl,
      _valorVendaCtrl,
    ]) {
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
        _recalc();
      });
    }
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _nomeCtrl.dispose();
    _detalhesCtrl.dispose();
    _marcaCtrl.dispose();
    _codBarrasCtrl.dispose();
    _codInternoCtrl.dispose();
    _estoqueCtrl.dispose();
    _estoqueAlertaCtrl.dispose();
    _custoCtrl.dispose();
    _valorVendaCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Helpers de usuário / permissões (única fonte de verdade)
  // ---------------------------------------------------------------

  Future<
    ({Map<String, dynamic> data, DocumentReference<Map<String, dynamic>>? ref})
  >
  _getUserDoc() async {
    final uid = _uid;
    if (uid == null) return (data: <String, dynamic>{}, ref: null);

    try {
      // 1) tenta por UID
      final byUidRef = _fs.collection('users').doc(uid);
      final byUidSnap = await byUidRef.get();
      if (byUidSnap.exists) {
        return (
          data: (byUidSnap.data() ?? {}) as Map<String, dynamic>,
          ref: byUidRef,
        );
      }

      // 2) tenta por email/emailKey
      final email = _auth.currentUser?.email?.trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) {
          final snap = q.docs.first;
          return (
            data: (snap.data() ?? {}) as Map<String, dynamic>,
            ref: snap.reference,
          );
        }
      }
    } catch (_) {}

    return (data: <String, dynamic>{}, ref: null);
  }

  bool _hasPermission(Map<String, dynamic> d, String key) {
    final perms = (d['permissions'] ?? {}) as Map<String, dynamic>;
    final dynamic fromPerms = perms[key];
    final dynamic fromRoot = d[key];
    return (fromPerms == true) || (fromRoot == true);
  }

  /// Multiempresa estrito:
  /// - Exige companyId para qualquer criação (admin e funcionário)
  /// - funcionário precisa `canManageProducts`
  Future<(String?, String?)> _resolveOwnerAndCompany() async {
    final uid = _uid;
    if (uid == null) return (null, null);

    final u = await _getUserDoc();
    final d = u.data;
    if (d.isEmpty) return (null, null);

    final role = (d['role'] ?? '').toString().toLowerCase().trim();
    final companyId = (d['companyId'] ?? '').toString().trim();

    // 🔁 multiempresa: companyId é obrigatório para cadastrar
    if (companyId.isEmpty) return (null, null);

    if (role == 'admin') {
      // ownerId pode ser o próprio companyId para manter consistência
      return (companyId, companyId);
    }
    if (role == 'funcionario') {
      return (companyId, companyId);
    }
    return (null, null);
  }

  Future<bool> _temPermissaoCriarProduto() async {
    final uid = _uid;
    if (uid == null) return false;

    final u = await _getUserDoc();
    final d = u.data;
    if (d.isEmpty) return false;

    final role = (d['role'] ?? '').toString().toLowerCase().trim();
    final companyId = (d['companyId'] ?? '').toString().trim();

    // 🔁 exige companyId para qualquer perfil
    if (companyId.isEmpty) return false;

    if (role == 'admin') return true;
    if (role == 'funcionario') {
      return _hasPermission(d, 'canManageProducts');
    }
    return false;
  }
  // ---------------------------------------------------------------

  Future<void> _logCreateProduct({
    required String produtoId,
    required double valorVenda,
    required double custo,
    required bool controlaEstoque,
    required bool possuiCategoria,
  }) async {
    // ============================================================
    // FIREBASE ANALYTICS
    // ============================================================
    try {
      await _analytics.logEvent(
        name: 'create_product',
        parameters: {
          'produto_id': produtoId,
          'value': valorVenda,
          'currency': 'BRL',
          'cost': custo,
          'stock_control': controlaEstoque ? 1 : 0,
          'has_category': possuiCategoria ? 1 : 0,
        },
      );

      debugPrint('✅ Firebase: create_product enviado');
    } catch (e) {
      debugPrint('⚠️ Firebase: erro ao enviar create_product: $e');
    }

    // ============================================================
    // META / FACEBOOK APP EVENTS
    // ============================================================
    try {
      await _facebookAppEvents.logEvent(
        name: 'create_product',
        parameters: {
          'produto_id': produtoId,
          'value': valorVenda,
          'currency': 'BRL',
          'cost': custo,
          'stock_control': controlaEstoque ? 1 : 0,
          'has_category': possuiCategoria ? 1 : 0,
        },
      );

      // Durante o teste, deixe o flush para aparecer mais rápido na Meta.
      await _facebookAppEvents.flush();

      debugPrint(
        '✅ Meta: create_product enviado '
        'produto=$produtoId valor=$valorVenda',
      );
    } catch (e) {
      debugPrint('⚠️ Meta: erro ao enviar create_product: $e');
    }
  }

  Future<String> _resolveDownloadUrl(String raw) async {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    Reference ref =
        raw.startsWith('gs://')
            ? FirebaseStorage.instance.refFromURL(raw)
            : FirebaseStorage.instance.ref(raw);
    return await ref.getDownloadURL();
  }

  Future<void> _deleteFromStorage(String raw) async {
    try {
      final ref =
          raw.startsWith('http')
              ? FirebaseStorage.instance.refFromURL(raw)
              : FirebaseStorage.instance.ref(raw);
      await ref.delete();
    } catch (_) {}
  }

  Future<void> _carregar() async {
    final u = await _getUserDoc();
    final planId = (u.data['planId'] ?? 'free').toString().trim().toLowerCase();

    _currentPlan =
        PlanService.instance.isLoaded
            ? PlanService.instance.planId
            : (planId.isEmpty ? 'free' : planId);
    if (widget.produtoId == null) {
      setState(() => _inicializando = false);
      return;
    }
    try {
      final doc = await _fs.collection('produtos').doc(widget.produtoId).get();
      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Produto não encontrado.')),
          );
          Navigator.pop(context);
        }
        return;
      }
      final d = doc.data() as Map<String, dynamic>;
      _nomeCtrl.text = (d['nome'] ?? '').toString();
      _detalhesCtrl.text = (d['detalhes'] ?? '').toString();
      _marcaCtrl.text = (d['marca'] ?? '').toString();
      _codBarrasCtrl.text = (d['codBarras'] ?? '').toString();
      _codInternoCtrl.text = (d['codInterno'] ?? '').toString();
      _unidade = (d['unidade'] ?? 'UN').toString();
      _controlaEstoque = (d['controlaEstoque'] as bool?) ?? true;

      _estoqueCtrl.text = _fmtCampo(d['estoque']);
      _estoqueAlertaCtrl.text = _fmtCampo(d['estoqueAlerta']);
      _custoCtrl.text = _fmtCampo(d['custo']);
      _valorVendaCtrl.text = _fmtCampo(d['valorVenda']);
      _categoriaId =
          (d['categoriaId'] ?? '').toString().trim().isEmpty
              ? null
              : (d['categoriaId'] ?? '').toString();

      _categoriaNome =
          (d['categoriaNome'] ?? '').toString().trim().isEmpty
              ? null
              : (d['categoriaNome'] ?? '').toString();

      final fotos =
          (d['fotos'] as List?)
              ?.cast<dynamic>()
              .map((e) => e.toString())
              .toList() ??
          [];
      if (fotos.isNotEmpty) {
        _fotoUrls.addAll(fotos.take(_maxFotosProduto));
      } else {
        final unica = (d['fotoUrl'] ?? '').toString();
        if (unica.isNotEmpty) _fotoUrls.add(unica);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _inicializando = false);
    }
  }

  String _fmtCampo(dynamic v) {
    if (v == null) return '';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    return n.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  double _parseNumero(String s) {
    final x = s.trim().replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  double get _custo => _parseMoeda(_custoCtrl.text);
  double get _venda => _parseMoeda(_valorVendaCtrl.text);
  double get _lucro => (_venda - _custo);
  double get _margem => _venda <= 0 ? 0 : _lucro / _venda;
  double get _markup => _custo <= 0 ? 0 : (_venda - _custo) / _custo;
  void _recalc() => setState(() {});

  Future<void> _removerImagemExistente(int index) async {
    final alvo = _fotoUrls[index];
    setState(() => _carregando = true);
    try {
      await _deleteFromStorage(alvo);
      if (widget.produtoId != null) {
        await _fs.collection('produtos').doc(widget.produtoId).update({
          'fotos': FieldValue.arrayRemove([alvo]),
        });
      }
      setState(() {
        _fotoUrls.removeAt(index);
        _dirty = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Imagem removida.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao remover imagem: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _selecionarCategoria() async {
    final result = await showModalBottomSheet<CategoriaSelecionada>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const SelecionarCategoriaSheet(tipo: 'produto'),
    );

    if (result == null) return;

    setState(() {
      _categoriaId = result.id;
      _categoriaNome = result.nome;
      _dirty = true;
    });
  }

  Future<void> _selecionarImagens() async {
    final vagas = _maxFotosProduto - (_fotoUrls.length + _novasImagens.length);
    if (vagas <= 0) return;

    if (kIsWeb) {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: _maxFotosProduto > 1,
        withData: true,
      );
      if (res == null || res.files.isEmpty || res.files.first.bytes == null)
        return;
      final arquivos =
          res.files.where((f) => f.bytes != null).take(vagas).toList();

      setState(() {
        for (final f in arquivos) {
          final mime = lookupMimeType(f.name) ?? 'image/jpeg';
          _novasImagens.add(
            XFile.fromData(f.bytes!, name: f.name, mimeType: mime),
          );
        }
        _dirty = true;
      });
      return;
    }

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (x == null) return;
    setState(() {
      _novasImagens
        ..clear()
        ..add(x);
      _dirty = true;
    });
  }

  void _removerImagemNova(int index) {
    setState(() {
      _novasImagens.removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _salvar() async {
    if (_uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login para salvar.')));
      return;
    }

    // 🔒 Multiempresa + permissão
    if (!await _temPermissaoCriarProduto()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para cadastrar produtos.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifique os campos obrigatórios.')),
      );
      return;
    }

    setState(() => _carregando = true);

    try {
      final dados = <String, dynamic>{
        'nome': _nomeCtrl.text.trim(),
        'nomeLower': _nomeCtrl.text.trim().toLowerCase(),
        'detalhes':
            _detalhesCtrl.text.trim().isEmpty
                ? null
                : _detalhesCtrl.text.trim(),
        'categoriaId': _categoriaId,
        'categoriaNome': _categoriaNome,
        'unidade': _unidade,

        // Estoque
        'controlaEstoque': _controlaEstoque,
        'estoque': _controlaEstoque ? _parseNumero(_estoqueCtrl.text) : null,
        'estoqueAlerta':
            _controlaEstoque ? _parseNumero(_estoqueAlertaCtrl.text) : null,

        // Preços
        'custo': _custo,
        'valorVenda': _venda,

        'marca': _marcaCtrl.text.trim().isEmpty ? null : _marcaCtrl.text.trim(),
        'codBarras':
            _codBarrasCtrl.text.trim().isEmpty
                ? null
                : _codBarrasCtrl.text.trim(),
        'codInterno':
            _codInternoCtrl.text.trim().isEmpty
                ? null
                : _codInternoCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final bool isNovoProduto = widget.produtoId == null;

      String docId = widget.produtoId ?? '';

      if (isNovoProduto) {
        // 🔁 multiempresa estrito: companyId é obrigatório
        final (ownerId, companyId) = await _resolveOwnerAndCompany();
        if (ownerId == null || companyId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sem empresa vinculada: configure o companyId no cadastro do usuário.',
                ),
              ),
            );
          }
          setState(() => _carregando = false);
          return;
        }

        final ref = await _fs.collection('produtos').add({
          ...dados,
          'ownerId': ownerId,
          'companyId': companyId, // 🔁 chave de escopo multiempresa
          'createdByUid': _uid,
          'userId': _uid, // ✅ SEMPRE o UID de quem cria
          'fotos': _fotoUrls,
          'createdAt': FieldValue.serverTimestamp(),
        });
        docId = ref.id;
      } else {
        await _fs.collection('produtos').doc(widget.produtoId).update(dados);
      }

      // upload de novas imagens (mantido)
      if (_novasImagens.isNotEmpty) {
        final baseTs = DateTime.now().microsecondsSinceEpoch;
        final novosUrls = <String>[];
        for (var i = 0; i < _novasImagens.length; i++) {
          final img = _novasImagens[i];
          final ts = baseTs + i;
          final path = 'produtos_pendentes/${_uid}/${docId}_$ts.jpg';
          final ref = _storage.ref().child(path);
          if (kIsWeb) {
            final bytes = await img.readAsBytes();
            final mime =
                img.mimeType ?? lookupMimeType(img.name) ?? 'image/jpeg';
            await ref.putData(bytes, SettableMetadata(contentType: mime));
          } else {
            final file = File(img.path);
            final mime = lookupMimeType(img.path) ?? 'image/jpeg';
            await ref.putFile(file, SettableMetadata(contentType: mime));
          }
          novosUrls.add(ref.fullPath);
        }
        final finalUrls =
            [..._fotoUrls, ...novosUrls].take(_maxFotosProduto).toList();
        await _fs.collection('produtos').doc(docId).update({
          'fotosPendentes': FieldValue.arrayUnion(novosUrls),
          'imagemStatus': 'pendente',
          'imagemAprovada': false,
          'imagemModeracaoPendenteEm': FieldValue.serverTimestamp(),
        });
        _fotoUrls
          ..clear()
          ..addAll(finalUrls);
        _novasImagens.clear();
      }

      if (isNovoProduto) {
        await _logCreateProduct(
          produtoId: docId,
          valorVenda: _venda,
          custo: _custo,
          controlaEstoque: _controlaEstoque,
          possuiCategoria: _categoriaId != null,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.produtoId == null
                  ? 'Produto cadastrado com sucesso.'
                  : 'Produto atualizado com sucesso.',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String? _validaNome(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o nome';
    if (s.length < 2) return 'Nome muito curto';
    return null;
  }

  String? _validaNumero(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Campo obrigatório';
    final n = _parseMoeda(s);
    if (n < 0) return 'Valor inválido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_inicializando) {
      return const Scaffold(
        backgroundColor: _ProdutoVisual.bg,
        body: Center(
          child: CircularProgressIndicator(color: _ProdutoVisual.primary),
        ),
      );
    }

    final isNovo = widget.produtoId == null;

    return WillPopScope(
      onWillPop: () async {
        if (!_dirty) return true;
        final sair = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                title: const Text(
                  'Descartar alterações?',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                content: const Text('Você tem alterações não salvas.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _ProdutoVisual.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sair'),
                  ),
                ],
              ),
        );
        return sair ?? false;
      },
      child: Scaffold(
        backgroundColor: _ProdutoVisual.bg,
        bottomNavigationBar: _BottomActions(
          carregando: _carregando,
          isNovo: isNovo,
          onVoltar: () => Navigator.pop(context),
          onSalvar: _salvar,
        ),
        body: AbsorbPointer(
          absorbing: _carregando,
          child: Column(
            children: [
              _ProdutoHeader(
                titulo: isNovo ? 'Novo produto' : 'Editar produto',
                subtitulo:
                    isNovo
                        ? 'Cadastre seu produto de forma simples e organizada.'
                        : 'Atualize as informações do produto.',
                onBack: () async {
                  if (!_dirty) {
                    Navigator.pop(context);
                    return;
                  }
                  final sair = await showDialog<bool>(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          title: const Text(
                            'Descartar alterações?',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          content: const Text(
                            'Você tem alterações não salvas.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _ProdutoVisual.primary,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Sair'),
                            ),
                          ],
                        ),
                  );
                  if (sair == true && mounted) Navigator.pop(context);
                },
                onSalvar: _carregando ? null : _salvar,
              ),
              if (_carregando)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: _ProdutoVisual.orange,
                  backgroundColor: Color(0xFFE9E2FA),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                  children: [
                    _FotosGrid(
                      urls: _fotoUrls,
                      novas: _novasImagens,
                      onAdd: _selecionarImagens,
                      onRemoveExistente: _removerImagemExistente,
                      onRemoveNova: _removerImagemNova,
                      maxFotos: _maxFotosProduto,
                    ),
                    const SizedBox(height: 14),

                    _SectionCard(
                      title: 'Identificação',
                      subtitle: 'Informações principais do produto',
                      icon: Icons.inventory_2_outlined,
                      color: _ProdutoVisual.primary,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _field(
                              controller: _nomeCtrl,
                              label: 'Nome *',
                              hint: 'Ex.: Coca-Cola Lata 350ml',
                              validator: _validaNome,
                              textInputAction: TextInputAction.next,
                              prefixIcon: Icons.label_outline,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              controller: _detalhesCtrl,
                              label: 'Detalhes do produto',
                              hint: 'Observações, descrição, composição…',
                              maxLines: 3,
                              prefixIcon: Icons.description_outlined,
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _selecionarCategoria,
                              child: InputDecorator(
                                decoration: _inputDecoration(
                                  label: 'Categoria',
                                  helper: 'Opcional',
                                  prefixIcon: Icons.category_outlined,
                                  suffixIcon:
                                      _categoriaId == null
                                          ? const Icon(
                                            Icons.search_rounded,
                                            color: _ProdutoVisual.primary,
                                          )
                                          : IconButton(
                                            tooltip: 'Remover categoria',
                                            icon: const Icon(Icons.close),
                                            onPressed: () {
                                              setState(() {
                                                _categoriaId = null;
                                                _categoriaNome = null;
                                                _dirty = true;
                                              });
                                            },
                                          ),
                                ),
                                child: Text(
                                  _categoriaNome == null ||
                                          _categoriaNome!.isEmpty
                                      ? 'Selecionar categoria'
                                      : _categoriaNome!,
                                  style: TextStyle(
                                    color:
                                        _categoriaNome == null ||
                                                _categoriaNome!.isEmpty
                                            ? _ProdutoVisual.muted
                                            : _ProdutoVisual.text,
                                    fontWeight:
                                        _categoriaNome == null ||
                                                _categoriaNome!.isEmpty
                                            ? FontWeight.w500
                                            : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _field(
                              controller: _marcaCtrl,
                              label: 'Marca',
                              hint: 'Ex.: Nestlé',
                              prefixIcon: Icons.local_offer_outlined,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              controller: _codInternoCtrl,
                              label: 'Código interno',
                              hint: 'SKU, referência…',
                              prefixIcon: Icons.qr_code_2_outlined,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              controller: _codBarrasCtrl,
                              label: 'Código de barras',
                              hint: 'EAN/UPC',
                              keyboardType: TextInputType.number,
                              prefixIcon: Icons.qr_code_scanner_outlined,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    _SectionCard(
                      title: 'Estoque',
                      subtitle: 'Defina unidade, saldo e nível de alerta',
                      icon: Icons.inventory_outlined,
                      color: _ProdutoVisual.green,
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _unidade,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              label: 'Unidade de medida *',
                              prefixIcon: Icons.straighten_outlined,
                            ),
                            items:
                                _unidadesDesc.entries.map((e) {
                                  return DropdownMenuItem(
                                    value: e.key,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.key,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          e.value,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: _ProdutoVisual.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            selectedItemBuilder: (ctx) {
                              final keys = _unidadesDesc.keys.toList();
                              return keys.map((k) {
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '$k — ${_unidadesDesc[k]}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _ProdutoVisual.text,
                                    ),
                                  ),
                                );
                              }).toList();
                            },
                            onChanged:
                                (v) => setState(() {
                                  _unidade = v ?? 'UN';
                                  _dirty = true;
                                }),
                          ),
                          const SizedBox(height: 12),
                          _StockSwitchCard(
                            value: _controlaEstoque,
                            onChanged: (v) {
                              setState(() {
                                _controlaEstoque = v;
                                if (!v) {
                                  _estoqueCtrl.clear();
                                  _estoqueAlertaCtrl.clear();
                                }
                                _dirty = true;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _field(
                                  controller: _estoqueCtrl,
                                  label: 'Estoque *',
                                  hint: _controlaEstoque ? '0' : '—',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d,\.]'),
                                    ),
                                  ],
                                  validator:
                                      _controlaEstoque ? _validaNumero : null,
                                  prefixIcon: Icons.inventory_2_outlined,
                                  enabled: _controlaEstoque,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  controller: _estoqueAlertaCtrl,
                                  label: 'Estoque alerta',
                                  hint: _controlaEstoque ? 'Ex.: 5' : '—',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d,\.]'),
                                    ),
                                  ],
                                  prefixIcon:
                                      Icons.notification_important_outlined,
                                  enabled: _controlaEstoque,
                                ),
                              ),
                            ],
                          ),
                          if (_controlaEstoque) ...[
                            const SizedBox(height: 10),
                            const _HintBox(
                              icon: Icons.notifications_active_outlined,
                              text:
                                  'O estoque alerta avisa quando a quantidade atingir ou ficar abaixo do nível definido.',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    _SectionCard(
                      title: 'Preços',
                      subtitle: 'Informe custo e valor de venda',
                      icon: Icons.payments_outlined,
                      color: _ProdutoVisual.orange,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _field(
                                  controller: _custoCtrl,
                                  label: 'Custo *',
                                  hint: '0,00',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d,\. ,]'),
                                    ),
                                  ],
                                  validator: _validaNumero,
                                  prefixIcon: Icons.request_page_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  controller: _valorVendaCtrl,
                                  label: 'Venda *',
                                  hint: '0,00',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d,\. ,]'),
                                    ),
                                  ],
                                  validator: _validaNumero,
                                  prefixIcon: Icons.sell_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _ResumoPreco(
                            custo: _custo,
                            venda: _venda,
                            lucro: _lucro,
                            margem: _margem,
                            markup: _markup,
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
      ),
    );
  }

  InputDecoration _inputDecoration({
    String? label,
    String? hint,
    String? helper,
    IconData? prefixIcon,
    Widget? suffixIcon,
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      filled: true,
      fillColor: enabled ? _ProdutoVisual.fieldBg : const Color(0xFFF1F2F5),
      prefixIcon:
          prefixIcon == null
              ? null
              : Icon(prefixIcon, color: _ProdutoVisual.primary, size: 21),
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _ProdutoVisual.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _ProdutoVisual.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _ProdutoVisual.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _ProdutoVisual.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _ProdutoVisual.red, width: 1.5),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    String? label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    IconData? prefixIcon,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      enabled: enabled,
      style: const TextStyle(
        color: _ProdutoVisual.text,
        fontWeight: FontWeight.w600,
      ),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        prefixIcon: prefixIcon,
        enabled: enabled,
        suffixIcon:
            (!enabled || controller.text.isEmpty)
                ? null
                : IconButton(
                  tooltip: 'Limpar',
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
      ),
      onChanged: (_) => setState(() => _dirty = true),
    );
  }
}

class _ProdutoVisual {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFFF6A00);
  static const Color green = Color(0xFF16A34A);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF5F6FA);
  static const Color fieldBg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get shadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.055),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

class _ProdutoHeader extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final VoidCallback onBack;
  final VoidCallback? onSalvar;

  const _ProdutoHeader({
    required this.titulo,
    required this.subtitulo,
    required this.onBack,
    required this.onSalvar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: _ProdutoVisual.gradient,
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
              _HeaderButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              Expanded(
                child: Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              _HeaderButton(icon: Icons.check_rounded, onTap: onSalvar),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(onTap == null ? 0.08 : 0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: Colors.white.withOpacity(onTap == null ? 0.45 : 1),
          ),
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final bool carregando;
  final bool isNovo;
  final VoidCallback onVoltar;
  final VoidCallback onSalvar;

  const _BottomActions({
    required this.carregando,
    required this.isNovo,
    required this.onVoltar,
    required this.onSalvar,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: carregando ? null : onVoltar,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Voltar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ProdutoVisual.primary,
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: Color(0xFFD8C8F5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: carregando ? null : _ProdutoVisual.gradient,
                  color: carregando ? const Color(0xFFE5E7EB) : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow:
                      carregando
                          ? null
                          : [
                            BoxShadow(
                              color: _ProdutoVisual.primary.withOpacity(0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                ),
                child: FilledButton.icon(
                  onPressed: carregando ? null : onSalvar,
                  icon:
                      carregando
                          ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _ProdutoVisual.primary,
                            ),
                          )
                          : const Icon(Icons.save_outlined),
                  label: Text(isNovo ? 'Salvar produto' : 'Atualizar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: _ProdutoVisual.muted,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _ProdutoVisual.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ProdutoVisual.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _ProdutoVisual.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _IconBadge({required this.icon, required this.color, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class _StockSwitchCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _StockSwitchCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: value ? const Color(0xFFF3FCF6) : _ProdutoVisual.fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? const Color(0xFFBCE8C8) : _ProdutoVisual.border,
        ),
      ),
      child: Row(
        children: [
          _IconBadge(
            icon: value ? Icons.inventory_2_outlined : Icons.block_outlined,
            color: value ? _ProdutoVisual.green : _ProdutoVisual.muted,
            size: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Controlar estoque',
                  style: TextStyle(
                    color: _ProdutoVisual.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Entradas e saídas serão consideradas no saldo.'
                      : 'A quantidade do produto não será controlada.',
                  style: const TextStyle(
                    color: _ProdutoVisual.muted,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: _ProdutoVisual.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _HintBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HintBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _ProdutoVisual.orange, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoPreco extends StatelessWidget {
  final double custo;
  final double venda;
  final double lucro;
  final double margem;
  final double markup;

  const _ResumoPreco({
    required this.custo,
    required this.venda,
    required this.lucro,
    required this.margem,
    required this.markup,
  });

  @override
  Widget build(BuildContext context) {
    final lucroPositivo = lucro >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _ProdutoVisual.primary.withOpacity(0.08),
            _ProdutoVisual.orange.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DDF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.insights_outlined,
                color: _ProdutoVisual.primary,
                size: 19,
              ),
              SizedBox(width: 7),
              Text(
                'Resumo de preços',
                style: TextStyle(
                  color: _ProdutoVisual.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PriceMetric(
                  label: 'Custo',
                  value: _fmt(custo),
                  color: _ProdutoVisual.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PriceMetric(
                  label: 'Venda',
                  value: _fmt(venda),
                  color: _ProdutoVisual.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PriceMetric(
                  label: 'Lucro',
                  value: _fmt(lucro),
                  color:
                      lucroPositivo ? _ProdutoVisual.green : _ProdutoVisual.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PriceMetric(
                  label: 'Margem',
                  value: _pct(margem),
                  color: _ProdutoVisual.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PriceMetric(
                  label: 'Markup',
                  value: _pct(markup),
                  color: _ProdutoVisual.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      'R\$ ${v.isFinite ? v.toStringAsFixed(2).replaceAll('.', ',') : '—'}';

  static String _pct(double v) =>
      v.isFinite ? '${(v * 100).toStringAsFixed(0)}%' : '—';
}

class _PriceMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PriceMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _ProdutoVisual.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FotosGrid extends StatelessWidget {
  final List<String> urls;
  final List<XFile> novas;
  final VoidCallback onAdd;
  final void Function(int index) onRemoveExistente;
  final void Function(int index) onRemoveNova;
  final int maxFotos;

  const _FotosGrid({
    required this.urls,
    required this.novas,
    required this.onAdd,
    required this.onRemoveExistente,
    required this.onRemoveNova,
    this.maxFotos = 1,
  });

  @override
  Widget build(BuildContext context) {
    final itens = <Widget>[];

    for (var i = 0; i < urls.length; i++) {
      itens.add(
        _FotoTile(
          child: FutureBuilder<String>(
            future: (context
                    .findAncestorStateOfType<_CadastroProdutoScreenState>())
                ?._resolveDownloadUrl(urls[i]),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done ||
                  !snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _ProdutoVisual.primary,
                  ),
                );
              }
              return Image.network(
                snap.data!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder:
                    (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 32),
                    ),
              );
            },
          ),
          onRemove: () => onRemoveExistente(i),
        ),
      );
    }

    for (var i = 0; i < novas.length; i++) {
      final x = novas[i];
      final Widget img =
          kIsWeb
              ? FutureBuilder<Uint8List>(
                future: x.readAsBytes(),
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Icon(Icons.image_outlined, size: 32);
                  }
                  return Image.memory(snap.data!, fit: BoxFit.cover);
                },
              )
              : Image.file(File(x.path), fit: BoxFit.cover);
      itens.add(_FotoTile(child: img, onRemove: () => onRemoveNova(i)));
    }

    final total = urls.length + novas.length;
    final vagas = maxFotos - total;
    if (vagas > 0) itens.add(_AddTile(onTap: onAdd, vagas: vagas));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _ProdutoVisual.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(
                icon: Icons.photo_library_outlined,
                color: _ProdutoVisual.primary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fotos do produto',
                      style: TextStyle(
                        color: _ProdutoVisual.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Adicione até $maxFotos foto${maxFotos > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: _ProdutoVisual.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EAFE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$total/$maxFotos',
                  style: const TextStyle(
                    color: _ProdutoVisual.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: itens,
          ),
        ],
      ),
    );
  }
}

class _FotoTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;

  const _FotoTile({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(color: _ProdutoVisual.fieldBg, child: child),
          ),
        ),
        Positioned(
          right: 5,
          top: 5,
          child: Material(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  final int vagas;

  const _AddTile({required this.onTap, required this.vagas});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: DottedBorder(
        color: _ProdutoVisual.primary.withOpacity(0.45),
        strokeWidth: 1.5,
        dashPattern: const [6, 5],
        borderType: BorderType.RRect,
        radius: const Radius.circular(16),
        child: Container(
          color: const Color(0xFFFBF9FF),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0E8FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: _ProdutoVisual.primary,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Adicionar',
                style: TextStyle(
                  color: _ProdutoVisual.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$vagas vaga${vagas > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: _ProdutoVisual.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
