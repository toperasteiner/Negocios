import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Seletores/SelecionarClienteSheet.dart';
import '../Seletores/SelecionarFornecedorSheet.dart';
import '../Seletores/SelecionarCategoriaPagamentoSheet.dart';

enum TipoRecorrenciaFinanceira { pagar, receber }

class CadastroRecorrenciaFinanceiraScreen extends StatefulWidget {
  final TipoRecorrenciaFinanceira tipo;
  final String? recorrenciaId;

  const CadastroRecorrenciaFinanceiraScreen({
    super.key,
    required this.tipo,
    this.recorrenciaId,
  });

  @override
  State<CadastroRecorrenciaFinanceiraScreen> createState() =>
      _CadastroRecorrenciaFinanceiraScreenState();
}

class _CadastroRecorrenciaFinanceiraScreenState
    extends State<CadastroRecorrenciaFinanceiraScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _descricaoController = TextEditingController();
  final _valorController = TextEditingController();
  final _diaVencimentoController = TextEditingController();
  final _categoriaNomeController = TextEditingController();
  final _clienteFornecedorController = TextEditingController();
  final _observacaoController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _ativo = true;

  String? _companyId;
  String? _userId;
  String? _clienteFornecedorId;
  String? _categoriaId;

  bool get _isPagar => widget.tipo == TipoRecorrenciaFinanceira.pagar;

  String get _collectionName =>
      _isPagar ? 'recorrencias_pagar' : 'recorrencias_receber';

  String get _titulo =>
      _isPagar ? 'Conta a Pagar Recorrente' : 'Conta a Receber Recorrente';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    _diaVencimentoController.dispose();
    _categoriaNomeController.dispose();
    _clienteFornecedorController.dispose();
    _observacaoController.dispose();
    super.dispose();
  }

  Future<void> _selecionarClienteFornecedor() async {
    if (_isPagar) {
      final fornecedor = await showModalBottomSheet<FornecedorSelecionado>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const SelecionarFornecedorSheet(),
      );

      if (fornecedor == null) return;

      setState(() {
        _clienteFornecedorId = fornecedor.id;
        _clienteFornecedorController.text = fornecedor.nome;
      });

      return;
    }

    final cliente = await showModalBottomSheet<ClienteSelecionado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const SelecionarClienteSheet(),
    );

    if (cliente == null) return;

    setState(() {
      _clienteFornecedorId = cliente.id;
      _clienteFornecedorController.text = cliente.nome;
    });
  }

  Future<void> _selecionarCategoria() async {
    final categoria = await showModalBottomSheet<CategoriaSelecionada>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (_) => SelecionarCategoriaPagamentoSheet(
            filtroTipo: _isPagar ? 'pagar' : 'receber',
          ),
    );

    if (categoria == null) return;

    setState(() {
      _categoriaId = categoria.id;
      _categoriaNomeController.text = categoria.nome;
    });
  }

  Future<void> _init() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      _userId = user.uid;

      final userDoc = await _fs.collection('users').doc(user.uid).get();
      final data = userDoc.data();

      _companyId = (data?['companyId'] ?? user.uid).toString().trim();

      if (widget.recorrenciaId != null) {
        await _loadRecorrencia();
      } else {
        _diaVencimentoController.text = '1';
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
    }
  }

  Future<void> _loadRecorrencia() async {
    final doc =
        await _fs.collection(_collectionName).doc(widget.recorrenciaId).get();

    if (!doc.exists) return;

    final data = doc.data() ?? {};

    _categoriaId =
        (data['categoriaId'] ?? data['categoriaKey'] ?? '').toString();
    _clienteFornecedorId =
        (data[_isPagar ? 'fornecedorId' : 'clienteId'] ?? '').toString();
    _descricaoController.text = (data['descricao'] ?? '').toString();
    _valorController.text = _formatValor(
      (data['valor'] as num?)?.toDouble() ?? 0,
    );
    _diaVencimentoController.text = (data['diaVencimento'] ?? 1).toString();
    _categoriaNomeController.text = (data['categoriaNome'] ?? '').toString();
    _clienteFornecedorController.text =
        (data[_isPagar ? 'fornecedorNome' : 'clienteNome'] ?? '').toString();
    _observacaoController.text = (data['observacao'] ?? '').toString();
    _ativo = (data['ativo'] ?? true) == true;
  }

  String _formatValor(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseValor(String value) {
    final clean =
        value
            .replaceAll('R\$', '')
            .replaceAll('.', '')
            .replaceAll(',', '.')
            .trim();

    return double.tryParse(clean) ?? 0.0;
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final valor = _parseValor(_valorController.text);
    final diaVencimento = int.parse(_diaVencimentoController.text);

    setState(() => _saving = true);

    try {
      final data = {
        'companyId': _companyId,
        'userId': _userId,
        'descricao': _descricaoController.text.trim(),
        'categoriaId': _categoriaId,
        'categoriaKey': _categoriaId, // mantém compatibilidade
        'categoriaNome': _categoriaNomeController.text.trim(),
        'valor': valor,
        'diaVencimento': diaVencimento,
        'ativo': _ativo,
        'observacao': _observacaoController.text.trim(),
        'tipo': _isPagar ? 'pagar' : 'receber',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isPagar) {
        data['fornecedorId'] = _clienteFornecedorId;
        data['fornecedorNome'] = _clienteFornecedorController.text.trim();
      } else {
        data['clienteId'] = _clienteFornecedorId;
        data['clienteNome'] = _clienteFornecedorController.text.trim();
      }

      if (widget.recorrenciaId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['createdByUid'] = user.uid;
        data['ultimaGeracao'] = null;

        await _fs.collection(_collectionName).add(data);
      } else {
        await _fs
            .collection(_collectionName)
            .doc(widget.recorrenciaId)
            .update(data);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recorrência salva com sucesso.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3B0CA3),
            Color(0xFF5B21B6),
            Color(0xFFF97316),
          ],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.recorrenciaId != null
                          ? 'Editar Recorrência'
                          : 'Nova Recorrência',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _titulo,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPagar ? Icons.upload_rounded : Icons.download_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isPagar ? 'Pagar' : 'Receber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
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

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF3B0CA3), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3B0CA3), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B0CA3)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.tune_rounded,
                                    color: Color(0xFF3B0CA3), size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Dados da Recorrência',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _descricaoController,
                              decoration: _decoration(
                                'Descrição do título',
                                Icons.description_outlined,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe a descrição.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _clienteFornecedorController,
                              readOnly: true,
                              decoration: _decoration(
                                _isPagar ? 'Fornecedor' : 'Cliente',
                                _isPagar
                                    ? Icons.store_outlined
                                    : Icons.person_outline,
                              ).copyWith(
                                suffixIcon: const Icon(
                                  Icons.search,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              onTap: _selecionarClienteFornecedor,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return _isPagar
                                      ? 'Selecione o fornecedor.'
                                      : 'Selecione o cliente.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _categoriaNomeController,
                              readOnly: true,
                              decoration: _decoration(
                                'Categoria Financeira',
                                Icons.category_outlined,
                              ).copyWith(
                                suffixIcon: const Icon(
                                  Icons.search,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              onTap: _selecionarCategoria,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Selecione a categoria.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _valorController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _decoration(
                                      'Valor mensal',
                                      Icons.payments_outlined,
                                    ).copyWith(prefixText: 'R\$ '),
                                    validator: (v) {
                                      if (_parseValor(v ?? '') <= 0) {
                                        return 'Valor inválido.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _diaVencimentoController,
                                    keyboardType: TextInputType.number,
                                    decoration: _decoration(
                                      'Dia Venc.',
                                      Icons.calendar_month_outlined,
                                    ),
                                    validator: (v) {
                                      final dia = int.tryParse(v ?? '');
                                      if (dia == null || dia < 1 || dia > 31) {
                                        return '1 a 31';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _observacaoController,
                              maxLines: 3,
                              decoration: _decoration(
                                'Observações adicionais (opcional)',
                                Icons.notes_outlined,
                              ),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: const Color(0xFFEDF2F7)),
                              ),
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                activeTrackColor: const Color(0xFF3B0CA3),
                                value: _ativo,
                                title: const Text(
                                  'Recorrência Ativa',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                subtitle: const Text(
                                  'Quando ativa, gera automaticamente contas mensais.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                onChanged: (v) {
                                  setState(() => _ativo = v);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _salvar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B0CA3),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 20),
                          label: Text(
                            _saving ? 'Salvando...' : 'Salvar Recorrência',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
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
