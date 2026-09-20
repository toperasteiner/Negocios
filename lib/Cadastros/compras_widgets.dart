import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ComprasStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get headerGradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

class ComprasHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  const ComprasHeader({
    super.key,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: ComprasStyle.headerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        22,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Expanded(
                child: Center(
                  child: Text(
                    'Compras',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(icon: Icons.refresh_rounded, onTap: onRefresh),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Controle compras, entregas, fornecedores e atualização de estoque.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 16,
              height: 1.28,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

/*class PurchasePlanWarningCard extends StatelessWidget {
  final String currentPlan;
  final int monthlyPurchasesCount;
  final int monthlyPurchasesLimit;
  final String? purchasePlanError;
  final VoidCallback onUpgrade;

  const PurchasePlanWarningCard({
    super.key,
    required this.currentPlan,
    required this.monthlyPurchasesCount,
    required this.monthlyPurchasesLimit,
    required this.purchasePlanError,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final planoAtual = currentPlan.toUpperCase();
    final ilimitado = monthlyPurchasesLimit == -1;
    final restantes =
        ilimitado ? 999999 : (monthlyPurchasesLimit - monthlyPurchasesCount);
    final atingiuLimite =
        !ilimitado && monthlyPurchasesCount >= monthlyPurchasesLimit;
    final mostrarAviso = atingiuLimite || (!ilimitado && restantes <= 3);

    if (!mostrarAviso && purchasePlanError == null) {
      return const SizedBox.shrink();
    }

    final accent = atingiuLimite ? ComprasStyle.red : ComprasStyle.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.22)),
        boxShadow: ComprasStyle.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.workspace_premium_outlined, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Plano: $planoAtual',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: ComprasStyle.text,
                  ),
                ),
              ),
              if (!ilimitado)
                _SmallBadge(
                  text: '$monthlyPurchasesCount / $monthlyPurchasesLimit',
                  color: accent,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ilimitado
                ? 'Seu plano possui compras ilimitadas.'
                : atingiuLimite
                ? 'Você atingiu o limite mensal de compras do seu plano.'
                : 'Atenção: faltam apenas $restantes compra(s) para atingir o limite mensal do seu plano.',
            style: const TextStyle(
              color: ComprasStyle.muted,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onUpgrade,
              style: FilledButton.styleFrom(
                backgroundColor: ComprasStyle.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Fazer upgrade'),
            ),
          ),
          if (purchasePlanError != null) ...[
            const SizedBox(height: 10),
            Text(
              purchasePlanError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}*/

class ComprasFiltrosCard extends StatelessWidget {
  final List<String> statusOptions;
  final String filtroStatus;
  final String filtroFornecedorId;
  final Map<String, String> fornecedores;
  final String Function(String status) statusLabel;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onFornecedorChanged;
  final VoidCallback onLimpar;

  const ComprasFiltrosCard({
    super.key,
    required this.statusOptions,
    required this.filtroStatus,
    required this.filtroFornecedorId,
    required this.fornecedores,
    required this.statusLabel,
    required this.onStatusChanged,
    required this.onFornecedorChanged,
    required this.onLimpar,
  });

  @override
  Widget build(BuildContext context) {
    final filtrosAtivos =
        filtroStatus != 'todos' || filtroFornecedorId != 'todos';

    final statusField = _ModernDropdown<String>(
      value: filtroStatus,
      label: 'Status',
      icon: Icons.filter_alt_outlined,
      items:
          statusOptions
              .map(
                (s) => DropdownMenuItem<String>(
                  value: s,
                  child: Text(
                    s == 'todos' ? 'Todos (exceto canceladas)' : statusLabel(s),
                  ),
                ),
              )
              .toList(),
      onChanged: (value) {
        if (value != null) onStatusChanged(value);
      },
    );

    final fornecedorField = _ModernDropdown<String>(
      value: filtroFornecedorId,
      label: 'Fornecedor',
      icon: Icons.local_shipping_outlined,
      items: [
        const DropdownMenuItem<String>(value: 'todos', child: Text('Todos')),
        ...fornecedores.entries.map(
          (e) => DropdownMenuItem<String>(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) {
        if (value != null) onFornecedorChanged(value);
      },
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ComprasStyle.softShadow,
      ),
      child: Column(
        children: [
          if (filtrosAtivos)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onLimpar,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpar'),
              ),
            ),

          if (filtrosAtivos) const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              if (narrow) {
                return Column(
                  children: [
                    statusField,
                    const SizedBox(height: 10),
                    fornecedorField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: statusField),
                  const SizedBox(width: 10),
                  Expanded(child: fornecedorField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModernDropdown<T> extends StatelessWidget {
  final T value;
  final String label;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _ModernDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: ComprasStyle.primary),
        filled: true,
        fillColor: ComprasStyle.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ComprasStyle.primary, width: 1.4),
        ),
        isDense: true,
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class ComprasResumoSection extends StatelessWidget {
  final bool loadingPurchaseLimit;
  final int monthlyPurchasesCount;
  final int monthlyPurchasesLimit;
  final String totalText;

  const ComprasResumoSection({
    super.key,
    required this.loadingPurchaseLimit,
    required this.monthlyPurchasesCount,
    required this.monthlyPurchasesLimit,
    required this.totalText,
  });

  @override
  Widget build(BuildContext context) {
    final comprasValue =
        loadingPurchaseLimit
            ? '...'
            : monthlyPurchasesLimit == -1
            ? '$monthlyPurchasesCount/Ilimitado'
            : '$monthlyPurchasesCount/$monthlyPurchasesLimit';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: ResumoBox(
              icon: Icons.shopping_bag_outlined,
              label: 'Compras',
              value: comprasValue,
              color: ComprasStyle.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ResumoBox(
              icon: Icons.payments_outlined,
              label: 'Total',
              value: totalText,
              color: ComprasStyle.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class ResumoBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const ResumoBox({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = ComprasStyle.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ComprasStyle.softShadow,
      ),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ComprasStyle.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ComprasStyle.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CompraCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String Function(num value) fmtMoeda;
  final String Function(dynamic value) fmtData;
  final double Function(dynamic value) toDouble;
  final String Function(String status) normalizarStatusFiltro;
  final String Function(String status) statusLabel;
  final Color Function(String status) statusColor;
  final IconData Function(String status) statusIcon;
  final void Function(String compraId) onEditar;
  final void Function(String compraId) onCancelar;
  final void Function(String compraId, String statusAtual) onAlterarStatus;

  const CompraCard({
    super.key,
    required this.doc,
    required this.fmtMoeda,
    required this.fmtData,
    required this.toDouble,
    required this.normalizarStatusFiltro,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
    required this.onEditar,
    required this.onCancelar,
    required this.onAlterarStatus,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final numeroCompra = (data['numeroCompra'] ?? '').toString().trim();

    final fornecedorNome =
        (data['fornecedorNome'] ?? 'Fornecedor não informado').toString();

    final tituloCompra =
        numeroCompra.isEmpty ? 'Compra sem número' : 'Compra $numeroCompra';

    final valorTotal = toDouble(data['valorTotal'] ?? data['total']);

    final condicaoPagamento =
        (data['condicaoPagamento'] ?? 'Não informada').toString();

    final status = normalizarStatusFiltro(
      (data['status'] ?? 'aberta').toString(),
    );

    final color = statusColor(status);

    final compraCancelada = status == 'cancelada';
    final compraEntregue = status == 'entregue';

    final podeEditar = !compraCancelada && !compraEntregue;
    final podeAlterarStatus = !compraCancelada;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: ComprasStyle.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: podeEditar ? () => onEditar(doc.id) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconBadge(icon: statusIcon(status), color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tituloCompra,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: ComprasStyle.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              fornecedorNome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ComprasStyle.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(
                      label: statusLabel(status),
                      color: color,
                      enabled: podeAlterarStatus,
                      onTap: () => onAlterarStatus(doc.id, status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ComprasStyle.bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      InfoPill(
                        icon: Icons.payments_outlined,
                        label: 'Total',
                        value: fmtMoeda(valorTotal),
                      ),
                      InfoPill(
                        icon: Icons.event_outlined,
                        label: 'Previsão',
                        value: fmtData(data['dataEntrega']),
                      ),
                      InfoPill(
                        icon: Icons.credit_card_outlined,
                        label: 'Pagamento',
                        value: condicaoPagamento,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: podeEditar ? () => onEditar(doc.id) : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Alterar'),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: podeEditar ? () => onCancelar(doc.id) : null,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusOptionTile extends StatelessWidget {
  final String status;
  final String statusAtual;
  final String label;
  final IconData icon;
  final Color color;

  const StatusOptionTile({
    super.key,
    required this.status,
    required this.statusAtual,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final selecionado = statusAtual.toLowerCase() == status.toLowerCase();

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: _IconBadge(icon: icon, color: color),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: selecionado ? const Icon(Icons.check) : null,
      onTap: () => Navigator.pop(context, status),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 3),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Colors.white,
            ),
          ],
        ],
      ),
    );

    if (!enabled) return chip;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: chip,
    );
  }
}

class InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ComprasStyle.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: ComprasStyle.text,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: ComprasStyle.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ComprasEmptyState extends StatelessWidget {
  final bool possuiCompras;

  const ComprasEmptyState({super.key, required this.possuiCompras});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: ComprasStyle.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _IconBadge(
                icon: Icons.shopping_bag_outlined,
                color: ComprasStyle.primary,
                size: 58,
                iconSize: 30,
              ),
              const SizedBox(height: 14),
              Text(
                possuiCompras
                    ? 'Nenhuma compra encontrada'
                    : 'Nenhuma compra cadastrada',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ComprasStyle.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                possuiCompras
                    ? 'Altere os filtros selecionados para visualizar outros registros.'
                    : 'Clique em "Nova compra" para começar a controlar suas compras.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ComprasStyle.muted,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _SmallBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const _IconBadge({
    required this.icon,
    required this.color,
    this.size = 46,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
