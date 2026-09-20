import 'package:flutter/material.dart';

import 'agenda_publica_controller.dart';
import 'agenda_publica_widgets.dart';

class EtapaServico extends StatelessWidget {
  final AgendaPublicaController controller;
  final Future<void> Function(Map<String, dynamic> servico) onSelecionar;

  const EtapaServico({
    super.key,
    required this.controller,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    return AgendaPublicaEtapaCard(
      icon: Icons.design_services_outlined,
      iconColor: AgendaPublicaStyle.primary,
      titulo: 'Escolha o serviço',
      subtitulo: 'Selecione o serviço que você deseja agendar.',
      child: _buildConteudo(context),
    );
  }

  /* ==========================================================
     CONTEÚDO
     ========================================================== */

  Widget _buildConteudo(BuildContext context) {
    if (controller.carregandoServicos) {
      return const AgendaPublicaCarregando(texto: 'Carregando serviços...');
    }

    if (controller.servicos.isEmpty) {
      return const AgendaPublicaEstadoVazio(
        icon: Icons.event_busy_outlined,
        titulo: 'Nenhum serviço disponível',
        descricao:
            'No momento não existem serviços disponíveis para agendamento online.',
      );
    }

    return Column(
      children: [
        ...controller.servicos.map(
          (servico) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ServicoCard(
              servico: servico,
              selecionado:
                  controller.servicoId == (servico['id'] ?? '').toString(),
              onTap: () async {
                await onSelecionar(servico);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   CARD DO SERVIÇO
   ============================================================ */

class _ServicoCard extends StatelessWidget {
  final Map<String, dynamic> servico;
  final bool selecionado;
  final VoidCallback onTap;

  const _ServicoCard({
    required this.servico,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nome = _nomeServico();
    final descricao = _descricaoServico();
    final duracao = _duracaoMinutos();
    final intervalo = _intervaloMinutos();

    final exibirPreco = servico['exibirPrecoAgenda'] == true;

    final preco = _precoServico();

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
                    ? AgendaPublicaStyle.primary.withValues(alpha: 0.055)
                    : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  selecionado
                      ? AgendaPublicaStyle.primary
                      : AgendaPublicaStyle.border,
              width: selecionado ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /* ==============================================
                 ÍCONE
                 ============================================== */
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AgendaPublicaStyle.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  selecionado
                      ? Icons.check_rounded
                      : Icons.design_services_outlined,
                  color: AgendaPublicaStyle.primary,
                  size: 25,
                ),
              ),

              const SizedBox(width: 14),

              /* ==============================================
                 INFORMAÇÕES
                 ============================================== */
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

                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 5),

                      Text(
                        descricao,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AgendaPublicaStyle.muted,
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 11),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (duracao > 0)
                          _InfoChip(
                            icon: Icons.schedule_outlined,
                            texto: _formatarDuracao(duracao),
                          ),

                        if (intervalo > 0)
                          _InfoChip(
                            icon: Icons.hourglass_bottom_rounded,
                            texto: '+ $intervalo min intervalo',
                          ),

                        if (exibirPreco)
                          _InfoChip(
                            icon: Icons.payments_outlined,
                            texto: _formatarPreco(preco),
                            destaque: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              /* ==============================================
                 SETA / SELEÇÃO
                 ============================================== */
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Icon(
                  selecionado
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: selecionado ? 22 : 17,
                  color:
                      selecionado
                          ? AgendaPublicaStyle.green
                          : AgendaPublicaStyle.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     NOME
     ========================================================== */

  String _nomeServico() {
    final nome = (servico['nome'] ?? '').toString().trim();

    if (nome.isNotEmpty) {
      return nome;
    }

    final descricao = (servico['descricao'] ?? '').toString().trim();

    if (descricao.isNotEmpty) {
      return descricao;
    }

    return 'Serviço';
  }

  /* ==========================================================
     DESCRIÇÃO
     ========================================================== */

  String _descricaoServico() {
    final nome = (servico['nome'] ?? '').toString().trim();

    final descricao = (servico['descricao'] ?? '').toString().trim();

    /*
     * Caso não exista nome, a descrição é utilizada
     * como nome principal. Nesse caso não repetimos
     * a mesma informação abaixo.
     */
    if (nome.isEmpty) {
      return '';
    }

    if (descricao == nome) {
      return '';
    }

    return descricao;
  }

  /* ==========================================================
     DURAÇÃO
     ========================================================== */

  int _duracaoMinutos() {
    final valor = servico['duracaoMinutos'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  /* ==========================================================
     INTERVALO
     ========================================================== */

  int _intervaloMinutos() {
    final valor = servico['intervaloAposAtendimentoMinutos'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  /* ==========================================================
     PREÇO
     ========================================================== */

  double _precoServico() {
    /*
     * Campo oficial utilizado pelo cadastro atual
     * de serviços do CRUD Negócios:
     *
     * valorUnitario
     *
     * Os demais campos são mantidos apenas como
     * compatibilidade com registros antigos.
     */
    final valor =
        servico['valorUnitario'] ??
        servico['valor'] ??
        servico['preco'] ??
        servico['price'];

    if (valor is num) {
      return valor.toDouble();
    }

    if (valor is String) {
      var texto = valor.trim();

      if (texto.isEmpty) {
        return 0;
      }

      /*
       * Compatibilidade com:
       *
       * 100
       * 100.50
       * 100,50
       * 1.250,50
       */
      if (texto.contains(',') && texto.contains('.')) {
        texto = texto.replaceAll('.', '').replaceAll(',', '.');
      } else if (texto.contains(',')) {
        texto = texto.replaceAll(',', '.');
      }

      return double.tryParse(texto) ?? 0;
    }

    return 0;
  }

  /* ==========================================================
     FORMATAÇÃO DA DURAÇÃO
     ========================================================== */

  String _formatarDuracao(int minutos) {
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

  /* ==========================================================
     FORMATAÇÃO DO PREÇO
     ========================================================== */

  String _formatarPreco(double valor) {
    final partes = valor.toStringAsFixed(2).split('.');

    final inteiro = partes[0];
    final decimal = partes[1];

    final buffer = StringBuffer();

    for (var i = 0; i < inteiro.length; i++) {
      final posicaoRestante = inteiro.length - i;

      buffer.write(inteiro[i]);

      if (posicaoRestante > 1 && posicaoRestante % 3 == 1) {
        buffer.write('.');
      }
    }

    return 'R\$ ${buffer.toString()},$decimal';
  }
}

/* ============================================================
   CHIP DE INFORMAÇÃO
   ============================================================ */

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String texto;
  final bool destaque;

  const _InfoChip({
    required this.icon,
    required this.texto,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final cor = destaque ? AgendaPublicaStyle.green : AgendaPublicaStyle.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: destaque ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cor),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              color: cor,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
