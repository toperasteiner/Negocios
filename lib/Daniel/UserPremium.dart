import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserPremium extends StatefulWidget {
  const UserPremium({super.key});

  @override
  State<UserPremium> createState() => _UserPremiumState();
}

enum FiltroVencimento { todos, vencidos, venceHoje, venceSemana }

class _UserPremiumState extends State<UserPremium> {
  FiltroVencimento filtro = FiltroVencimento.todos;

  static const Color purple = Color(0xFF4A18B8);
  static const Color orange = Color(0xFFFF6A21);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color background = Color(0xFFFBFAFF);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamPremiumUsers() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('planId', isEqualTo: 'premium')
        .orderBy('planEndAt', descending: false)
        .snapshots();
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  bool _passaFiltro(DateTime? planEndAt) {
    if (filtro == FiltroVencimento.todos) return true;
    if (planEndAt == null) return false;

    final agora = DateTime.now();
    final hojeInicio = _startOfDay(agora);
    final hojeFim = _endOfDay(agora);

    final semanaFim = hojeInicio.add(const Duration(days: 7));

    switch (filtro) {
      case FiltroVencimento.vencidos:
        return planEndAt.isBefore(hojeInicio);

      case FiltroVencimento.venceHoje:
        return planEndAt.isAfter(
              hojeInicio.subtract(const Duration(seconds: 1)),
            ) &&
            planEndAt.isBefore(hojeFim.add(const Duration(seconds: 1)));

      case FiltroVencimento.venceSemana:
        return planEndAt.isAfter(
              hojeInicio.subtract(const Duration(seconds: 1)),
            ) &&
            planEndAt.isBefore(semanaFim);

      case FiltroVencimento.todos:
        return true;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';

    String two(int v) => v.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _statusPlano(DateTime? planEndAt) {
    if (planEndAt == null) return 'Sem vencimento';

    final hoje = _startOfDay(DateTime.now());
    final vencimento = _startOfDay(planEndAt);

    if (vencimento.isBefore(hoje)) return 'Vencido';
    if (vencimento.isAtSameMomentAs(hoje)) return 'Vence hoje';
    if (vencimento.isBefore(hoje.add(const Duration(days: 7)))) {
      return 'Vence essa semana';
    }

    return 'Ativo';
  }

  Color _statusColor(DateTime? planEndAt) {
    final status = _statusPlano(planEndAt);

    if (status == 'Vencido') return Colors.redAccent;
    if (status == 'Vence hoje') return orange;
    if (status == 'Vence essa semana') return blue;

    return green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text(
          'Testes - Usuários Premium',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: purple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _streamPremiumUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Erro ao carregar usuários: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          final ativos =
              docs.where((doc) {
                final data = doc.data();
                return data['active'] == true;
              }).length;

          final filtrados =
              docs.where((doc) {
                final data = doc.data();
                final planEndAt = _toDate(data['planEndAt']);
                return _passaFiltro(planEndAt);
              }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ResumoCard(
                ativos: ativos,
                totalPremium: docs.length,
                totalFiltrado: filtrados.length,
              ),

              const SizedBox(height: 16),

              _FiltroCard(
                filtroAtual: filtro,
                onChanged: (value) {
                  setState(() {
                    filtro = value;
                  });
                },
              ),

              const SizedBox(height: 16),

              if (filtrados.isEmpty)
                const _EmptyCard()
              else
                ...filtrados.map((doc) {
                  final data = doc.data();

                  final displayName =
                      (data['displayName'] ?? 'Sem nome').toString();

                  final email = (data['email'] ?? '').toString();

                  final updatedAt = _toDate(data['updatedAt']);
                  final planEndAt = _toDate(data['planEndAt']);

                  final active = data['active'] == true;
                  final subscriptionActive = data['subscriptionActive'] == true;

                  return _UsuarioPremiumCard(
                    displayName: displayName,
                    email: email,
                    updatedAt: _formatDate(updatedAt),
                    planEndAt: _formatDate(planEndAt),
                    statusPlano: _statusPlano(planEndAt),
                    statusColor: _statusColor(planEndAt),
                    active: active,
                    subscriptionActive: subscriptionActive,
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _ResumoCard extends StatelessWidget {
  final int ativos;
  final int totalPremium;
  final int totalFiltrado;

  const _ResumoCard({
    required this.ativos,
    required this.totalPremium,
    required this.totalFiltrado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_UserPremiumState.purple, Color(0xFF2F148C)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _UserPremiumState.purple.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: Colors.white,
            size: 38,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usuários Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ativos: $ativos  •  Total: $totalPremium  •  Filtro: $totalFiltrado',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _FiltroCard extends StatelessWidget {
  final FiltroVencimento filtroAtual;
  final ValueChanged<FiltroVencimento> onChanged;

  const _FiltroCard({required this.filtroAtual, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: DropdownButtonFormField<FiltroVencimento>(
        value: filtroAtual,
        decoration: const InputDecoration(
          labelText: 'Filtro por vencimento do plano',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.filter_alt_outlined),
        ),
        items: const [
          DropdownMenuItem(value: FiltroVencimento.todos, child: Text('Todos')),
          DropdownMenuItem(
            value: FiltroVencimento.vencidos,
            child: Text('Já está vencido'),
          ),
          DropdownMenuItem(
            value: FiltroVencimento.venceHoje,
            child: Text('Vence hoje'),
          ),
          DropdownMenuItem(
            value: FiltroVencimento.venceSemana,
            child: Text('Vence essa semana'),
          ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _UsuarioPremiumCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String updatedAt;
  final String planEndAt;
  final String statusPlano;
  final Color statusColor;
  final bool active;
  final bool subscriptionActive;

  const _UsuarioPremiumCard({
    required this.displayName,
    required this.email,
    required this.updatedAt,
    required this.planEndAt,
    required this.statusPlano,
    required this.statusColor,
    required this.active,
    required this.subscriptionActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withOpacity(0.12),
                child: Icon(Icons.person_outline_rounded, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _UserPremiumState.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _UserPremiumState.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusPlano,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _InfoLinha(
            icon: Icons.access_time_outlined,
            label: 'Último acesso',
            value: updatedAt,
          ),
          const SizedBox(height: 8),
          _InfoLinha(
            icon: Icons.event_available_outlined,
            label: 'Vencimento do plano',
            value: planEndAt,
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              _MiniBadge(
                text: active ? 'Usuário ativo' : 'Usuário inativo',
                color: active ? Colors.green : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              _MiniBadge(
                text:
                    subscriptionActive
                        ? 'Assinatura ativa'
                        : 'Assinatura inativa',
                color: subscriptionActive ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLinha extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoLinha({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _UserPremiumState.purple),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            color: _UserPremiumState.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _UserPremiumState.textDark,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 42,
            color: _UserPremiumState.textMuted,
          ),
          SizedBox(height: 10),
          Text(
            'Nenhum usuário encontrado para este filtro.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _UserPremiumState.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
