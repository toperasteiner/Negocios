// lib/Pedidos/MeiosPagamentoScreen.dart
import 'package:flutter/material.dart';

enum MetodoPagamento {
  boleto,
  transferencia,
  dinheiro,
  cheque,
  cartaoCredito,
  cartaoDebito,
  pix,
}

extension MetodoPagamentoX on MetodoPagamento {
  String get label {
    switch (this) {
      case MetodoPagamento.boleto:
        return 'Boleto';
      case MetodoPagamento.transferencia:
        return 'Transferência bancária';
      case MetodoPagamento.dinheiro:
        return 'Dinheiro';
      case MetodoPagamento.cheque:
        return 'Cheque';
      case MetodoPagamento.cartaoCredito:
        return 'Cartão de crédito';
      case MetodoPagamento.cartaoDebito:
        return 'Cartão de débito';
      case MetodoPagamento.pix:
        return 'PIX';
    }
  }
}

const _labels = {
  MetodoPagamento.boleto: 'Boleto',
  MetodoPagamento.transferencia: 'Transferência bancária',
  MetodoPagamento.dinheiro: 'Dinheiro',
  MetodoPagamento.cheque: 'Cheque',
  MetodoPagamento.cartaoCredito: 'Cartão de crédito',
  MetodoPagamento.cartaoDebito: 'Cartão de débito',
  MetodoPagamento.pix: 'PIX',
};

class MeiosPagamentoResult {
  final List<MetodoPagamento> selecionados;
  const MeiosPagamentoResult(this.selecionados);

  List<String> toStringList() =>
      selecionados.map((m) => _labels[m]!).toList(growable: false);

  Map<String, dynamic> toMap() => {
    'metodos': selecionados.map((m) => m.name).toList(),
  };

  String resumo() {
    if (selecionados.isEmpty) return 'nenhum selecionado';
    final nomes = toStringList();
    if (nomes.length <= 3) return nomes.join(', ');
    return '${nomes.take(3).join(", ")} +${nomes.length - 3}';
  }
}

class MeiosPagamentoScreen extends StatefulWidget {
  final List<MetodoPagamento> initial;
  final List<MetodoPagamento>? permitidos;
  const MeiosPagamentoScreen({
    super.key,
    required this.initial,
    this.permitidos,
  });

  @override
  State<MeiosPagamentoScreen> createState() => _MeiosPagamentoScreenState();
}

class _MeiosPagamentoScreenState extends State<MeiosPagamentoScreen> {
  late final Map<MetodoPagamento, bool> _checked;

  @override
  void initState() {
    super.initState();

    // se a lista inicial vier vazia, marcamos todos por padrão
    final base = List<MetodoPagamento>.from(widget.initial);

    _checked = {for (final m in MetodoPagamento.values) m: base.contains(m)};
  }

  void _toggle(MetodoPagamento m, bool v) => setState(() => _checked[m] = v);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selecionados =
        _checked.entries.where((e) => e.value).map((e) => e.key).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Meios de pagamento')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () {
              if (selecionados.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione pelo menos um meio de pagamento.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, MeiosPagamentoResult(selecionados));
            },
            child: const Text('salvar meios de pagamento'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Text(
            'Como o cliente pode pagar? Selecione aqui os meios de pagamento que você aceita.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          const Divider(),
          ...MetodoPagamento.values.map(
            (m) => CheckboxListTile(
              value: _checked[m],
              onChanged: (v) => _toggle(m, v ?? false),
              title: Text(_labels[m]!),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: cs.primary,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}
