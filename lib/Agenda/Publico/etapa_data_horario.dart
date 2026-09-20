import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'agenda_publica_controller.dart';
import 'agenda_publica_widgets.dart';

class EtapaDataHorario extends StatelessWidget {
  final AgendaPublicaController controller;
  final VoidCallback onVoltar;
  final VoidCallback onContinuar;

  const EtapaDataHorario({
    super.key,
    required this.controller,
    required this.onVoltar,
    required this.onContinuar,
  });

  @override
  Widget build(BuildContext context) {
    final escolhendoHorario = controller.dataSelecionada != null;

    return AgendaPublicaEtapaCard(
      icon:
          escolhendoHorario
              ? Icons.schedule_outlined
              : Icons.calendar_month_outlined,
      iconColor: AgendaPublicaStyle.orange,
      titulo: escolhendoHorario ? 'Escolha o horário' : 'Escolha a data',
      subtitulo:
          escolhendoHorario
              ? 'Agora selecione um dos horários disponíveis.'
              : 'Selecione uma das datas disponíveis para o atendimento.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResumoSelecao(controller: controller),

          const SizedBox(height: 22),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child:
                escolhendoHorario
                    ? _buildEtapaHorario(context)
                    : _buildEtapaData(context),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     ETAPA - ESCOLHA DA DATA
     ========================================================== */

  Widget _buildEtapaData(BuildContext context) {
    return Column(
      key: const ValueKey('escolha_data'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: AgendaPublicaStyle.primary,
            ),
            SizedBox(width: 8),
            Text(
              'Escolha uma data',
              style: TextStyle(
                color: AgendaPublicaStyle.text,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 5),

        const Text(
          'Selecione um dos dias disponíveis abaixo.',
          style: TextStyle(
            color: AgendaPublicaStyle.muted,
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 16),

        _buildDatas(),

        const SizedBox(height: 24),

        Align(
          alignment: Alignment.centerLeft,
          child: AgendaPublicaBotaoVoltar(onPressed: onVoltar),
        ),
      ],
    );
  }

  /* ==========================================================
     ETAPA - ESCOLHA DO HORÁRIO
     ========================================================== */

  Widget _buildEtapaHorario(BuildContext context) {
    return Column(
      key: const ValueKey('escolha_horario'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DataSelecionadaCard(
          controller: controller,
          onAlterarData: _alterarData,
        ),

        const SizedBox(height: 22),

        const Row(
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 20,
              color: AgendaPublicaStyle.primary,
            ),
            SizedBox(width: 8),
            Text(
              'Escolha um horário',
              style: TextStyle(
                color: AgendaPublicaStyle.text,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 5),

        const Text(
          'Selecione um dos horários disponíveis abaixo.',
          style: TextStyle(
            color: AgendaPublicaStyle.muted,
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 16),

        _buildHorarios(),

        if (_podeContinuar) ...[
          const SizedBox(height: 24),

          AgendaPublicaBotaoPrincipal(
            texto: 'Continuar',
            icon: Icons.arrow_forward_rounded,
            onPressed: onContinuar,
          ),
        ],

        const SizedBox(height: 12),

        Align(
          alignment: Alignment.centerLeft,
          child: AgendaPublicaBotaoVoltar(onPressed: _alterarData),
        ),
      ],
    );
  }

  /* ==========================================================
     ALTERAR DATA
     ========================================================== */

  void _alterarData() {
    controller.alterarDataSelecionada();
  }

  /* ==========================================================
     DATAS
     ========================================================== */

  Widget _buildDatas() {
    if (controller.carregandoDatas) {
      return const AgendaPublicaCarregando(
        texto: 'Buscando datas disponíveis...',
      );
    }

    if (controller.datasDisponiveis.isEmpty) {
      return const AgendaPublicaEstadoVazio(
        icon: Icons.event_busy_outlined,
        titulo: 'Nenhuma data disponível',
        descricao:
            'No momento não encontramos datas disponíveis para este serviço e profissional.',
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children:
          controller.datasDisponiveis.map((data) {
            return _DataCard(
              data: data,
              onTap: () async {
                await controller.selecionarData(data);
              },
            );
          }).toList(),
    );
  }

  /* ==========================================================
     HORÁRIOS
     ========================================================== */

  Widget _buildHorarios() {
    if (controller.carregandoHorarios) {
      return const AgendaPublicaCarregando(
        texto: 'Buscando horários disponíveis...',
      );
    }

    if (controller.horariosDisponiveis.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgendaPublicaEstadoVazio(
            icon: Icons.schedule_outlined,
            titulo: 'Nenhum horário disponível',
            descricao: 'Não encontramos horários disponíveis para esta data.',
          ),

          const SizedBox(height: 14),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AgendaPublicaStyle.primary,
              side: const BorderSide(color: AgendaPublicaStyle.primary),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: _alterarData,
            icon: const Icon(Icons.calendar_month_outlined, size: 19),
            label: const Text(
              'Escolher outra data',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children:
          controller.horariosDisponiveis.map((horario) {
            final selecionado = controller.horarioSelecionado == horario;

            return _HorarioCard(
              horario: horario,
              selecionado: selecionado,
              onTap: () {
                controller.selecionarHorario(horario);
              },
            );
          }).toList(),
    );
  }

  bool get _podeContinuar {
    return controller.dataSelecionada != null &&
        controller.horarioSelecionado != null &&
        controller.horarioSelecionado!.trim().isNotEmpty;
  }
}

/* ============================================================
   RESUMO SERVIÇO / PROFISSIONAL
   ============================================================ */

class _ResumoSelecao extends StatelessWidget {
  final AgendaPublicaController controller;

  const _ResumoSelecao({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AgendaPublicaStyle.primary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgendaPublicaStyle.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          _ResumoLinha(
            icon: Icons.design_services_outlined,
            titulo: 'Serviço',
            valor: controller.servicoNome,
          ),

          const SizedBox(height: 11),

          _ResumoLinha(
            icon: Icons.person_outline_rounded,
            titulo: 'Profissional',
            valor: controller.profissionalNome,
          ),
        ],
      ),
    );
  }
}

class _ResumoLinha extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String valor;

  const _ResumoLinha({
    required this.icon,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AgendaPublicaStyle.primary),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: AgendaPublicaStyle.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                valor.isEmpty ? '-' : valor,
                style: const TextStyle(
                  color: AgendaPublicaStyle.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   DATA SELECIONADA
   ============================================================ */

class _DataSelecionadaCard extends StatelessWidget {
  final AgendaPublicaController controller;
  final VoidCallback onAlterarData;

  const _DataSelecionadaCard({
    required this.controller,
    required this.onAlterarData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgendaPublicaStyle.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: AgendaPublicaStyle.orange.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AgendaPublicaStyle.orange.withValues(alpha: 0.20),
              ),
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: AgendaPublicaStyle.orange,
              size: 24,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data selecionada',
                  style: TextStyle(
                    color: AgendaPublicaStyle.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  controller.dataFormatadaCompleta,
                  style: const TextStyle(
                    color: AgendaPublicaStyle.text,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          TextButton.icon(
            onPressed: onAlterarData,
            icon: const Icon(Icons.edit_calendar_outlined, size: 17),
            label: const Text(
              'Alterar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   CARD DE DATA
   ============================================================ */

class _DataCard extends StatelessWidget {
  final DateTime data;
  final VoidCallback onTap;

  const _DataCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final diaSemana = DateFormat(
      'EEE',
      'pt_BR',
    ).format(data).replaceAll('.', '');

    final dia = DateFormat('dd').format(data);

    final mes = DateFormat('MMM', 'pt_BR').format(data).replaceAll('.', '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AgendaPublicaStyle.border),
          ),
          child: Column(
            children: [
              Text(
                _capitalizar(diaSemana),
                style: const TextStyle(
                  color: AgendaPublicaStyle.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                dia,
                style: const TextStyle(
                  color: AgendaPublicaStyle.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                _capitalizar(mes),
                style: const TextStyle(
                  color: AgendaPublicaStyle.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalizar(String texto) {
    if (texto.isEmpty) {
      return texto;
    }

    return '${texto[0].toUpperCase()}${texto.substring(1)}';
  }
}

/* ============================================================
   CARD DE HORÁRIO
   ============================================================ */

class _HorarioCard extends StatelessWidget {
  final String horario;
  final bool selecionado;
  final VoidCallback onTap;

  const _HorarioCard({
    required this.horario,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
          decoration: BoxDecoration(
            color: selecionado ? AgendaPublicaStyle.primary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selecionado
                      ? AgendaPublicaStyle.primary
                      : AgendaPublicaStyle.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selecionado ? Icons.check_rounded : Icons.schedule_outlined,
                size: 17,
                color: selecionado ? Colors.white : AgendaPublicaStyle.primary,
              ),

              const SizedBox(width: 6),

              Text(
                horario,
                style: TextStyle(
                  color: selecionado ? Colors.white : AgendaPublicaStyle.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
