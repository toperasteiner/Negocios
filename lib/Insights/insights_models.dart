class InsightItem {
  final String titulo;
  final String descricao;
  final InsightTipo tipo;
  final int prioridade;

  InsightItem({
    required this.titulo,
    required this.descricao,
    required this.tipo,
    required this.prioridade,
  });
}

enum InsightTipo { alerta, oportunidade, resultado }
