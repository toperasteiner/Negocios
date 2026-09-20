import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../Cadastros/ProdutoScreen.dart';
import '../Cadastros/ServicosCrudScreen.dart';
import '../Cadastros/Cliente_screen.dart';
import '../Cadastros/ComprasCrudScreen.dart';
import '../atividades/ConsultarAjustarEstoqueScreen.dart';
import '../Financeiro/ContasPagarHomeScreen.dart';
import '../Financeiro/ContasReceberHomeScreen.dart';
import '../Planos/PlanosScreen.dart';
import '../atividades/ComprasAprovacaoScreen.dart';
import '../atividades/RevisaoCustoProdutosScreen.dart';
import '../Home/home_widgets.dart';
import '../Treinamento/TreinamentosHomeScreen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../Agenda/AgendaMenuScreen.dart';

class SugestoesHomeWidget extends StatelessWidget {
  final String scopeField;
  final String scopeUserId;
  final String? companyId;
  final bool isPremium;
  final VoidCallback onCatalogo;
  final Future<void> Function() onComputador;

  const SugestoesHomeWidget({
    super.key,
    required this.scopeField,
    required this.scopeUserId,
    required this.companyId,
    required this.isPremium,
    required this.onCatalogo,
    required this.onComputador,
  });

  Future<int> _countProdutosComCustoDiferente() async {
    if (scopeUserId.isEmpty) return 0;

    final snap =
        await FirebaseFirestore.instance
            .collection('produtos')
            .where(scopeField, isEqualTo: scopeUserId)
            .get();

    int total = 0;

    for (final doc in snap.docs) {
      final m = doc.data();

      final custo = (m['custo'] as num?)?.toDouble() ?? 0.0;
      final precoMedio = (m['precoMedio'] as num?)?.toDouble() ?? 0.0;

      if (precoMedio > 0 && (custo - precoMedio).abs() >= 0.01) {
        total++;
      }
    }

    return total;
  }

  Future<int> _countCollection(String collection) async {
    if (scopeUserId.isEmpty) return 0;

    final snap =
        await FirebaseFirestore.instance
            .collection(collection)
            .where(scopeField, isEqualTo: scopeUserId)
            .limit(1)
            .get();

    return snap.docs.length;
  }

  Future<void> _shareComputerAccess(BuildContext context) async {
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

  Future<bool> _temPendenciaEstoque() async {
    if (scopeUserId.isEmpty) return false;

    final snap =
        await FirebaseFirestore.instance
            .collection('produtos')
            .where(scopeField, isEqualTo: scopeUserId)
            .where('controlaEstoque', isEqualTo: true)
            .get();

    for (final doc in snap.docs) {
      final m = doc.data();

      final estoque = (m['estoque'] as num?)?.toDouble() ?? 0.0;
      final minimo =
          (m['estoqueMin'] as num?)?.toDouble() ??
          (m['estoqueAlerta'] as num?)?.toDouble() ??
          0.0;

      if (minimo > 0) {
        if (estoque < minimo) return true;
      } else {
        if (estoque <= 0) return true;
      }
    }

    return false;
  }

  Future<bool> _temContaPagarAtrasada() async {
    if (scopeUserId.isEmpty) return false;

    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);

    final snap =
        await FirebaseFirestore.instance
            .collection('contas_pagar')
            .where(scopeField, isEqualTo: scopeUserId)
            .get();

    for (final doc in snap.docs) {
      final m = doc.data();

      final status = (m['status'] ?? '').toString().toLowerCase();
      if (status == 'pago' || status == 'cancelado') continue;

      final dataVencimento = m['vencimento'];

      if (dataVencimento is Timestamp &&
          dataVencimento.toDate().isBefore(inicioHoje)) {
        return true;
      }
    }

    return false;
  }

  Future<int> _countComprasParaAprovar() async {
    if (scopeUserId.isEmpty) return 0;

    final snap =
        await FirebaseFirestore.instance
            .collection('compras')
            .where(scopeField, isEqualTo: scopeUserId)
            .where('status', whereIn: ['aberta', 'entrega_parcial'])
            .get();

    return snap.docs.length;
  }

  Future<bool> _temContaReceberAtrasada() async {
    if (scopeUserId.isEmpty) return false;

    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);

    final snap =
        await FirebaseFirestore.instance
            .collection('contas_receber')
            .where(scopeField, isEqualTo: scopeUserId)
            .get();

    for (final doc in snap.docs) {
      final m = doc.data();

      final status = (m['status'] ?? '').toString().toLowerCase();
      if (status == 'pago' || status == 'cancelado') continue;

      final dataVencimento = m['vencimento'];

      if (dataVencimento is Timestamp &&
          dataVencimento.toDate().isBefore(inicioHoje)) {
        return true;
      }
    }

    return false;
  }

  Future<List<QuickActionData>> montarAcoesRapidas(BuildContext context) async {
    final sugestoes = <QuickActionData>[];

    sugestoes.add(
      QuickActionData(
        icon: Icons.ondemand_video_rounded,
        label: 'Treinamentos',
        color: HomeColors.deepPurple,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TreinamentosHomeScreen()),
          );
        },
      ),
    );

    final produtos = await _countCollection('produtos');
    if (produtos == 0) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.inventory_2_outlined,
          label: 'Cadastrar Produto',
          color: HomeColors.purple,
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProdutoScreen()));
          },
        ),
      );
    }

    final servicos = await _countCollection('servicos');
    if (servicos == 0) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.build_outlined,
          label: 'Cadastrar Serviço',
          color: HomeColors.orange,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServicosCrudScreen()),
            );
          },
        ),
      );
    }

    final clientes = await _countCollection('clientes');
    if (clientes == 0) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.group_outlined,
          label: 'Cadastrar Cliente',
          color: HomeColors.green,
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ClienteScreen()));
          },
        ),
      );
    }

    await _countCollection('compras');

    sugestoes.add(
      QuickActionData(
        icon: Icons.shopping_cart_outlined,
        label: 'Cadastrar Compra',
        color: HomeColors.purple,
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ComprasCrudScreen()));
        },
      ),
    );

    final comprasParaAprovar = await _countComprasParaAprovar();
    final produtosRevisarCusto = await _countProdutosComCustoDiferente();

    if (produtosRevisarCusto > 0) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.price_change_outlined,
          label: produtosRevisarCusto == 1 ? 'Revisar Custo' : 'Revisar Custos',
          color: HomeColors.yellow,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RevisaoCustoProdutosScreen(),
              ),
            );
          },
        ),
      );
    }

    if (comprasParaAprovar > 0) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.fact_check_outlined,
          label: comprasParaAprovar == 1 ? 'Aprovar Compra' : 'Aprovar Compras',
          color: HomeColors.orange,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ComprasAprovacaoScreen()),
            );
          },
        ),
      );
    }

    if (await _temPendenciaEstoque()) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.inventory_outlined,
          label: 'Atualizar Estoque',
          color: HomeColors.green,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ConsultarAjustarEstoqueScreen(),
              ),
            );
          },
        ),
      );
    }

    if (await _temContaPagarAtrasada()) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.receipt_long_outlined,
          label: 'Contas a Pagar',
          color: HomeColors.redOrange,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ContasPagarHomeScreen()),
            );
          },
        ),
      );
    }

    if (await _temContaReceberAtrasada()) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.request_quote_outlined,
          label: 'Contas a Receber',
          color: HomeColors.green,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ContasReceberHomeScreen(),
              ),
            );
          },
        ),
      );
    }

    if (!isPremium) {
      sugestoes.add(
        QuickActionData(
          icon: Icons.workspace_premium_outlined,
          label: 'Ver Planos',
          color: HomeColors.purple,
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
          },
        ),
      );
    }

    sugestoes.add(
      QuickActionData(
        icon:
            isPremium
                ? Icons.storefront_outlined
                : Icons.workspace_premium_outlined,
        label: 'Catálogo Online',
        color: HomeColors.orange,
        onTap: onCatalogo,
      ),
    );

    sugestoes.add(
      QuickActionData(
        icon:
            isPremium
                ? Icons.calendar_month_outlined
                : Icons.workspace_premium_outlined,
        label: 'Agenda Online',
        color: HomeColors.green,
        onTap: () {
          if (isPremium) {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AgendaMenuScreen()));
            return;
          }

          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
        },
      ),
    );

    sugestoes.add(
      QuickActionData(
        icon:
            isPremium
                ? Icons.computer_outlined
                : Icons.workspace_premium_outlined,
        label: 'Acesso Computador',
        color: HomeColors.purple,
        onTap: () async {
          if (isPremium) {
            await _shareComputerAccess(context);
            return;
          }

          if (!context.mounted) return;

          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
        },
      ),
    );

    return sugestoes;
  }

  @override
  Widget build(BuildContext context) {
    if (scopeUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<QuickActionData>>(
      future: montarAcoesRapidas(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final sugestoes = snapshot.data ?? [];

        if (sugestoes.isEmpty) {
          return const SizedBox.shrink();
        }

        final cs = Theme.of(context).colorScheme;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sugestão para você',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.spaceAround,
                children:
                    sugestoes.map((s) {
                      return SizedBox(
                        width: 96,
                        child: _SugestaoItem(
                          icon: s.icon,
                          label: s.label,
                          onTap: s.onTap,
                        ),
                      );
                    }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SugestaoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SugestaoItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cs.primaryContainer,
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
