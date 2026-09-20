// lib/Ajuda/AjudaSheet.dart
import 'package:flutter/material.dart';
// (opcional) para abrir links de suporte/whatsapp/email
// adicione no pubspec.yaml: url_launcher: ^6.3.0
// import 'package:url_launcher/url_launcher.dart';

Future<void> showAjuda(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _AjudaSheet(),
  );
}

class _AjudaSheet extends StatelessWidget {
  const _AjudaSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ajuda',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.menu_book_outlined), text: 'Guia'),
                  Tab(icon: Icon(Icons.quiz_outlined), text: 'FAQ'),
                  Tab(icon: Icon(Icons.flash_on_outlined), text: 'Ações'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: TabBarView(
                children: [_GuiaRapidoTab(), _FaqTab(), _AcoesRapidasTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuiaRapidoTab extends StatelessWidget {
  const _GuiaRapidoTab();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget h(String s) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        s,
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
    Widget p(String s) =>
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s));
    Widget li(String s) => Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const Text('•  '), Expanded(child: Text(s))],
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      children: [
        h('Como começar'),
        li('Abra “Pedidos” e toque em **novo pedido**.'),
        li('Selecione o **cliente**.'),
        li('Em **Pedido**, adicione **Serviços** e/ou **Produtos**.'),
        li('Defina **Parcelas** e **Meios de pagamento** em **Detalhes**.'),
        li(
          'Opcional: **Garantia**, **Cláusulas**, **Informações** e **Compromissos**.',
        ),
        li('Toque em **salvar pedido**.'),

        h('Produtos & Estoque'),
        p(
          'Ao escolher produtos do catálogo, o sistema mostra o preço e permite ajustar a quantidade.',
        ),
        li(
          'Se o produto **controla estoque** e você informar quantidade maior que o disponível, o campo de quantidade fica **vermelho** (alerta).',
        ),
        li(
          'Ao salvar: baixa/repõe estoque automaticamente conforme a diferença entre o que já havia e o que ficou no pedido.',
        ),
        li('Cancelar pedido repõe o saldo; tirar de cancelado volta a baixar.'),

        h('Pagamentos'),
        li(
          'Configure **à vista** ou **parcelado** e a data do primeiro vencimento.',
        ),
        li('Os **Recebíveis** são gerados após salvar.'),

        h('Numeração'),
        p(
          'A numeração é única por **ano** e **usuário**. Se já existir, o sistema sugere o próximo número disponível.',
        ),

        h('Dicas'),
        li('Use o menu ⋮ no item para **editar** ou **excluir**.'),
        li('Use **Duplicar pedido** na lista para reaproveitar dados.'),
      ],
    );
  }
}

class _FaqTab extends StatelessWidget {
  const _FaqTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        _FaqQ(
          q: 'Não consigo salvar o pedido.',
          a: 'Verifique: cliente selecionado, forma de pagamento definida em Parcelas e ao menos um item (produto ou serviço).',
        ),
        _FaqQ(
          q: 'Quantidade maior que o estoque.',
          a: 'Ajuste a quantidade (o campo fica vermelho) ou prossiga mesmo assim ao salvar; o sistema avisa e permite continuar.',
        ),
        _FaqQ(
          q: 'Como funciona o estoque quando edito um pedido?',
          a: 'Somente a diferença entre as quantidades antigas e novas é aplicada no estoque (com log em movimento_estoque).',
        ),
        _FaqQ(
          q: 'O número do pedido já existe.',
          a: 'Aceite a sugestão apresentada (próximo número) ou edite manualmente para um número livre.',
        ),
        _FaqQ(
          q: 'Posso duplicar um pedido?',
          a: 'Sim. Use “Duplicar pedido” na lista; revise e salve como novo.',
        ),
      ],
    );
  }
}

class _FaqQ extends StatelessWidget {
  final String q;
  final String a;
  const _FaqQ({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 12, right: 4, bottom: 8),
      title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [Text(a)],
    );
  }
}

class _AcoesRapidasTab extends StatelessWidget {
  const _AcoesRapidasTab();

  // Future<void> _openUrl(String url) async {
  //   final uri = Uri.parse(url);
  //   if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  // }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    ListTile tile({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
    }) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: cs.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
    }

    void snack(String msg) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg)));

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        tile(
          icon: Icons.play_circle_outline,
          title: 'Tour rápido da tela de pedidos',
          subtitle: 'Veja onde fica cada ação',
          onTap: () => snack('Tour rápido: em breve 😉'),
        ),
        tile(
          icon: Icons.menu_book_outlined,
          title: 'Abrir guia completo',
          subtitle: 'Passo-a-passo detalhado',
          onTap:
              () => showDialog(
                context: context,
                builder: (_) => const _GuiaDialog(),
              ),
        ),
        tile(
          icon: Icons.help_outline,
          title: 'Dúvidas sobre estoque',
          subtitle: 'Baixa/Reposição, cancelamento e alertas',
          onTap:
              () => showDialog(
                context: context,
                builder: (_) => const _AjudaEstoqueDialog(),
              ),
        ),
        const Divider(height: 24),
        tile(
          icon: Icons.support_agent_outlined,
          title: 'Falar com o suporte',
          subtitle: 'WhatsApp / E-mail',
          onTap: () {
            // _openUrl('https://wa.me/5599999999999'); // habilite url_launcher
            snack('Abra o WhatsApp/email do suporte (configure url_launcher).');
          },
        ),
        tile(
          icon: Icons.bug_report_outlined,
          title: 'Reportar um problema',
          subtitle: 'Envie logs e descrição',
          onTap: () => snack('Abra o formulário de feedback (implementar).'),
        ),
      ],
    );
  }
}

class _GuiaDialog extends StatelessWidget {
  const _GuiaDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Guia completo'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _GuideBlock(
                title: '1) Criar pedido',
                bullets: [
                  'Toque em “novo pedido”, selecione o cliente.',
                  'Adicione serviços e/ou produtos.',
                  'Defina desconto, taxas e detalhes.',
                ],
              ),
              _GuideBlock(
                title: '2) Pagamentos',
                bullets: [
                  'Configure à vista ou parcelado e 1º vencimento.',
                  'Escolha os meios aceitos.',
                ],
              ),
              _GuideBlock(
                title: '3) Estoque',
                bullets: [
                  'Produtos com “controlaEstoque=true” são validados.',
                  'Se quantidade > estoque, o campo fica vermelho.',
                  'Ao salvar, baixa/repõe somente a DIFERENÇA.',
                  'Cancelar pedido repõe; tirar de cancelado volta a baixar.',
                ],
              ),
              _GuideBlock(
                title: '4) Status & Recebíveis',
                bullets: [
                  'Escolha o status após salvar.',
                  'Gere a prévia das contas a receber.',
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi'),
        ),
      ],
      backgroundColor: cs.surface,
    );
  }
}

class _AjudaEstoqueDialog extends StatelessWidget {
  const _AjudaEstoqueDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajuda — Estoque'),
      content: const SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _GuideBlock(
            title: 'Regras de estoque',
            bullets: [
              'Validação visual: quantidade em vermelho se excede o estoque.',
              'Salvar com excedente: o sistema pergunta se deseja continuar.',
              'Baixa/Reposição: aplica a diferença em relação ao pedido anterior.',
              'Cancelado → repõe; voltar de cancelado → baixa novamente.',
              'Log em “movimento_estoque” para auditoria.',
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _GuideBlock extends StatelessWidget {
  final String title;
  final List<String> bullets;
  const _GuideBlock({required this.title, required this.bullets});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [const Text('•  '), Expanded(child: Text(b))],
              ),
            ),
        ],
      ),
    );
  }
}
