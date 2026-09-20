import 'package:flutter/material.dart';

import 'agenda_publica_controller.dart';
import 'agenda_publica_widgets.dart';

class EtapaConfirmacao extends StatelessWidget {
  final AgendaPublicaController controller;
  final VoidCallback onVoltar;
  final Future<void> Function() onConfirmar;

  const EtapaConfirmacao({
    super.key,
    required this.controller,
    required this.onVoltar,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    return AgendaPublicaEtapaCard(
      icon: Icons.check_circle_outline_rounded,
      iconColor: AgendaPublicaStyle.green,
      titulo: 'Confirmar agendamento',
      subtitulo: 'Confira os dados abaixo antes de confirmar o seu horário.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SecaoResumo(
            titulo: 'Agendamento',
            icon: Icons.event_available_outlined,
            itens: [
              _ResumoItem(
                label: 'Serviço',
                valor: controller.servicoNome,
                icon: Icons.design_services_outlined,
              ),
              _ResumoItem(
                label: 'Profissional',
                valor: controller.profissionalNome,
                icon: Icons.person_outline_rounded,
              ),
              _ResumoItem(
                label: 'Data',
                valor: controller.dataFormatadaCompleta,
                icon: Icons.calendar_today_outlined,
              ),
              _ResumoItem(
                label: 'Horário',
                valor: controller.horarioSelecionado ?? '',
                icon: Icons.schedule_outlined,
              ),
              _ResumoItem(
                label: 'Duração',
                valor: _formatarDuracao(controller.duracaoServicoMinutos),
                icon: Icons.timelapse_outlined,
              ),
              if (controller.exibirPrecoServico)
                _ResumoItem(
                  label: 'Valor',
                  valor: controller.precoServicoFormatado,
                  icon: Icons.payments_outlined,
                ),
            ],
          ),

          const SizedBox(height: 16),

          _SecaoResumo(
            titulo: 'Seus dados',
            icon: Icons.badge_outlined,
            itens: [
              _ResumoItem(
                label: 'Nome',
                valor: controller.nomeCliente,
                icon: Icons.person_outline,
              ),
              _ResumoItem(
                label: 'Telefone',
                valor: controller.telefoneCliente,
                icon: Icons.phone_outlined,
              ),
              if (controller.emailCliente.isNotEmpty)
                _ResumoItem(
                  label: 'E-mail',
                  valor: controller.emailCliente,
                  icon: Icons.email_outlined,
                ),
              if (controller.observacao.isNotEmpty)
                _ResumoItem(
                  label: 'Observação',
                  valor: controller.observacao,
                  icon: Icons.notes_outlined,
                ),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AgendaPublicaStyle.orange.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: AgendaPublicaStyle.orange.withValues(alpha: 0.18),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AgendaPublicaStyle.orange,
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Confira atentamente os dados antes de confirmar o agendamento.',
                    style: TextStyle(
                      color: AgendaPublicaStyle.muted,
                      fontSize: 11.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 480;

              if (compacto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AgendaPublicaBotaoPrincipal(
                      texto: 'Confirmar agendamento',
                      icon: Icons.check_rounded,
                      carregando: controller.confirmandoAgendamento,
                      onPressed:
                          controller.confirmandoAgendamento
                              ? null
                              : () async {
                                await onConfirmar();
                              },
                    ),
                    const SizedBox(height: 10),
                    AgendaPublicaBotaoVoltar(
                      onPressed:
                          controller.confirmandoAgendamento ? () {} : onVoltar,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  AgendaPublicaBotaoVoltar(
                    onPressed:
                        controller.confirmandoAgendamento ? () {} : onVoltar,
                  ),
                  const Spacer(),
                  AgendaPublicaBotaoPrincipal(
                    texto: 'Confirmar agendamento',
                    icon: Icons.check_rounded,
                    carregando: controller.confirmandoAgendamento,
                    onPressed:
                        controller.confirmandoAgendamento
                            ? null
                            : () async {
                              await onConfirmar();
                            },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatarDuracao(int minutos) {
    if (minutos <= 0) {
      return '-';
    }

    if (minutos < 60) {
      return '$minutos min';
    }

    final horas = minutos ~/ 60;
    final restante = minutos % 60;

    if (restante == 0) {
      return horas == 1 ? '1 hora' : '$horas horas';
    }

    return '${horas}h ${restante}min';
  }
}

/* ============================================================
   SEÇÃO DO RESUMO
   ============================================================ */

class _SecaoResumo extends StatelessWidget {
  final String titulo;
  final IconData icon;
  final List<_ResumoItem> itens;

  const _SecaoResumo({
    required this.titulo,
    required this.icon,
    required this.itens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgendaPublicaStyle.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgendaPublicaStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AgendaPublicaStyle.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: AgendaPublicaStyle.primary),
              ),
              const SizedBox(width: 10),
              Text(
                titulo,
                style: const TextStyle(
                  color: AgendaPublicaStyle.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(itens.length, (index) {
            final item = itens[index];

            return Column(
              children: [
                _LinhaResumo(item: item),
                if (index < itens.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 11),
                    child: Divider(height: 1, color: AgendaPublicaStyle.border),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/* ============================================================
   ITEM DO RESUMO
   ============================================================ */

class _ResumoItem {
  final String label;
  final String valor;
  final IconData icon;

  const _ResumoItem({
    required this.label,
    required this.valor,
    required this.icon,
  });
}

class _LinhaResumo extends StatelessWidget {
  final _ResumoItem item;

  const _LinhaResumo({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AgendaPublicaStyle.border),
          ),
          child: Icon(item.icon, size: 18, color: AgendaPublicaStyle.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  color: AgendaPublicaStyle.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.valor.trim().isEmpty ? '-' : item.valor,
                style: const TextStyle(
                  color: AgendaPublicaStyle.text,
                  fontSize: 13.5,
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
