import 'package:flutter/material.dart';

import 'agenda_publica_controller.dart';
import 'agenda_publica_widgets.dart';

class EtapaProfissional extends StatelessWidget {
  final AgendaPublicaController controller;

  final VoidCallback onVoltar;

  final Future<void> Function(Map<String, dynamic> profissional) onSelecionar;

  const EtapaProfissional({
    super.key,
    required this.controller,
    required this.onVoltar,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    return AgendaPublicaEtapaCard(
      icon: Icons.person_outline_rounded,
      iconColor: AgendaPublicaStyle.blue,
      titulo: 'Escolha o profissional',
      subtitulo: 'Selecione quem você deseja para realizar o atendimento.',
      child: _buildConteudo(context),
    );
  }

  /* ==========================================================
     CONTEÚDO
     ========================================================== */

  Widget _buildConteudo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        /*
         * BOTÃO VOLTAR
         */
        Align(
          alignment: Alignment.centerLeft,
          child: AgendaPublicaBotaoVoltar(onPressed: onVoltar),
        ),

        const SizedBox(height: 16),

        /*
         * CARREGANDO
         */
        if (controller.carregandoProfissionais)
          const AgendaPublicaCarregando(texto: 'Carregando profissionais...')
        /*
         * NENHUM PROFISSIONAL
         */
        else if (controller.profissionais.isEmpty)
          const AgendaPublicaEstadoVazio(
            icon: Icons.person_off_outlined,
            titulo: 'Nenhum profissional disponível',
            descricao:
                'No momento não existem profissionais disponíveis para este serviço.',
          )
        /*
         * LISTA
         */
        else
          Column(
            children: [
              ...controller.profissionais.map(
                (profissional) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProfissionalCard(
                    profissional: profissional,
                    selecionado:
                        controller.profissionalId ==
                        (profissional['id'] ?? '').toString(),
                    onTap: () async {
                      await onSelecionar(profissional);
                    },
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/* ============================================================
   CARD DO PROFISSIONAL
   ============================================================ */

class _ProfissionalCard extends StatelessWidget {
  final Map<String, dynamic> profissional;

  final bool selecionado;

  final VoidCallback onTap;

  const _ProfissionalCard({
    required this.profissional,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nome = _nomeProfissional();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                selecionado
                    ? AgendaPublicaStyle.blue.withValues(alpha: 0.055)
                    : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  selecionado
                      ? AgendaPublicaStyle.blue
                      : AgendaPublicaStyle.border,
              width: selecionado ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              /*
               * AVATAR / ÍCONE
               */
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AgendaPublicaStyle.blue.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  selecionado
                      ? Icons.check_rounded
                      : Icons.person_outline_rounded,
                  color: AgendaPublicaStyle.blue,
                  size: 27,
                ),
              ),

              const SizedBox(width: 14),

              /*
               * NOME
               */
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        color: AgendaPublicaStyle.text,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'Profissional disponível para este serviço',
                      style: TextStyle(
                        color: AgendaPublicaStyle.muted,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              /*
               * INDICADOR
               */
              Icon(
                selecionado
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_ios_rounded,
                size: selecionado ? 22 : 17,
                color:
                    selecionado
                        ? AgendaPublicaStyle.green
                        : AgendaPublicaStyle.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     NOME DO PROFISSIONAL
     ========================================================== */

  String _nomeProfissional() {
    /*
     * Na projeção pública que criaremos, vamos utilizar
     * "nome".
     *
     * Mantemos "displayName" como compatibilidade.
     */

    final nome = (profissional['nome'] ?? '').toString().trim();

    if (nome.isNotEmpty) {
      return nome;
    }

    final displayName = (profissional['displayName'] ?? '').toString().trim();

    if (displayName.isNotEmpty) {
      return displayName;
    }

    return 'Profissional';
  }
}
