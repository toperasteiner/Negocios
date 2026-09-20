// lib/Home/home_widgets.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

/* ========================== CORES DO NOVO LAYOUT ========================== */

class HomeColors {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color yellow = Color(0xFFFFB51F);
  static const Color green = Color(0xFF08A64B);
  static const Color redOrange = Color(0xFFE85A12);
  static const Color background = Color(0xFFF7F7FA);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
}

/* ========================== FORMATADORES ========================== */

String homeMoney(double v) {
  final s = v.toStringAsFixed(2);
  final p = s.split('.');

  final inteiro = p[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );

  return 'R\$ $inteiro,${p[1]}';
}

/* ========================== HEADER ========================== */

class HomeHeader extends StatelessWidget {
  final String userName;
  final int notificationCount;
  final VoidCallback onOpenMenu;
  final VoidCallback? onNotifications;

  const HomeHeader({
    super.key,
    required this.userName,
    required this.notificationCount,
    required this.onOpenMenu,
    this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 305,
      padding: EdgeInsets.fromLTRB(
        28,
        MediaQuery.of(context).padding.top + 22,
        28,
        28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [HomeColors.deepPurple, HomeColors.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -40,
            child: _GlowCircle(size: 190, opacity: 0.08),
          ),
          Positioned(
            left: -90,
            bottom: -80,
            child: _GlowCircle(size: 210, opacity: 0.07),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.menu_rounded,
                    onTap: onOpenMenu,
                  ),
                  const Spacer(),
                  _NotificationButton(
                    count: notificationCount,
                    onTap: onNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Text(
                'Olá, $userName! 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Aqui está o resumo do seu negócio.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final double opacity;

  const _GlowCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.white, size: 34),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _NotificationButton({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _HeaderIconButton(icon: Icons.notifications_none_rounded, onTap: onTap),
        if (count > 0)
          Positioned(
            right: 3,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: HomeColors.orange,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ========================== KPIs COM FIREBASE ========================== */

class PedidosHojeStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const PedidosHojeStat({
    super.key,
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  Future<Map<String, dynamic>> _buscarComparativoPedidos() async {
    final fs = FirebaseFirestore.instance;

    final agora = DateTime.now();

    final inicioHoje = DateTime(agora.year, agora.month, agora.day);
    final inicioAmanha = inicioHoje.add(const Duration(days: 1));
    final inicioOntem = inicioHoje.subtract(const Duration(days: 1));

    final hojeSnap =
        await fs
            .collection('pedidos')
            .where(scopeField, isEqualTo: scopeUserId)
            .where(
              'data',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicioHoje),
            )
            .where('data', isLessThan: Timestamp.fromDate(inicioAmanha))
            .get();

    final ontemSnap =
        await fs
            .collection('pedidos')
            .where(scopeField, isEqualTo: scopeUserId)
            .where(
              'data',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicioOntem),
            )
            .where('data', isLessThan: Timestamp.fromDate(inicioHoje))
            .get();

    final hoje = hojeSnap.docs.length;
    final ontem = ontemSnap.docs.length;

    String subtitulo;

    if (ontem == 0 && hoje == 0) {
      subtitulo = 'Sem pedidos hoje';
    } else if (ontem == 0 && hoje > 0) {
      subtitulo = 'Primeiros pedidos hoje';
    } else {
      final variacao = ((hoje - ontem) / ontem) * 100;

      if (variacao > 0) {
        subtitulo = '+${variacao.toStringAsFixed(0)}% vs ontem';
      } else if (variacao < 0) {
        subtitulo = '${variacao.toStringAsFixed(0)}% vs ontem';
      } else {
        subtitulo = 'Mesmo volume de ontem';
      }
    }

    return {'hoje': hoje, 'ontem': ontem, 'subtitulo': subtitulo};
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const HomeKpiCard(
        title: 'Pedidos hoje',
        value: '—',
        subtitle: 'Sem acesso',
        icon: Icons.lock_outline_rounded,
        iconColor: HomeColors.purple,
        disabled: true,
      );
    }

    if (scopeUserId.isEmpty) {
      return const HomeKpiCard(
        title: 'Pedidos hoje',
        value: '—',
        subtitle: 'Usuário não identificado',
        icon: Icons.info_outline_rounded,
        iconColor: HomeColors.purple,
        disabled: true,
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarComparativoPedidos(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const HomeKpiCard(
            title: 'Pedidos hoje',
            value: '...',
            subtitle: 'Carregando',
            icon: Icons.calendar_month_rounded,
            iconColor: HomeColors.purple,
          );
        }

        if (s.hasError) {
          String? indexUrl;

          const friendly =
              'Sua consulta requer um índice composto no Firestore.';

          final err = s.error;

          if (err is FirebaseException) {
            final msg = err.message ?? '';
            final m = RegExp(r'https?://[^\s)]+').firstMatch(msg);

            if (m != null) {
              indexUrl = m.group(0);
            }
          }

          return IndexHintCard(
            title: 'Pedidos hoje',
            message: friendly,
            indexUrl: indexUrl,
          );
        }

        final dados = s.data ?? {};
        final hoje = dados['hoje'] ?? 0;
        final subtitulo = dados['subtitulo'] ?? 'Sem comparação';

        final isPositive = subtitulo.toString().startsWith('+');

        return HomeKpiCard(
          title: 'Pedidos hoje',
          value: '$hoje',
          subtitle: subtitulo,
          icon: Icons.calendar_month_rounded,
          iconColor: HomeColors.purple,
          subtitleColor: isPositive ? HomeColors.green : HomeColors.textMuted,
          onTap: onTap,
        );
      },
    );
  }
}

class AReceberStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const AReceberStat({
    super.key,
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final q = fs
        .collection('contas_receber')
        .where(scopeField, isEqualTo: scopeUserId);

    return StreamBuilder<QuerySnapshot>(
      stream: enabled ? q.snapshots() : const Stream.empty(),
      builder: (context, s) {
        double soma = 0.0;
        int qtd = 0;

        if (enabled && s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data() as Map<String, dynamic>;

            final status = (m['status'] ?? '').toString().toLowerCase();

            if (status == 'pago' || status == 'cancelado') continue;

            final valor = (m['valor'] as num?)?.toDouble() ?? 0.0;
            final valorPago = (m['valorPago'] as num?)?.toDouble() ?? 0.0;
            final saldo = valor - valorPago;

            if (saldo > 0) {
              soma += saldo;
              qtd++;
            }
          }
        }

        return HomeKpiCard(
          title: 'A receber',
          value: enabled ? homeMoney(soma) : 'R\$ —',
          subtitle: enabled ? '$qtd pedidos' : 'Sem acesso',
          icon: enabled ? Icons.payments_outlined : Icons.lock_outline_rounded,
          iconColor: HomeColors.green,
          subtitleColor: HomeColors.green,
          disabled: !enabled,
          onTap: onTap,
        );
      },
    );
  }
}

class ItensEmFaltaStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const ItensEmFaltaStat({
    super.key,
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final q = fs
        .collection('produtos')
        .where(scopeField, isEqualTo: scopeUserId)
        .where('controlaEstoque', isEqualTo: true);

    return StreamBuilder<QuerySnapshot>(
      stream: enabled ? q.snapshots() : const Stream.empty(),
      builder: (context, s) {
        int faltando = 0;

        if (enabled && s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data() as Map<String, dynamic>;

            final estoque = (m['estoque'] as num?)?.toDouble() ?? 0.0;

            final min =
                (m['estoqueMin'] as num?)?.toDouble() ??
                (m['estoqueAlerta'] as num?)?.toDouble() ??
                0.0;

            if (min > 0 ? estoque < min : estoque <= 0) {
              faltando++;
            }
          }
        }

        return HomeKpiCard(
          title: 'Itens em falta',
          value: enabled ? '$faltando' : '—',
          subtitle: enabled ? 'Ver estoque' : 'Sem acesso',
          icon:
              enabled ? Icons.inventory_2_outlined : Icons.lock_outline_rounded,
          iconColor: HomeColors.orange,
          subtitleColor: HomeColors.yellow,
          disabled: !enabled,
          onTap: onTap,
        );
      },
    );
  }
}

class ContasAPagarStat extends StatelessWidget {
  final String scopeUserId;
  final String scopeField;
  final bool enabled;
  final VoidCallback? onTap;

  const ContasAPagarStat({
    super.key,
    required this.scopeUserId,
    required this.scopeField,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    final q = fs
        .collection('contas_pagar')
        .where(scopeField, isEqualTo: scopeUserId);

    if (!enabled) {
      return const HomeKpiCard(
        title: 'A pagar',
        value: 'R\$ —',
        subtitle: 'Sem acesso',
        icon: Icons.lock_outline_rounded,
        iconColor: HomeColors.yellow,
        disabled: true,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, s) {
        double soma = 0.0;
        int qtd = 0;

        if (s.hasData) {
          for (final d in s.data!.docs) {
            final m = d.data();

            final status = (m['status'] ?? '').toString().toLowerCase();

            if (status == 'pago' || status == 'cancelado') continue;

            final valor = (m['valor'] as num?)?.toDouble() ?? 0.0;
            final valorPago = (m['valorPago'] as num?)?.toDouble() ?? 0.0;
            final saldo = valor - valorPago;

            if (saldo > 0) {
              soma += saldo;
              qtd++;
            }
          }
        }

        return HomeKpiCard(
          title: 'A pagar',
          value: homeMoney(soma),
          subtitle: '$qtd contas',
          icon: Icons.receipt_long_outlined,
          iconColor: HomeColors.yellow,
          valueColor: HomeColors.redOrange,
          subtitleColor: HomeColors.yellow,
          onTap: onTap,
        );
      },
    );
  }
}

/* ========================== KPI CARD VISUAL ========================== */

class HomeKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color? valueColor;
  final Color? subtitleColor;
  final VoidCallback? onTap;
  final bool disabled;

  const HomeKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.valueColor,
    this.subtitleColor,
    this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = disabled ? Colors.grey.shade500 : iconColor;
    final effectiveValueColor =
        disabled ? Colors.grey.shade500 : valueColor ?? iconColor;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: effectiveIconColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: effectiveIconColor.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HomeColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: TextStyle(
                            color: effectiveValueColor,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            height: 1.05,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              disabled
                                  ? Colors.grey.shade500
                                  : subtitleColor ?? HomeColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ========================== SPOTLIGHT PEDIDOS ========================== */

/* ========================== SPOTLIGHT PEDIDOS ========================== */

class OrdersSpotlight extends StatelessWidget {
  final void Function(BuildContext) onNewOrder;
  final void Function(BuildContext) onSeeOrders;
  final bool loadingPlan;
  final bool canRegisterOrders;
  final bool isOrdersLimitReached;
  final int monthlyOrdersCount;
  final int monthlyOrdersLimit;

  const OrdersSpotlight({
    super.key,
    required this.onNewOrder,
    required this.onSeeOrders,
    required this.loadingPlan,
    required this.canRegisterOrders,
    required this.isOrdersLimitReached,
    required this.monthlyOrdersCount,
    required this.monthlyOrdersLimit,
  });

  double get _progress {
    if (monthlyOrdersLimit <= 0) return 0.0;
    return (monthlyOrdersCount / monthlyOrdersLimit).clamp(0.0, 1.0);
  }

  String get _usageText {
    if (loadingPlan) return 'Verificando limite do plano...';
    if (!canRegisterOrders) return 'Sem acesso a Pedidos.';
    if (monthlyOrdersLimit == -1) {
      return '$monthlyOrdersCount pedidos incluídos este mês.';
    }

    return '$monthlyOrdersCount/$monthlyOrdersLimit pedidos incluídos este mês.';
  }

  bool get _locked =>
      loadingPlan ? false : (!canRegisterOrders || isOrdersLimitReached);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 185,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [
            HomeColors.deepPurple,
            HomeColors.purple,
            Color(0xFFB44250),
            HomeColors.orange,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: HomeColors.purple.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 0),
            child: SizedBox(
              width: 82,
              height: 82,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(78, 78),
                    painter: _CircularProgressPainter(progress: _progress),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.11),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _locked
                          ? Icons.lock_outline_rounded
                          : Icons.shopping_bag_outlined,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gerencie seus pedidos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  _usageText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.94),
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 7),

                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: _progress,
                    backgroundColor: HomeColors.deepPurple.withOpacity(0.90),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      HomeColors.orange,
                    ),
                  ),
                ),

                const Spacer(),

                SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _locked ? null : () => onNewOrder(context),
                    icon: Icon(
                      _locked
                          ? Icons.lock_outline_rounded
                          : Icons.add_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _locked ? 'Limite atingido' : 'Novo pedido',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withOpacity(0.70),
                      foregroundColor:
                          _locked ? HomeColors.textMuted : HomeColors.purple,
                      disabledForegroundColor: HomeColors.textMuted,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 7),

                SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onSeeOrders(context),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text(
                      'Ver pedidos',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.95),
                        width: 1.4,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
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
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;

  _CircularProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 7.0;
    final rect = Offset.zero & size;
    final startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    final bg =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.16);

    final fg =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = HomeColors.yellow;

    canvas.drawArc(rect.deflate(strokeWidth / 2), 0, 2 * math.pi, false, bg);

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      startAngle,
      sweepAngle,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/* ========================== AÇÕES RÁPIDAS ========================== */

class QuickActionData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const QuickActionData({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });
}

class QuickActionsSection extends StatelessWidget {
  final List<QuickActionData> actions;

  const QuickActionsSection({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SectionHeader(title: 'Ações rápidas'),

        const SizedBox(height: 14),

        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final action = actions[index];

              return SizedBox(
                width: 120,
                child: QuickActionCard(
                  icon: action.icon,
                  label: action.label,
                  color: action.color,
                  onTap: action.onTap,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 132,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const Spacer(),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: HomeColors.textDark,
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ========================== RESUMO DO MÊS ========================== */

class MonthlySummaryCard extends StatelessWidget {
  final double faturamento;
  final double variacaoPercentual;
  final VoidCallback? onTap;
  final VoidCallback? onPeriodoTap;

  const MonthlySummaryCard({
    super.key,
    required this.faturamento,
    required this.variacaoPercentual,
    this.onTap,
    this.onPeriodoTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = variacaoPercentual >= 0;

    return Column(
      children: [
        SectionHeader(
          title: 'Resumo do mês',
          //actionText: 'Este mês',
          //actionIcon: Icons.keyboard_arrow_down_rounded,
          onAction: onPeriodoTap,
          pillAction: true,
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: 116,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.045),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: HomeColors.purple.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      color: HomeColors.purple,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Faturamento',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: HomeColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            homeMoney(faturamento),
                            maxLines: 1,
                            style: const TextStyle(
                              color: HomeColors.purple,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isPositive ? '+' : ''}${variacaoPercentual.toStringAsFixed(0)}% vs mês anterior',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                isPositive
                                    ? HomeColors.green
                                    : HomeColors.redOrange,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  const SizedBox(width: 92, height: 58, child: MiniLineChart()),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MiniLineChart extends StatelessWidget {
  const MiniLineChart({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MiniLineChartPainter());
  }
}

class _MiniLineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(0, size.height * 0.70),
      Offset(size.width * 0.10, size.height * 0.62),
      Offset(size.width * 0.20, size.height * 0.66),
      Offset(size.width * 0.30, size.height * 0.52),
      Offset(size.width * 0.40, size.height * 0.58),
      Offset(size.width * 0.52, size.height * 0.20),
      Offset(size.width * 0.63, size.height * 0.34),
      Offset(size.width * 0.72, size.height * 0.58),
      Offset(size.width * 0.82, size.height * 0.50),
      Offset(size.width * 0.92, size.height * 0.24),
      Offset(size.width, size.height * 0.30),
    ];

    final fillPath = Path()..moveTo(points.first.dx, size.height);

    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }

    fillPath
      ..lineTo(size.width, size.height)
      ..close();

    final fillPaint =
        Paint()
          ..shader = LinearGradient(
            colors: [
              HomeColors.purple.withOpacity(0.15),
              HomeColors.purple.withOpacity(0.01),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Offset.zero & size);

    canvas.drawPath(fillPath, fillPaint);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlX = (previous.dx + current.dx) / 2;

      linePath.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    final linePaint =
        Paint()
          ..color = HomeColors.purple
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* ========================== SECTION HEADER ========================== */

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool pillAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.actionIcon,
    this.onAction,
    this.pillAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final action = actionText;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: HomeColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (action != null)
          Material(
            color: pillAction ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    pillAction
                        ? const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        )
                        : EdgeInsets.zero,
                decoration:
                    pillAction
                        ? BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFEAE7F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.035),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        )
                        : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action,
                      style: const TextStyle(
                        color: HomeColors.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (actionIcon != null) ...[
                      const SizedBox(width: 6),
                      Icon(actionIcon, color: HomeColors.textMuted, size: 22),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ========================== BOTTOM NAV CUSTOMIZADO ========================== */

class HomeBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int activityBadgeCount;

  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.activityBadgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom > 0 ? bottom : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 22,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: HomeBottomNavItem(
              icon: Icons.home_rounded,
              label: 'Início',
              selected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
          ),
          Expanded(
            child: HomeBottomNavItem(
              icon: Icons.inventory_2_outlined,
              label: 'Cadastro',
              selected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
          ),
          Expanded(
            child: HomeBottomNavItem(
              icon: Icons.check_circle_outline_rounded,
              label: 'Atividade',
              selected: currentIndex == 2,
              badgeCount: activityBadgeCount,
              onTap: () => onTap(2),
            ),
          ),
          Expanded(
            child: HomeBottomNavItem(
              icon: Icons.insights_rounded,
              label: 'Dashboard',
              selected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ),
          Expanded(
            child: HomeBottomNavItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Financeiro',
              selected: currentIndex == 4,
              onTap: () => onTap(4),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeBottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const HomeBottomNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? HomeColors.purple : const Color(0xFF5D5965);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 54,
                  height: 42,
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? HomeColors.purple.withOpacity(0.12)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 29),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 2,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ========================== CARD DE ÍNDICE FIRESTORE ========================== */

class IndexHintCard extends StatelessWidget {
  final String title;
  final String message;
  final String? indexUrl;

  const IndexHintCard({
    super.key,
    required this.title,
    required this.message,
    this.indexUrl,
  });

  Future<void> _open(String url) async {
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return HomeKpiCard(
      title: title,
      value: '—',
      subtitle: 'Criar índice',
      icon: Icons.error_outline_rounded,
      iconColor: HomeColors.orange,
      onTap: () {
        if (indexUrl != null) {
          _open(indexUrl!);
          return;
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }
}

/* ========================== BENEFÍCIOS DO PLANO ========================== */

class PlanBenefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const PlanBenefit({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: HomeColors.purple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: HomeColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
