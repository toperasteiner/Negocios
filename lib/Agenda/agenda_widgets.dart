import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'agenda_controller.dart';

/* ============================================================
   CORES / ESTILO
   ============================================================ */

class AgendaStyle {
  static const Color primary = Color(0xFF6A2BFF);
  static const Color primaryDark = Color(0xFF32106C);

  static const Color background = Color(0xFFF7F7FB);
  static const Color surface = Colors.white;

  static const Color text = Color(0xFF17152B);
  static const Color muted = Color(0xFF77758A);

  static const Color border = Color(0xFFE7E7EF);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
}

/* ============================================================
   LOADING
   ============================================================ */

class AgendaCarregando extends StatelessWidget {
  const AgendaCarregando({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
      decoration: BoxDecoration(
        color: AgendaStyle.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgendaStyle.border),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(color: AgendaStyle.primary),
          SizedBox(height: 14),
          Text(
            'Carregando agendamentos...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AgendaStyle.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   ERRO
   ============================================================ */

class AgendaErro extends StatelessWidget {
  final String mensagem;
  final Future<void> Function() onTentarNovamente;

  const AgendaErro({
    super.key,
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgendaStyle.border),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AgendaStyle.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AgendaStyle.danger,
              size: 28,
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'Não foi possível carregar a agenda',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AgendaStyle.text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaStyle.muted,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: () async {
              await onTentarNovamente();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AgendaStyle.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'Tentar novamente',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   AGENDA VAZIA
   ============================================================ */

class AgendaVazia extends StatelessWidget {
  final DateTime data;

  const AgendaVazia({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final dataFormatada = DateFormat("dd 'de' MMMM", 'pt_BR').format(data);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgendaStyle.border),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AgendaStyle.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.event_available_outlined,
              size: 30,
              color: AgendaStyle.primary,
            ),
          ),

          const SizedBox(height: 15),

          const Text(
            'Nenhum agendamento',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AgendaStyle.text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Não existem agendamentos para $dataFormatada.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaStyle.muted,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   CARD DO AGENDAMENTO
   ============================================================ */

class AgendaAgendamentoCard extends StatelessWidget {
  final AgendaAgendamento agendamento;
  final VoidCallback onTap;

  final VoidCallback? onEditar;
  final VoidCallback? onConcluir;
  final VoidCallback? onCancelar;
  final VoidCallback? onDescancelar;
  final VoidCallback? onNaoCompareceu;
  final VoidCallback? onDesfazerNaoComparecimento;

  const AgendaAgendamentoCard({
    super.key,
    required this.agendamento,
    required this.onTap,
    this.onEditar,
    this.onConcluir,
    this.onCancelar,
    this.onDescancelar,
    this.onNaoCompareceu,
    this.onDesfazerNaoComparecimento,
  });

  @override
  Widget build(BuildContext context) {
    final statusTexto = agendamento.status.trim().toLowerCase();

    final status = _AgendaStatusVisual.fromStatus(statusTexto);

    final cancelado = statusTexto == 'cancelado';
    final naoCompareceu = statusTexto == 'nao_compareceu';

    final podeAlterar =
        statusTexto == 'agendado' ||
        statusTexto == 'confirmado' ||
        statusTexto == 'em_atendimento';

    final mostrarMenu = podeAlterar || cancelado || naoCompareceu;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AgendaStyle.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AgendaStyle.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 66,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: AgendaStyle.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      agendamento.horarioInicio,
                      style: const TextStyle(
                        color: AgendaStyle.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      agendamento.horarioFim,
                      style: const TextStyle(
                        color: AgendaStyle.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            agendamento.clienteNome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AgendaStyle.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        _StatusChip(visual: status),

                        if (mostrarMenu) ...[
                          const SizedBox(width: 4),

                          PopupMenuButton<String>(
                            tooltip: 'Ações',
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: AgendaStyle.muted,
                            ),

                            onSelected: (acao) {
                              switch (acao) {
                                case 'editar':
                                  onEditar?.call();
                                  break;

                                case 'concluir':
                                  onConcluir?.call();
                                  break;

                                case 'cancelar':
                                  onCancelar?.call();
                                  break;

                                case 'descancelar':
                                  onDescancelar?.call();
                                  break;

                                case 'nao_compareceu':
                                  onNaoCompareceu?.call();
                                  break;

                                case 'desfazer_nao_comparecimento':
                                  onDesfazerNaoComparecimento?.call();
                                  break;
                              }
                            },

                            itemBuilder: (context) {
                              /*
     * AGENDAMENTO CANCELADO
     *
     * Mostra somente a opção de descancelar.
     */
                              if (cancelado) {
                                return const [
                                  PopupMenuItem<String>(
                                    value: 'descancelar',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.restore_rounded,
                                          size: 19,
                                          color: AgendaStyle.success,
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Descancelar',
                                          style: TextStyle(
                                            color: AgendaStyle.success,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ];
                              }

                              /*
     * NÃO COMPARECEU
     *
     * Permite reativar o agendamento caso tenha sido
     * marcado por engano.
     */
                              if (naoCompareceu) {
                                return const [
                                  PopupMenuItem<String>(
                                    value: 'desfazer_nao_comparecimento',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.restore_rounded,
                                          size: 19,
                                          color: AgendaStyle.success,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Reativar agendamento',
                                            style: TextStyle(
                                              color: AgendaStyle.success,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ];
                              }

                              /*
     * AGENDAMENTO ATIVO
     */
                              return const [
                                PopupMenuItem<String>(
                                  value: 'editar',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                        color: AgendaStyle.text,
                                      ),
                                      SizedBox(width: 10),
                                      Text('Editar'),
                                    ],
                                  ),
                                ),

                                PopupMenuItem<String>(
                                  value: 'concluir',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.task_alt_rounded,
                                        size: 19,
                                        color: AgendaStyle.success,
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text('Marcar como concluído'),
                                      ),
                                    ],
                                  ),
                                ),

                                PopupMenuDivider(),

                                PopupMenuItem<String>(
                                  value: 'nao_compareceu',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_off_outlined,
                                        size: 19,
                                        color: AgendaStyle.warning,
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Marcar como não compareceu',
                                          style: TextStyle(
                                            color: AgendaStyle.warning,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                PopupMenuItem<String>(
                                  value: 'cancelar',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.cancel_outlined,
                                        size: 19,
                                        color: AgendaStyle.danger,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Cancelar',
                                        style: TextStyle(
                                          color: AgendaStyle.danger,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 8),

                    _LinhaCard(
                      icon: Icons.design_services_outlined,
                      texto: agendamento.servicoNome,
                    ),

                    const SizedBox(height: 6),

                    _LinhaCard(
                      icon: Icons.person_outline_rounded,
                      texto: agendamento.profissionalNome,
                    ),

                    if (agendamento.telefoneExibicao.isNotEmpty) ...[
                      const SizedBox(height: 6),

                      _LinhaCard(
                        icon: Icons.phone_outlined,
                        texto: _formatarTelefone(agendamento.telefoneExibicao),
                      ),
                    ],

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        _OrigemChip(origem: agendamento.origem),

                        const Spacer(),

                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AgendaStyle.muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ============================================================
   DETALHES DO AGENDAMENTO
   ============================================================ */

class AgendaDetalhesAgendamento extends StatefulWidget {
  final AgendaAgendamento agendamento;

  final VoidCallback onFechar;

  /*
   * Retorna true quando o cancelamento foi realizado.
   *
   * O motivo é opcional.
   */
  final Future<bool> Function(String? motivo)? onCancelar;

  const AgendaDetalhesAgendamento({
    super.key,
    required this.agendamento,
    required this.onFechar,
    this.onCancelar,
  });

  @override
  State<AgendaDetalhesAgendamento> createState() =>
      _AgendaDetalhesAgendamentoState();
}

class _AgendaDetalhesAgendamentoState extends State<AgendaDetalhesAgendamento> {
  bool _cancelando = false;

  /* ==========================================================
     PODE CANCELAR
     ========================================================== */

  bool get _podeCancelar {
    final status = widget.agendamento.status.trim().toLowerCase();

    return status == 'agendado' ||
        status == 'confirmado' ||
        status == 'em_atendimento';
  }

  /* ==========================================================
     SOLICITA CANCELAMENTO
     ========================================================== */

  Future<void> _solicitarCancelamento() async {
    if (_cancelando) {
      return;
    }

    final motivoCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cancel_outlined, color: AgendaStyle.danger),
              SizedBox(width: 10),
              Expanded(child: Text('Cancelar agendamento')),
            ],
          ),

          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deseja realmente cancelar este agendamento?',
                  style: TextStyle(
                    color: AgendaStyle.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8FC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AgendaStyle.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.agendamento.clienteNome,
                        style: const TextStyle(
                          color: AgendaStyle.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '${widget.agendamento.horarioInicio} - '
                        '${widget.agendamento.servicoNome}',
                        style: const TextStyle(
                          color: AgendaStyle.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: motivoCtrl,
                  maxLines: 3,
                  maxLength: 250,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Motivo do cancelamento',
                    hintText: 'Opcional',
                    prefixIcon: const Icon(Icons.notes_outlined),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFFF8F8FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: AgendaStyle.muted,
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'O agendamento não será excluído. '
                        'Ele permanecerá no histórico com o status Cancelado.',
                        style: TextStyle(
                          color: AgendaStyle.muted,
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Voltar'),
            ),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AgendaStyle.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancelar agendamento'),
            ),
          ],
        );
      },
    );

    final motivo = motivoCtrl.text.trim();

    motivoCtrl.dispose();

    if (confirmar != true) {
      return;
    }

    if (widget.onCancelar == null) {
      return;
    }

    setState(() {
      _cancelando = true;
    });

    try {
      final sucesso = await widget.onCancelar!(motivo.isEmpty ? null : motivo);

      if (!mounted) {
        return;
      }

      if (sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Agendamento cancelado com sucesso.'),
          ),
        );

        widget.onFechar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Não foi possível cancelar o agendamento.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _cancelando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agendamento = widget.agendamento;

    final status = _AgendaStatusVisual.fromStatus(agendamento.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              /* ==========================================
                 CABEÇALHO
                 ========================================== */
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AgendaStyle.border,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AgendaStyle.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.calendar_month_outlined,
                            color: AgendaStyle.primary,
                            size: 23,
                          ),
                        ),

                        const SizedBox(width: 12),

                        const Expanded(
                          child: Text(
                            'Detalhes do agendamento',
                            style: TextStyle(
                              color: AgendaStyle.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),

                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: _cancelando ? null : widget.onFechar,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AgendaStyle.border),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(18),
                  children: [
                    _DetalheDestaque(agendamento: agendamento, status: status),

                    const SizedBox(height: 16),

                    _DetalhesSecao(
                      titulo: 'Cliente',
                      icon: Icons.person_outline_rounded,
                      itens: [
                        _DetalheItem(
                          label: 'Nome',
                          valor: agendamento.clienteNome,
                        ),

                        if (agendamento.telefoneExibicao.isNotEmpty)
                          _DetalheItem(
                            label: 'Telefone / WhatsApp',
                            valor: _formatarTelefone(
                              agendamento.telefoneExibicao,
                            ),
                          ),

                        if (agendamento.clienteEmail.isNotEmpty)
                          _DetalheItem(
                            label: 'E-mail',
                            valor: agendamento.clienteEmail,
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    _DetalhesSecao(
                      titulo: 'Atendimento',
                      icon: Icons.design_services_outlined,
                      itens: [
                        _DetalheItem(
                          label: 'Serviço',
                          valor: agendamento.servicoNome,
                        ),

                        _DetalheItem(
                          label: 'Profissional',
                          valor: agendamento.profissionalNome,
                        ),

                        _DetalheItem(
                          label: 'Data',
                          valor: DateFormat(
                            'dd/MM/yyyy',
                            'pt_BR',
                          ).format(agendamento.inicio),
                        ),

                        _DetalheItem(
                          label: 'Horário',
                          valor: agendamento.horarioPeriodo,
                        ),

                        if (agendamento.duracaoMinutos > 0)
                          _DetalheItem(
                            label: 'Duração',
                            valor: _formatarDuracao(agendamento.duracaoMinutos),
                          ),

                        if (agendamento.valorServico > 0)
                          _DetalheItem(
                            label: 'Valor',
                            valor: NumberFormat.currency(
                              locale: 'pt_BR',
                              symbol: 'R\$',
                            ).format(agendamento.valorServico),
                          ),
                      ],
                    ),

                    if (agendamento.observacao.isNotEmpty) ...[
                      const SizedBox(height: 14),

                      _DetalhesSecao(
                        titulo: 'Observação',
                        icon: Icons.notes_rounded,
                        itens: [
                          _DetalheItem(
                            label: '',
                            valor: agendamento.observacao,
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    _DetalhesSecao(
                      titulo: 'Informações',
                      icon: Icons.info_outline,
                      itens: [
                        _DetalheItem(
                          label: 'Status',
                          valor: agendamento.statusDescricao,
                        ),

                        _DetalheItem(
                          label: 'Origem',
                          valor: _descricaoOrigem(agendamento.origem),
                        ),

                        _DetalheItem(label: 'Código', valor: agendamento.id),
                      ],
                    ),

                    /* ======================================
                       AÇÕES
                       ====================================== */
                    if (_podeCancelar && widget.onCancelar != null) ...[
                      const SizedBox(height: 22),

                      const Text(
                        'Ações',
                        style: TextStyle(
                          color: AgendaStyle.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      const SizedBox(height: 10),

                      OutlinedButton.icon(
                        onPressed: _cancelando ? null : _solicitarCancelamento,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AgendaStyle.danger,
                          side: const BorderSide(color: AgendaStyle.danger),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon:
                            _cancelando
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.cancel_outlined, size: 18),
                        label: Text(
                          _cancelando
                              ? 'Cancelando...'
                              : 'Cancelar agendamento',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: _cancelando ? null : widget.onFechar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AgendaStyle.text,
                        side: const BorderSide(color: AgendaStyle.border),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'Fechar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/* ============================================================
   DESTAQUE DO DETALHE
   ============================================================ */

class _DetalheDestaque extends StatelessWidget {
  final AgendaAgendamento agendamento;
  final _AgendaStatusVisual status;

  const _DetalheDestaque({required this.agendamento, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status.cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: status.cor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: status.cor.withValues(alpha: 0.20)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  agendamento.horarioInicio,
                  style: TextStyle(
                    color: status.cor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  agendamento.horarioFim,
                  style: const TextStyle(
                    color: AgendaStyle.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agendamento.clienteNome,
                  style: const TextStyle(
                    color: AgendaStyle.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  agendamento.servicoNome,
                  style: const TextStyle(
                    color: AgendaStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusChip(visual: status),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   SEÇÃO DO DETALHE
   ============================================================ */

class _DetalhesSecao extends StatelessWidget {
  final String titulo;
  final IconData icon;
  final List<_DetalheItem> itens;

  const _DetalhesSecao({
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
        color: const Color(0xFFFAFAFD),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AgendaStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AgendaStyle.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: AgendaStyle.primary, size: 18),
              ),

              const SizedBox(width: 10),

              Text(
                titulo,
                style: const TextStyle(
                  color: AgendaStyle.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          for (var i = 0; i < itens.length; i++) ...[
            _DetalheLinha(item: itens[i]),

            if (i < itens.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: AgendaStyle.border),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetalheItem {
  final String label;
  final String valor;

  const _DetalheItem({required this.label, required this.valor});
}

class _DetalheLinha extends StatelessWidget {
  final _DetalheItem item;

  const _DetalheLinha({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.label.isNotEmpty) ...[
          Text(
            item.label,
            style: const TextStyle(
              color: AgendaStyle.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 3),
        ],

        SelectableText(
          item.valor.trim().isEmpty ? '-' : item.valor,
          style: const TextStyle(
            color: AgendaStyle.text,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   LINHA SIMPLES DO CARD
   ============================================================ */

class _LinhaCard extends StatelessWidget {
  final IconData icon;
  final String texto;

  const _LinhaCard({required this.icon, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AgendaStyle.muted),

        const SizedBox(width: 7),

        Expanded(
          child: Text(
            texto.trim().isEmpty ? '-' : texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AgendaStyle.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   STATUS
   ============================================================ */

class _AgendaStatusVisual {
  final String descricao;
  final Color cor;
  final IconData icon;

  const _AgendaStatusVisual({
    required this.descricao,
    required this.cor,
    required this.icon,
  });

  factory _AgendaStatusVisual.fromStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'confirmado':
        return const _AgendaStatusVisual(
          descricao: 'Confirmado',
          cor: AgendaStyle.success,
          icon: Icons.check_circle_outline,
        );

      case 'em_atendimento':
        return const _AgendaStatusVisual(
          descricao: 'Em atendimento',
          cor: AgendaStyle.warning,
          icon: Icons.timelapse_rounded,
        );

      case 'concluido':
        return const _AgendaStatusVisual(
          descricao: 'Concluído',
          cor: AgendaStyle.success,
          icon: Icons.task_alt_rounded,
        );

      case 'cancelado':
        return const _AgendaStatusVisual(
          descricao: 'Cancelado',
          cor: AgendaStyle.danger,
          icon: Icons.cancel_outlined,
        );

      case 'nao_compareceu':
        return const _AgendaStatusVisual(
          descricao: 'Não compareceu',
          cor: AgendaStyle.danger,
          icon: Icons.person_off_outlined,
        );

      case 'agendado':
      default:
        return const _AgendaStatusVisual(
          descricao: 'Agendado',
          cor: AgendaStyle.info,
          icon: Icons.event_available_outlined,
        );
    }
  }
}

class _StatusChip extends StatelessWidget {
  final _AgendaStatusVisual visual;

  const _StatusChip({required this.visual});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: visual.cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: visual.cor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, color: visual.cor, size: 14),

          const SizedBox(width: 5),

          Text(
            visual.descricao,
            style: TextStyle(
              color: visual.cor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   ORIGEM
   ============================================================ */

class _OrigemChip extends StatelessWidget {
  final String origem;

  const _OrigemChip({required this.origem});

  @override
  Widget build(BuildContext context) {
    final publico = origem.trim().toLowerCase() == 'agenda_publica';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: publico ? const Color(0xFFF5F3FF) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            publico ? Icons.public_rounded : Icons.person_outline,
            size: 13,
            color: publico ? AgendaStyle.primary : AgendaStyle.muted,
          ),

          const SizedBox(width: 4),

          Text(
            publico ? 'Agenda online' : 'Interno',
            style: TextStyle(
              color: publico ? AgendaStyle.primary : AgendaStyle.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   HELPERS
   ============================================================ */

String _descricaoOrigem(String origem) {
  switch (origem.trim().toLowerCase()) {
    case 'agenda_publica':
      return 'Agenda online';

    case 'interno':
      return 'Agendamento interno';

    default:
      return origem.trim().isEmpty ? 'Não informado' : origem;
  }
}

String _formatarDuracao(int minutos) {
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

String _formatarTelefone(String telefone) {
  final numeros = telefone.replaceAll(RegExp(r'[^0-9]'), '');

  if (numeros.length == 11) {
    return '(${numeros.substring(0, 2)}) '
        '${numeros.substring(2, 7)}-'
        '${numeros.substring(7)}';
  }

  if (numeros.length == 10) {
    return '(${numeros.substring(0, 2)}) '
        '${numeros.substring(2, 6)}-'
        '${numeros.substring(6)}';
  }

  return telefone;
}
