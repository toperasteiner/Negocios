import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ConfiguracaoPaginaPublica extends StatefulWidget {
  const ConfiguracaoPaginaPublica({super.key});

  @override
  State<ConfiguracaoPaginaPublica> createState() =>
      _ConfiguracaoPaginaPublicaState();
}

class _ConfiguracaoPaginaPublicaState extends State<ConfiguracaoPaginaPublica> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();

  final _slugCtrl = TextEditingController();
  final _tituloCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  bool _ativo = false;
  bool _exibirEndereco = false;

  String? _companyId;
  String? _slugOriginal;

  /* ==========================================================
     URL DA PÁGINA PÚBLICA
     ========================================================== */

  String get _baseUrl => 'https://projeto-pedidos-472813.web.app/agendar';

  String get _linkCompleto {
    final slug = _normalizarSlug(_slugCtrl.text);

    if (slug.isEmpty) {
      return _baseUrl;
    }

    return '$_baseUrl/$slug';
  }

  bool get _possuiLink {
    return _normalizarSlug(_slugCtrl.text).isNotEmpty;
  }

  @override
  void initState() {
    super.initState();

    _inicializar();
  }

  @override
  void dispose() {
    _slugCtrl.dispose();
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    _whatsappCtrl.dispose();
    _instagramCtrl.dispose();
    _enderecoCtrl.dispose();

    super.dispose();
  }

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> _inicializar() async {
    try {
      final companyId = await _descobrirCompanyId();

      if (!mounted) return;

      if (companyId == null || companyId.isEmpty) {
        setState(() {
          _carregando = false;
        });

        _mensagem('Não foi possível identificar a empresa.');

        return;
      }

      _companyId = companyId;

      await _carregarConfiguracao();

      if (!mounted) return;

      setState(() {
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem('Erro ao carregar página pública: $e');
    }
  }

  /* ==========================================================
     IDENTIFICAR EMPRESA
     ========================================================== */

  Future<String?> _descobrirCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    try {
      final doc = await _fs.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        final companyId = (data['companyId'] ?? '').toString().trim();

        if (companyId.isNotEmpty) {
          return companyId;
        }
      }
    } catch (_) {}

    final email = (user.email ?? '').trim().toLowerCase();

    if (email.isEmpty) {
      return null;
    }

    final query =
        await _fs
            .collection('users')
            .where('emailKey', isEqualTo: email)
            .limit(1)
            .get();

    if (query.docs.isEmpty) {
      return null;
    }

    final data = query.docs.first.data();

    final companyId = (data['companyId'] ?? '').toString().trim();

    return companyId.isEmpty ? null : companyId;
  }

  /* ==========================================================
     CARREGAR CONFIGURAÇÃO
     ========================================================== */

  Future<void> _carregarConfiguracao() async {
    if (_companyId == null) {
      return;
    }

    final doc =
        await _fs.collection('agenda_configuracoes').doc(_companyId).get();

    if (!doc.exists) {
      return;
    }

    final data = doc.data();

    if (data == null) {
      return;
    }

    final pagina = data['paginaPublica'];

    if (pagina is! Map) {
      return;
    }

    _ativo = (pagina['ativo'] ?? false) == true;

    _exibirEndereco = (pagina['exibirEndereco'] ?? false) == true;

    _slugCtrl.text = (pagina['slug'] ?? '').toString();

    _slugOriginal = _slugCtrl.text.trim();

    _tituloCtrl.text = (pagina['titulo'] ?? '').toString();

    _descricaoCtrl.text = (pagina['descricao'] ?? '').toString();

    _whatsappCtrl.text = (pagina['whatsapp'] ?? '').toString();

    _instagramCtrl.text = (pagina['instagram'] ?? '').toString();

    _enderecoCtrl.text = (pagina['endereco'] ?? '').toString();
  }

  /* ==========================================================
     SLUG / NOME DO LINK
     ========================================================== */

  String _normalizarSlug(String valor) {
    var slug = valor.trim().toLowerCase();

    const origem = 'áàâãäéèêëíìîïóòôõöúùûüçñ';

    const destino = 'aaaaaeeeeiiiiooooouuuucn';

    for (int i = 0; i < origem.length; i++) {
      slug = slug.replaceAll(origem[i], destino[i]);
    }

    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');

    slug = slug.replaceAll(RegExp(r'-+'), '-');

    slug = slug.replaceAll(RegExp(r'^-|-$'), '');

    return slug;
  }

  void _ajustarSlug() {
    final normalizado = _normalizarSlug(_slugCtrl.text);

    if (_slugCtrl.text != normalizado) {
      _slugCtrl.value = TextEditingValue(
        text: normalizado,
        selection: TextSelection.collapsed(offset: normalizado.length),
      );
    }
  }

  Future<bool> _slugJaExiste(String slug) async {
    if (slug.isEmpty) {
      return false;
    }

    if (_slugOriginal != null && _slugOriginal == slug) {
      return false;
    }

    final doc = await _fs.collection('agenda_paginas_publicas').doc(slug).get();

    return doc.exists;
  }

  /* ==========================================================
     COPIAR LINK
     ========================================================== */

  Future<void> _copiarLink() async {
    if (!_possuiLink) {
      _mensagem('Informe primeiro o nome do link.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: _linkCompleto));

    if (!mounted) return;

    _mensagem('Link copiado.');
  }

  /* ==========================================================
     COMPARTILHAR LINK
     ========================================================== */

  Future<void> _compartilharLink() async {
    if (!_possuiLink) {
      _mensagem('Informe primeiro o nome do link.');
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text: 'Agende seu horário online:\n$_linkCompleto',
        subject: 'Agendamento Online',
      ),
    );
  }

  /* ==========================================================
     VALIDAÇÃO
     ========================================================== */

  String? _validarSlug(String? value) {
    final slug = _normalizarSlug(value ?? '');

    if (slug.isEmpty) {
      return 'Informe o nome do link.';
    }

    if (slug.length < 3) {
      return 'Utilize pelo menos 3 caracteres.';
    }

    if (slug.length > 50) {
      return 'Utilize no máximo 50 caracteres.';
    }

    final regex = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

    if (!regex.hasMatch(slug)) {
      return 'Utilize apenas letras, números e hífen.';
    }

    return null;
  }

  String? _validarTitulo(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'Informe o nome que será exibido na página.';
    }

    return null;
  }

  /* ==========================================================
     SALVAR
     ========================================================== */

  Future<void> _salvar() async {
    _ajustarSlug();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_companyId == null || _companyId!.isEmpty) {
      _mensagem('Empresa não identificada.');

      return;
    }

    final slug = _normalizarSlug(_slugCtrl.text);

    setState(() {
      _salvando = true;
    });

    try {
      final existe = await _slugJaExiste(slug);

      if (existe) {
        if (!mounted) return;

        _mensagem('Este nome de link já está sendo utilizado. Escolha outro.');

        return;
      }

      final titulo = _tituloCtrl.text.trim();

      final descricao = _descricaoCtrl.text.trim();

      final whatsapp = _whatsappCtrl.text.trim();

      final instagram = _instagramCtrl.text.trim();

      final endereco = _enderecoCtrl.text.trim();

      final configuracao = <String, dynamic>{
        'ativo': _ativo,
        'slug': slug,
        'titulo': titulo,
        'descricao': descricao,
        'whatsapp': whatsapp,
        'instagram': instagram,
        'endereco': endereco,
        'exibirEndereco': _exibirEndereco,
        'linkCompleto': '$_baseUrl/$slug',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final refConfig = _fs.collection('agenda_configuracoes').doc(_companyId);

      final docConfig = await refConfig.get();

      final dadosConfig = <String, dynamic>{
        'companyId': _companyId,
        'paginaPublica': configuracao,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      };

      if (!docConfig.exists) {
        dadosConfig['createdAt'] = FieldValue.serverTimestamp();
      }

      final refPublico = _fs.collection('agenda_paginas_publicas').doc(slug);

      final dadosPublicos = <String, dynamic>{
        'companyId': _companyId,
        'ativo': _ativo,
        'slug': slug,
        'titulo': titulo,
        'descricao': descricao,
        'whatsapp': whatsapp,
        'instagram': instagram,
        'endereco': endereco,
        'exibirEndereco': _exibirEndereco,
        'linkCompleto': '$_baseUrl/$slug',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final batch = _fs.batch();

      batch.set(refConfig, dadosConfig, SetOptions(merge: true));

      batch.set(refPublico, dadosPublicos, SetOptions(merge: true));

      /*
       * Se o usuário alterou o nome do link,
       * remove o documento público antigo.
       */
      if (_slugOriginal != null &&
          _slugOriginal!.isNotEmpty &&
          _slugOriginal != slug) {
        final refAntigo = _fs
            .collection('agenda_paginas_publicas')
            .doc(_slugOriginal);

        batch.delete(refAntigo);
      }

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _slugOriginal = slug;
        _slugCtrl.text = slug;
      });

      _mensagem('Página pública salva com sucesso.');
    } catch (e) {
      if (!mounted) return;

      _mensagem('Erro ao salvar página pública: $e');
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  /* ==========================================================
     MENSAGEM
     ========================================================== */

  void _mensagem(String texto) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: PaginaPublicaStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: PaginaPublicaStyle.bg,

      body: Column(
        children: [
          _AgendaPageHeader(
            title: 'Página pública',
            subtitle:
                'Configure como sua empresa será apresentada aos clientes na Agenda Online.',
            icon: Icons.public_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),

          Expanded(
            child: AbsorbPointer(
              absorbing: _salvando,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _statusCard(),

                      const SizedBox(height: 14),

                      _identificacaoCard(),

                      const SizedBox(height: 14),

                      _compartilhamentoCard(),

                      const SizedBox(height: 14),

                      _qrCodeCard(),

                      const SizedBox(height: 14),

                      _contatoCard(),

                      const SizedBox(height: 14),

                      _localizacaoCard(),

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: PaginaPublicaStyle.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _salvando ? null : _salvar,
                          icon:
                              _salvando
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.save_outlined),
                          label: Text(
                            _salvando ? 'Salvando...' : 'Salvar página pública',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     STATUS
     ========================================================== */

  Widget _statusCard() {
    return _cardPadrao(
      icon: Icons.public_outlined,
      iconColor: PaginaPublicaStyle.green,
      title: 'Publicação da página',
      subtitle:
          'Controle se a página de agendamento estará disponível para seus clientes.',
      child: _switchOpcao(
        icon:
            _ativo ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        iconColor: _ativo ? PaginaPublicaStyle.green : PaginaPublicaStyle.muted,
        title: 'Página ativa',
        subtitle:
            _ativo
                ? 'Clientes poderão acessar sua página pública de agendamento.'
                : 'A página não estará disponível para novos agendamentos.',
        value: _ativo,
        onChanged: (value) {
          setState(() {
            _ativo = value;
          });
        },
      ),
    );
  }

  /* ==========================================================
     IDENTIFICAÇÃO E LINK
     ========================================================== */

  Widget _identificacaoCard() {
    return _cardPadrao(
      icon: Icons.storefront_outlined,
      iconColor: PaginaPublicaStyle.primary,
      title: 'Identificação',
      subtitle:
          'Defina como sua empresa será apresentada e escolha o endereço público da agenda.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _tituloCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: 'Nome exibido',
              icon: Icons.storefront_outlined,
              helperText: 'Ex.: Barbearia do João',
            ),
            validator: _validarTitulo,
          ),

          const SizedBox(height: 14),

          TextFormField(
            controller: _descricaoCtrl,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: _inputDecoration(
              label: 'Descrição',
              icon: Icons.notes_outlined,
              helperText: 'Apresente seu negócio para seus clientes.',
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Link público da agenda',
            style: TextStyle(
              color: PaginaPublicaStyle.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Escolha um nome curto para divulgar sua página de agendamento.',
            style: TextStyle(
              color: PaginaPublicaStyle.muted,
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 14),

          /*
           * URL BASE
           */
          /*Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: PaginaPublicaStyle.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PaginaPublicaStyle.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.language_outlined,
                  color: PaginaPublicaStyle.muted,
                  size: 19,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    '$_baseUrl/',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PaginaPublicaStyle.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),*/
          const SizedBox(height: 12),

          /*
           * NOME DO LINK
           */
          TextFormField(
            controller: _slugCtrl,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            decoration: _inputDecoration(
              label: 'Nome do link',
              icon: Icons.link_rounded,
              helperText: 'Use letras, números e hífen. Ex.: barbearia-do-joao',
            ),
            onChanged: (value) {
              final slug = _normalizarSlug(value);

              if (slug != value) {
                _slugCtrl.value = TextEditingValue(
                  text: slug,
                  selection: TextSelection.collapsed(offset: slug.length),
                );
              }

              setState(() {});
            },
            validator: _validarSlug,
          ),

          const SizedBox(height: 14),

          /*
           * LINK COMPLETO
           */
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PaginaPublicaStyle.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: PaginaPublicaStyle.primary.withOpacity(0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Link completo',
                  style: TextStyle(
                    color: PaginaPublicaStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 7),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.language_outlined,
                      color: PaginaPublicaStyle.primary,
                      size: 20,
                    ),

                    const SizedBox(width: 9),

                    Expanded(
                      child: SelectableText(
                        _linkCompleto,
                        style: const TextStyle(
                          color: PaginaPublicaStyle.text,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     COMPARTILHAR
     ========================================================== */

  Widget _compartilhamentoCard() {
    return _cardPadrao(
      icon: Icons.share_outlined,
      iconColor: PaginaPublicaStyle.blue,
      title: 'Compartilhe sua página',
      subtitle: 'Copie ou compartilhe o link de agendamento com seus clientes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PaginaPublicaStyle.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PaginaPublicaStyle.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.link_outlined,
                  color: PaginaPublicaStyle.primary,
                  size: 20,
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: SelectableText(
                    _linkCompleto,
                    style: TextStyle(
                      color:
                          _possuiLink
                              ? PaginaPublicaStyle.text
                              : PaginaPublicaStyle.muted,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PaginaPublicaStyle.primary,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: PaginaPublicaStyle.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _possuiLink ? _copiarLink : null,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text(
                    'Copiar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: PaginaPublicaStyle.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _possuiLink ? _compartilharLink : null,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text(
                    'Compartilhar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     QR CODE
     ========================================================== */

  Widget _qrCodeCard() {
    return _cardPadrao(
      icon: Icons.qr_code_2_outlined,
      iconColor: PaginaPublicaStyle.orange,
      title: 'QR Code',
      subtitle:
          'Seus clientes podem escanear o QR Code para acessar diretamente sua página de agendamento.',
      child: Column(
        children: [
          if (!_possuiLink)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PaginaPublicaStyle.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: PaginaPublicaStyle.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: PaginaPublicaStyle.muted),

                  SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'Informe o nome do link para gerar o QR Code.',
                      style: TextStyle(
                        color: PaginaPublicaStyle.muted,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PaginaPublicaStyle.border),
                ),
                child: QrImageView(
                  data: _linkCompleto,
                  version: QrVersions.auto,
                  size: 210,
                  backgroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 16),

            SelectableText(
              _linkCompleto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PaginaPublicaStyle.muted,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: PaginaPublicaStyle.primary,
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: PaginaPublicaStyle.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _copiarLink,
                icon: const Icon(Icons.copy_outlined),
                label: const Text(
                  'Copiar link do QR Code',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /* ==========================================================
     CONTATO
     ========================================================== */

  Widget _contatoCard() {
    return _cardPadrao(
      icon: Icons.contact_phone_outlined,
      iconColor: PaginaPublicaStyle.orange,
      title: 'Contato',
      subtitle:
          'Essas informações poderão ser apresentadas ao cliente na página pública.',
      child: Column(
        children: [
          TextFormField(
            controller: _whatsappCtrl,
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration(
              label: 'WhatsApp',
              icon: Icons.chat_outlined,
              helperText: 'Opcional.',
            ),
          ),

          const SizedBox(height: 14),

          TextFormField(
            controller: _instagramCtrl,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: _inputDecoration(
              label: 'Instagram',
              icon: Icons.alternate_email,
              helperText: 'Ex.: @minhaempresa',
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     LOCALIZAÇÃO
     ========================================================== */

  Widget _localizacaoCard() {
    return _cardPadrao(
      icon: Icons.location_on_outlined,
      iconColor: PaginaPublicaStyle.blue,
      title: 'Localização',
      subtitle: 'Informe onde os atendimentos são realizados.',
      child: Column(
        children: [
          TextFormField(
            controller: _enderecoCtrl,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              label: 'Endereço',
              icon: Icons.location_on_outlined,
              helperText: 'Ex.: Rua Central, 150 - Centro',
            ),
          ),

          const SizedBox(height: 10),

          _switchOpcao(
            icon: Icons.map_outlined,
            iconColor: PaginaPublicaStyle.blue,
            title: 'Exibir endereço',
            subtitle: 'Mostra o endereço informado para os clientes.',
            value: _exibirEndereco,
            onChanged: (value) {
              setState(() {
                _exibirEndereco = value;
              });
            },
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     CARD PADRÃO
     ========================================================== */

  Widget _cardPadrao({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PaginaPublicaStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AgendaIconBadge(icon: icon, color: iconColor),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: PaginaPublicaStyle.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: PaginaPublicaStyle.muted,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          child,
        ],
      ),
    );
  }

  /* ==========================================================
     SWITCH
     ========================================================== */

  Widget _switchOpcao({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: PaginaPublicaStyle.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  subtitle,
                  style: const TextStyle(
                    color: PaginaPublicaStyle.muted,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Switch.adaptive(
            value: value,
            activeColor: PaginaPublicaStyle.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     INPUT
     ========================================================== */

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,

      prefixIcon: Icon(icon, color: PaginaPublicaStyle.primary),

      filled: true,

      fillColor: Colors.white,

      labelStyle: const TextStyle(
        color: PaginaPublicaStyle.muted,
        fontWeight: FontWeight.w600,
      ),

      helperStyle: const TextStyle(
        color: PaginaPublicaStyle.muted,
        fontSize: 11.5,
      ),

      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PaginaPublicaStyle.border),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PaginaPublicaStyle.border),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: PaginaPublicaStyle.primary,
          width: 1.5,
        ),
      ),
    );
  }
}

/* ============================================================
   HEADER
   ============================================================ */

class _AgendaPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  const _AgendaPageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        gradient: PaginaPublicaStyle.gradient,

        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),

      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        20,
      ),

      child: Column(
        children: [
          Row(
            children: [
              _AgendaHeaderButton(
                icon: Icons.arrow_back_rounded,
                onTap: onBack,
              ),

              Expanded(
                child: Center(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 42),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.92), size: 19),

              const SizedBox(width: 7),

              Flexible(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 13.5,
                    height: 1.30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   COMPONENTES VISUAIS
   ============================================================ */

class _AgendaHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AgendaHeaderButton({required this.icon, required this.onTap});

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

class _AgendaIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 25),
    );
  }
}

/* ============================================================
   STYLE
   ============================================================ */

class PaginaPublicaStyle {
  static const Color primary = Color(0xFF5B21B6);

  static const Color primaryDark = Color(0xFF3B0CA3);

  static const Color orange = Color(0xFFF97316);

  static const Color green = Color(0xFF16A34A);

  static const Color blue = Color(0xFF2563EB);

  static const Color purple = Color(0xFF7C3AED);

  static const Color bg = Color(0xFFF8FAFC);

  static const Color text = Color(0xFF111827);

  static const Color muted = Color(0xFF64748B);

  static const Color border = Color(0xFFE5E7EB);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
