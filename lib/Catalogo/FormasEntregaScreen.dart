import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FormasEntregaScreen extends StatefulWidget {
  const FormasEntregaScreen({super.key});

  @override
  State<FormasEntregaScreen> createState() => _FormasEntregaScreenState();
}

class _FormasEntregaScreenState extends State<FormasEntregaScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _saving = false;
  bool _mostrarSucesso = false;

  String? _companyId;
  String? _erro;

  final List<_FormaEntrega> _formas = [];

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

  _FormaEntrega _formaPadraoLocal() {
    return _FormaEntrega(
      id: 'retirada_local',
      tipo: 'retirada',
      nome: 'Retirada no local',
      descricao:
          'O cliente deverá retirar o pedido no estabelecimento após a confirmação.',
      valor: 0,
      prazo: 'Retirada no local',
      ativo: true,
    );
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

      _formas.clear();

      final doc = await _fs.collection('catalogo').doc(companyId).get();
      final data = doc.data();
      final formasRaw = data?['formasEntrega'];

      if (formasRaw is List) {
        for (final item in formasRaw) {
          if (item is Map) {
            _formas.add(
              _FormaEntrega(
                id:
                    (item['id'] ??
                            DateTime.now().millisecondsSinceEpoch.toString())
                        .toString(),
                tipo: (item['tipo'] ?? 'entrega').toString(),
                nome: (item['nome'] ?? '').toString().trim(),
                descricao: (item['descricao'] ?? '').toString().trim(),
                valor: (item['valor'] as num?)?.toDouble() ?? 0.0,
                prazo: (item['prazo'] ?? 'A combinar').toString().trim(),
                ativo: (item['ativo'] ?? true) == true,
              ),
            );
          }
        }
      }

      if (_formas.isEmpty) {
        _formas.add(_formaPadraoLocal());
      }

      setState(() {
        _companyId = companyId;
        _loading = false;
        _erro = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _erro = 'Erro ao carregar forma de entrega: $e';
      });
    }
  }

  Future<void> _salvarDireto() async {
    final companyId = _companyId;

    if (companyId == null || companyId.isEmpty) return;

    final formasEntrega =
        _formas.map((f) {
          return {
            'id': f.id,
            'tipo': f.tipo,
            'nome': f.nome.trim(),
            'descricao': f.descricao.trim(),
            'valor': f.valor,
            'prazo': f.prazo.trim(),
            'ativo': f.ativo,
          };
        }).toList();

    await _fs.collection('catalogo').doc(companyId).set({
      'companyId': companyId,
      'formasEntrega': formasEntrega,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => _mostrarSucesso = true);

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _mostrarSucesso = false);
      }
    });
  }

  Future<void> _salvar() async {
    final companyId = _companyId;

    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    if (_formas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre pelo menos uma forma de entrega.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final formasEntrega =
          _formas.map((f) {
            return {
              'id': f.id,
              'tipo': f.tipo,
              'nome': f.nome.trim(),
              'descricao': f.descricao.trim(),
              'valor': f.valor,
              'prazo': f.prazo.trim(),
              'ativo': f.ativo,
            };
          }).toList();

      await _fs.collection('catalogo').doc(companyId).set({
        'companyId': companyId,
        'formasEntrega': formasEntrega,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _saving = false;
        _mostrarSucesso = true;
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() => _mostrarSucesso = false);
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar configuração: $e')),
      );
    }
  }

  Future<void> _abrirFormularioForma({_FormaEntrega? forma}) async {
    final nomeCtrl = TextEditingController(text: forma?.nome ?? '');
    final descCtrl = TextEditingController(text: forma?.descricao ?? '');
    final prazoCtrl = TextEditingController(text: forma?.prazo ?? '');
    final valorCtrl = TextEditingController(
      text:
          forma == null
              ? '0,00'
              : forma.valor.toStringAsFixed(2).replaceAll('.', ','),
    );

    bool ativo = forma?.ativo ?? true;

    final result = await showDialog<_FormaEntrega>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                forma == null
                    ? 'Nova forma de entrega'
                    : 'Editar forma de entrega',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: prazoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Prazo',
                        hintText: 'Ex: 30 a 60 minutos',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: valorCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        hintText: '0,00',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ativo,
                      title: const Text('Ativo'),
                      onChanged: (v) {
                        setDialogState(() => ativo = v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final nome = nomeCtrl.text.trim();

                    if (nome.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Informe o nome da forma de entrega.'),
                        ),
                      );
                      return;
                    }

                    final valor =
                        double.tryParse(
                          valorCtrl.text
                              .replaceAll('R\$', '')
                              .replaceAll('.', '')
                              .replaceAll(',', '.')
                              .trim(),
                        ) ??
                        0.0;

                    final novaForma = _FormaEntrega(
                      id:
                          forma?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      tipo: forma?.tipo ?? 'entrega',
                      nome: nome,
                      descricao: descCtrl.text.trim(),
                      valor: valor,
                      prazo:
                          prazoCtrl.text.trim().isEmpty
                              ? 'A combinar'
                              : prazoCtrl.text.trim(),
                      ativo: ativo,
                    );

                    // Atualiza lista local
                    setState(() {
                      final index = _formas.indexWhere(
                        (f) => f.id == novaForma.id,
                      );
                      if (index >= 0) {
                        _formas[index] = novaForma;
                      } else {
                        _formas.add(novaForma);
                      }
                    });

                    // 🔥 SALVA DIRETO NO FIRESTORE
                    await _salvarDireto();

                    if (!mounted) return;

                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nomeCtrl.dispose();
    descCtrl.dispose();
    prazoCtrl.dispose();
    valorCtrl.dispose();

    if (result == null) return;

    setState(() {
      final index = _formas.indexWhere((f) => f.id == result.id);

      if (index >= 0) {
        _formas[index] = result;
      } else {
        _formas.add(result);
      }
    });
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
                onPressed: () => setState(() => _mostrarSucesso = false),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtMoeda(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Forma de entrega')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Forma de entrega')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_mostrarSucesso) _buildSucessoBanner(),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Formas cadastradas',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _abrirFormularioForma(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            ..._formas.map((forma) {
              return Card(
                key: ValueKey(forma.id),
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    child: Icon(
                      forma.tipo == 'retirada'
                          ? Icons.storefront_outlined
                          : Icons.local_shipping_outlined,
                    ),
                  ),
                  title: Text(
                    forma.nome,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (forma.descricao.isNotEmpty) Text(forma.descricao),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Chip(
                            label: Text(
                              forma.valor <= 0
                                  ? 'Sem cobrança'
                                  : _fmtMoeda(forma.valor),
                            ),
                          ),
                          Chip(label: Text(forma.prazo)),
                          Chip(label: Text(forma.ativo ? 'Ativo' : 'Inativo')),
                        ],
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'editar') {
                        _abrirFormularioForma(forma: forma);
                      }

                      if (value == 'remover') {
                        if (_formas.length == 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Cadastre pelo menos uma forma de entrega.',
                              ),
                            ),
                          );
                          return;
                        }

                        setState(() {
                          _formas.removeWhere((f) => f.id == forma.id);
                        });

                        await _salvarDireto();
                      }
                    },
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem(
                            value: 'editar',
                            child: Text('Editar'),
                          ),
                          const PopupMenuItem(
                            value: 'remover',
                            child: Text('Remover'),
                          ),
                        ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),

            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class _FormaEntrega {
  final String id;
  final String tipo;
  final String nome;
  final String descricao;
  double valor;
  String prazo;
  bool ativo;

  _FormaEntrega({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.descricao,
    required this.valor,
    required this.prazo,
    required this.ativo,
  });
}
