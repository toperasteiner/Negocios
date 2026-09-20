import 'package:flutter/material.dart';
import 'MeiosPagamentoPreferenciasScreen.dart';
import 'CondicoesPagamentoPreferenciasScreen.dart';

// se você quiser já abrir a tela de meios de pagamento que você usa no pedido,
// pode descomentar o import abaixo (ajuste o caminho se for diferente):
// import '../Pedidos/MeiosPagamentoScreen.dart';

class PagamentosPreferenciasScreen extends StatelessWidget {
  const PagamentosPreferenciasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personalizar pagamentos')),
      body: ListView(
        children: [
          _PrefItem(
            title: 'Meios de pagamento',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MeiosPagamentoPreferenciasScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _PrefItem(
            title: 'Condições de pagamento',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CondicoesPagamentoPreferenciasScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _PrefItem extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _PrefItem({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
