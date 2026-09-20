import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'agenda_dashboard_controller.dart';
import 'agenda_dashboard_widgets.dart';

class AgendaDashboardScreen extends StatefulWidget {
  const AgendaDashboardScreen({super.key});

  @override
  State<AgendaDashboardScreen> createState() => _AgendaDashboardScreenState();
}

class _AgendaDashboardScreenState extends State<AgendaDashboardScreen> {
  late final AgendaDashboardController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AgendaDashboardController();
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.inicializar();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /* ==========================================================
     PERÍODO PERSONALIZADO
     ========================================================== */

  Future<void> _selecionarPeriodoPersonalizado() async {
    final hoje = DateTime.now();

    var inicioAtual = _somenteData(_controller.dataInicial);
    var fimAtual = _somenteData(_controller.dataFinal);

    /*
     * DateTimeRange exige que o intervalo inicial esteja dentro
     * dos limites permitidos pelo DateRangePicker.
     */
    final primeiraData = DateTime(2020, 1, 1);
    final ultimaData = DateTime(hoje.year + 5, 12, 31);

    if (inicioAtual.isBefore(primeiraData)) {
      inicioAtual = primeiraData;
    }

    if (fimAtual.isBefore(inicioAtual)) {
      fimAtual = inicioAtual;
    }

    if (fimAtual.isAfter(ultimaData)) {
      fimAtual = ultimaData;
    }

    final intervalo = await showDateRangePicker(
      context: context,
      firstDate: primeiraData,
      lastDate: ultimaData,
      initialDateRange: DateTimeRange(start: inicioAtual, end: fimAtual),
      currentDate: hoje,
      helpText: 'Selecione o período',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
      fieldStartHintText: 'Data inicial',
      fieldEndHintText: 'Data final',
      fieldStartLabelText: 'Data inicial',
      fieldEndLabelText: 'Data final',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AgendaDashboardStyle.primary),
          ),
          child: child!,
        );
      },
    );

    if (intervalo == null || !mounted) {
      return;
    }

    await _controller.selecionarPeriodoPersonalizado(
      inicio: intervalo.start,
      fim: intervalo.end,
    );
  }

  /* ==========================================================
     REFRESH
     ========================================================== */

  Future<void> _atualizar() async {
    await _controller.carregarDados();
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AgendaDashboardStyle.text,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resultados da Agenda',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AgendaDashboardStyle.text,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'Acompanhe o desempenho dos seus atendimentos',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AgendaDashboardStyle.muted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _controller.carregando ? null : _atualizar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AgendaDashboardStyle.border,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    /*
     * Na primeira carga ainda não há dados para manter na tela.
     */
    if (_controller.carregando &&
        _controller.companyId.isEmpty &&
        _controller.agendamentos.isEmpty) {
      return const AgendaDashboardLoading();
    }

    /*
     * Erro de inicialização sem dados disponíveis.
     */
    if (_controller.erro != null &&
        _controller.agendamentos.isEmpty &&
        !_controller.carregando) {
      return AgendaDashboardErro(
        mensagem: _controller.erro!,
        onTentarNovamente: () {
          _controller.inicializar();
        },
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _atualizar,
          color: AgendaDashboardStyle.primary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  _paddingHorizontal(constraints.maxWidth),
                  18,
                  _paddingHorizontal(constraints.maxWidth),
                  32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CabecalhoPeriodo(controller: _controller),
                        const SizedBox(height: 16),

                        AgendaDashboardFiltros(
                          controller: _controller,
                          onPeriodoPersonalizado:
                              _selecionarPeriodoPersonalizado,
                        ),

                        if (_controller.erro != null) ...[
                          const SizedBox(height: 12),
                          _AvisoDashboard(
                            mensagem: _controller.erro!,
                            onAtualizar: _atualizar,
                          ),
                        ],

                        const SizedBox(height: 16),

                        AgendaDashboardIndicadores(controller: _controller),

                        const SizedBox(height: 16),

                        _buildPrimeiraLinha(constraints.maxWidth),

                        const SizedBox(height: 16),

                        AgendaDashboardEvolucaoCard(controller: _controller),

                        const SizedBox(height: 16),

                        _buildRankings(constraints.maxWidth),

                        const SizedBox(height: 16),

                        _buildUltimaLinha(constraints.maxWidth),

                        const SizedBox(height: 18),

                        _RodapeDashboard(controller: _controller),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        if (_controller.carregando)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AgendaDashboardStyle.primary,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }

  /* ==========================================================
     SEÇÕES RESPONSIVAS
     ========================================================== */

  Widget _buildPrimeiraLinha(double largura) {
    final comparecimento = AgendaDashboardComparecimentoCard(
      controller: _controller,
    );

    final financeiro = AgendaDashboardFinanceiroCard(controller: _controller);

    if (largura < 850) {
      return Column(
        children: [comparecimento, const SizedBox(height: 16), financeiro],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: comparecimento),
          const SizedBox(width: 16),
          Expanded(child: financeiro),
        ],
      ),
    );
  }

  Widget _buildRankings(double largura) {
    final profissionais = AgendaDashboardProfissionaisCard(
      controller: _controller,
    );

    final servicos = AgendaDashboardServicosCard(controller: _controller);

    if (largura < 900) {
      return Column(
        children: [profissionais, const SizedBox(height: 16), servicos],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: profissionais),
          const SizedBox(width: 16),
          Expanded(child: servicos),
        ],
      ),
    );
  }

  Widget _buildUltimaLinha(double largura) {
    final perdas = AgendaDashboardPerdasCard(controller: _controller);

    final resumo = _ResumoOperacionalCard(controller: _controller);

    if (largura < 850) {
      return Column(children: [perdas, const SizedBox(height: 16), resumo]);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: perdas),
          const SizedBox(width: 16),
          Expanded(child: resumo),
        ],
      ),
    );
  }

  double _paddingHorizontal(double largura) {
    if (largura >= 1200) {
      return 28;
    }

    if (largura >= 700) {
      return 20;
    }

    return 12;
  }

  static DateTime _somenteData(DateTime data) {
    return DateTime(data.year, data.month, data.day);
  }
}

/* ============================================================
   CABEÇALHO DO PERÍODO
   ============================================================ */

class _CabecalhoPeriodo extends StatelessWidget {
  final AgendaDashboardController controller;

  const _CabecalhoPeriodo({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Visão geral',
                style: TextStyle(
                  color: AgendaDashboardStyle.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _descricaoPeriodo(controller),
                style: const TextStyle(
                  color: AgendaDashboardStyle.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (controller.profissionalFiltroId.isNotEmpty ||
            controller.servicoFiltroId.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF1ECFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  size: 14,
                  color: AgendaDashboardStyle.primary,
                ),
                SizedBox(width: 5),
                Text(
                  'Filtros aplicados',
                  style: TextStyle(
                    color: AgendaDashboardStyle.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _descricaoPeriodo(AgendaDashboardController controller) {
    final inicio = DateFormat('dd/MM/yyyy').format(controller.dataInicial);
    final fim = DateFormat('dd/MM/yyyy').format(controller.dataFinal);

    if (_mesmoDia(controller.dataInicial, controller.dataFinal)) {
      return inicio;
    }

    return '$inicio a $fim';
  }

  bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/* ============================================================
   RESUMO OPERACIONAL
   ============================================================ */

class _ResumoOperacionalCard extends StatelessWidget {
  final AgendaDashboardController controller;

  const _ResumoOperacionalCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AgendaDashboardSectionCard(
      title: 'Resumo operacional',
      subtitle: 'Distribuição dos agendamentos no período',
      icon: Icons.insights_outlined,
      child: Column(
        children: [
          _ResumoOperacionalLinha(
            label: 'Total de agendamentos',
            value: controller.totalAgendamentos.toString(),
            icon: Icons.calendar_month_outlined,
            color: AgendaDashboardStyle.primary,
          ),
          const Divider(height: 25, color: AgendaDashboardStyle.border),
          _ResumoOperacionalLinha(
            label: 'Ainda ativos',
            value: controller.totalAgendados.toString(),
            icon: Icons.schedule_outlined,
            color: AgendaDashboardStyle.info,
          ),
          const Divider(height: 25, color: AgendaDashboardStyle.border),
          _ResumoOperacionalLinha(
            label: 'Concluídos',
            value: controller.totalConcluidos.toString(),
            icon: Icons.check_circle_outline,
            color: AgendaDashboardStyle.success,
          ),
          const Divider(height: 25, color: AgendaDashboardStyle.border),
          _ResumoOperacionalLinha(
            label: 'Cancelados',
            value: controller.totalCancelados.toString(),
            icon: Icons.event_busy_outlined,
            color: AgendaDashboardStyle.warning,
          ),
          const Divider(height: 25, color: AgendaDashboardStyle.border),
          _ResumoOperacionalLinha(
            label: 'Não compareceram',
            value: controller.totalNaoCompareceram.toString(),
            icon: Icons.person_off_outlined,
            color: AgendaDashboardStyle.danger,
          ),
        ],
      ),
    );
  }
}

class _ResumoOperacionalLinha extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ResumoOperacionalLinha({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AgendaDashboardStyle.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   AVISO DE ERRO DURANTE ATUALIZAÇÃO
   ============================================================ */

class _AvisoDashboard extends StatelessWidget {
  final String mensagem;
  final Future<void> Function() onAtualizar;

  const _AvisoDashboard({required this.mensagem, required this.onAtualizar});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 19,
            color: AgendaDashboardStyle.warning,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              mensagem,
              style: const TextStyle(
                color: Color(0xFF9A5A05),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              onAtualizar();
            },
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   RODAPÉ
   ============================================================ */

class _RodapeDashboard extends StatelessWidget {
  final AgendaDashboardController controller;

  const _RodapeDashboard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final quantidade = controller.agendamentosFiltrados.length;

    return Center(
      child: Column(
        children: [
          Text(
            quantidade == 1
                ? '1 agendamento considerado nos indicadores'
                : '$quantidade agendamentos considerados nos indicadores',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'O valor potencial não realizado é uma estimativa baseada '
            'no valor cadastrado dos serviços.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AgendaDashboardStyle.muted,
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
