import 'package:cloud_firestore/cloud_firestore.dart';
import '../Insights/insights_models.dart';

class InsightsService {
  final FirebaseFirestore fs;

  InsightsService(this.fs);

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  Future<List<InsightItem>> carregarInsights({
    required String scopeField,
    required String scopeUserId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final snap =
        await fs
            .collection('pedidos')
            .where(scopeField, isEqualTo: scopeUserId)
            .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
            .where('data', isLessThan: Timestamp.fromDate(fim))
            .get();

    final insights = <InsightItem>[];

    double faturamento = 0;
    double custo = 0;
    double lucro = 0;

    int pedidos = 0;
    int prejuizo = 0;
    int semCusto = 0;

    final Map<String, double> clienteLucro = {};
    final Map<String, double> produtoLucro = {};
    final Map<String, int> diasVenda = {};

    final Map<String, double> clienteFaturamento = {};
    final Map<String, int> clientePedidos = {};
    final Map<String, int> produtoQtd = {};
    final Map<String, double> produtoFaturamento = {};

    for (final d in snap.docs) {
      final m = d.data();

      final sub = _toDouble(m['subtotal']);
      final cus = _toDouble(m['custoTotal']);
      final luc = _toDouble(m['lucroLiquido']);
      final cliente = (m['clienteNome'] ?? '').toString();

      final data = (m['data'] as Timestamp?)?.toDate();

      faturamento += sub;
      custo += cus;
      lucro += luc;
      pedidos++;

      if (cliente.isNotEmpty) {
        clienteFaturamento[cliente] =
            (clienteFaturamento[cliente] ?? 0.0) + sub;

        clientePedidos[cliente] = (clientePedidos[cliente] ?? 0) + 1;
      }

      if (luc < 0) prejuizo++;
      if (cus <= 0 && sub > 0) semCusto++;

      if (cliente.isNotEmpty) {
        clienteLucro[cliente] = (clienteLucro[cliente] ?? 0) + luc;
      }

      if (data != null) {
        final key = "${data.day}/${data.month}";
        diasVenda[key] = (diasVenda[key] ?? 0) + 1;
      }

      // PRODUTOS
      final itens = (m['itensProdutos'] ?? []) as List;

      for (final i in itens) {
        final item = Map<String, dynamic>.from(i as Map);

        final nome = (item['nome'] ?? '').toString();
        if (nome.isEmpty) continue;

        final qtd = _toDouble(item['quantidade']);
        final lucroItem = _toDouble(item['lucroItem']);
        final totalItem = _toDouble(item['total']);

        produtoLucro[nome] = (produtoLucro[nome] ?? 0.0) + lucroItem;

        produtoQtd[nome] = (produtoQtd[nome] ?? 0) + qtd.toInt();

        produtoFaturamento[nome] =
            (produtoFaturamento[nome] ?? 0.0) + totalItem;
      }
    }

    // ===== INSIGHTS =====

    // 1 - prejuízo
    if (prejuizo > 0) {
      insights.add(
        InsightItem(
          titulo: 'Pedidos com prejuízo',
          descricao: '$prejuizo pedido(s) com lucro negativo.',
          tipo: InsightTipo.alerta,
          prioridade: 100,
        ),
      );
    }

    // 2 - sem custo
    if (semCusto > 0) {
      insights.add(
        InsightItem(
          titulo: 'Pedidos sem custo',
          descricao: '$semCusto pedido(s) sem custo cadastrado.',
          tipo: InsightTipo.alerta,
          prioridade: 95,
        ),
      );
    }

    // 3 - faturamento
    insights.add(
      InsightItem(
        titulo: 'Faturamento do mês',
        descricao: 'R\$ ${faturamento.toStringAsFixed(2)}',
        tipo: InsightTipo.resultado,
        prioridade: 80,
      ),
    );

    // 4 - lucro
    insights.add(
      InsightItem(
        titulo: 'Lucro do mês',
        descricao: 'R\$ ${lucro.toStringAsFixed(2)}',
        tipo: InsightTipo.resultado,
        prioridade: 85,
      ),
    );

    // 5 - margem
    final margem = faturamento > 0 ? (lucro / faturamento) * 100 : 0;
    insights.add(
      InsightItem(
        titulo: 'Margem média',
        descricao: '${margem.toStringAsFixed(1)}%',
        tipo: InsightTipo.resultado,
        prioridade: 70,
      ),
    );

    // 6 - melhor cliente
    if (clienteLucro.isNotEmpty) {
      final melhor = clienteLucro.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      insights.add(
        InsightItem(
          titulo: 'Melhor cliente',
          descricao:
              '${melhor.key} gerou R\$ ${melhor.value.toStringAsFixed(2)}',
          tipo: InsightTipo.oportunidade,
          prioridade: 90,
        ),
      );
    }

    // 7 - melhor produto
    if (produtoLucro.isNotEmpty) {
      final melhor = produtoLucro.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      insights.add(
        InsightItem(
          titulo: 'Produto mais lucrativo',
          descricao:
              '${melhor.key} gerou R\$ ${melhor.value.toStringAsFixed(2)}',
          tipo: InsightTipo.oportunidade,
          prioridade: 88,
        ),
      );
    }

    // 8 - ticket médio
    if (pedidos > 0) {
      final ticket = faturamento / pedidos;
      insights.add(
        InsightItem(
          titulo: 'Ticket médio',
          descricao: 'R\$ ${ticket.toStringAsFixed(2)}',
          tipo: InsightTipo.resultado,
          prioridade: 75,
        ),
      );
    }

    // 9 - dias sem venda
    final totalDias = fim.difference(inicio).inDays;
    final diasAtivos = diasVenda.length;
    final diasSemVenda = totalDias - diasAtivos;

    if (diasSemVenda > 0) {
      insights.add(
        InsightItem(
          titulo: 'Dias sem venda',
          descricao: '$diasSemVenda dia(s) sem pedidos.',
          tipo: InsightTipo.alerta,
          prioridade: 60,
        ),
      );
    }

    // cliente que mais comprou
    if (clientePedidos.isNotEmpty) {
      final top = clientePedidos.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      insights.add(
        InsightItem(
          titulo: 'Cliente mais ativo',
          descricao: '${top.key} fez ${top.value} pedidos.',
          tipo: InsightTipo.oportunidade,
          prioridade: 80,
        ),
      );
    }

    // cliente com maior faturamento
    if (clienteFaturamento.isNotEmpty) {
      final top = clienteFaturamento.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      insights.add(
        InsightItem(
          titulo: 'Cliente com maior faturamento',
          descricao: '${top.key} gerou R\$ ${top.value.toStringAsFixed(2)}',
          tipo: InsightTipo.oportunidade,
          prioridade: 78,
        ),
      );
    }

    // produto mais vendido
    if (produtoQtd.isNotEmpty) {
      final top = produtoQtd.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      insights.add(
        InsightItem(
          titulo: 'Produto mais vendido',
          descricao: '${top.key} vendido ${top.value} vezes.',
          tipo: InsightTipo.oportunidade,
          prioridade: 77,
        ),
      );
    }

    // produto maior faturamento
    if (produtoFaturamento.isNotEmpty) {
      final top = produtoFaturamento.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      insights.add(
        InsightItem(
          titulo: 'Produto que mais fatura',
          descricao: '${top.key} gerou R\$ ${top.value.toStringAsFixed(2)}',
          tipo: InsightTipo.oportunidade,
          prioridade: 76,
        ),
      );
    }

    // lucro positivo
    if (lucro > 0) {
      insights.add(
        InsightItem(
          titulo: 'Negócio lucrativo',
          descricao: 'Você teve lucro neste período.',
          tipo: InsightTipo.resultado,
          prioridade: 70,
        ),
      );
    }

    // lucro negativo
    if (lucro < 0) {
      insights.add(
        InsightItem(
          titulo: 'Atenção: prejuízo geral',
          descricao: 'Seu lucro total está negativo.',
          tipo: InsightTipo.alerta,
          prioridade: 95,
        ),
      );
    }

    // média pedidos por dia
    if (totalDias > 0) {
      final media = pedidos / totalDias;

      insights.add(
        InsightItem(
          titulo: 'Média de pedidos por dia',
          descricao: media.toStringAsFixed(1),
          tipo: InsightTipo.resultado,
          prioridade: 60,
        ),
      );
    }

    if (margem < 10 && faturamento > 0) {
      insights.add(
        InsightItem(
          titulo: 'Margem baixa',
          descricao: 'Sua margem está abaixo de 10%',
          tipo: InsightTipo.alerta,
          prioridade: 90,
        ),
      );
    }

    insights.sort((a, b) => b.prioridade.compareTo(a.prioridade));

    return insights;
  }
}
