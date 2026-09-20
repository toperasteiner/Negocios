import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'agenda_dashboard_controller.dart';

/* ============================================================
   ESTILO
   ============================================================ */

class AgendaDashboardStyle {
  static const Color primary = Color(0xFF6A2BFF);
  static const Color primaryDark = Color(0xFF32106C);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  static const Color text = Color(0xFF17152B);
  static const Color muted = Color(0xFF77758A);
  static const Color border = Color(0xFFE7E7EF);
  static const Color surface = Color(0xFFF8F8FC);
}

/* ============================================================
   FILTROS
   ============================================================ */

class AgendaDashboardFiltros extends StatelessWidget {
  final AgendaDashboardController controller;
  final VoidCallback? onPeriodoPersonalizado;

  const AgendaDashboardFiltros({
    super.key,
    required this.controller,
    this.onPeriodoPersonalizado,
  });

  @override
  Widget build(BuildContext context) {
    return AgendaDashboardSectionCard(
      title: 'Período e filtros',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PeriodoChip(
                label: 'Hoje',
                selected: controller.periodo == AgendaDashboardPeriodo.hoje,
                onTap:
                    () => controller.selecionarPeriodo(
                      AgendaDashboardPeriodo.hoje,
                    ),
              ),
              _PeriodoChip(
                label: '7 dias',
                selected: controller.periodo == AgendaDashboardPeriodo.seteDias,
                onTap:
                    () => controller.selecionarPeriodo(
                      AgendaDashboardPeriodo.seteDias,
                    ),
              ),
              _PeriodoChip(
                label: '30 dias',
                selected:
                    controller.periodo == AgendaDashboardPeriodo.trintaDias,
                onTap:
                    () => controller.selecionarPeriodo(
                      AgendaDashboardPeriodo.trintaDias,
                    ),
              ),
              _PeriodoChip(
                label: 'Este mês',
                selected: controller.periodo == AgendaDashboardPeriodo.esteMes,
                onTap:
                    () => controller.selecionarPeriodo(
                      AgendaDashboardPeriodo.esteMes,
                    ),
              ),
              _PeriodoChip(
                label: 'Personalizado',
                selected:
                    controller.periodo == AgendaDashboardPeriodo.personalizado,
                icon: Icons.date_range_outlined,
                onTap: onPeriodoPersonalizado,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${_formatarData(controller.dataInicial)} até '
            '${_formatarData(controller.dataFinal)}',
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final estreito = constraints.maxWidth < 650;

              final profissional = _FiltroDropdown(
                label: 'Profissional',
                icon: Icons.badge_outlined,
                value:
                    controller.profissionalFiltroId.isEmpty
                        ? null
                        : controller.profissionalFiltroId,
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Todos os profissionais'),
                  ),
                  ...controller.profissionais.map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.nome, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) {
                  controller.selecionarProfissional(value);
                },
              );

              final servico = _FiltroDropdown(
                label: 'Serviço',
                icon: Icons.design_services_outlined,
                value:
                    controller.servicoFiltroId.isEmpty
                        ? null
                        : controller.servicoFiltroId,
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Todos os serviços'),
                  ),
                  ...controller.servicos.map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.nome, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) {
                  controller.selecionarServico(value);
                },
              );

              if (estreito) {
                return Column(
                  children: [profissional, const SizedBox(height: 12), servico],
                );
              }

              return Row(
                children: [
                  Expanded(child: profissional),
                  const SizedBox(width: 12),
                  Expanded(child: servico),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatarData(DateTime data) {
    return DateFormat('dd/MM/yyyy', 'pt_BR').format(data);
  }
}

class _PeriodoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  const _PeriodoChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected
              ? AgendaDashboardStyle.primary
              : AgendaDashboardStyle.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color:
                  selected
                      ? AgendaDashboardStyle.primary
                      : AgendaDashboardStyle.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : AgendaDashboardStyle.muted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AgendaDashboardStyle.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltroDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _FiltroDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AgendaDashboardStyle.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AgendaDashboardStyle.border),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/* ============================================================
   INDICADORES
   ============================================================ */

class AgendaDashboardIndicadores extends StatelessWidget {
  final AgendaDashboardController controller;

  const AgendaDashboardIndicadores({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      AgendaDashboardMetricCard(
        title: 'Agendamentos',
        value: controller.totalAgendamentos.toString(),
        subtitle: '${controller.totalAgendados} ainda ativos',
        icon: Icons.calendar_month_outlined,
        accentColor: AgendaDashboardStyle.primary,
      ),
      AgendaDashboardMetricCard(
        title: 'Concluídos',
        value: controller.totalConcluidos.toString(),
        subtitle:
            '${_percentual(controller.taxaComparecimento)} de comparecimento',
        icon: Icons.check_circle_outline_rounded,
        accentColor: AgendaDashboardStyle.success,
      ),
      AgendaDashboardMetricCard(
        title: 'Faturamento',
        value: _moeda(controller.faturamento),
        subtitle: 'Atendimentos concluídos',
        icon: Icons.payments_outlined,
        accentColor: AgendaDashboardStyle.success,
      ),
      AgendaDashboardMetricCard(
        title: 'Ticket médio',
        value: _moeda(controller.ticketMedio),
        subtitle: 'Por atendimento concluído',
        icon: Icons.receipt_long_outlined,
        accentColor: AgendaDashboardStyle.info,
      ),
      AgendaDashboardMetricCard(
        title: 'Não compareceram',
        value: controller.totalNaoCompareceram.toString(),
        subtitle:
            '${_percentual(controller.taxaNaoComparecimento)} dos comparecimentos',
        icon: Icons.person_off_outlined,
        accentColor: AgendaDashboardStyle.danger,
      ),
      AgendaDashboardMetricCard(
        title: 'Cancelados',
        value: controller.totalCancelados.toString(),
        subtitle:
            '${_percentual(controller.taxaCancelamento)} dos agendamentos',
        icon: Icons.event_busy_outlined,
        accentColor: AgendaDashboardStyle.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        int colunas;

        // 2 cards por linha no celular/tablet e 3 em telas maiores.
        if (constraints.maxWidth >= 900) {
          colunas = 3;
        } else {
          colunas = 2;
        }

        const gap = 10.0;
        final largura =
            (constraints.maxWidth - ((colunas - 1) * gap)) / colunas;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children:
              cards
                  .map((card) => SizedBox(width: largura, child: card))
                  .toList(),
        );
      },
    );
  }
}

class AgendaDashboardMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  const AgendaDashboardMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AgendaDashboardStyle.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AgendaDashboardStyle.text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: AgendaDashboardStyle.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   COMPARECIMENTO
   ============================================================ */

class AgendaDashboardComparecimentoCard extends StatelessWidget {
  final AgendaDashboardController controller;

  const AgendaDashboardComparecimentoCard({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AgendaDashboardSectionCard(
      title: 'Comparecimento',
      subtitle: 'Resultado dos horários que chegaram ao atendimento',
      icon: Icons.how_to_reg_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _percentual(controller.taxaComparecimento),
                style: const TextStyle(
                  color: AgendaDashboardStyle.text,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  'taxa de comparecimento',
                  style: TextStyle(
                    color: AgendaDashboardStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 11,
              value: controller.taxaComparecimento.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFEDEDF3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AgendaDashboardStyle.success,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniResultado(
                label: 'Concluídos',
                value: controller.totalConcluidos.toString(),
                icon: Icons.check_circle_outline,
                color: AgendaDashboardStyle.success,
              ),
              _MiniResultado(
                label: 'Não compareceram',
                value: controller.totalNaoCompareceram.toString(),
                icon: Icons.person_off_outlined,
                color: AgendaDashboardStyle.danger,
              ),
              _MiniResultado(
                label: 'Cancelados',
                value: controller.totalCancelados.toString(),
                icon: Icons.event_busy_outlined,
                color: AgendaDashboardStyle.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniResultado extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniResultado({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   EVOLUÇÃO DIÁRIA - GRÁFICO SEM DEPENDÊNCIA EXTERNA
   ============================================================ */

class AgendaDashboardEvolucaoCard extends StatelessWidget {
  final AgendaDashboardController controller;

  const AgendaDashboardEvolucaoCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final dados = controller.evolucaoDiaria;

    return AgendaDashboardSectionCard(
      title: 'Resultados dos atendimentos',
      subtitle: 'Faturamento dos atendimentos concluídos por dia',
      icon: Icons.show_chart_rounded,
      child:
          dados.isEmpty
              ? const AgendaDashboardEmptyState(
                icon: Icons.show_chart_rounded,
                title: 'Sem dados no período',
                message:
                    'Quando houver atendimentos, a evolução será apresentada aqui.',
              )
              : SizedBox(
                height: 240,
                child: _GraficoBarrasFaturamento(dados: dados),
              ),
    );
  }
}

class _GraficoBarrasFaturamento extends StatelessWidget {
  final List<AgendaDashboardDia> dados;

  const _GraficoBarrasFaturamento({required this.dados});

  @override
  Widget build(BuildContext context) {
    final maximo = dados.fold<double>(
      0,
      (maior, item) => item.faturamento > maior ? item.faturamento : maior,
    );

    /*
     * Para períodos grandes, reduzimos visualmente a quantidade
     * de barras agrupando apenas a apresentação. Os dados do
     * controller permanecem diários e completos.
     */
    final exibir =
        dados.length <= 15
            ? dados
            : dados
                .whereIndexed(
                  (index, _) =>
                      index == 0 ||
                      index == dados.length - 1 ||
                      index % ((dados.length / 12).ceil()) == 0,
                )
                .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < exibir.length; i++) ...[
              Expanded(child: _BarraDia(item: exibir[i], maximo: maximo)),
              if (i < exibir.length - 1) const SizedBox(width: 5),
            ],
          ],
        );
      },
    );
  }
}

class _BarraDia extends StatelessWidget {
  final AgendaDashboardDia item;
  final double maximo;

  const _BarraDia({required this.item, required this.maximo});

  @override
  Widget build(BuildContext context) {
    final proporcao =
        maximo <= 0 ? 0.0 : (item.faturamento / maximo).clamp(0.0, 1.0);

    return Tooltip(
      message:
          '${DateFormat('dd/MM').format(item.data)}\n'
          '${_moeda(item.faturamento)}\n'
          '${item.concluidos} concluído(s)',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: proporcao == 0 ? 0.015 : proporcao,
                widthFactor: 0.72,
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        item.faturamento > 0
                            ? AgendaDashboardStyle.primary
                            : AgendaDashboardStyle.border,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('dd').format(item.data),
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   PROFISSIONAIS
   ============================================================ */

class AgendaDashboardProfissionaisCard extends StatelessWidget {
  final AgendaDashboardController controller;
  final int limite;

  const AgendaDashboardProfissionaisCard({
    super.key,
    required this.controller,
    this.limite = 5,
  });

  @override
  Widget build(BuildContext context) {
    final dados = controller.resultadoPorProfissional.take(limite).toList();

    return AgendaDashboardSectionCard(
      title: 'Desempenho por profissional',
      subtitle: 'Baseado nos atendimentos concluídos',
      icon: Icons.groups_2_outlined,
      child:
          dados.isEmpty
              ? const AgendaDashboardEmptyState(
                icon: Icons.badge_outlined,
                title: 'Nenhum atendimento concluído',
                message:
                    'O desempenho dos profissionais aparecerá após as conclusões.',
              )
              : Column(
                children: [
                  for (var i = 0; i < dados.length; i++) ...[
                    _ProfissionalLinha(posicao: i + 1, item: dados[i]),
                    if (i < dados.length - 1)
                      const Divider(
                        height: 24,
                        color: AgendaDashboardStyle.border,
                      ),
                  ],
                ],
              ),
    );
  }
}

class _ProfissionalLinha extends StatelessWidget {
  final int posicao;
  final AgendaDashboardResultadoProfissional item;

  const _ProfissionalLinha({required this.posicao, required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RankingBadge(posicao: posicao),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.profissionalNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AgendaDashboardStyle.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.atendimentos} atendimento(s) • '
                'Ticket ${_moeda(item.ticketMedio)}',
                style: const TextStyle(
                  color: AgendaDashboardStyle.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _moeda(item.faturamento),
              style: const TextStyle(
                color: AgendaDashboardStyle.text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Recebido ${_moeda(item.valorRecebido)}',
              style: const TextStyle(
                color: AgendaDashboardStyle.success,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/* ============================================================
   SERVIÇOS
   ============================================================ */

class AgendaDashboardServicosCard extends StatelessWidget {
  final AgendaDashboardController controller;
  final int limite;

  const AgendaDashboardServicosCard({
    super.key,
    required this.controller,
    this.limite = 5,
  });

  @override
  Widget build(BuildContext context) {
    final dados = controller.resultadoPorServico.take(limite).toList();

    return AgendaDashboardSectionCard(
      title: 'Serviços mais realizados',
      subtitle: 'Ranking dos atendimentos concluídos',
      icon: Icons.design_services_outlined,
      child:
          dados.isEmpty
              ? const AgendaDashboardEmptyState(
                icon: Icons.design_services_outlined,
                title: 'Nenhum serviço concluído',
                message: 'Os serviços mais realizados aparecerão neste espaço.',
              )
              : Column(
                children: [
                  for (var i = 0; i < dados.length; i++) ...[
                    _ServicoLinha(posicao: i + 1, item: dados[i]),
                    if (i < dados.length - 1)
                      const Divider(
                        height: 24,
                        color: AgendaDashboardStyle.border,
                      ),
                  ],
                ],
              ),
    );
  }
}

class _ServicoLinha extends StatelessWidget {
  final int posicao;
  final AgendaDashboardResultadoServico item;

  const _ServicoLinha({required this.posicao, required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RankingBadge(posicao: posicao),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.servicoNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AgendaDashboardStyle.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.atendimentos} atendimento(s) • '
                'Ticket ${_moeda(item.ticketMedio)}',
                style: const TextStyle(
                  color: AgendaDashboardStyle.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _moeda(item.faturamento),
          style: const TextStyle(
            color: AgendaDashboardStyle.text,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _RankingBadge extends StatelessWidget {
  final int posicao;

  const _RankingBadge({required this.posicao});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 31,
      height: 31,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AgendaDashboardStyle.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AgendaDashboardStyle.border),
      ),
      child: Text(
        '$posicaoº',
        style: const TextStyle(
          color: AgendaDashboardStyle.primaryDark,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/* ============================================================
   CANCELAMENTOS E FALTAS
   ============================================================ */

class AgendaDashboardPerdasCard extends StatelessWidget {
  final AgendaDashboardController controller;

  const AgendaDashboardPerdasCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AgendaDashboardSectionCard(
      title: 'Cancelamentos e faltas',
      subtitle: 'Valor potencial não realizado no período',
      icon: Icons.trending_down_rounded,
      child: Column(
        children: [
          _PerdaLinha(
            label: 'Cancelamentos',
            quantidade: controller.totalCancelados,
            valor: controller.valorPotencialCancelamentos,
            icon: Icons.event_busy_outlined,
            color: AgendaDashboardStyle.warning,
          ),
          const Divider(height: 26, color: AgendaDashboardStyle.border),
          _PerdaLinha(
            label: 'Não compareceram',
            quantidade: controller.totalNaoCompareceram,
            valor: controller.valorPotencialNaoComparecimento,
            icon: Icons.person_off_outlined,
            color: AgendaDashboardStyle.danger,
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AgendaDashboardStyle.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AgendaDashboardStyle.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Potencial não realizado',
                        style: TextStyle(
                          color: AgendaDashboardStyle.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Estimativa pelo valor cadastrado dos serviços',
                        style: TextStyle(
                          color: AgendaDashboardStyle.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _moeda(controller.valorPotencialNaoRealizado),
                  style: const TextStyle(
                    color: AgendaDashboardStyle.danger,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PerdaLinha extends StatelessWidget {
  final String label;
  final int quantidade;
  final double valor;
  final IconData icon;
  final Color color;

  const _PerdaLinha({
    required this.label,
    required this.quantidade,
    required this.valor,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AgendaDashboardStyle.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$quantidade ocorrência(s)',
                style: const TextStyle(
                  color: AgendaDashboardStyle.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Text(
          _moeda(valor),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   RESUMO FINANCEIRO
   ============================================================ */

class AgendaDashboardFinanceiroCard extends StatelessWidget {
  final AgendaDashboardController controller;

  const AgendaDashboardFinanceiroCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AgendaDashboardSectionCard(
      title: 'Resumo financeiro da agenda',
      subtitle: 'Valores dos atendimentos concluídos',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        children: [
          _FinanceiroLinha(
            label: 'Faturamento',
            value: controller.faturamento,
            color: AgendaDashboardStyle.text,
          ),
          const SizedBox(height: 11),
          _FinanceiroLinha(
            label: 'Recebido',
            value: controller.valorRecebido,
            color: AgendaDashboardStyle.success,
          ),
          const SizedBox(height: 11),
          _FinanceiroLinha(
            label: 'Em aberto',
            value: controller.valorEmAberto,
            color: AgendaDashboardStyle.warning,
          ),
          const Divider(height: 28, color: AgendaDashboardStyle.border),
          _FinanceiroLinha(
            label: 'Descontos concedidos',
            value: controller.totalDescontos,
            color: AgendaDashboardStyle.danger,
          ),
          const SizedBox(height: 11),
          _FinanceiroLinha(
            label: 'Acréscimos',
            value: controller.totalAcrescimos,
            color: AgendaDashboardStyle.info,
          ),
        ],
      ),
    );
  }
}

class _FinanceiroLinha extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _FinanceiroLinha({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          _moeda(value),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   COMPONENTES BASE
   ============================================================ */

class AgendaDashboardSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  const AgendaDashboardSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgendaDashboardStyle.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1ECFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AgendaDashboardStyle.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AgendaDashboardStyle.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AgendaDashboardStyle.muted,
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class AgendaDashboardEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const AgendaDashboardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AgendaDashboardStyle.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgendaDashboardStyle.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 31, color: AgendaDashboardStyle.muted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaDashboardStyle.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 10.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AgendaDashboardLoading extends StatelessWidget {
  const AgendaDashboardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class AgendaDashboardErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const AgendaDashboardErro({
    super.key,
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AgendaDashboardStyle.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: AgendaDashboardStyle.danger,
            ),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar o dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaDashboardStyle.text,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AgendaDashboardStyle.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   HELPERS
   ============================================================ */

String _moeda(double valor) {
  return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
}

String _percentual(double valor) {
  return NumberFormat.percentPattern('pt_BR').format(valor);
}

/*
 * Extensão local para evitar dependência de package:collection.
 */
extension _IterableIndexado<T> on Iterable<T> {
  Iterable<T> whereIndexed(bool Function(int index, T element) teste) sync* {
    var index = 0;

    for (final element in this) {
      if (teste(index, element)) {
        yield element;
      }

      index++;
    }
  }
}
