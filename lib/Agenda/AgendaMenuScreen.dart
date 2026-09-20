import 'package:flutter/material.dart';
import 'ProfissionaisAgendaScreen.dart';
import 'HorariosFuncionamentoScreen.dart';
import '../Cadastros/ServicosCrudScreen.dart';
import 'ServicosPorProfissionalScreen.dart';
import 'ConfiguracaoPaginaPublica.dart';
import 'BloqueiosAgendaScreen.dart';
import 'NovoAgendamentoScreen.dart';
import 'AgendaScreen.dart';
import 'Dashboard/agenda_dashboard_screen.dart';

class AgendaMenuScreen extends StatelessWidget {
  const AgendaMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgendaMenuStyle.bg,
      body: Column(
        children: [
          _AgendaHeader(onBack: () => Navigator.of(context).maybePop()),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                //const _IntroCard(),
                const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.schedule_outlined,
                  color: AgendaMenuStyle.blue,
                  title: 'Horários de atendimento',
                  subtitle:
                      'Defina os dias e horários em que os atendimentos poderão ser realizados.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HorariosFuncionamentoScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 18),

                _AgendaMenuCard(
                  icon: Icons.people_alt_outlined,
                  color: AgendaMenuStyle.primary,
                  title: 'Profissionais',
                  subtitle:
                      'Cadastre e configure os profissionais que receberão clientes.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProfissionaisAgendaScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.design_services_outlined,
                  color: AgendaMenuStyle.purple,
                  title: 'Serviços',
                  subtitle:
                      'Cadastre os serviços que poderão ser oferecidos nos agendamentos.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ServicosCrudScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.design_services_outlined,
                  color: AgendaMenuStyle.orange,
                  title: 'Serviços por profissional',
                  subtitle:
                      'Informe quais serviços cada profissional está autorizado a realizar.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ServicosPorProfissionalScreen(),
                      ),
                    );
                  },
                ),

                /*const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.rule_outlined,
                  color: AgendaMenuStyle.green,
                  title: 'Regras de agendamento',
                  subtitle:
                      'Configure antecedência, cancelamentos e outras regras da agenda.',
                  onTap: () {
                    _emDesenvolvimento(context, 'Regras de agendamento');
                  },
                ),*/
                const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.public_outlined,
                  color: AgendaMenuStyle.purple,
                  title: 'Página pública',
                  subtitle:
                      'Configure a página que seus clientes utilizarão para fazer agendamentos.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConfiguracaoPaginaPublica(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),
                _AgendaMenuCard(
                  icon: Icons.event_busy_outlined,
                  color: AgendaMenuStyle.orange,
                  title: 'Bloqueios da agenda',
                  subtitle:
                      'Cadastre folgas, reuniões, compromissos e outros períodos indisponíveis.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BloqueiosAgendaScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.calendar_month_outlined,
                  color: AgendaMenuStyle.blue,
                  title: 'Consultar agenda',
                  subtitle:
                      'Visualize os agendamentos do dia, filtre por profissional e acompanhe os atendimentos.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AgendaScreen()),
                    );
                  },
                ),

                const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.analytics_outlined,
                  color: AgendaMenuStyle.green,
                  title: 'Resultados da agenda',
                  subtitle:
                      'Acompanhe faturamento, atendimentos, comparecimento, cancelamentos e desempenho dos profissionais.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AgendaDashboardScreen(),
                      ),
                    );
                  },
                ),

                /*const SizedBox(height: 12),

                _AgendaMenuCard(
                  icon: Icons.event_available_outlined,
                  color: AgendaMenuStyle.green,
                  title: 'Novo agendamento',
                  subtitle:
                      'Cadastre manualmente um atendimento para um cliente, serviço e profissional.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NovoAgendamentoScreen(),
                      ),
                    );
                  },
                ),*/
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _emDesenvolvimento(BuildContext context, String opcao) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$opcao ainda está em desenvolvimento.')),
    );
  }
}

/* ============================================================
   HEADER
   ============================================================ */

class _AgendaHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _AgendaHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AgendaMenuStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        20,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Expanded(
                child: Center(
                  child: Text(
                    'Agenda',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 42),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Configure sua agenda online e prepare seu negócio para receber agendamentos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontSize: 14,
              height: 1.30,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   ITEM DO MENU
   ============================================================ */

class _AgendaMenuCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AgendaMenuCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              _IconBadge(icon: icon, color: color),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AgendaMenuStyle.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AgendaMenuStyle.muted,
                        fontSize: 12.5,
                        height: 1.30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              const Icon(
                Icons.chevron_right_rounded,
                color: AgendaMenuStyle.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ============================================================
   COMPONENTES VISUAIS
   ============================================================ */

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 25),
    );
  }
}

/* ============================================================
   STYLE
   ============================================================ */

class AgendaMenuStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);

  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color purple = Color(0xFF7C3AED);

  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
