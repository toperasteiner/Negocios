import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProdutosSemEstoqueScreen extends StatefulWidget {
  const ProdutosSemEstoqueScreen({super.key});

  @override
  State<ProdutosSemEstoqueScreen> createState() =>
      _ProdutosSemEstoqueScreenState();
}

class _ProdutosSemEstoqueScreenState extends State<ProdutosSemEstoqueScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _saving = false;
  String? _companyId;
  String? _erro;
  bool _mostrarSucesso = false;

  String _opcaoSelecionada = 'exibir_normalmente';

  @override
  void initState() {
    super.initState();
    _carregar();
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

  Future<void> _carregar() async {
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

      final doc = await _fs.collection('catalogo').doc(companyId).get();
      final data = doc.data();

      setState(() {
        _companyId = companyId;
        _opcaoSelecionada =
            (data?['produtosSemEstoque'] ?? 'exibir_normalmente').toString();
        _loading = false;
        _erro = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _erro = 'Erro ao carregar configuração: $e';
      });
    }
  }

  Future<void> _salvar(String valor) async {
    final companyId = _companyId;

    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    setState(() {
      _opcaoSelecionada = valor;
      _saving = true;
    });

    try {
      await _fs.collection('catalogo').doc(companyId).set({
        'companyId': companyId,
        'produtosSemEstoque': valor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _saving = false;
        _mostrarSucesso = true;
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() {
            _mostrarSucesso = false;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar configuração: $e')),
      );
    }
  }

  Widget _buildSucessoBanner() {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      offset: _mostrarSucesso ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _mostrarSucesso ? 1 : 0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Configuração atualizada',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () {
                  setState(() {
                    _mostrarSucesso = false;
                  });
                },
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
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
        appBar: AppBar(title: const Text('Produtos sem estoque')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Produtos sem estoque')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_mostrarSucesso) _buildSucessoBanner(),
            const Text(
              'Estas opções serão aplicadas aos produtos sem estoque no seu catálogo virtual.',
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            _OpcaoCard(
              value: 'exibir_normalmente',
              groupValue: _opcaoSelecionada,
              title: 'Exibir normalmente',
              subtitle: 'O produto continuará aparecendo e poderá ser pedido.',
              onTap: () => _salvar('exibir_normalmente'),
            ),
            const SizedBox(height: 14),
            _OpcaoCard(
              value: 'nao_mostrar',
              groupValue: _opcaoSelecionada,
              title: 'Não mostrar no catálogo',
              subtitle: 'O produto sem estoque ficará oculto para o cliente.',
              onTap: () => _salvar('nao_mostrar'),
            ),
            const SizedBox(height: 14),
            _OpcaoCard(
              value: 'mostrar_nao_disponivel',
              groupValue: _opcaoSelecionada,
              title: "Mostrar 'Não disponível'",
              subtitle:
                  'O produto aparecerá no catálogo, mas não poderá ser adicionado ao carrinho.',
              onTap: () => _salvar('mostrar_nao_disponivel'),
            ),
            if (_saving) ...[
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _OpcaoCard extends StatelessWidget {
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OpcaoCard({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withOpacity(0.35) : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1.4,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.25),
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
