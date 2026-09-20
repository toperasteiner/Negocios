import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:share_plus/share_plus.dart';

import '../Cadastros/PerfilNegocioScreen.dart';
import '../Catalogo/CatalogoMenuScreen.dart';
import '../Planos/PlanosScreen.dart';
import '../Preferencias/PreferenciasScreen.dart';
import '../Login/login_screnn.dart';
import '../Daniel/TesteDanielScreen.dart';
import '../Treinamento/TreinamentosHomeScreen.dart';
import '../Agenda/AgendaMenuScreen.dart';

class AppMenuSheet {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color yellow = Color(0xFFFFB51F);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color sheetBackground = Color(0xFFFBFAFF);

  static void show(
    BuildContext context, {
    required bool isAdmin,
    required bool isPremium,
    required String? companyId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ModernMenuSheet(
          isAdmin: isAdmin,
          isPremium: isPremium,
          companyId: companyId,
          onPerfilNegocio: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PerfilNegocioScreen()),
            );
          },
          onPlanos: () {
            Navigator.pop(ctx);
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
          },
          onCatalogo: () {
            Navigator.pop(ctx);

            if (!isPremium) {
              _showPremiumRequiredDialog(
                context,
                titulo: 'Catálogo Online disponível no Premium',
                mensagem:
                    'O Catálogo Online é um recurso exclusivo do plano Premium.\n\n'
                    'Faça upgrade para criar e compartilhar seu catálogo público com seus clientes.',
              );
              return;
            }

            if (companyId == null || companyId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Empresa não identificada.')),
              );
              return;
            }

            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CatalogoMenuScreen()),
            );
          },
          onAgenda: () {
            Navigator.pop(ctx);
            if (!isPremium) {
              _showPremiumRequiredDialog(
                context,
                titulo: 'Agenda Online disponível no Premium',
                mensagem:
                    'A Agenda Online é um recurso exclusivo do plano Premium.\n\n'
                    'Faça upgrade para configurar profissionais, serviços, horários '
                    'e receber agendamentos online dos seus clientes.',
              );
              return;
            }
            if (companyId == null || companyId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Empresa não identificada.')),
              );
              return;
            }
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AgendaMenuScreen()));
          },
          onPreferencias: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PreferenciasScreen()),
            );
          },
          onAcessoComputador: () async {
            Navigator.pop(ctx);

            if (isPremium) {
              await _shareComputerAccess(context);
              return;
            }

            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
          },
          onAjuda: () {
            Navigator.pop(ctx);
            _showInfoDialog(
              context,
              titulo: 'Ajuda',
              mensagem:
                  'Em caso de dúvidas ou erro, entre em contato com nosso suporte pelo e-mail suporte@crudsistemas.com.br',
            );
          },
          onSobre: () {
            Navigator.pop(ctx);
            _showInfoDialog(
              context,
              titulo: 'Sobre o aplicativo',
              mensagem:
                  'CRUD Sistemas\n'
                  'Uma plataforma completa para gestão de pedidos, financeiro, estoque e clientes.',
            );
          },
          onSair: () async {
            Navigator.pop(ctx);
            await _confirmAndLogout(context);
          },
        );
      },
    );
  }

  static void _showPremiumRequiredDialog(
    BuildContext context, {
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  static Future<void> _shareComputerAccess(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';

      const link = 'https://projeto-pedidos-472813.web.app';

      final text = '''
Acesse o sistema no computador pelo link abaixo:

$link

${email.isNotEmpty ? 'Login sugerido: $email\n' : ''}Abra no navegador e entre com sua conta.
''';

      final params = ShareParams(text: text, subject: 'Acesso no computador');

      await SharePlus.instance.share(params);
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao compartilhar: $e')));
    }
  }

  static void _showInfoDialog(
    BuildContext context, {
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (dCtx) => AlertDialog(
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  static Future<void> _confirmAndLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dCtx) => AlertDialog(
            title: const Text('Sair do aplicativo?'),
            content: const Text(
              'Você precisará entrar novamente para continuar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
                onPressed: () => Navigator.pop(dCtx, true),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}

      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível sair. Tente novamente.'),
        ),
      );
      return;
    }

    if (!context.mounted) return;

    bool went = false;

    try {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      went = true;
    } catch (_) {}

    if (!went) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }
}

class _ModernMenuSheet extends StatelessWidget {
  final bool isAdmin;
  final bool isPremium;
  final String? companyId;
  final VoidCallback onPerfilNegocio;
  final VoidCallback onPlanos;
  final VoidCallback onCatalogo;
  final VoidCallback onAgenda;
  final VoidCallback onPreferencias;
  final Future<void> Function() onAcessoComputador;
  final VoidCallback onAjuda;
  final VoidCallback onSobre;
  final Future<void> Function() onSair;

  const _ModernMenuSheet({
    required this.isAdmin,
    required this.isPremium,
    required this.companyId,
    required this.onPerfilNegocio,
    required this.onPlanos,
    required this.onCatalogo,
    required this.onAgenda,
    required this.onPreferencias,
    required this.onAcessoComputador,
    required this.onAjuda,
    required this.onSobre,
    required this.onSair,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    final userEmail =
        FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();

    final isUsuarioTeste = userEmail == 'dani@dani.com';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, bottom + 18),
      decoration: const BoxDecoration(
        color: AppMenuSheet.sheetBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppMenuSheet.purple,
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    if (isAdmin)
                      _MenuItem(
                        icon: Icons.person_outline_rounded,
                        title: 'Perfil do Negócio',
                        color: AppMenuSheet.purple,
                        onTap: onPerfilNegocio,
                      ),

                    _MenuItem(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Planos',
                      color: AppMenuSheet.deepPurple,
                      onTap: onPlanos,
                    ),

                    if (isAdmin)
                      _MenuItem(
                        icon:
                            isPremium
                                ? Icons.storefront_outlined
                                : Icons.workspace_premium_outlined,
                        title: 'Catálogo Online',
                        subtitle:
                            isPremium
                                ? 'Visualizar catálogo público'
                                : 'Disponível no plano Premium',
                        color: AppMenuSheet.orange,
                        onTap: onCatalogo,
                      ),

                    if (isAdmin)
                      _MenuItem(
                        icon:
                            isPremium
                                ? Icons.calendar_month_outlined
                                : Icons.workspace_premium_outlined,
                        title: 'Agenda Online',
                        subtitle:
                            isPremium
                                ? 'Configurar e consultar agenda'
                                : 'Disponível no plano Premium',
                        color: AppMenuSheet.green,
                        onTap: onAgenda,
                      ),

                    if (isAdmin)
                      _MenuItem(
                        icon: Icons.settings_outlined,
                        title: 'Preferências',
                        color: AppMenuSheet.purple,
                        highlighted: true,
                        onTap: onPreferencias,
                      ),

                    _MenuItem(
                      icon:
                          isPremium
                              ? Icons.computer_outlined
                              : Icons.workspace_premium_outlined,
                      title: 'Acesso no computador',
                      subtitle:
                          isPremium
                              ? 'Compartilhar link de acesso'
                              : 'Disponível no plano Premium',
                      color: AppMenuSheet.blue,
                      onTap: onAcessoComputador,
                    ),

                    if (isUsuarioTeste)
                      _MenuItem(
                        icon: Icons.science_outlined,
                        title: 'Testes',
                        subtitle: 'Recursos internos',
                        color: AppMenuSheet.yellow,
                        onTap: () {
                          Navigator.pop(context);

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TesteDanielScreen(),
                            ),
                          );
                        },
                      ),

                    if (isUsuarioTeste)
                      _MenuItem(
                        icon: Icons.ondemand_video_rounded,
                        title: 'Treinamento',
                        subtitle: 'Treinamentos oficiais do aplicativo',
                        color: AppMenuSheet.deepPurple,
                        onTap: () {
                          Navigator.pop(context);

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TreinamentosHomeScreen(),
                            ),
                          );
                        },
                      ),

                    _MenuItem(
                      icon: Icons.help_outline_rounded,
                      title: 'Ajuda',
                      color: const Color(0xFF8E7CC3),
                      onTap: onAjuda,
                    ),

                    _MenuItem(
                      icon: Icons.info_outline_rounded,
                      title: 'Sobre',
                      color: AppMenuSheet.green,
                      onTap: onSobre,
                    ),

                    const SizedBox(height: 8),

                    _MenuItem(
                      icon: Icons.logout_rounded,
                      title: 'Sair',
                      color: Colors.redAccent,
                      danger: true,
                      onTap: onSair,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final bool highlighted;
  final bool danger;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.highlighted = false,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        highlighted
            ? AppMenuSheet.purple.withOpacity(0.08)
            : Colors.transparent;

    final titleColor = danger ? Colors.redAccent : AppMenuSheet.textDark;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.95), color.withOpacity(0.70)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppMenuSheet.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (!danger)
                Icon(Icons.chevron_right_rounded, color: color, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
