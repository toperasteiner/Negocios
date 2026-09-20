// lib/Config/PerfilNegocioScreen.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PerfilNegocioScreen extends StatefulWidget {
  const PerfilNegocioScreen({super.key});

  @override
  State<PerfilNegocioScreen> createState() => _PerfilNegocioScreenState();
}

class _PerfilNegocioScreenState extends State<PerfilNegocioScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  String? get _uid => _auth.currentUser?.uid;
  DocumentReference<Map<String, dynamic>> get _doc =>
      _fs.collection('perfil_negocio').doc(_uid ?? '_');

  // --------- Controllers ----------
  // Dados da empresa
  final _nomeEmpCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _razaoCtrl = TextEditingController();

  // Contato
  final _tel1Ctrl = TextEditingController();
  final _tel2Ctrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _logradouroCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();

  // Redes sociais
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _siteCtrl = TextEditingController();

  // Detalhes
  final _sloganCtrl = TextEditingController();
  final _historiaCtrl = TextEditingController();
  final _agradecimentoCtrl = TextEditingController();

  // Logo
  String? _logoDownloadUrl;
  Uint8List? _logoPreviewBytes;

  String? _bannerDownloadUrl;
  Uint8List? _bannerPreviewBytes;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _auth.authStateChanges().listen((u) {
      if (mounted) setState(() {});
    });
    _load();

    // marcar dirty ao editar
    for (final c in [
      _nomeEmpCtrl,
      _cnpjCtrl,
      _razaoCtrl,
      _tel1Ctrl,
      _tel2Ctrl,
      _cepCtrl,
      _logradouroCtrl,
      _numeroCtrl,
      _complCtrl,
      _bairroCtrl,
      _cidadeCtrl,
      _ufCtrl,
      _facebookCtrl,
      _instagramCtrl,
      _youtubeCtrl,
      _siteCtrl,
      _sloganCtrl,
      _historiaCtrl,
      _agradecimentoCtrl,
    ]) {
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _nomeEmpCtrl.dispose();
    _cnpjCtrl.dispose();
    _razaoCtrl.dispose();
    _tel1Ctrl.dispose();
    _tel2Ctrl.dispose();
    _cepCtrl.dispose();
    _logradouroCtrl.dispose();
    _numeroCtrl.dispose();
    _complCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _ufCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _youtubeCtrl.dispose();
    _siteCtrl.dispose();
    _sloganCtrl.dispose();
    _historiaCtrl.dispose();
    _agradecimentoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await _doc.get();
      final d = doc.data() ?? {};
      _nomeEmpCtrl.text = (d['empresa_nome'] ?? '').toString();
      _cnpjCtrl.text = (d['empresa_cnpj'] ?? '').toString();
      _razaoCtrl.text = (d['empresa_razao'] ?? '').toString();

      _tel1Ctrl.text = (d['contato_tel1'] ?? '').toString();
      _tel2Ctrl.text = (d['contato_tel2'] ?? '').toString();
      _cepCtrl.text = (d['end_cep'] ?? '').toString();
      _logradouroCtrl.text = (d['end_logradouro'] ?? '').toString();
      _numeroCtrl.text = (d['end_numero'] ?? '').toString();
      _complCtrl.text = (d['end_complemento'] ?? '').toString();
      _bairroCtrl.text = (d['end_bairro'] ?? '').toString();
      _cidadeCtrl.text = (d['end_cidade'] ?? '').toString();
      _ufCtrl.text = (d['end_uf'] ?? '').toString();

      _facebookCtrl.text = (d['social_facebook'] ?? '').toString();
      _instagramCtrl.text = (d['social_instagram'] ?? '').toString();
      _youtubeCtrl.text = (d['social_youtube'] ?? '').toString();
      _siteCtrl.text = (d['social_site'] ?? '').toString();

      _sloganCtrl.text = (d['det_slogan'] ?? '').toString();
      _historiaCtrl.text = (d['det_historia'] ?? '').toString();
      _agradecimentoCtrl.text = (d['det_agradecimento'] ?? '').toString();

      _logoDownloadUrl =
          (d['logoUrl'] ?? '').toString().isEmpty
              ? null
              : d['logoUrl'].toString();

      _bannerDownloadUrl =
          (d['bannerCatalogoUrl'] ?? d['bannerUrl'] ?? '').toString().isEmpty
              ? null
              : (d['bannerCatalogoUrl'] ?? d['bannerUrl']).toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickBanner() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );

      if (x == null) return;

      final bytes = await x.readAsBytes();

      setState(() {
        _bannerPreviewBytes = bytes;
        _dirty = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao selecionar banner: $e')));
    }
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _logoPreviewBytes = bytes;
        _dirty = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao selecionar imagem: $e')));
    }
  }

  Future<String?> _uploadBytes(
    Uint8List data,
    String path,
    String contentType,
  ) async {
    try {
      final ref = _storage.ref(path);
      await ref.putData(data, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao subir arquivo: $e')));
      }
      return null;
    }
  }

  Future<void> _save() async {
    if (_uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login para salvar.')));
      return;
    }

    setState(() => _saving = true);

    try {
      // Upload do logo (se selecionado agora)
      if (_logoPreviewBytes != null) {
        _logoDownloadUrl = await _uploadBytes(
          _logoPreviewBytes!,
          'perfil/$_uid/logo.jpg',
          'image/jpeg',
        );
      }

      if (_bannerPreviewBytes != null) {
        _bannerDownloadUrl = await _uploadBytes(
          _bannerPreviewBytes!,
          'perfil/$_uid/banner_catalogo.jpg',
          'image/jpeg',
        );
      }

      // Salvar Firestore
      final data = {
        'empresa_nome': _nomeEmpCtrl.text.trim(),
        'empresa_cnpj': _cnpjCtrl.text.trim(),
        'empresa_razao': _razaoCtrl.text.trim(),
        'contato_tel1': _tel1Ctrl.text.trim(),
        'contato_tel2': _tel2Ctrl.text.trim(),
        'end_cep': _cepCtrl.text.trim(),
        'end_logradouro': _logradouroCtrl.text.trim(),
        'end_numero': _numeroCtrl.text.trim(),
        'end_complemento': _complCtrl.text.trim(),
        'end_bairro': _bairroCtrl.text.trim(),
        'end_cidade': _cidadeCtrl.text.trim(),
        'end_uf': _ufCtrl.text.trim(),
        'social_facebook': _facebookCtrl.text.trim(),
        'social_instagram': _instagramCtrl.text.trim(),
        'social_youtube': _youtubeCtrl.text.trim(),
        'social_site': _siteCtrl.text.trim(),
        'det_slogan': _sloganCtrl.text.trim(),
        'det_historia': _historiaCtrl.text.trim(),
        'det_agradecimento': _agradecimentoCtrl.text.trim(),
        if (_logoDownloadUrl != null) 'logoUrl': _logoDownloadUrl,
        if (_bannerDownloadUrl != null) 'bannerUrl': _bannerDownloadUrl,
        if (_bannerDownloadUrl != null) 'bannerCatalogoUrl': _bannerDownloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _doc.set({
        ...data,
        'userId': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        _dirty = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil salvo com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    final sair = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
                SizedBox(width: 8),
                Text('Descartar alterações?'),
              ],
            ),
            content: const Text(
              'Você possui alterações não salvas no perfil. Deseja realmente descartá-las?',
              style: TextStyle(color: Color(0xFF475569)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continuar editando'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar'),
              ),
            ],
          ),
    );
    return sair ?? false;
  }

  Widget _buildHeader() {
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
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: () async {
                        final canPop = await _confirmExit();
                        if (canPop && mounted) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      tooltip: 'Voltar',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perfil do Negócio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Identidade, contato e dados da empresa',
                          style: TextStyle(
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
                      tooltip: 'Salvar alterações',
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              if (_dirty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Você tem alterações não salvas',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5B21B6),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              shadowColor: const Color(0xFF5B21B6).withValues(alpha: 0.4),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(
              _saving ? 'Salvando...' : 'Salvar Perfil',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
            color: Color(0xFF5B21B6),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final sair = await _confirmExit();
        if (sair && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Logotipo
                  _CollapsibleSection(
                    title: 'Logotipo',
                    subtitle: 'Identidade visual exibida nos documentos',
                    icon: Icons.photo_size_select_actual_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    initiallyExpanded: true,
                    child: Row(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _logoPreviewBytes != null
                              ? Image.memory(
                                  _logoPreviewBytes!,
                                  fit: BoxFit.cover,
                                )
                              : (_logoDownloadUrl == null
                                  ? const Center(
                                      child: Icon(
                                        Icons.image_outlined,
                                        size: 36,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    )
                                  : Image.network(
                                      _logoDownloadUrl!,
                                      fit: BoxFit.cover,
                                    )),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _pickLogo,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF5B21B6),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  minimumSize: const Size.fromHeight(46),
                                ),
                                icon: const Icon(Icons.upload_rounded, size: 18),
                                label: const Text(
                                  'Selecionar imagem',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Recomendado: imagem quadrada (JPG ou PNG).',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Banner do catálogo
                  _CollapsibleSection(
                    title: 'Banner do Catálogo',
                    subtitle: 'Imagem de topo para o catálogo virtual',
                    icon: Icons.panorama_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    initiallyExpanded: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _bannerPreviewBytes != null
                              ? Image.memory(
                                  _bannerPreviewBytes!,
                                  fit: BoxFit.cover,
                                )
                              : (_bannerDownloadUrl == null
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.panorama_outlined,
                                            size: 38,
                                            color: Color(0xFF94A3B8),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Nenhum banner selecionado',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Image.network(
                                      _bannerDownloadUrl!,
                                      fit: BoxFit.cover,
                                    )),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickBanner,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF5B21B6),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            minimumSize: const Size.fromHeight(46),
                          ),
                          icon: const Icon(Icons.upload_rounded, size: 18),
                          label: const Text(
                            'Selecionar banner 1200 x 300',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Recomendado: imagem horizontal 1200 x 300 px.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Dados da empresa
                  _CollapsibleSection(
                    title: 'Dados da Empresa',
                    subtitle: 'Informações fiscais e de identificação',
                    icon: Icons.business_rounded,
                    iconColor: const Color(0xFF3B82F6),
                    initiallyExpanded: true,
                    child: Column(
                      children: [
                        _txt(
                          _nomeEmpCtrl,
                          label: 'Nome fantasia *',
                          icon: Icons.store_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _razaoCtrl,
                          label: 'Razão social',
                          icon: Icons.badge_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _cnpjCtrl,
                          label: 'CNPJ',
                          icon: Icons.assignment_outlined,
                          keyboard: TextInputType.number,
                        ),
                      ],
                    ),
                  ),

                  // Contato & Endereço
                  _CollapsibleSection(
                    title: 'Contato e Endereço',
                    subtitle: 'Telefones e localização do estabelecimento',
                    icon: Icons.location_on_rounded,
                    iconColor: const Color(0xFF10B981),
                    initiallyExpanded: false,
                    child: Column(
                      children: [
                        _txt(
                          _tel1Ctrl,
                          label: 'Telefone 1',
                          icon: Icons.call_outlined,
                          next: true,
                          keyboard: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _tel2Ctrl,
                          label: 'Telefone 2',
                          icon: Icons.phone_iphone_outlined,
                          next: true,
                          keyboard: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _cepCtrl,
                          label: 'CEP',
                          icon: Icons.local_post_office_outlined,
                          next: true,
                          keyboard: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _ufCtrl,
                          label: 'UF (Estado)',
                          icon: Icons.flag_outlined,
                          next: true,
                          keyboard: TextInputType.text,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _logradouroCtrl,
                          label: 'Logradouro (Rua/Avenida)',
                          icon: Icons.location_on_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _numeroCtrl,
                          label: 'Número',
                          icon: Icons.numbers_outlined,
                          next: true,
                          keyboard: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _complCtrl,
                          label: 'Complemento',
                          icon: Icons.add_location_alt_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _bairroCtrl,
                          label: 'Bairro',
                          icon: Icons.maps_home_work_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _cidadeCtrl,
                          label: 'Cidade',
                          icon: Icons.location_city_outlined,
                          next: true,
                        ),
                      ],
                    ),
                  ),

                  // Redes sociais
                  _CollapsibleSection(
                    title: 'Redes Sociais',
                    subtitle: 'Links para suas redes e website',
                    icon: Icons.share_rounded,
                    iconColor: const Color(0xFFEC4899),
                    initiallyExpanded: false,
                    child: Column(
                      children: [
                        _txt(
                          _facebookCtrl,
                          label: 'Facebook',
                          icon: Icons.facebook_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _instagramCtrl,
                          label: 'Instagram',
                          icon: Icons.camera_alt_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _youtubeCtrl,
                          label: 'YouTube',
                          icon: Icons.ondemand_video_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _txt(
                          _siteCtrl,
                          label: 'Website',
                          icon: Icons.public_outlined,
                          keyboard: TextInputType.url,
                        ),
                      ],
                    ),
                  ),

                  // Detalhes do meu negócio
                  _CollapsibleSection(
                    title: 'Detalhes do Negócio',
                    subtitle: 'Slogan, história e mensagem ao cliente',
                    icon: Icons.auto_awesome_rounded,
                    iconColor: const Color(0xFF6366F1),
                    initiallyExpanded: false,
                    child: Column(
                      children: [
                        _txt(
                          _sloganCtrl,
                          label: 'Slogan',
                          icon: Icons.short_text_outlined,
                          next: true,
                        ),
                        const SizedBox(height: 12),
                        _multi(
                          _historiaCtrl,
                          label: 'História da empresa',
                          hint: 'Conte um pouco sobre a trajetória...',
                        ),
                        const SizedBox(height: 12),
                        _multi(
                          _agradecimentoCtrl,
                          label: 'Mensagem de agradecimento',
                          hint: 'Mensagem exibida em orçamentos, pedidos, etc.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  // ----------- UI helpers -----------
  Widget _txt(
    TextEditingController c, {
    required String label,
    required IconData icon,
    bool next = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      textInputAction: next ? TextInputAction.next : TextInputAction.done,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF5B21B6), width: 1.5),
        ),
        suffixIcon:
            c.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      c.clear();
                      setState(() => _dirty = true);
                    },
                    icon: const Icon(
                      Icons.clear_rounded,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
      ),
      onChanged: (_) => setState(() => _dirty = true),
    );
  }

  Widget _multi(
    TextEditingController c, {
    required String label,
    String? hint,
  }) {
    return TextField(
      controller: c,
      minLines: 3,
      maxLines: 8,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF5B21B6), width: 1.5),
        ),
      ),
      onChanged: (_) => setState(() => _dirty = true),
    );
  }
}

/* ===================== Collapsible Section ===================== */

class _CollapsibleSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final IconData icon;
  final Color iconColor;
  final String? subtitle;

  const _CollapsibleSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.icon = Icons.article_outlined,
    this.iconColor = const Color(0xFF5B21B6),
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                )
              : null,
          children: [child],
        ),
      ),
    );
  }
}
