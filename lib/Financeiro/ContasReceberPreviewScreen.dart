// lib/Financeiro/ContasReceberPreviewScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Pedidos/ConfigurarPagamentoScreen.dart'; // usa PagamentoConfig

// topo do arquivo (após imports)
const _CR_CAT_KEY = 'vendas_produtos_servicos';
const _CR_CAT_NAME = 'Vendas de produtos/serviços';

class ContasReceberPreviewScreen extends StatefulWidget {
  final String pedidoId;
  final double totalPedido;
  final PagamentoConfig pagamento;
  final String? clienteNome;

  // 👇 já existiam
  final int numero;
  final int ano;

  // 👇 NOVO (opcional): se o chamador já tiver o escopo resolvido
  final String? scopeUserId;

  const ContasReceberPreviewScreen({
    super.key,
    required this.pedidoId,
    required this.totalPedido,
    required this.pagamento,
    this.clienteNome,
    required this.numero,
    required this.ano,
    this.scopeUserId,
  });

  @override
  State<ContasReceberPreviewScreen> createState() =>
      _ContasReceberPreviewScreenState();
}

class _ContasReceberPreviewScreenState
    extends State<ContasReceberPreviewScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ===== escopo multiempresa =====
  String? _scopeUserId; // = companyId ?? uid
  String? _companyId;
  bool _loadingScope = true;
  String? _scopeError;

  bool _salvando = false;
  late List<_Parcela> _parcelas;

  // ======== helpers de moeda/data ========
  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final p = s.split('.');
    final inteiro = p[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${p[1]}';
  }

  double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void initState() {
    super.initState();
    _parcelas = _gerarParcelas(
      total: widget.totalPedido,
      parcelado: widget.pagamento.parcelado,
      n: widget.pagamento.parcelado ? widget.pagamento.numeroParcelas : 1,
      primeiroVenc: DateTime(
        widget.pagamento.dataPrimeiroPgto.year,
        widget.pagamento.dataPrimeiroPgto.month,
        widget.pagamento.dataPrimeiroPgto.day,
      ),
    );
    _initScope();
  }

  // ======== ESCOP0 ========
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
        _scopeError = null;
        _loadingScope = false;
      });
    } catch (e) {
      setState(() {
        _scopeError = 'Erro ao resolver escopo: $e';
        _loadingScope = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord(User u) async {
    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) return (byUid.data() ?? {}) as Map<String, dynamic>;
    } catch (_) {}
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

  // ======== parcelas ========
  List<_Parcela> _gerarParcelas({
    required double total,
    required bool parcelado,
    required int n,
    required DateTime primeiroVenc,
  }) {
    final totalCents = (total * 100).round();
    final nParc = parcelado ? n.clamp(1, 360) : 1;
    final baseCents = totalCents ~/ nParc;
    final resto = totalCents - baseCents * nParc;

    final out = <_Parcela>[];
    for (int i = 0; i < nParc; i++) {
      final cents = baseCents + (i < resto ? 1 : 0);
      final valor = cents / 100.0;
      final venc = DateTime(
        primeiroVenc.year,
        primeiroVenc.month + i,
        primeiroVenc.day,
      );
      out.add(
        _Parcela(numero: i + 1, total: nParc, valor: valor, vencimento: venc),
      );
    }
    return out;
  }

  double get _somaParcelas =>
      _parcelas.fold(0.0, (a, p) => a + (p.valor.isFinite ? p.valor : 0.0));

  double get _diffTotal => (_somaParcelas - widget.totalPedido);

  bool get _totalOK {
    final a = (_somaParcelas * 100).round();
    final b = (widget.totalPedido * 100).round();
    return a == b;
  }

  Future<void> _editarData(int idx) async {
    final atual = _parcelas[idx].vencimento;
    final d = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(atual.year - 2, 1, 1),
      lastDate: DateTime(atual.year + 5, 12, 31),
      helpText: 'Escolha o vencimento',
    );
    if (d == null) return;
    setState(() {
      _parcelas[idx] = _parcelas[idx].copyWith(
        vencimento: DateTime(d.year, d.month, d.day),
      );
    });
  }

  void _ajustarUltimaParcela() {
    final centsSoma = (_somaParcelas * 100).round();
    final centsTotal = (widget.totalPedido * 100).round();
    final delta = centsTotal - centsSoma;
    if (delta == 0 || _parcelas.isEmpty) return;
    setState(() {
      final last = _parcelas.last;
      final novo = ((last.valor * 100).round() + delta) / 100.0;
      _parcelas[_parcelas.length - 1] = last.copyWith(valor: novo);
    });
  }

  Future<bool> _perguntar(String titulo, String mensagem) async {
    return (await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(titulo),
                content: Text(mensagem),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Não'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sim'),
                  ),
                ],
              ),
        )) ??
        false;
  }

  Future<int> _qtdExistentes(String scopeId) async {
    // Preferencial: filtra por companyId (escopo correto)
    final q1 =
        await _fs
            .collection('contas_receber')
            .where('companyId', isEqualTo: scopeId)
            .where('pedidoId', isEqualTo: widget.pedidoId)
            .get();
    if (q1.size > 0) return q1.size;

    // Legado: alguns registros antigos podem ter sido gravados apenas com userId = scopeId
    final q2 =
        await _fs
            .collection('contas_receber')
            .where('userId', isEqualTo: scopeId)
            .where('pedidoId', isEqualTo: widget.pedidoId)
            .get();
    return q2.size;
  }

  Future<void> _apagarExistentes(String scopeId) async {
    // Apaga por companyId (escopo atual)
    var snap =
        await _fs
            .collection('contas_receber')
            .where('companyId', isEqualTo: scopeId)
            .where('pedidoId', isEqualTo: widget.pedidoId)
            .get();

    // Se nada encontrado, tenta legado por userId
    if (snap.size == 0) {
      snap =
          await _fs
              .collection('contas_receber')
              .where('userId', isEqualTo: scopeId)
              .where('pedidoId', isEqualTo: widget.pedidoId)
              .get();
    }

    final batch = _fs.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  Future<void> _criarRegistros(String scopeId) async {
    final codigoPedido =
        '${widget.numero.toString().padLeft(3, '0')}-${widget.ano}';
    final batch = _fs.batch();

    for (final p in _parcelas) {
      final payload = {
        'userId': _auth.currentUser?.uid,
        'createdByUid': _auth.currentUser?.uid,
        'pedidoId': widget.pedidoId,
        'pedidoNumero': widget.numero,
        'pedidoAno': widget.ano,
        'pedidoCodigo': codigoPedido,
        'origem': 'pedido',
        'clienteNome': widget.clienteNome,
        'parcelaNumero': p.numero,
        'parcelasTotal': p.total,
        'valor': p.valor,
        'vencimento': Timestamp.fromDate(
          DateTime(p.vencimento.year, p.vencimento.month, p.vencimento.day),
        ),
        'status': 'aberto',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'companyId': _scopeUserId,

        // >>> CATEGORIA FIXA (requisito)
        'categoriaKey': _CR_CAT_KEY, // <-- ADICIONADO
        'categoriaNome': _CR_CAT_NAME, // <-- ADICIONADO
      };
      batch.set(_fs.collection('contas_receber').doc(), payload);
    }

    await batch.commit();
  }

  /// Fluxo automático (se quiser chamar em onInit/future). Mantive aqui caso use.
  Future<void> _fluxoChecarCriarOuRecriar() async {
    final scopeId = _scopeUserId;
    if (scopeId == null) return;
    if (!_totalOK) return;

    final existentes = await _qtdExistentes(scopeId);

    if (existentes > 0) {
      final ok = await _perguntar(
        'Registros encontrados',
        'Já existem registros no contas a receber para esse pedido, '
            'deseja eliminar e recriar com os novos dados?',
      );
      if (!ok) return;

      setState(() => _salvando = true);
      try {
        await _apagarExistentes(scopeId);
        await _criarRegistros(scopeId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registros recriados (${_parcelas.length}).'),
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Falha ao recriar: $e')));
        }
      } finally {
        if (mounted) setState(() => _salvando = false);
      }
    } else {
      final ok = await _perguntar(
        'Criar recebíveis',
        'Deseja criar os registros no contas a receb?',
      );
      if (!ok) return;

      setState(() => _salvando = true);
      try {
        await _criarRegistros(scopeId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Registros criados (${_parcelas.length}).')),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Falha ao criar: $e')));
        }
      } finally {
        if (mounted) setState(() => _salvando = false);
      }
    }
  }

  /// Botão "Confirmar e salvar" – aplica a MESMA regra, agora com escopo.
  Future<void> _confirmarESalvar() async {
    if (!_totalOK) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A soma das parcelas (${_fmtMoeda(_somaParcelas)}) deve ser igual ao total do pedido (${_fmtMoeda(widget.totalPedido)}).',
          ),
          action: SnackBarAction(
            label: 'Ajustar última',
            onPressed: _ajustarUltimaParcela,
          ),
        ),
      );
      return;
    }

    final scopeId = _scopeUserId;
    if (scopeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível determinar o escopo.')),
      );
      return;
    }

    final existentes = await _qtdExistentes(scopeId);
    bool prosseguir = true;
    bool apagarAntes = false;

    if (existentes > 0) {
      prosseguir = await _perguntar(
        'Registros encontrados',
        'Já existem registros no contas a receber para esse pedido, '
            'deseja eliminar e recriar com os novos dados?',
      );
      apagarAntes = prosseguir;
    } else {
      prosseguir = await _perguntar(
        'Criar recebíveis',
        'Deseja criar os registros no contas a receber?',
      );
    }

    if (!prosseguir) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma alteração realizada.')),
        );
        Navigator.pop(context, false);
      }
      return;
    }

    setState(() => _salvando = true);
    try {
      if (apagarAntes) await _apagarExistentes(scopeId);
      await _criarRegistros(scopeId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              apagarAntes
                  ? 'Registros recriados (${_parcelas.length}).'
                  : 'Registros criados (${_parcelas.length}).',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalFmt = _fmtMoeda(widget.totalPedido);
    final titulo =
        widget.pagamento.parcelado
            ? 'Gerar parcelas (${_parcelas.length}x)'
            : 'Pagamento à vista';

    final codigoPedido =
        '${widget.numero.toString().padLeft(3, '0')}-${widget.ano}';

    if (_loadingScope) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Recebíveis • $titulo'),
        actions: [
          if (_scopeUserId != null)
            IconButton(
              tooltip: 'Escopo: $_scopeUserId',
              onPressed: () {},
              icon: const Icon(Icons.account_tree_outlined),
            ),
          TextButton.icon(
            onPressed: _salvando || !_totalOK ? null : _confirmarESalvar,
            icon: const Icon(Icons.save_alt),
            label: const Text('Confirmar'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scopeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _scopeError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // cabeçalho
          ListTile(
            title: Text(
              widget.clienteNome?.isNotEmpty == true
                  ? widget.clienteNome!
                  : 'Cliente',
            ),
            subtitle: Text('Pedido $codigoPedido • Total $totalFmt'),
          ),
          // barra de status dos totais
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color:
                _totalOK
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.08),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Soma das parcelas: ${_fmtMoeda(_somaParcelas)}'
                    '  •  Pedido: ${_fmtMoeda(widget.totalPedido)}'
                    '${_totalOK ? '' : '  •  Dif.: ${_fmtMoeda(_diffTotal.abs())}'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _totalOK ? Colors.green[800] : Colors.red[800],
                    ),
                  ),
                ),
                if (!_totalOK)
                  TextButton(
                    onPressed: _ajustarUltimaParcela,
                    child: const Text('Ajustar última'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // lista editável
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _parcelas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _parcelas[i];
                final titulo =
                    widget.pagamento.parcelado
                        ? 'Parcela ${p.numero}/${p.total}'
                        : 'À vista';

                final valorCtrl = TextEditingController(
                  text: p.valor.toStringAsFixed(2).replaceAll('.', ','),
                );

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // linha superior: título + valor editável
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                titulo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: valorCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d\., ]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Valor',
                                  prefixText: 'R\$ ',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (txt) {
                                  final v = _parseMoeda(txt);
                                  setState(() {
                                    _parcelas[i] = p.copyWith(
                                      valor: v.isFinite ? v : 0.0,
                                    );
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // linha inferior: data + botão alterar
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Venc.: ${_fmtData(p.vencimento)}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _editarData(i),
                              icon: const Icon(Icons.event),
                              label: const Text('Alterar vencimento'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Rodapé com botões
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: !_totalOK ? _ajustarUltimaParcela : null,
                      icon: const Icon(Icons.tune),
                      label: const Text('Ajustar última parcela'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _salvando || !_totalOK ? null : _confirmarESalvar,
                      icon:
                          _salvando
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.check),
                      label: const Text('Confirmar e salvar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Parcela {
  final int numero;
  final int total;
  final double valor;
  final DateTime vencimento;
  _Parcela({
    required this.numero,
    required this.total,
    required this.valor,
    required this.vencimento,
  });

  _Parcela copyWith({
    int? numero,
    int? total,
    double? valor,
    DateTime? vencimento,
  }) {
    return _Parcela(
      numero: numero ?? this.numero,
      total: total ?? this.total,
      valor: valor ?? this.valor,
      vencimento: vencimento ?? this.vencimento,
    );
  }
}
