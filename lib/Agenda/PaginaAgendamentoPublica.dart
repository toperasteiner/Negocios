import 'package:flutter/material.dart';

import 'Publico/agenda_publica_controller.dart';
import 'Publico/agenda_publica_widgets.dart';
import 'Publico/etapa_servico.dart';
import 'Publico/etapa_profissional.dart';
import 'Publico/etapa_data_horario.dart';
import 'Publico/etapa_cliente.dart';
import 'Publico/etapa_confirmacao.dart';

class PaginaAgendamentoPublica extends StatefulWidget {
  final String slug;

  const PaginaAgendamentoPublica({super.key, required this.slug});

  @override
  State<PaginaAgendamentoPublica> createState() =>
      _PaginaAgendamentoPublicaState();
}

class _PaginaAgendamentoPublicaState extends State<PaginaAgendamentoPublica> {
  late final AgendaPublicaController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AgendaPublicaController(slug: widget.slug);

    _controller.addListener(_onControllerChanged);

    _controller.inicializar();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();

    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    if (_controller.carregandoPagina) {
      return const Scaffold(
        backgroundColor: AgendaPublicaStyle.bg,
        body: Center(
          child: CircularProgressIndicator(color: AgendaPublicaStyle.primary),
        ),
      );
    }

    if (_controller.erroPagina != null) {
      return _buildPaginaErro();
    }

    if (_controller.agendamentoConcluido) {
      return _buildAgendamentoConcluido();
    }

    return Scaffold(
      backgroundColor: AgendaPublicaStyle.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AgendaPublicaHeader(
                    titulo: _controller.tituloPagina,
                    descricao: _controller.descricaoPagina,
                  ),

                  const SizedBox(height: 18),

                  AgendaPublicaProgresso(etapaAtual: _controller.etapaAtual),

                  const SizedBox(height: 18),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _buildEtapaAtual(),
                  ),

                  if (_controller.possuiContato) ...[
                    const SizedBox(height: 18),

                    AgendaPublicaContatoCard(
                      whatsapp: _controller.whatsapp,
                      instagram: _controller.instagram,
                    ),
                  ],

                  if (_controller.exibirLocalizacao) ...[
                    const SizedBox(height: 18),

                    AgendaPublicaLocalizacaoCard(
                      endereco: _controller.endereco,
                    ),
                  ],

                  const SizedBox(height: 26),

                  const AgendaPublicaRodape(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     ETAPA ATUAL
     ========================================================== */

  Widget _buildEtapaAtual() {
    switch (_controller.etapaAtual) {
      /* ======================================================
         0 - SERVIÇO
         ====================================================== */

      case 0:
        return EtapaServico(
          key: const ValueKey('etapa_servico'),
          controller: _controller,
          onSelecionar: (servico) async {
            await _controller.selecionarServico(servico);
          },
        );

      /* ======================================================
         1 - PROFISSIONAL
         ====================================================== */

      case 1:
        return EtapaProfissional(
          key: const ValueKey('etapa_profissional'),
          controller: _controller,
          onVoltar: () {
            _controller.voltarParaServico();
          },
          onSelecionar: (profissional) async {
            await _controller.selecionarProfissional(profissional);
          },
        );

      /* ======================================================
         2 - DATA E HORÁRIO
         ====================================================== */

      case 2:
        return EtapaDataHorario(
          key: const ValueKey('etapa_data_horario'),
          controller: _controller,
          onVoltar: () {
            _controller.voltarParaProfissional();
          },
          onContinuar: () {
            _controller.irParaDadosCliente();
          },
        );

      /* ======================================================
         3 - DADOS DO CLIENTE
         ====================================================== */

      case 3:
        return EtapaCliente(
          key: const ValueKey('etapa_cliente'),
          controller: _controller,
          onVoltar: () {
            _controller.voltarParaDataHorario();
          },
          onContinuar: () {
            _controller.irParaConfirmacao();
          },
        );

      /* ======================================================
         4 - CONFIRMAÇÃO
         ====================================================== */

      case 4:
        return EtapaConfirmacao(
          key: const ValueKey('etapa_confirmacao'),
          controller: _controller,
          onVoltar: () {
            _controller.voltarParaDadosCliente();
          },
          onConfirmar: () async {
            await _confirmarAgendamento();
          },
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /* ==========================================================
     CONFIRMAR AGENDAMENTO
     ========================================================== */

  Future<void> _confirmarAgendamento() async {
    if (_controller.confirmandoAgendamento) {
      return;
    }

    FocusScope.of(context).unfocus();

    final resultado = await _controller.confirmarAgendamento();

    if (!mounted) {
      return;
    }

    if (resultado.sucesso) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          resultado.mensagem ?? 'Não foi possível realizar o agendamento.',
        ),
      ),
    );
  }

  /* ==========================================================
     PÁGINA DE ERRO
     ========================================================== */

  Widget _buildPaginaErro() {
    return Scaffold(
      backgroundColor: AgendaPublicaStyle.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AgendaPublicaStyle.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AgendaPublicaStyle.primary.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.event_busy_outlined,
                        color: AgendaPublicaStyle.primary,
                        size: 38,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      _controller.tituloPagina.isNotEmpty
                          ? _controller.tituloPagina
                          : 'Agenda Online',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AgendaPublicaStyle.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      _controller.erroPagina ??
                          'Não foi possível carregar esta página.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AgendaPublicaStyle.muted,
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 22),

                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AgendaPublicaStyle.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () async {
                        await _controller.inicializar();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'Tentar novamente',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     AGENDAMENTO CONCLUÍDO
     ========================================================== */

  Widget _buildAgendamentoConcluido() {
    return Scaffold(
      backgroundColor: AgendaPublicaStyle.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AgendaPublicaStyle.border),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            color: AgendaPublicaStyle.green.withValues(
                              alpha: 0.10,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: AgendaPublicaStyle.green,
                            size: 54,
                          ),
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'Agendamento realizado!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AgendaPublicaStyle.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Seu horário foi reservado com sucesso.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AgendaPublicaStyle.muted,
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 26),

                        _resumoConcluido(),

                        const SizedBox(height: 26),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AgendaPublicaStyle.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              _controller.novoAgendamento();
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text(
                              'Fazer novo agendamento',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  const AgendaPublicaRodape(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     RESUMO DO AGENDAMENTO CONCLUÍDO
     ========================================================== */

  Widget _resumoConcluido() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AgendaPublicaStyle.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgendaPublicaStyle.border),
      ),
      child: Column(
        children: [
          _linhaResumo(
            icon: Icons.design_services_outlined,
            label: 'Serviço',
            valor: _controller.servicoNome,
          ),

          const Divider(height: 24, color: AgendaPublicaStyle.border),

          _linhaResumo(
            icon: Icons.person_outline,
            label: 'Profissional',
            valor: _controller.profissionalNome,
          ),

          const Divider(height: 24, color: AgendaPublicaStyle.border),

          _linhaResumo(
            icon: Icons.calendar_today_outlined,
            label: 'Data',
            valor: _controller.dataFormatada,
          ),

          const Divider(height: 24, color: AgendaPublicaStyle.border),

          _linhaResumo(
            icon: Icons.schedule_outlined,
            label: 'Horário',
            valor: _controller.horarioSelecionado ?? '',
          ),

          if (_controller.exibirPrecoServico) ...[
            const Divider(height: 24, color: AgendaPublicaStyle.border),

            _linhaResumo(
              icon: Icons.payments_outlined,
              label: 'Valor',
              valor: _controller.precoServicoFormatado,
            ),
          ],

          if (_controller.protocoloAgendamento.isNotEmpty) ...[
            const Divider(height: 24, color: AgendaPublicaStyle.border),

            _linhaResumo(
              icon: Icons.confirmation_number_outlined,
              label: 'Protocolo',
              valor: _controller.protocoloAgendamento,
            ),
          ],
        ],
      ),
    );
  }

  Widget _linhaResumo({
    required IconData icon,
    required String label,
    required String valor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AgendaPublicaStyle.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AgendaPublicaStyle.primary, size: 21),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AgendaPublicaStyle.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                valor.isNotEmpty ? valor : '-',
                style: const TextStyle(
                  color: AgendaPublicaStyle.text,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
