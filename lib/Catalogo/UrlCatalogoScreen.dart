import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class UrlCatalogoScreen extends StatefulWidget {
  const UrlCatalogoScreen({super.key});

  @override
  State<UrlCatalogoScreen> createState() => _UrlCatalogoScreenState();
}

class _UrlCatalogoScreenState extends State<UrlCatalogoScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _slugCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _catalogoAtivo = true;

  String? _companyId;
  String? _erro;

  String get _baseUrl => 'https://projeto-pedidos-472813.web.app';

  String get _linkCatalogo {
    final slug = _slugCtrl.text.trim();
    if (slug.isEmpty) return _baseUrl;
    return '$_baseUrl/$slug';
  }

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _slugCtrl.dispose();
    super.dispose();
  }

  String _normalizarSlug(String value) {
    var slug = value.trim().toLowerCase();

    slug = slug
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c');

    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'-+'), '-');
    slug = slug.replaceAll(RegExp(r'^-|-$'), '');

    return slug;
  }

  Future<Map<String, dynamic>?> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final byUid = await _fs.collection('users').doc(user.uid).get();
    if (byUid.exists) return byUid.data();

    final emailKey = (user.email ?? '').trim().toLowerCase();
    if (emailKey.isNotEmpty) {
      final q =
          await _fs
              .collection('users')
              .where('emailKey', isEqualTo: emailKey)
              .limit(1)
              .get();

      if (q.docs.isNotEmpty) return q.docs.first.data();
    }

    return null;
  }

  Future<void> _carregarDados() async {
    try {
      final userData = await _loadUserData();
      final companyId = (userData?['companyId'] ?? '').toString().trim();

      if (companyId.isEmpty) {
        setState(() {
          _loading = false;
          _erro = 'Empresa não identificada para este usuário.';
        });
        return;
      }

      final companyDoc = await _fs.collection('catalogo').doc(companyId).get();
      final companyData = companyDoc.data();

      setState(() {
        _companyId = companyId;
        _slugCtrl.text = (companyData?['catalogoSlug'] ?? '').toString();
        _catalogoAtivo = (companyData?['catalogoAtivo'] ?? true) == true;
        _loading = false;
        _erro = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _erro = 'Erro ao carregar URL do catálogo: $e';
      });
    }
  }

  Future<bool> _slugDisponivel(String slug) async {
    final q =
        await _fs
            .collection('catalogo')
            .where('catalogoSlug', isEqualTo: slug)
            .limit(1)
            .get();

    if (q.docs.isEmpty) return true;

    return q.docs.first.id == _companyId;
  }

  Future<void> _salvar() async {
    final companyId = _companyId;

    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    final slug = _normalizarSlug(_slugCtrl.text);

    if (slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma URL para o catálogo.')),
      );
      return;
    }

    if (slug.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A URL deve ter pelo menos 3 caracteres.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final disponivel = await _slugDisponivel(slug);

      if (!disponivel) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Essa URL já está em uso. Escolha outra.'),
          ),
        );
        setState(() => _saving = false);
        return;
      }

      await _fs.collection('catalogo').doc(companyId).set({
        'catalogoSlug': slug,
        'catalogoAtivo': _catalogoAtivo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _slugCtrl.text = slug;
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL do catálogo salva com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar URL: $e')));
    }
  }

  Future<void> _copiarLink() async {
    await Clipboard.setData(ClipboardData(text: _linkCatalogo));

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copiado.')));
  }

  Future<void> _compartilharLink() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Acesse nosso catálogo online:\n$_linkCatalogo',
        subject: 'Catálogo Online',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('URL do catálogo')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('URL do catálogo'),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _saving ? null : _salvar,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Link público da loja',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Escolha um nome curto para divulgar o catálogo aos seus clientes.',
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'URL do catálogo',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),

                        const SizedBox(height: 8),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.language_outlined,
                                size: 18,
                                color: Colors.grey.shade700,
                              ),

                              const SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  '$_baseUrl/',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        TextField(
                          controller: _slugCtrl,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Nome do link',
                            hintText: 'crud-sistemas',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link_rounded),
                            helperText: 'Use apenas letras, números e hífen.',
                          ),
                          onChanged: (value) {
                            final slug = _normalizarSlug(value);

                            if (slug != value) {
                              _slugCtrl.value = TextEditingValue(
                                text: slug,
                                selection: TextSelection.collapsed(
                                  offset: slug.length,
                                ),
                              );
                            }

                            setState(() {});
                          },
                        ),

                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.20),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Link completo',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 5),

                              SelectableText(
                                _linkCatalogo,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _catalogoAtivo,
                      title: const Text('Catálogo ativo'),
                      subtitle: Text(
                        _catalogoAtivo
                            ? 'Clientes poderão acessar o catálogo pelo link.'
                            : 'O link ficará indisponível para clientes.',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _catalogoAtivo = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Link gerado',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      _linkCatalogo,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copiarLink,
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _compartilharLink,
                            icon: const Icon(Icons.share),
                            label: const Text('Compartilhar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'QR Code do Catálogo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Os clientes podem escanear este QR Code para abrir seu catálogo.',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    QrImageView(
                      data: _linkCatalogo,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),

                    const SizedBox(height: 16),

                    SelectableText(_linkCatalogo, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _salvar,
              icon:
                  _saving
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Salvando...' : 'Salvar URL'),
            ),
          ],
        ),
      ),
    );
  }
}
