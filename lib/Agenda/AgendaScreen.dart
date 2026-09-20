import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'agenda_controller.dart';
import 'agenda_widgets.dart';
import 'NovoAgendamentoScreen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late final AgendaController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AgendaController();
    _controller.addListener(_atualizarTela);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.inicializar();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_atualizarTela);
    _controller.dispose();

    super.dispose();
  }

  void _atualizarTela() {
    if (!mounted) return;

    setState(() {});
  }

  /* ==========================================================
     EDITAR AGENDAMENTO
     ========================================================== */

  Future<void> _editarAgendamento(AgendaAgendamento agendamento) async {
    final alterado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NovoAgendamentoScreen(agendamentoEdicao: agendamento),
      ),
    );

    if (!mounted) return;

    if (alterado == true) {
      await _controller.carregarAgendamentos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Agendamento atualizado com sucesso.'),
        ),
      );
    }
  }

  /* ==========================================================
     CONCLUIR AGENDAMENTO
     ========================================================== */

  Future<void> _concluirAgendamento(AgendaAgendamento agendamento) async {
    if (agendamento.status == 'concluido') {
      _mostrarMensagem('Este agendamento já está concluído.');
      return;
    }

    if (agendamento.status == 'cancelado') {
      _mostrarMensagem('Um agendamento cancelado não pode ser concluído.');
      return;
    }

    if (agendamento.status == 'nao_compareceu') {
      _mostrarMensagem(
        'Um agendamento marcado como não compareceu não pode ser concluído.',
      );
      return;
    }

    final valorOriginal = agendamento.valorServico;

    final valorController = TextEditingController(
      text: valorOriginal.toStringAsFixed(2).replaceAll('.', ','),
    );

    String profissionalSelecionadoId = agendamento.profissionalId;

    bool pagamentoRecebido = true;

    String formaPagamento = 'pix';

    final profissionalExiste = _controller.profissionais.any(
      (profissional) => profissional.id == profissionalSelecionadoId,
    );

    if (!profissionalExiste) {
      profissionalSelecionadoId = '';
    }

    double converterValor(String texto) {
      var valor = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');

      if (valor.contains(',') && valor.contains('.')) {
        valor = valor.replaceAll('.', '').replaceAll(',', '.');
      } else if (valor.contains(',')) {
        valor = valor.replaceAll(',', '.');
      }

      return double.tryParse(valor) ?? 0;
    }

    String moeda(double valor) {
      return NumberFormat.currency(
        locale: 'pt_BR',
        symbol: 'R\$',
      ).format(valor);
    }

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool processando = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final valorFinal = converterValor(valorController.text);

            final diferenca = valorFinal - valorOriginal;

            final desconto = diferenca < 0 ? diferenca.abs() : 0.0;

            final acrescimo = diferenca > 0 ? diferenca : 0.0;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),

              title: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF16A34A),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text('Concluir atendimento')),
                ],
              ),

              content: SingleChildScrollView(
                child: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Confirme os dados do atendimento realizado.',
                        style: TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 18),

                      _informacaoConclusao(
                        icone: Icons.person_outline,
                        titulo: 'Cliente',
                        valor: agendamento.clienteNome,
                      ),

                      const SizedBox(height: 10),

                      _informacaoConclusao(
                        icone: Icons.design_services_outlined,
                        titulo: 'Serviço',
                        valor: agendamento.servicoNome,
                      ),

                      const SizedBox(height: 10),

                      _informacaoConclusao(
                        icone: Icons.schedule_outlined,
                        titulo: 'Data e horário',
                        valor:
                            '${DateFormat('dd/MM/yyyy').format(agendamento.inicio)} '
                            '${agendamento.horarioPeriodo}',
                      ),

                      const SizedBox(height: 20),

                      // =========================================
                      // PREÇO CADASTRADO
                      // =========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE7E7EF)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.sell_outlined,
                              color: Color(0xFF6A2BFF),
                            ),

                            const SizedBox(width: 10),

                            const Expanded(
                              child: Text(
                                'Valor cadastrado no serviço',
                                style: TextStyle(
                                  color: Color(0xFF77758A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            Text(
                              moeda(valorOriginal),
                              style: const TextStyle(
                                color: Color(0xFF17152B),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // =========================================
                      // VALOR FINAL
                      // =========================================
                      TextField(
                        controller: valorController,
                        enabled: !processando,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],

                        /*
                       * Atualiza desconto/acréscimo
                       * conforme digita.
                       */
                        onChanged: (_) {
                          setDialogState(() {});
                        },

                        decoration: InputDecoration(
                          labelText: 'Valor final do serviço',
                          hintText: '0,00',

                          helperText:
                              'Pode ser alterado em caso de desconto ou acréscimo.',

                          prefixText: 'R\$ ',

                          prefixIcon: const Icon(Icons.payments_outlined),

                          filled: true,

                          fillColor: const Color(0xFFF8F8FC),

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),

                      // =========================================
                      // DESCONTO
                      // =========================================
                      if (desconto > 0) ...[
                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.discount_outlined,
                                size: 19,
                                color: Color(0xFFF97316),
                              ),

                              const SizedBox(width: 9),

                              const Expanded(
                                child: Text(
                                  'Desconto aplicado',
                                  style: TextStyle(
                                    color: Color(0xFF9A3412),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                              Text(
                                moeda(desconto),
                                style: const TextStyle(
                                  color: Color(0xFF9A3412),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // =========================================
                      // ACRÉSCIMO
                      // =========================================
                      if (acrescimo > 0) ...[
                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.add_circle_outline,
                                size: 19,
                                color: Color(0xFF2563EB),
                              ),

                              const SizedBox(width: 9),

                              const Expanded(
                                child: Text(
                                  'Acréscimo aplicado',
                                  style: TextStyle(
                                    color: Color(0xFF1D4ED8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                              Text(
                                moeda(acrescimo),
                                style: const TextStyle(
                                  color: Color(0xFF1D4ED8),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // =========================================
                      // PAGAMENTO RECEBIDO
                      // =========================================
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE7E7EF)),
                        ),
                        child: CheckboxListTile(
                          value: pagamentoRecebido,
                          enabled: !processando,

                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),

                          title: const Text(
                            'Pagamento recebido',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),

                          subtitle: const Text(
                            'Marque quando o cliente já tiver pago o valor final do atendimento.',
                          ),

                          activeColor: const Color(0xFF16A34A),

                          onChanged: (value) {
                            setDialogState(() {
                              pagamentoRecebido = value ?? false;
                            });
                          },
                        ),
                      ),

                      // =========================================
                      // FORMA DE PAGAMENTO
                      // =========================================
                      if (pagamentoRecebido) ...[
                        const SizedBox(height: 14),

                        DropdownButtonFormField<String>(
                          value: formaPagamento,

                          decoration: InputDecoration(
                            labelText: 'Forma de pagamento',

                            prefixIcon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),

                            filled: true,

                            fillColor: const Color(0xFFF8F8FC),

                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),

                          items: const [
                            DropdownMenuItem(value: 'pix', child: Text('PIX')),

                            DropdownMenuItem(
                              value: 'dinheiro',
                              child: Text('Dinheiro'),
                            ),

                            DropdownMenuItem(
                              value: 'cartao_credito',
                              child: Text('Cartão de crédito'),
                            ),

                            DropdownMenuItem(
                              value: 'cartao_debito',
                              child: Text('Cartão de débito'),
                            ),

                            DropdownMenuItem(
                              value: 'transferencia',
                              child: Text('Transferência'),
                            ),

                            DropdownMenuItem(
                              value: 'boleto',
                              child: Text('Boleto'),
                            ),

                            DropdownMenuItem(
                              value: 'cheque',
                              child: Text('Cheque'),
                            ),
                          ],

                          onChanged:
                              processando
                                  ? null
                                  : (value) {
                                    setDialogState(() {
                                      formaPagamento = value ?? 'pix';
                                    });
                                  },
                        ),
                      ],

                      const SizedBox(height: 16),

                      // =========================================
                      // PROFISSIONAL EXECUTANTE
                      // =========================================
                      DropdownButtonFormField<String>(
                        value:
                            profissionalSelecionadoId.isEmpty
                                ? null
                                : profissionalSelecionadoId,

                        isExpanded: true,

                        decoration: InputDecoration(
                          labelText: 'Profissional que realizou',

                          prefixIcon: const Icon(Icons.badge_outlined),

                          filled: true,

                          fillColor: const Color(0xFFF8F8FC),

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),

                        items:
                            _controller.profissionais.map((profissional) {
                              return DropdownMenuItem<String>(
                                value: profissional.id,

                                child: Text(
                                  profissional.nome,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),

                        onChanged:
                            processando
                                ? null
                                : (value) {
                                  setDialogState(() {
                                    profissionalSelecionadoId = value ?? '';
                                  });
                                },
                      ),

                      const SizedBox(height: 16),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Color(0xFF16A34A),
                            ),

                            SizedBox(width: 8),

                            Expanded(
                              child: Text(
                                'Ao concluir, o sistema criará automaticamente '
                                'o pedido referente ao atendimento.',
                                style: TextStyle(
                                  color: Color(0xFF166534),
                                  fontSize: 11.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed:
                      processando
                          ? null
                          : () {
                            Navigator.of(dialogContext).pop(false);
                          },
                  child: const Text('Voltar'),
                ),

                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),

                  onPressed:
                      processando
                          ? null
                          : () async {
                            final valorFinal = converterValor(
                              valorController.text,
                            );

                            if (valorFinal <= 0) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Informe um valor final maior que zero.',
                                  ),
                                ),
                              );

                              return;
                            }

                            if (profissionalSelecionadoId.isEmpty) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Selecione o profissional que realizou o atendimento.',
                                  ),
                                ),
                              );

                              return;
                            }

                            final profissional = _controller.profissionais
                                .firstWhere(
                                  (item) =>
                                      item.id == profissionalSelecionadoId,
                                );

                            setDialogState(() {
                              processando = true;
                            });

                            /*
                             * Por enquanto enviamos para o
                             * controller os parâmetros que
                             * ele já possui.
                             *
                             * No próximo ajuste adicionaremos:
                             *
                             * pagamentoRecebido
                             * formaPagamento
                             * valorOriginal
                             * desconto
                             * acrescimo
                             */
                            final diferenca = valorFinal - valorOriginal;

                            final desconto =
                                diferenca < 0 ? diferenca.abs() : 0.0;

                            final acrescimo = diferenca > 0 ? diferenca : 0.0;

                            final resultado = await _controller
                                .concluirAgendamento(
                                  agendamento: agendamento,

                                  valorOriginal: valorOriginal,
                                  valorFinal: valorFinal,

                                  desconto: desconto,
                                  acrescimo: acrescimo,

                                  pagamentoRecebido: pagamentoRecebido,

                                  formaPagamento:
                                      pagamentoRecebido ? formaPagamento : null,

                                  profissionalExecutanteId: profissional.id,

                                  profissionalExecutanteNome: profissional.nome,
                                );
                            if (!dialogContext.mounted) {
                              return;
                            }

                            if (resultado.sucesso) {
                              Navigator.of(dialogContext).pop(true);

                              return;
                            }

                            setDialogState(() {
                              processando = false;
                            });

                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  resultado.mensagem ??
                                      'Não foi possível concluir o atendimento.',
                                ),
                              ),
                            );
                          },

                  icon:
                      processando
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.check_rounded),

                  label: Text(
                    processando ? 'Concluindo...' : 'Concluir atendimento',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    valorController.dispose();

    if (!mounted) {
      return;
    }

    if (confirmar == true) {
      _mostrarMensagem('Atendimento concluído e pedido criado com sucesso.');
    }
  }

  Widget _informacaoConclusao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E7EF)),
      ),
      child: Row(
        children: [
          Icon(icone, size: 20, color: const Color(0xFF6A2BFF)),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Color(0xFF77758A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  valor,
                  style: const TextStyle(
                    color: Color(0xFF17152B),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(mensagem)),
    );
  }

  /* ==========================================================
     CANCELAR AGENDAMENTO
     ========================================================== */

  Future<void> _cancelarAgendamento(AgendaAgendamento agendamento) async {
    final motivoCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cancel_outlined, color: Color(0xFFDC2626)),
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
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 12),

                Text(
                  agendamento.clienteNome,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),

                const SizedBox(height: 4),

                Text(
                  '${agendamento.horarioInicio} - '
                  '${agendamento.servicoNome}',
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: motivoCtrl,
                  maxLines: 3,
                  maxLength: 250,
                  decoration: InputDecoration(
                    labelText: 'Motivo do cancelamento',
                    hintText: 'Opcional',
                    prefixIcon: const Icon(Icons.notes_outlined),
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'O agendamento não será excluído. '
                  'Ele continuará no histórico como cancelado.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF77758A)),
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
                backgroundColor: const Color(0xFFDC2626),
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

    final sucesso = await _controller.cancelarAgendamento(
      agendamento: agendamento,
      motivo: motivo.isEmpty ? null : motivo,
    );

    if (!mounted) return;

    _mostrarMensagem(
      sucesso
          ? 'Agendamento cancelado com sucesso.'
          : 'Não foi possível cancelar o agendamento.',
    );
  }

  /* ==========================================================
     DESCANCELAR
     ========================================================== */

  Future<void> _descancelarAgendamento(AgendaAgendamento agendamento) async {
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restore_rounded, color: Color(0xFF16A34A)),
              SizedBox(width: 10),
              Expanded(child: Text('Descancelar agendamento')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deseja realmente reativar este agendamento?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8FC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E7EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agendamento.clienteNome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        agendamento.servicoNome,
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        '${DateFormat('dd/MM/yyyy').format(agendamento.inicio)} '
                        'às ${agendamento.horarioInicio}',
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        'Profissional: '
                        '${agendamento.profissionalNome}',
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xFF77758A),
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'O agendamento voltará para o status Agendado.',
                        style: TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 11.5,
                          height: 1.4,
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
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('Descancelar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    final sucesso = await _controller.descancelarAgendamento(
      agendamento: agendamento,
    );

    if (!mounted) return;

    _mostrarMensagem(
      sucesso
          ? 'Agendamento reativado com sucesso.'
          : 'Não foi possível descancelar o agendamento.',
    );
  }

  /* ==========================================================
     MARCAR COMO NÃO COMPARECEU
     ========================================================== */

  Future<void> _marcarNaoCompareceu(AgendaAgendamento agendamento) async {
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_off_outlined, color: Color(0xFFF59E0B)),
              SizedBox(width: 10),
              Expanded(child: Text('Cliente não compareceu')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirma que o cliente não compareceu a este agendamento?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8FC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E7EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agendamento.clienteNome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        agendamento.servicoNome,
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(agendamento.inicio)} '
                        'às ${agendamento.horarioInicio}',
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Profissional: ${agendamento.profissionalNome}',
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xFF77758A),
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'O agendamento permanecerá no histórico com o status '
                        'Não compareceu. Nenhum pedido ou lançamento financeiro '
                        'será criado.',
                        style: TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 11.5,
                          height: 1.4,
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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: const Text('Não compareceu'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    final sucesso = await _controller.marcarNaoCompareceu(
      agendamento: agendamento,
    );

    if (!mounted) return;

    _mostrarMensagem(
      sucesso
          ? 'Agendamento marcado como não compareceu.'
          : (_controller.erro ??
              'Não foi possível marcar o agendamento como não compareceu.'),
    );
  }

  /* ==========================================================
     REATIVAR NÃO COMPARECIMENTO
     ========================================================== */

  Future<void> _desfazerNaoComparecimento(AgendaAgendamento agendamento) async {
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restore_rounded, color: Color(0xFF16A34A)),
              SizedBox(width: 10),
              Expanded(child: Text('Reativar agendamento')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deseja desfazer a marcação de não comparecimento?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8FC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E7EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agendamento.clienteNome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(agendamento.inicio)} '
                        'às ${agendamento.horarioInicio}',
                        style: const TextStyle(
                          color: Color(0xFF77758A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'O agendamento voltará para o status Agendado.',
                  style: TextStyle(color: Color(0xFF77758A), fontSize: 11.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('Reativar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    final sucesso = await _controller.desfazerNaoComparecimento(
      agendamento: agendamento,
    );

    if (!mounted) return;

    _mostrarMensagem(
      sucesso
          ? 'Agendamento reativado com sucesso.'
          : (_controller.erro ?? 'Não foi possível reativar o agendamento.'),
    );
  }

  /* ==========================================================
     NOVO AGENDAMENTO
     ========================================================== */

  Future<void> _novoAgendamento() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NovoAgendamentoScreen()));

    if (!mounted) return;

    await _controller.carregarAgendamentos();
  }

  /* ==========================================================
     SELECIONAR DATA
     ========================================================== */

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _controller.dataSelecionada,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      locale: const Locale('pt', 'BR'),
      helpText: 'Selecionar data',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );

    if (data == null) {
      return;
    }

    await _controller.selecionarData(data);
  }

  /* ==========================================================
     DETALHES
     ========================================================== */

  Future<void> _abrirAgendamento(AgendaAgendamento agendamento) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return AgendaDetalhesAgendamento(
          agendamento: agendamento,

          onFechar: () {
            Navigator.of(bottomSheetContext).pop();
          },

          onCancelar: (motivo) async {
            return await _controller.cancelarAgendamento(
              agendamento: agendamento,
              motivo: motivo,
            );
          },
        );
      },
    );

    if (!mounted) return;

    await _controller.carregarAgendamentos();
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
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF17152B),

        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agenda',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              'Consulte seus agendamentos',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF77758A),
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Novo agendamento',
            onPressed: _novoAgendamento,
            icon: const Icon(Icons.add_rounded),
          ),

          IconButton(
            tooltip: 'Atualizar',
            onPressed:
                _controller.carregando
                    ? null
                    : () {
                      _controller.carregarAgendamentos();
                    },
            icon: const Icon(Icons.refresh_rounded),
          ),

          const SizedBox(width: 6),
        ],
      ),

      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _controller.carregarAgendamentos,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth >= 900 ? 28 : 16,
                  vertical: 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildNavegacaoData(),

                        const SizedBox(height: 14),

                        _buildFiltros(),

                        const SizedBox(height: 16),

                        _buildResumo(),

                        const SizedBox(height: 14),

                        _buildConteudo(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novoAgendamento,
        backgroundColor: const Color(0xFF6A2BFF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Novo agendamento',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  /* ==========================================================
     NAVEGAÇÃO DATA
     ========================================================== */

  Widget _buildNavegacaoData() {
    final data = _controller.dataSelecionada;

    final diaSemana = _capitalizar(DateFormat('EEEE', 'pt_BR').format(data));

    final dataFormatada = DateFormat(
      "dd 'de' MMMM 'de' yyyy",
      'pt_BR',
    ).format(data);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E7EF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _BotaoNavegacaoData(
                tooltip: 'Dia anterior',
                icon: Icons.chevron_left_rounded,
                onPressed: () {
                  _controller.diaAnterior();
                },
              ),

              const SizedBox(width: 10),

              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _selecionarData,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    child: Column(
                      children: [
                        Text(
                          diaSemana,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF6A2BFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          dataFormatada,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF17152B),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              _BotaoNavegacaoData(
                tooltip: 'Próximo dia',
                icon: Icons.chevron_right_rounded,
                onPressed: () {
                  _controller.proximoDia();
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _controller.ehHoje
                        ? null
                        : () {
                          _controller.irParaHoje();
                        },
                icon: const Icon(Icons.today_outlined, size: 18),
                label: const Text('Hoje'),
              ),

              const SizedBox(width: 8),

              OutlinedButton.icon(
                onPressed: _selecionarData,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Calendário'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     FILTROS
     ========================================================== */

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: Color(0xFF6A2BFF), size: 19),
              SizedBox(width: 7),
              Text(
                'Filtros',
                style: TextStyle(
                  color: Color(0xFF17152B),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 620;

              final profissional = _buildFiltroProfissional();

              final status = _buildFiltroStatus();

              if (vertical) {
                return Column(
                  children: [profissional, const SizedBox(height: 10), status],
                );
              }

              return Row(
                children: [
                  Expanded(child: profissional),
                  const SizedBox(width: 12),
                  Expanded(child: status),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroProfissional() {
    return DropdownButtonFormField<String>(
      initialValue: _controller.profissionalFiltroId,
      decoration: InputDecoration(
        labelText: 'Profissional',
        prefixIcon: const Icon(Icons.person_outline_rounded),
        filled: true,
        fillColor: const Color(0xFFF8F8FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE7E7EF)),
        ),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Todos os profissionais'),
        ),

        ..._controller.profissionais.map((profissional) {
          return DropdownMenuItem<String>(
            value: profissional.id,
            child: Text(profissional.nome, overflow: TextOverflow.ellipsis),
          );
        }),
      ],
      onChanged: (value) {
        _controller.selecionarProfissional(value ?? '');
      },
    );
  }

  Widget _buildFiltroStatus() {
    return DropdownButtonFormField<String>(
      initialValue: _controller.statusFiltro,
      decoration: InputDecoration(
        labelText: 'Status',
        prefixIcon: const Icon(Icons.flag_outlined),
        filled: true,
        fillColor: const Color(0xFFF8F8FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE7E7EF)),
        ),
      ),
      items:
          const [
            ['todos', 'Todos os status'],
            ['agendado', 'Agendados'],
            //['confirmado', 'Confirmados'],
            //['em_atendimento', 'Em atendimento'],
            ['concluido', 'Concluídos'],
            ['cancelado', 'Cancelados'],
            ['nao_compareceu', 'Não compareceu'],
          ].map((item) {
            return DropdownMenuItem<String>(
              value: item[0],
              child: Text(item[1]),
            );
          }).toList(),
      onChanged: (value) {
        _controller.selecionarStatus(value ?? 'todos');
      },
    );
  }

  /* ==========================================================
     RESUMO
     ========================================================== */

  Widget _buildResumo() {
    final quantidade = _controller.agendamentosFiltrados.length;

    return Row(
      children: [
        Expanded(
          child: Text(
            quantidade == 1 ? '1 agendamento' : '$quantidade agendamentos',
            style: const TextStyle(
              color: Color(0xFF17152B),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        if (_controller.carregando)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  /* ==========================================================
     CONTEÚDO
     ========================================================== */

  Widget _buildConteudo() {
    if (_controller.carregando && _controller.agendamentos.isEmpty) {
      return const AgendaCarregando();
    }

    if (_controller.erro != null) {
      return AgendaErro(
        mensagem: _controller.erro!,
        onTentarNovamente: _controller.carregarAgendamentos,
      );
    }

    final registros = _controller.agendamentosFiltrados;

    if (registros.isEmpty) {
      return AgendaVazia(data: _controller.dataSelecionada);
    }

    return Column(
      children: [
        for (final agendamento in registros) ...[
          AgendaAgendamentoCard(
            agendamento: agendamento,

            onTap: () {
              _abrirAgendamento(agendamento);
            },

            onEditar: () {
              _editarAgendamento(agendamento);
            },

            /*
             * AGORA ESTÁ ATIVO.
             */
            onConcluir: () {
              _concluirAgendamento(agendamento);
            },

            onCancelar: () {
              _cancelarAgendamento(agendamento);
            },

            onDescancelar: () {
              _descancelarAgendamento(agendamento);
            },

            onNaoCompareceu: () {
              _marcarNaoCompareceu(agendamento);
            },

            onDesfazerNaoComparecimento: () {
              _desfazerNaoComparecimento(agendamento);
            },
          ),

          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _capitalizar(String texto) {
    if (texto.isEmpty) {
      return texto;
    }

    return '${texto[0].toUpperCase()}'
        '${texto.substring(1)}';
  }
}

/* ============================================================
   BOTÃO DE NAVEGAÇÃO
   ============================================================ */

class _BotaoNavegacaoData extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _BotaoNavegacaoData({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: const Color(0xFF6A2BFF), size: 26),
          ),
        ),
      ),
    );
  }
}
