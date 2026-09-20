import 'package:flutter/material.dart';

enum BillingPeriod { mensal, semestral, anual }

const _periodLabel = {
  BillingPeriod.mensal: 'Mensal',
  BillingPeriod.semestral: 'Semestral',
  BillingPeriod.anual: 'Anual',
};

class PlanosScreen extends StatefulWidget {
  const PlanosScreen({super.key});

  @override
  State<PlanosScreen> createState() => _PlanosScreenState();
}

class _PlanosScreenState extends State<PlanosScreen> {
  BillingPeriod _period = BillingPeriod.mensal;

  // ==== PREÇOS (pode jogar isso depois para Firestore/API) ====

  double _priceFree(BillingPeriod p) => 0.0;

  double _priceStarter(BillingPeriod p) {
    switch (p) {
      case BillingPeriod.mensal:
        return 31.50;
      case BillingPeriod.semestral:
        return 169.99;
      case BillingPeriod.anual:
        return 305.99;
    }
  }

  double _pricePremium(BillingPeriod p) {
    switch (p) {
      case BillingPeriod.mensal:
        return 36.99;
      case BillingPeriod.semestral:
        return 199.99;
      case BillingPeriod.anual:
        return 359.99;
    }
  }

  String _periodSuffix(BillingPeriod p) {
    switch (p) {
      case BillingPeriod.mensal:
        return '/mês';
      case BillingPeriod.semestral:
        return '/semestre';
      case BillingPeriod.anual:
        return '/ano';
    }
  }

  String _formatCurrency(double value) {
    // bem simples, suficiente para exibir
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Escolha seu plano')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Controle total do seu negócio em um só lugar. '
              'Comece grátis e desbloqueie mais recursos com os planos Starter e Premium.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),

          // ====== Seletor de período (Mensal / Semestral / Anual) ======
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ToggleButtons(
              isSelected: BillingPeriod.values
                  .map((p) => p == _period)
                  .toList(growable: false),
              onPressed: (index) {
                setState(() {
                  _period = BillingPeriod.values[index];
                });
              },
              borderRadius: BorderRadius.circular(24),
              children:
                  BillingPeriod.values.map((p) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(_periodLabel[p]!),
                    );
                  }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // ====== Lista de planos ======
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _buildPlanCard(
                  name: 'FREE',
                  highlight: 'Ideal para começar',
                  price: _priceFree(_period),
                  periodSuffix: _periodSuffix(_period),
                  color: Colors.grey.shade200,
                  isCurrentPlan: true, // ajuste isso em tempo de execução
                  bullets: const [
                    '1 usuário',
                    '10 clientes/fornecedores',
                    '10 produtos',
                    'Sem fotos de produto',
                    '3 serviços',
                    'Até 10 pedidos',
                    'Sem módulos de financeiro',
                    'Sem dashboards',
                  ],
                  onAssinar: null, // plano free não precisa de ação
                ),
                const SizedBox(height: 12),
                _buildPlanCard(
                  name: 'Starter',
                  highlight: 'Perfeito para pequenos negócios',
                  price: _priceStarter(_period),
                  periodSuffix: _periodSuffix(_period),
                  color: Colors.green.shade50,
                  tag: 'Mais escolhido',
                  bullets: const [
                    'Até 3 usuários',
                    '30 clientes/fornecedores',
                    '50 produtos',
                    '1 foto por produto',
                    '10 serviços',
                    'Até 50 pedidos',
                    'Compromissos ilimitados',
                    'Estoque ilimitado',
                    'Contas a pagar/receber ilimitadas',
                    'Dashboards liberados (financeiro, pedidos, top produtos/serviços)',
                  ],
                  onAssinar: () {
                    // TODO: abrir fluxo de assinatura Starter
                    // ex: Navigator.pushNamed(context, '/assinarStarter');
                  },
                ),
                const SizedBox(height: 12),
                _buildPlanCard(
                  name: 'Premium',
                  highlight: 'Tudo ilimitado para crescer sem limites',
                  price: _pricePremium(_period),
                  periodSuffix: _periodSuffix(_period),
                  color: Colors.purple.shade50,
                  bullets: const [
                    'Usuários ilimitados',
                    'Clientes/fornecedores ilimitados',
                    'Produtos ilimitados',
                    'Até 3 fotos por produto',
                    'Serviços ilimitados',
                    'Pedidos ilimitados',
                    'Compromissos ilimitados',
                    'Estoque ilimitado',
                    'Contas a pagar/receber ilimitadas',
                    'Todos os dashboards liberados',
                  ],
                  onAssinar: () {
                    // TODO: abrir fluxo de assinatura Premium
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String name,
    required String highlight,
    required double price,
    required String periodSuffix,
    required Color color,
    required List<String> bullets,
    required VoidCallback? onAssinar,
    String? tag,
    bool isCurrentPlan = false,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toUpperCase(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(highlight, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (isCurrentPlan)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Seu plano atual',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (tag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tag,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Preço
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatCurrency(price),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Text(periodSuffix, style: theme.textTheme.bodyMedium),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Lista de benefícios
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(b, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (onAssinar != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAssinar,
                  child: const Text('Assinar plano'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
