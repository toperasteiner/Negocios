import 'package:flutter/material.dart';

// Ajuste o import abaixo conforme a localização real da tela:
import 'TextosPadroesScreen.dart';
import 'PagamentosPreferenciasScreen.dart';

class PreferenciasScreen extends StatelessWidget {
  const PreferenciasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Preferências')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        children: [
          /*_PrefTile(
            icon: Icons.list_alt_outlined,
            color: cs.primary,
            title: 'Pedidos & Catálogos',
            subtitle: 'Escolha campos, unidades e muito mais',
            onTap: () {
              // TODO: Navegar para tela de preferências de pedidos/catálogos
            },
          ),
          _PrefTile(
            icon: Icons.event_note_outlined,
            color: Colors.indigo,
            title: 'Agenda',
            subtitle: 'Configure seus compromissos',
            onTap: () {
              // TODO: Tela de preferências da agenda
            },
          ),*/
          _PrefTile(
            icon: Icons.payments_outlined,
            color: Colors.teal,
            title: 'Pagamentos',
            subtitle: 'Escolha meios e condições de pagamento',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PagamentosPreferenciasScreen(),
                ),
              );
            },
          ),
          /*_PrefTile(
            icon: Icons.request_quote_outlined,
            color: Colors.deepPurple,
            title: 'Financeiro',
            subtitle: 'Escolha moeda e categorias de custos',
            onTap: () {
              // TODO: Tela de preferências financeiras
            },
          ),
          _PrefTile(
            icon: Icons.description_outlined,
            color: Colors.orange,
            title: 'Documentos',
            subtitle: 'Escolha modelo, cor, tipo e mais',
            onTap: () {
              // TODO: Tela de preferências de documentos
            },
          ),*/
          _PrefTile(
            icon: Icons.sticky_note_2_outlined,
            color: Colors.pink,
            title: 'Textos padronizados',
            subtitle: 'Crie textos padronizados para os pedidos',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TextosPadroesScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _PrefTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
