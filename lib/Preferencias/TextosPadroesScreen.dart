// lib/Config/TextosPadroesScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TextosPadroesScreen extends StatefulWidget {
  const TextosPadroesScreen({super.key});

  @override
  State<TextosPadroesScreen> createState() => _TextosPadroesScreenState();
}

class _TextosPadroesScreenState extends State<TextosPadroesScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _infoCtrl = TextEditingController();
  final _garantiaCtrl = TextEditingController();
  final _clausulaCtrl = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  bool _dirty = false;

  String? get _uid => _auth.currentUser?.uid;
  DocumentReference<Map<String, dynamic>>? get _docRef =>
      _uid == null ? null : _fs.collection('textos_padroes').doc(_uid);

  @override
  void initState() {
    super.initState();
    _carregar();
    for (final c in [_infoCtrl, _garantiaCtrl, _clausulaCtrl]) {
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _infoCtrl.dispose();
    _garantiaCtrl.dispose();
    _clausulaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_docRef == null) {
      setState(() => _carregando = false);
      return;
    }
    try {
      final snap = await _docRef!.get();
      final data = snap.data() ?? {};
      _infoCtrl.text = (data['info_adicional'] ?? '').toString();
      _garantiaCtrl.text = (data['condicao_garantia'] ?? '').toString();
      _clausulaCtrl.text = (data['clausula_contratual'] ?? '').toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (_uid == null || _docRef == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login para salvar.')));
      return;
    }
    setState(() => _salvando = true);
    try {
      final data = {
        'info_adicional': _infoCtrl.text.trim(),
        'condicao_garantia': _garantiaCtrl.text.trim(),
        'clausula_contratual': _clausulaCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _docRef!.set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Textos salvos com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return WillPopScope(
      onWillPop: () async {
        if (!_dirty) return true;
        final sair = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Descartar alterações?'),
                content: const Text('Você tem alterações não salvas.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Descartar'),
                  ),
                ],
              ),
        );
        return sair ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Textos padronizados'),
          actions: [
            IconButton(
              tooltip: 'Salvar',
              onPressed: (_salvando || !_dirty) ? null : _salvar,
              icon:
                  _salvando
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.check_rounded),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: FilledButton.icon(
              onPressed: _salvar,
              icon:
                  _salvando
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _SectionCard(
              title: '1 • Informações adicionais',
              child: _multiline(
                controller: _infoCtrl,
                hint:
                    'Ex.: Prazo de entrega em até 7 dias úteis. '
                    'Instalação não inclusa. Condições de pagamento conforme proposta.',
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '2 • Condições da garantia',
              child: _multiline(
                controller: _garantiaCtrl,
                hint:
                    'Ex.: Garantia de 90 dias contra defeitos de fabricação. '
                    'Perde a validade em caso de mau uso ou instalação inadequada.',
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '3 • Cláusulas contratuais',
              child: _multiline(
                controller: _clausulaCtrl,
                hint:
                    'Ex.: As partes elegem o foro da comarca de ... para dirimir dúvidas. '
                    'Valores sujeitos a reajuste em caso de alteração tributária.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _multiline({required TextEditingController controller, String? hint}) {
    return TextField(
      controller: controller,
      minLines: 6,
      maxLines: 12,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        counterText: '${controller.text.length} caracteres',
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}

/* ======== UI util ======== */

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

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
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
