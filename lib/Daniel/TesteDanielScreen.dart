import 'package:flutter/material.dart';
import '../Daniel/UserPremium.dart';
import '../Daniel/EmailMarketingScreen.dart';
import '../daniel/ImagensPendentesScreen.dart';
import '../Daniel/UsuariosUltimoAcessoScreen.dart';
import '../Daniel/CotacaoFreteInternacionalScreen.dart';
import '../Daniel/CotacoesFreteInternacionalListScreen.dart';
import '../Daniel/TrainingLessonFormScreen.dart';
import '../Daniel/TrainingViewsDashboardScreen.dart';

class TesteDanielScreen extends StatelessWidget {
  const TesteDanielScreen({super.key});

  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color yellow = Color(0xFFFFB51F);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color background = Color(0xFFFBFAFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text(
          'Testes',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: purple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Área de Testes Daniel',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use esta tela para acessar funcionalidades internas de teste do aplicativo.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textMuted,
              ),
            ),

            const SizedBox(height: 22),

            _TestMenuItem(
              icon: Icons.science_outlined,
              title: 'Teste 1',
              subtitle: 'Área reservada para testes internos',
              color: purple,
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const UserPremium()));
              },
            ),

            /*_TestMenuItem(
              icon: Icons.science_outlined,
              title: 'Email Marketing',
              subtitle: 'Área reservada para testes internos',
              color: purple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EmailMarketingScreen(),
                  ),
                );
              },
            ),*/
            _TestMenuItem(
              icon: Icons.science_outlined,
              title: 'Imagens Pendentes',
              subtitle: 'Área reservada para testes internos',
              color: purple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ImagensPendentesScreen(),
                  ),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.science_outlined,
              title: 'Ultimo Acesso',
              subtitle: 'Área reservada para testes internos',
              color: purple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UsuariosUltimoAcessoScreen(),
                  ),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.science_outlined,
              title: 'Criar video aula',
              subtitle: 'Criar video aula',
              color: purple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TrainingLessonFormScreen(),
                  ),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.science_outlined,
              title: 'Relatorio de view',
              subtitle: 'Relatorio de view',
              color: purple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TrainingViewsDashboardScreen(),
                  ),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.bug_report_outlined,
              title: 'Testes Cotação',
              subtitle: 'Testes Cotação',
              color: orange,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CotacaoFreteInternacionalScreen(),
                  ),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.cloud_sync_outlined,
              title: 'Testes Envio Orçamento',
              subtitle: 'Testes Envio Orçamento',
              color: blue,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (_) => const CotacoesFreteInternacionalListScreen(),
                  ),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.workspace_premium_outlined,
              title: 'Testes de Plano',
              subtitle: 'Validar regras de Free, Starter e Premium',
              color: green,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Testes de Plano')),
                );
              },
            ),

            _TestMenuItem(
              icon: Icons.warning_amber_rounded,
              title: 'Área Experimental',
              subtitle: 'Funcionalidades ainda não liberadas',
              color: yellow,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Área Experimental')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TestMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TestMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.95),
                        color.withOpacity(0.70),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: TesteDanielScreen.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: TesteDanielScreen.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
