import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agenda_publica_controller.dart';
import 'agenda_publica_widgets.dart';

class EtapaCliente extends StatefulWidget {
  final AgendaPublicaController controller;
  final VoidCallback onVoltar;
  final VoidCallback onContinuar;

  const EtapaCliente({
    super.key,
    required this.controller,
    required this.onVoltar,
    required this.onContinuar,
  });

  @override
  State<EtapaCliente> createState() => _EtapaClienteState();
}

class _EtapaClienteState extends State<EtapaCliente> {
  final _formKey = GlobalKey<FormState>();

  /* ==========================================================
     CONTINUAR
     ========================================================== */

  void _continuar() {
    FocusScope.of(context).unfocus();

    final formularioValido = _formKey.currentState?.validate() ?? false;

    if (!formularioValido) {
      return;
    }

    final erro = widget.controller.validarDadosCliente();

    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(erro)),
      );

      return;
    }

    widget.onContinuar();
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    return AgendaPublicaEtapaCard(
      icon: Icons.badge_outlined,
      iconColor: AgendaPublicaStyle.blue,
      titulo: 'Seus dados',
      subtitulo: 'Informe seus dados para identificarmos o seu agendamento.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            /* ==================================================
               NOME
               ================================================== */
            _CampoAgenda(
              controller: widget.controller.nomeClienteCtrl,
              label: 'Nome completo',
              hint: 'Digite seu nome',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: (valor) {
                final texto = valor?.trim() ?? '';

                if (texto.isEmpty) {
                  return 'Informe seu nome.';
                }

                if (texto.length < 2) {
                  return 'Informe um nome válido.';
                }

                return null;
              },
            ),

            const SizedBox(height: 16),

            /* ==================================================
               TELEFONE / WHATSAPP
               ================================================== */
            _CampoAgenda(
              controller: widget.controller.telefoneClienteCtrl,
              label: 'WhatsApp ou telefone',
              hint: '(00) 00000-0000',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _TelefoneInputFormatter(),
              ],
              validator: (valor) {
                final numeros = (valor ?? '').replaceAll(RegExp(r'[^0-9]'), '');

                if (numeros.isEmpty) {
                  return 'Informe seu WhatsApp ou telefone.';
                }

                if (numeros.length < 10) {
                  return 'Informe um telefone válido com DDD.';
                }

                return null;
              },
            ),

            const SizedBox(height: 16),

            /* ==================================================
               E-MAIL
               ================================================== */
            _CampoAgenda(
              controller: widget.controller.emailClienteCtrl,
              label: 'E-mail',
              hint: 'seuemail@exemplo.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (valor) {
                final texto = valor?.trim() ?? '';

                // E-mail é opcional.
                if (texto.isEmpty) {
                  return null;
                }

                final emailValido = RegExp(
                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                ).hasMatch(texto);

                if (!emailValido) {
                  return 'Informe um e-mail válido.';
                }

                return null;
              },
            ),

            const SizedBox(height: 16),

            /* ==================================================
               OBSERVAÇÃO
               ================================================== */
            _CampoAgenda(
              controller: widget.controller.observacaoCtrl,
              label: 'Observação',
              hint:
                  'Se desejar, informe alguma observação sobre o atendimento.',
              icon: Icons.notes_rounded,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: 4,
              minLines: 3,
              maxLength: 500,
            ),

            const SizedBox(height: 8),

            /* ==================================================
               AVISO
               ================================================== */
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AgendaPublicaStyle.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AgendaPublicaStyle.primary.withValues(alpha: 0.10),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 19,
                    color: AgendaPublicaStyle.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Utilizaremos esses dados para identificar e gerenciar o seu agendamento.',
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

            /* ==================================================
               BOTÕES
               ================================================== */
            LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 480;

                if (compacto) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AgendaPublicaBotaoPrincipal(
                        texto: 'Continuar',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: _continuar,
                      ),
                      const SizedBox(height: 10),
                      AgendaPublicaBotaoVoltar(onPressed: widget.onVoltar),
                    ],
                  );
                }

                return Row(
                  children: [
                    AgendaPublicaBotaoVoltar(onPressed: widget.onVoltar),
                    const Spacer(),
                    AgendaPublicaBotaoPrincipal(
                      texto: 'Continuar',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _continuar,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   CAMPO PADRÃO DA AGENDA
   ============================================================ */

class _CampoAgenda extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  final String? Function(String?)? validator;

  final int maxLines;
  final int minLines;
  final int? maxLength;

  const _CampoAgenda({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.validator,
    this.maxLines = 1,
    this.minLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      validator: validator,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      style: const TextStyle(
        color: AgendaPublicaStyle.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AgendaPublicaStyle.primary, size: 21),
        labelStyle: const TextStyle(
          color: AgendaPublicaStyle.muted,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: AgendaPublicaStyle.muted.withValues(alpha: 0.70),
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        counterStyle: const TextStyle(
          color: AgendaPublicaStyle.muted,
          fontSize: 10,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AgendaPublicaStyle.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AgendaPublicaStyle.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(
            color: AgendaPublicaStyle.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }
}

/* ============================================================
   MÁSCARA DO TELEFONE
   ============================================================ */

class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var numeros = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length > 11) {
      numeros = numeros.substring(0, 11);
    }

    String texto;

    if (numeros.isEmpty) {
      texto = '';
    } else if (numeros.length <= 2) {
      texto = '($numeros';
    } else if (numeros.length <= 6) {
      texto =
          '(${numeros.substring(0, 2)}) '
          '${numeros.substring(2)}';
    } else if (numeros.length <= 10) {
      texto =
          '(${numeros.substring(0, 2)}) '
          '${numeros.substring(2, 6)}-'
          '${numeros.substring(6)}';
    } else {
      texto =
          '(${numeros.substring(0, 2)}) '
          '${numeros.substring(2, 7)}-'
          '${numeros.substring(7)}';
    }

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
