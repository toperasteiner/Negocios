// lib/Pedidos/SelecionarStatusPedidoScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Se já tiver esse enum/labels em outro arquivo, remova daqui e importe.
enum PedidoStatus {
  pendente,
  aguardando_aprovacao,
  aprovado,
  em_andamento,
  aguardando_pagamento,
  enviado,
  concluido,
  garantia,
  cancelado,
}

String statusLabel(PedidoStatus s) {
  switch (s) {
    case PedidoStatus.pendente:
      return 'Pendente';
    case PedidoStatus.aguardando_aprovacao:
      return 'Aguardando aprovação';
    case PedidoStatus.aprovado:
      return 'Aprovado';
    case PedidoStatus.em_andamento:
      return 'Em andamento';
    case PedidoStatus.aguardando_pagamento:
      return 'Aguardando pagamento';
    case PedidoStatus.enviado:
      return 'Enviado';
    case PedidoStatus.concluido:
      return 'Concluído';
    case PedidoStatus.garantia:
      return 'Garantia';
    case PedidoStatus.cancelado:
      return 'Cancelado';
  }
}

Color statusDotColor(PedidoStatus s) {
  switch (s) {
    case PedidoStatus.pendente:
    case PedidoStatus.aguardando_aprovacao:
      return const Color(0xFFD68B00); // laranja
    case PedidoStatus.aprovado:
    case PedidoStatus.em_andamento:
    case PedidoStatus.aguardando_pagamento:
    case PedidoStatus.enviado:
      return const Color(0xFF4D75C9); // azul
    case PedidoStatus.concluido:
    case PedidoStatus.garantia:
      return const Color(0xFF49A35B); // verde
    case PedidoStatus.cancelado:
      return const Color(0xFFE05656); // vermelho
  }
}

/// TELA: escolha e gravação do status do pedido.
class SelecionarStatusPedidoScreen extends StatefulWidget {
  final String pedidoId; // 🚩 obrigatório
  /// `initial` é usado como fallback caso o doc não tenha status.
  final PedidoStatus initial;
  final FirebaseFirestore? firestoreOverride; // para testes/mocks

  const SelecionarStatusPedidoScreen({
    super.key,
    required this.pedidoId,
    this.initial = PedidoStatus.pendente,
    this.firestoreOverride,
  });

  @override
  State<SelecionarStatusPedidoScreen> createState() =>
      _SelecionarStatusPedidoScreenState();
}

class _SelecionarStatusPedidoScreenState
    extends State<SelecionarStatusPedidoScreen> {
  late PedidoStatus _selecionado;
  bool _salvando = false;
  bool _carregando = true;

  FirebaseFirestore get _fs =>
      widget.firestoreOverride ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.initial;
    _carregarStatusAtual();
  }

  /// Busca o documento do pedido e define o status inicial da tela.
  Future<void> _carregarStatusAtual() async {
    try {
      final doc = await _fs.collection('pedidos').doc(widget.pedidoId).get();
      final data = doc.data();
      if (data != null) {
        final raw = (data['status'] ?? '').toString();
        final rawLabel = (data['statusLabel'] ?? '').toString();
        final parsed = _parseStatus(raw, rawLabel) ?? widget.initial;
        if (mounted) setState(() => _selecionado = parsed);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível ler o status atual: $e')),
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Converte strings comuns do banco para o enum.
  PedidoStatus? _parseStatus(String rawStatus, String rawLabel) {
    String norm(String s) =>
        s.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

    final r = norm(rawStatus);
    if (r.isNotEmpty) {
      for (final v in PedidoStatus.values) {
        if (norm(v.name) == r) return v; // bate com o .name salvo
      }
    }

    final l = norm(rawLabel);
    if (l.isNotEmpty) {
      switch (l) {
        case 'pendente':
          return PedidoStatus.pendente;
        case 'aguardando_aprovacao':
          return PedidoStatus.aguardando_aprovacao;
        case 'aprovado':
          return PedidoStatus.aprovado;
        case 'em_andamento':
          return PedidoStatus.em_andamento;
        case 'aguardando_pagamento':
          return PedidoStatus.aguardando_pagamento;
        case 'enviado':
          return PedidoStatus.enviado;
        case 'concluido':
        case 'concluído': // tolera acento removido
          return PedidoStatus.concluido;
        case 'garantia':
          return PedidoStatus.garantia;
        case 'cancelado':
          return PedidoStatus.cancelado;
      }
    }
    return null; // deixa cair no fallback
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await _fs.collection('pedidos').doc(widget.pedidoId).update({
        'status': _selecionado.name, // salva como string estável
        'statusLabel': statusLabel(_selecionado),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop<PedidoStatus>(context, _selecionado);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar status: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: const Text('Situação do pedido'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: (_salvando || _carregando) ? null : _salvar,
            child:
                _salvando
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Salvar status'),
          ),
        ),
      ),
      body:
          _carregando
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: PedidoStatus.values.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final s = PedidoStatus.values[i];
                  final active = s == _selecionado;
                  return Material(
                    color:
                        active
                            ? cs.primary.withOpacity(.08)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.circle,
                        size: 14,
                        color: statusDotColor(s),
                      ),
                      title: Text(statusLabel(s)),
                      trailing:
                          active
                              ? Icon(Icons.check_circle, color: cs.primary)
                              : null,
                      onTap: () => setState(() => _selecionado = s),
                    ),
                  );
                },
              ),
    );
  }
}
