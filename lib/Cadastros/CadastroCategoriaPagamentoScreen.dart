import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/* ====================== IDENTIDADE VISUAL ====================== */

class CategoriaPagamentoStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get headerGradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

/* ====================== TELA PRINCIPAL ====================== */

class CadastroCategoriaPagamentoScreen extends StatefulWidget {
  final String companyId; // escopo (companyId ?? uid) resolvido fora
  final String? categoriaId; // null = inclusão; not null = edição
  const CadastroCategoriaPagamentoScreen({
    super.key,
    required this.companyId,
    this.categoriaId,
  });

  @override
  State<CadastroCategoriaPagamentoScreen> createState() =>
      _CadastroCategoriaPagamentoScreenState();
}

class _CadastroCategoriaPagamentoScreenState
    extends State<CadastroCategoriaPagamentoScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _tipo = 'ambos'; // pagar | receber | ambos
  bool _ativa = true;

  bool _loading = true;
  bool _salvando = false;
  String? _loadError;

  bool get _isEdit => widget.categoriaId != null;

  @override
  void initState() {
    super.initState();
    _loadIfEdit();
  }

  Future<void> _loadIfEdit() async {
    if (widget.categoriaId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final d =
          await _fs
              .collection('categorias_pagamento')
              .doc(widget.categoriaId)
              .get();
      if (!d.exists) {
        setState(() {
          _loadError = 'Registro não encontrado.';
          _loading = false;
        });
        return;
      }
      final m = d.data()!;
      _nomeCtrl.text = (m['nome'] ?? '').toString();
      _descCtrl.text = (m['descricao'] ?? '').toString();
      _tipo = (m['tipo'] ?? 'ambos').toString();
      _ativa = (m['ativa'] ?? true) == true;
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loadError = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  Future<bool> _existeDuplicado({
    required String nome,
    required String tipo,
    String? ignoreId,
  }) async {
    // Unicidade: companyId + tipo + nome (exato, sensível a maiúsculas/minúsculas)
    final q =
        await _fs
            .collection('categorias_pagamento')
            .where('companyId', isEqualTo: widget.companyId)
            .where('tipo', isEqualTo: tipo)
            .where('nome', isEqualTo: nome)
            .limit(2)
            .get();

    final docs = q.docs.where((d) => d.id != ignoreId).toList();
    return docs.isNotEmpty;
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);

    final nome = _nomeCtrl.text.trim();
    final tipo = _tipo;
    final uid = _auth.currentUser?.uid ?? '';

    // unicidade
    if (await _existeDuplicado(
      nome: nome,
      tipo: tipo,
      ignoreId: widget.categoriaId,
    )) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Já existe uma categoria com esse nome e tipo.'),
          ),
        );
      }
      return;
    }

    try {
      if (widget.categoriaId == null) {
        await _fs.collection('categorias_pagamento').add({
          'companyId': widget.companyId,
          'nome': nome,
          'tipo': tipo,
          'ativa': _ativa,
          'descricao': _descCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': uid,
        });
      } else {
        await _fs
            .collection('categorias_pagamento')
            .doc(widget.categoriaId)
            .update({
              'nome': nome,
              'tipo': tipo,
              'ativa': _ativa,
              'descricao': _descCtrl.text.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.categoriaId == null
                  ? 'Categoria criada.'
                  : 'Categoria atualizada.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao salvar: $e')));
      }
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: CategoriaPagamentoStyle.bg,
        body: Center(
          child: CircularProgressIndicator(
            color: CategoriaPagamentoStyle.primary,
          ),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: CategoriaPagamentoStyle.bg,
        body: Column(
          children: [
            _cabecalho(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CategoriaPagamentoStyle.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: CategoriaPagamentoStyle.bg,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _salvando ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CategoriaPagamentoStyle.primary,
                    minimumSize: const Size.fromHeight(52),
                    side: BorderSide(
                      color: CategoriaPagamentoStyle.primary.withOpacity(0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text(
                    'Cancelar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  style: FilledButton.styleFrom(
                    backgroundColor: CategoriaPagamentoStyle.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
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
                    _salvando ? 'Salvando...' : 'Salvar categoria',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _salvando,
        child: Column(
          children: [
            _cabecalho(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Form(
                    key: _formKey,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: CategoriaPagamentoStyle.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const _IconBadge(
                                icon: Icons.category_outlined,
                                color: CategoriaPagamentoStyle.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Dados da Categoria',
                                      style: TextStyle(
                                        color: CategoriaPagamentoStyle.text,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Preencha as informações para organizar seus lançamentos.',
                                      style: const TextStyle(
                                        color: CategoriaPagamentoStyle.muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Nome
                          TextFormField(
                            controller: _nomeCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: 'Nome da categoria *',
                              hintText: 'Ex.: Aluguel, Vendas, Serviços...',
                              filled: true,
                              fillColor: CategoriaPagamentoStyle.bg,
                              prefixIcon: const Icon(
                                Icons.label_outline,
                                color: CategoriaPagamentoStyle.primary,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: CategoriaPagamentoStyle.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Informe o nome da categoria';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Tipo
                          DropdownButtonFormField<String>(
                            value: _tipo,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Tipo de movimentação *',
                              filled: true,
                              fillColor: CategoriaPagamentoStyle.bg,
                              prefixIcon: const Icon(
                                Icons.swap_vert_circle_outlined,
                                color: CategoriaPagamentoStyle.primary,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: CategoriaPagamentoStyle.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'pagar',
                                child: Text('Contas a Pagar'),
                              ),
                              DropdownMenuItem(
                                value: 'receber',
                                child: Text('Contas a Receber'),
                              ),
                              DropdownMenuItem(
                                value: 'ambos',
                                child: Text('Ambos (Pagar e Receber)'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _tipo = v ?? 'ambos'),
                          ),
                          const SizedBox(height: 14),

                          // Ativa
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  _ativa
                                      ? CategoriaPagamentoStyle.green.withOpacity(
                                        0.08,
                                      )
                                      : CategoriaPagamentoStyle.bg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color:
                                    _ativa
                                        ? CategoriaPagamentoStyle.green.withOpacity(
                                          0.3,
                                        )
                                        : const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _ativa
                                      ? Icons.check_circle_outline
                                      : Icons.pause_circle_outline,
                                  color:
                                      _ativa
                                          ? CategoriaPagamentoStyle.green
                                          : CategoriaPagamentoStyle.muted,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _ativa
                                            ? 'Categoria Ativa'
                                            : 'Categoria Inativa',
                                        style: TextStyle(
                                          color:
                                              _ativa
                                                  ? CategoriaPagamentoStyle.green
                                                  : CategoriaPagamentoStyle.text,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        _ativa
                                            ? 'Disponível para seleção nos lançamentos.'
                                            : 'Oculta nas seleções padrão.',
                                        style: const TextStyle(
                                          color: CategoriaPagamentoStyle.muted,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _ativa,
                                  activeColor: CategoriaPagamentoStyle.primary,
                                  onChanged: (v) => setState(() => _ativa = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Descrição
                          TextFormField(
                            controller: _descCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Descrição (opcional)',
                              hintText:
                                  'Observações ou detalhes sobre a categoria...',
                              filled: true,
                              fillColor: CategoriaPagamentoStyle.bg,
                              prefixIcon: const Icon(
                                Icons.notes_outlined,
                                color: CategoriaPagamentoStyle.primary,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: CategoriaPagamentoStyle.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      decoration: BoxDecoration(
        gradient: CategoriaPagamentoStyle.headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          _HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Text(
                  _isEdit ? 'Editar categoria' : 'Nova categoria',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nome, tipo e status',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HeaderIconButton(
            icon: Icons.check_rounded,
            onTap: _salvando ? () {} : _salvar,
          ),
        ],
      ),
    );
  }
}

/* ====================== WIDGETS AUXILIARES ====================== */

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

