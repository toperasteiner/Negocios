// lib/Pedidos/ConfigurarPagamentoScreen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PagamentoConfig {
  final bool parcelado; // false = à vista, true = parcelado
  final int numeroParcelas; // 1 se à vista
  final DateTime dataPrimeiroPgto; // se à vista: data única

  PagamentoConfig({
    required this.parcelado,
    required this.numeroParcelas,
    required this.dataPrimeiroPgto,
  });

  Map<String, dynamic> toMap() => {
    'tipo': parcelado ? 'parcelado' : 'avista',
    'numeroParcelas': numeroParcelas,
    'dataPrimeiroPagamento':
        DateTime(
          dataPrimeiroPgto.year,
          dataPrimeiroPgto.month,
          dataPrimeiroPgto.day,
        ).toIso8601String(),
  };
}

class ConfigurarPagamentoScreen extends StatefulWidget {
  final PagamentoConfig? initial;

  /// Opcional: se você já tiver resolvido o escopo no chamador
  /// (ex.: CadastroPedidoScreen), passe aqui para evitar nova consulta.
  final String? scopeUserId;

  const ConfigurarPagamentoScreen({super.key, this.initial, this.scopeUserId});

  @override
  State<ConfigurarPagamentoScreen> createState() =>
      _ConfigurarPagamentoScreenState();
}

class _ConfigurarPagamentoScreenState extends State<ConfigurarPagamentoScreen> {
  // ---------- Escopo multiempresa ----------
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  String? _scopeUserId; // = companyId ?? uid
  bool _loadingScope = true;
  String? _scopeError;

  // ---------- Estado de pagamento ----------
  bool _parcelado = false;
  int _parcelas = 1;
  DateTime _primeiraData = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Estado inicial do formulário
    final i = widget.initial;
    if (i != null) {
      _parcelado = i.parcelado;
      _parcelas = i.numeroParcelas;
      _primeiraData = i.dataPrimeiroPgto;
    }
    // Resolve escopo
    _initScope();
  }

  Future<void> _initScope() async {
    // Se veio do chamador, usa direto
    if (widget.scopeUserId != null && widget.scopeUserId!.isNotEmpty) {
      setState(() {
        _scopeUserId = widget.scopeUserId;
        _loadingScope = false;
      });
      return;
    }

    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _scopeError = 'Usuário não autenticado.';
        _scopeUserId = null;
        _loadingScope = false;
      });
      return;
    }

    try {
      final me = await _loadCurrentUserRecord(u);
      final companyId = (me?['companyId'] ?? '').toString().trim();
      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid;
        _loadingScope = false;
        _scopeError = null;
      });
      // Dica: se futuramente você quiser carregar/salvar padrão por escopo,
      // use _scopeUserId como chave/critério.
    } catch (e) {
      setState(() {
        _scopeError = 'Erro ao resolver escopo: $e';
        _loadingScope = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord(User u) async {
    // 1) por UID
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return (byUid.data() ?? {}) as Map<String, dynamic>;
    } catch (_) {}
    // 2) por emailKey (fallback)
    final email = (u.email ?? '').toLowerCase().trim();
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

  // ---------- UI/Fluxo ----------
  Future<void> _pickDate() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365 * 3)),
      initialDate: _primeiraData,
      helpText: _parcelado ? 'Data do 1º pagamento' : 'Data do pagamento',
    );
    if (d != null) {
      setState(() => _primeiraData = DateTime(d.year, d.month, d.day));
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  void _confirmar() {
    if (_parcelado && _parcelas < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamento parcelado precisa ter 2 ou mais parcelas.'),
        ),
      );
      return;
    }
    // Se precisar usar _scopeUserId no futuro, você pode guardar no chamador.
    final cfg = PagamentoConfig(
      parcelado: _parcelado,
      numeroParcelas: _parcelado ? _parcelas : 1,
      dataPrimeiroPgto: _primeiraData,
    );
    Navigator.pop(context, cfg);
  }

  @override
  Widget build(BuildContext context) {
    // Se preferir não travar a UI, você pode não exibir esse loading
    // (já que a tela não depende do escopo para funcionar). Mantive simples:
    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar pagamento'),
        // (Opcional) mostre discretamente o escopo atual no tooltip:
        actions: [
          if (_scopeUserId != null)
            IconButton(
              tooltip: 'Escopo: $_scopeUserId',
              onPressed: () {},
              icon: const Icon(Icons.account_tree_outlined),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: const Icon(Icons.check_rounded),
            label: const Text('confirmar'),
            onPressed: _confirmar,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (_scopeError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _scopeError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SwitchListTile.adaptive(
            title: const Text('Pagamento parcelado?'),
            subtitle: const Text(
              'Desative para marcar como pagamento à vista.',
            ),
            value: _parcelado,
            onChanged:
                (v) => setState(() {
                  _parcelado = v;
                  if (!v) _parcelas = 1;
                  if (v && _parcelas < 2) _parcelas = 2;
                }),
          ),
          const SizedBox(height: 8),
          if (_parcelado)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _parcelas.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de parcelas',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (s) {
                      final n = int.tryParse(s) ?? _parcelas;
                      setState(() => _parcelas = n.clamp(2, 240));
                    },
                  ),
                ),
              ],
            ),
          if (_parcelado) const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
              _parcelado
                  ? 'Data do 1º pagamento'
                  : 'Data do pagamento (à vista)',
            ),
            subtitle: Text(_fmt(_primeiraData)),
            trailing: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: const Text('alterar'),
            ),
          ),
        ],
      ),
    );
  }
}
