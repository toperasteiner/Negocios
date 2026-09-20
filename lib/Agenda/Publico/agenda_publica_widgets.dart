import 'package:flutter/material.dart';

class AgendaPublicaStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color purple = Color(0xFF7C3AED);

  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFE5E7EB);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/* ============================================================
   HEADER
   ============================================================ */

class AgendaPublicaHeader extends StatelessWidget {
  final String titulo;
  final String descricao;

  const AgendaPublicaHeader({
    super.key,
    required this.titulo,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
      decoration: BoxDecoration(
        gradient: AgendaPublicaStyle.gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            titulo.trim().isEmpty ? 'Agenda Online' : titulo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (descricao.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              descricao,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ============================================================
   PROGRESSO DAS ETAPAS
   ============================================================ */

class AgendaPublicaProgresso extends StatelessWidget {
  final int etapaAtual;

  const AgendaPublicaProgresso({super.key, required this.etapaAtual});

  static const _etapas = [
    _AgendaEtapaInfo(titulo: 'Serviço', icon: Icons.design_services_outlined),
    _AgendaEtapaInfo(
      titulo: 'Profissional',
      icon: Icons.person_outline_rounded,
    ),
    _AgendaEtapaInfo(
      titulo: 'Data e horário',
      icon: Icons.event_available_outlined,
    ),
    _AgendaEtapaInfo(titulo: 'Seus dados', icon: Icons.badge_outlined),
    _AgendaEtapaInfo(
      titulo: 'Confirmar',
      icon: Icons.check_circle_outline_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return _buildCompacto();
        }

        return _buildDesktop();
      },
    );
  }

  Widget _buildCompacto() {
    final etapaSegura = etapaAtual.clamp(0, _etapas.length - 1);

    final atual = _etapas[etapaSegura];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaPublicaStyle.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AgendaPublicaStyle.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              atual.icon,
              color: AgendaPublicaStyle.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Etapa ${etapaSegura + 1} de ${_etapas.length}',
                  style: const TextStyle(
                    color: AgendaPublicaStyle.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  atual.titulo,
                  style: const TextStyle(
                    color: AgendaPublicaStyle.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: (etapaSegura + 1) / _etapas.length,
                    backgroundColor: AgendaPublicaStyle.primary.withValues(
                      alpha: 0.08,
                    ),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AgendaPublicaStyle.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaPublicaStyle.border),
      ),
      child: Row(
        children: List.generate(_etapas.length, (index) {
          final concluida = index < etapaAtual;
          final atual = index == etapaAtual;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              concluida
                                  ? AgendaPublicaStyle.green
                                  : atual
                                  ? AgendaPublicaStyle.primary
                                  : AgendaPublicaStyle.bg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                concluida
                                    ? AgendaPublicaStyle.green
                                    : atual
                                    ? AgendaPublicaStyle.primary
                                    : AgendaPublicaStyle.border,
                          ),
                        ),
                        child: Icon(
                          concluida ? Icons.check_rounded : _etapas[index].icon,
                          size: 20,
                          color:
                              concluida || atual
                                  ? Colors.white
                                  : AgendaPublicaStyle.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _etapas[index].titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              atual
                                  ? AgendaPublicaStyle.primary
                                  : concluida
                                  ? AgendaPublicaStyle.green
                                  : AgendaPublicaStyle.muted,
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight:
                              atual || concluida
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < _etapas.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 28),
                      color:
                          index < etapaAtual
                              ? AgendaPublicaStyle.green
                              : AgendaPublicaStyle.border,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _AgendaEtapaInfo {
  final String titulo;
  final IconData icon;

  const _AgendaEtapaInfo({required this.titulo, required this.icon});
}

/* ============================================================
   CONTATO
   ============================================================ */

class AgendaPublicaContatoCard extends StatelessWidget {
  final String whatsapp;
  final String instagram;

  const AgendaPublicaContatoCard({
    super.key,
    required this.whatsapp,
    required this.instagram,
  });

  @override
  Widget build(BuildContext context) {
    final possuiWhatsapp = whatsapp.trim().isNotEmpty;
    final possuiInstagram = instagram.trim().isNotEmpty;

    if (!possuiWhatsapp && !possuiInstagram) {
      return const SizedBox.shrink();
    }

    return _AgendaPublicaCardBase(
      icon: Icons.forum_outlined,
      iconColor: AgendaPublicaStyle.green,
      titulo: 'Contato',
      subtitulo: 'Se precisar falar com a empresa, utilize os canais abaixo.',
      child: Column(
        children: [
          if (possuiWhatsapp)
            _AgendaInfoLinha(
              icon: Icons.chat_outlined,
              titulo: 'WhatsApp',
              valor: whatsapp,
            ),
          if (possuiWhatsapp && possuiInstagram)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AgendaPublicaStyle.border),
            ),
          if (possuiInstagram)
            _AgendaInfoLinha(
              icon: Icons.alternate_email_rounded,
              titulo: 'Instagram',
              valor: instagram,
            ),
        ],
      ),
    );
  }
}

/* ============================================================
   LOCALIZAÇÃO
   ============================================================ */

class AgendaPublicaLocalizacaoCard extends StatelessWidget {
  final String endereco;

  const AgendaPublicaLocalizacaoCard({super.key, required this.endereco});

  @override
  Widget build(BuildContext context) {
    if (endereco.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return _AgendaPublicaCardBase(
      icon: Icons.location_on_outlined,
      iconColor: AgendaPublicaStyle.orange,
      titulo: 'Local do atendimento',
      subtitulo: 'Confira onde o atendimento será realizado.',
      child: _AgendaInfoLinha(
        icon: Icons.place_outlined,
        titulo: 'Endereço',
        valor: endereco,
      ),
    );
  }
}

/* ============================================================
   RODAPÉ
   ============================================================ */

class AgendaPublicaRodape extends StatelessWidget {
  const AgendaPublicaRodape({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 4,
          decoration: BoxDecoration(
            color: AgendaPublicaStyle.border,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Agendamento online',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AgendaPublicaStyle.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Gerenciado pelo CRUD Negócios',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AgendaPublicaStyle.muted.withValues(alpha: 0.85),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
   CARD BASE
   ============================================================ */

class _AgendaPublicaCardBase extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String titulo;
  final String subtitulo;
  final Widget child;

  const _AgendaPublicaCardBase({
    required this.icon,
    required this.iconColor,
    required this.titulo,
    required this.subtitulo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaPublicaStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: AgendaPublicaStyle.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: AgendaPublicaStyle.muted,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

/* ============================================================
   LINHA DE INFORMAÇÃO
   ============================================================ */

class _AgendaInfoLinha extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String valor;

  const _AgendaInfoLinha({
    required this.icon,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AgendaPublicaStyle.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: AgendaPublicaStyle.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: AgendaPublicaStyle.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                valor,
                style: const TextStyle(
                  color: AgendaPublicaStyle.text,
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
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
   COMPONENTES REUTILIZÁVEIS PARA AS ETAPAS
   ============================================================ */

class AgendaPublicaEtapaCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String titulo;
  final String subtitulo;
  final Widget child;

  const AgendaPublicaEtapaCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.titulo,
    required this.subtitulo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _AgendaPublicaCardBase(
      icon: icon,
      iconColor: iconColor,
      titulo: titulo,
      subtitulo: subtitulo,
      child: child,
    );
  }
}

class AgendaPublicaBotaoVoltar extends StatelessWidget {
  final VoidCallback onPressed;

  const AgendaPublicaBotaoVoltar({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AgendaPublicaStyle.text,
        side: const BorderSide(color: AgendaPublicaStyle.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back_rounded, size: 19),
      label: const Text(
        'Voltar',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class AgendaPublicaBotaoPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final bool carregando;
  final IconData icon;

  const AgendaPublicaBotaoPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.carregando = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AgendaPublicaStyle.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AgendaPublicaStyle.primary.withValues(
          alpha: 0.35,
        ),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: carregando ? null : onPressed,
      icon:
          carregando
              ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
              : Icon(icon, size: 19),
      label: Text(
        carregando ? 'Aguarde...' : texto,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class AgendaPublicaEstadoVazio extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String descricao;

  const AgendaPublicaEstadoVazio({
    super.key,
    required this.icon,
    required this.titulo,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AgendaPublicaStyle.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgendaPublicaStyle.border),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AgendaPublicaStyle.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AgendaPublicaStyle.primary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaPublicaStyle.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            descricao,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgendaPublicaStyle.muted,
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

class AgendaPublicaCarregando extends StatelessWidget {
  final String texto;

  const AgendaPublicaCarregando({super.key, this.texto = 'Carregando...'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AgendaPublicaStyle.primary),
          const SizedBox(height: 14),
          Text(
            texto,
            style: const TextStyle(
              color: AgendaPublicaStyle.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
