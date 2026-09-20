import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Catalogo/CatalogoPublicoScreen.dart';
import 'UrlCatalogoScreen.dart';
import 'ProdutosSemEstoqueScreen.dart';
import 'HorarioFuncionamentoScreen.dart';
import 'FormasEntregaScreen.dart';
import '../Cadastros/PerfilNegocioScreen.dart';

class CatalogoMenuScreen extends StatelessWidget {
  const CatalogoMenuScreen({super.key});

  Future<String?> _getCompanyId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

    if (!doc.exists) return null;

    final companyId = (doc.data()?['companyId'] ?? '').toString().trim();

    if (companyId.isEmpty) return user.uid;

    return companyId;
  }

  Future<void> _abrirCatalogo(BuildContext context) async {
    final companyId = await _getCompanyId();

    if (!context.mounted) return;

    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogoPublicoScreen(companyId: companyId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo Online')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _OrientacaoCatalogoCard(),
          const SizedBox(height: 12),

          _MenuCard(
            icon: Icons.store_mall_directory_outlined,
            title: 'Perfil do negócio',
            subtitle: 'Cadastre nome, logo, banner e dados da empresa.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilNegocioScreen()),
              );
            },
          ),

          _MenuCard(
            icon: Icons.inventory_2_outlined,
            title: 'Produtos sem estoque',
            subtitle: 'Defina se produtos sem estoque aparecem no catálogo.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProdutosSemEstoqueScreen(),
                ),
              );
            },
          ),

          _MenuCard(
            icon: Icons.schedule_outlined,
            title: 'Horário de funcionamento',
            subtitle: 'Informe os dias e horários em que recebe pedidos.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HorarioFuncionamentoScreen(),
                ),
              );
            },
          ),

          _MenuCard(
            icon: Icons.local_shipping_outlined,
            title: 'Formas de entrega',
            subtitle: 'Configure retirada, entrega própria ou delivery.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FormasEntregaScreen()),
              );
            },
          ),

          _MenuCard(
            icon: Icons.link_outlined,
            title: 'URL do catálogo',
            subtitle: 'Configure e compartilhe o link público do catálogo.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UrlCatalogoScreen()),
              );
            },
          ),

          _MenuCard(
            icon: Icons.open_in_new,
            title: 'Visualizar catálogo',
            subtitle: 'Veja como seus clientes irão visualizar a loja.',
            onTap: () => _abrirCatalogo(context),
          ),
        ],
      ),
    );
  }
}

class _OrientacaoCatalogoCard extends StatelessWidget {
  const _OrientacaoCatalogoCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.primaryContainer.withOpacity(0.55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_outlined, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Como ativar seu catálogo online',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Para divulgar seus produtos e receber pedidos pelo catálogo online, configure as opções abaixo:',
              style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            const _PassoCatalogo(
              numero: '1',
              texto: 'Preencha o perfil do negócio com nome, logo e banner.',
            ),
            const _PassoCatalogo(
              numero: '2',
              texto: 'Defina como tratar produtos sem estoque.',
            ),
            const _PassoCatalogo(
              numero: '3',
              texto: 'Informe o horário de funcionamento.',
            ),
            const _PassoCatalogo(
              numero: '4',
              texto: 'Cadastre as formas de entrega.',
            ),
            const _PassoCatalogo(
              numero: '5',
              texto: 'Configure e compartilhe a URL do catálogo.',
            ),
            const SizedBox(height: 8),
            Text(
              'Depois de configurar, use a opção “Visualizar catálogo” para conferir como seus clientes irão visualizar a loja.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassoCatalogo extends StatelessWidget {
  final String numero;
  final String texto;

  const _PassoCatalogo({required this.numero, required this.texto});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: cs.primary,
            child: Text(
              numero,
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13.5, color: cs.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
