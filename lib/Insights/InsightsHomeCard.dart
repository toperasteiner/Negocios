import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../Insights/insights_service.dart';
import '../Insights/insights_models.dart';

class InsightsHomeCard extends StatelessWidget {
  final String scopeField;
  final String scopeUserId;

  const InsightsHomeCard({
    super.key,
    required this.scopeField,
    required this.scopeUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (scopeUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final inicioMes = DateTime(now.year, now.month, 1);
    final fimMes =
        now.month == 12
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);

    final service = InsightsService(FirebaseFirestore.instance);

    return FutureBuilder<List<InsightItem>>(
      future: service.carregarInsights(
        scopeField: scopeField,
        scopeUserId: scopeUserId,
        inicio: inicioMes,
        fim: fimMes,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snap.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Erro ao carregar insights: ${snap.error}'),
            ),
          );
        }

        final insights = snap.data ?? [];

        if (insights.isEmpty) {
          return const SizedBox.shrink();
        }

        final principais = insights.take(5).toList();

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insights do mês',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Alertas e oportunidades com base nos seus pedidos.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ...principais.map((i) => _InsightTile(insight: i)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InsightTile extends StatelessWidget {
  final InsightItem insight;

  const _InsightTile({required this.insight});

  @override
  Widget build(BuildContext context) {
    final color = _colorByTipo(insight.tipo);
    final icon = _iconByTipo(insight.tipo);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.14),
        child: Icon(icon, color: color),
      ),
      title: Text(
        insight.titulo,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(insight.descricao),
    );
  }

  Color _colorByTipo(InsightTipo tipo) {
    switch (tipo) {
      case InsightTipo.alerta:
        return Colors.red;
      case InsightTipo.oportunidade:
        return Colors.orange;
      case InsightTipo.resultado:
        return Colors.green;
    }
  }

  IconData _iconByTipo(InsightTipo tipo) {
    switch (tipo) {
      case InsightTipo.alerta:
        return Icons.warning_amber_outlined;
      case InsightTipo.oportunidade:
        return Icons.lightbulb_outline;
      case InsightTipo.resultado:
        return Icons.trending_up_outlined;
    }
  }
}
