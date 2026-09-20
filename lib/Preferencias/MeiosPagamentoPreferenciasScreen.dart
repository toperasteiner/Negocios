// lib/Preferencias/MeiosPagamentoPreferenciasScreen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MeiosPagamentoPreferenciasScreen extends StatefulWidget {
  const MeiosPagamentoPreferenciasScreen({super.key});

  @override
  State<MeiosPagamentoPreferenciasScreen> createState() =>
      _MeiosPagamentoPreferenciasScreenState();
}

class _MeiosPagamentoPreferenciasScreenState
    extends State<MeiosPagamentoPreferenciasScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  bool _loading = true;
  String? _loadError;
  bool _salvando = false;

  // Checks dos meios de pagamento
  bool _boleto = true;
  bool _transferencia = true;
  bool _dinheiro = true;
  bool _cheque = true;
  bool _cartaoCredito = true;
  bool _cartaoDebito = true;
  bool _pix = true;

  // Dados bancários
  final _bancoCtrl = TextEditingController();
  final _agenciaCtrl = TextEditingController();
  final _contaCtrl = TextEditingController();
  final _titularCtrl = TextEditingController();
  final _tipoContaCtrl = TextEditingController();

  // PIX
  final _pixChaveCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _bancoCtrl.dispose();
    _agenciaCtrl.dispose();
    _contaCtrl.dispose();
    _titularCtrl.dispose();
    _tipoContaCtrl.dispose();
    _pixChaveCtrl.dispose();
    super.dispose();
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

    // 2) por emailKey (fallback)
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

      // carrega doc único da empresa
      final doc =
          await _fs.collection('company_payment_settings').doc(companyId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        final methods =
            (data['methods'] ?? <String, dynamic>{}) as Map<String, dynamic>;
        _boleto = (methods['boleto'] ?? _boleto) == true;
        _transferencia = (methods['transferencia'] ?? _transferencia) == true;
        _dinheiro = (methods['dinheiro'] ?? _dinheiro) == true;
        _cheque = (methods['cheque'] ?? _cheque) == true;
        _cartaoCredito = (methods['cartaoCredito'] ?? _cartaoCredito) == true;
        _cartaoDebito = (methods['cartaoDebito'] ?? _cartaoDebito) == true;
        _pix = (methods['pix'] ?? _pix) == true;

        final bank =
            (data['bank'] ?? <String, dynamic>{}) as Map<String, dynamic>;
        _bancoCtrl.text = (bank['banco'] ?? '').toString();
        _agenciaCtrl.text = (bank['agencia'] ?? '').toString();
        _contaCtrl.text = (bank['conta'] ?? '').toString();
        _titularCtrl.text = (bank['titular'] ?? '').toString();
        _tipoContaCtrl.text = (bank['tipoConta'] ?? '').toString();

        _pixChaveCtrl.text = (data['pixKey'] ?? '').toString();
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

    final u = _auth.currentUser;
    setState(() => _salvando = true);

    final payload = <String, dynamic>{
      'companyId': _companyId,
      'methods': {
        'boleto': _boleto,
        'transferencia': _transferencia,
        'dinheiro': _dinheiro,
        'cheque': _cheque,
        'cartaoCredito': _cartaoCredito,
        'cartaoDebito': _cartaoDebito,
        'pix': _pix,
      },
      'bank': {
        'banco': _bancoCtrl.text.trim(),
        'agencia': _agenciaCtrl.text.trim(),
        'conta': _contaCtrl.text.trim(),
        'titular': _titularCtrl.text.trim(),
        'tipoConta': _tipoContaCtrl.text.trim(),
      },
      'pixKey': _pixChaveCtrl.text.trim(),
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
        const SnackBar(content: Text('Meios de pagamento salvos com sucesso.')),
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

  /* ===================== UI HELPERS ===================== */

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meios de pagamento')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meios de pagamento')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ative apenas os meios de pagamento que você realmente utiliza.',
              ),
            ),
          );
        },
        backgroundColor: Colors.green,
        child: const Icon(Icons.lightbulb_outline),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          // ===== lista de meios de pagamento =====
          CheckboxListTile(
            value: _boleto,
            onChanged: (v) => setState(() => _boleto = v ?? false),
            title: const Text('Boleto'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _transferencia,
            onChanged: (v) => setState(() => _transferencia = v ?? false),
            title: const Text('Transferência bancária'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _dinheiro,
            onChanged: (v) => setState(() => _dinheiro = v ?? false),
            title: const Text('Dinheiro'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _cheque,
            onChanged: (v) => setState(() => _cheque = v ?? false),
            title: const Text('Cheque'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _cartaoCredito,
            onChanged: (v) => setState(() => _cartaoCredito = v ?? false),
            title: const Text('Cartão de crédito'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _cartaoDebito,
            onChanged: (v) => setState(() => _cartaoDebito = v ?? false),
            title: const Text('Cartão de débito'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _pix,
            onChanged: (v) => setState(() => _pix = v ?? false),
            title: const Text('PIX'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),

          const Divider(height: 24),

          // ===== dados bancários =====
          Text(
            'Dados bancários',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Você só pode salvar uma conta bancária',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          TextField(controller: _bancoCtrl, decoration: _dec('Banco')),
          const SizedBox(height: 10),
          TextField(
            controller: _agenciaCtrl,
            decoration: _dec('Agência'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contaCtrl,
            decoration: _dec('Conta'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titularCtrl,
            decoration: _dec('CPF/CNPJ do titular da conta'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tipoContaCtrl,
            decoration: _dec('Tipo de conta', hint: 'Corrente, poupança...'),
          ),

          const Divider(height: 32),

          // ===== PIX =====
          Text(
            'PIX',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Insira aqui sua chave PIX',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pixChaveCtrl,
            decoration: _dec('Qual é a sua chave PIX?'),
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
                        'salvar meios de pagamento',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
