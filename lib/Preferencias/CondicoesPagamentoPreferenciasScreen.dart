// lib/Preferencias/CondicoesPagamentoPreferenciasScreen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CondicoesPagamentoPreferenciasScreen extends StatefulWidget {
  const CondicoesPagamentoPreferenciasScreen({super.key});

  @override
  State<CondicoesPagamentoPreferenciasScreen> createState() =>
      _CondicoesPagamentoPreferenciasScreenState();
}

class _CondicoesPagamentoPreferenciasScreenState
    extends State<CondicoesPagamentoPreferenciasScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  bool _loading = true;
  String? _loadError;
  bool _salvando = false;

  // Condições
  bool _aVista = true;
  bool _parcelas = true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  /* ===================== LOAD COMPANY + PREFERÊNCIAS ===================== */

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    // 1) por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return byUid.data();
    } catch (_) {}

    // 2) por emailKey
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();
        if (q.docs.isNotEmpty) return q.docs.first.data();
      } catch (_) {}
    }
    return null;
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final me = await _loadCurrentUserRecord();
      if (me == null) throw 'Usuário não encontrado em "users".';

      final companyId = (me['companyId'] ?? '').toString().trim();
      if (companyId.isEmpty) {
        throw 'Nenhuma empresa vinculada.\nConfigure o companyId no Perfil do Negócio.';
      }

      _companyId = companyId;

      final doc =
          await _fs.collection('company_payment_settings').doc(companyId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        final cond =
            (data['conditions'] ?? <String, dynamic>{}) as Map<String, dynamic>;

        _aVista = (cond['aVista'] ?? _aVista) == true;
        _parcelas = (cond['parcelas'] ?? _parcelas) == true;
      }
    } catch (e) {
      _loadError = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ===================== SALVAR ===================== */

  Future<void> _salvar() async {
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma empresa vinculada. Configure o Perfil do Negócio.',
          ),
        ),
      );
      return;
    }

    // 👇 NOVO: precisa ter pelo menos uma opção marcada
    if (!_aVista && !_parcelas) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos uma condição de pagamento.'),
        ),
      );
      return;
    }

    final u = _auth.currentUser;

    setState(() => _salvando = true);

    final payload = <String, dynamic>{
      'companyId': _companyId,
      'conditions': {'aVista': _aVista, 'parcelas': _parcelas},
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': u?.uid,
    };

    try {
      await _fs
          .collection('company_payment_settings')
          .doc(_companyId)
          .set(payload, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Condições de pagamento salvas com sucesso.'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /* ===================== UI ===================== */

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Condições de pagamento')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Condições de pagamento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          Text(
            'Escolha aqui como os clientes podem te pagar.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // À vista
          CheckboxListTile(
            value: _aVista,
            onChanged: (v) => setState(() => _aVista = v ?? false),
            title: const Text('À vista'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),

          // Parcelas
          CheckboxListTile(
            value: _parcelas,
            onChanged: (v) => setState(() => _parcelas = v ?? false),
            title: const Text('Parcelado'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              child:
                  _salvando
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text(
                        'salvar condições de pagamento',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
