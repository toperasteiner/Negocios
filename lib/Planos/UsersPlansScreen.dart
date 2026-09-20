import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersPlansScreen extends StatelessWidget {
  const UsersPlansScreen({super.key});

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '-';

    final d = ts.toDate();

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuários e Planos')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: fs.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }

          final docs = [...(snapshot.data?.docs ?? [])];

          docs.sort((a, b) {
            final planA =
                (a.data()['subscriptions'] ?? a.data()['planId'] ?? 'free')
                    .toString()
                    .toLowerCase();

            final planB =
                (b.data()['subscriptions'] ?? b.data()['planId'] ?? 'free')
                    .toString()
                    .toLowerCase();

            int order(String plan) {
              switch (plan) {
                case 'premium':
                  return 0;
                case 'starter':
                  return 1;
                default:
                  return 2; // free ou outros
              }
            }

            return order(planA).compareTo(order(planB));
          });

          if (docs.isEmpty) {
            return const Center(child: Text('Nenhum usuário encontrado'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data();

              final email = (data['email'] ?? '').toString();

              final planId =
                  (data['subscriptions'] ?? data['planId'] ?? 'free')
                      .toString();

              // 🔹 NOVOS CAMPOS
              final createdAt = data['createdAt'] as Timestamp?;
              final planStart =
                  data['planStartedAt'] as Timestamp? ??
                  data['subscriptionStart'] as Timestamp? ??
                  data['planStartDate'] as Timestamp?;

              return ListTile(
                leading: CircleAvatar(
                  child: Text(email.isNotEmpty ? email[0].toUpperCase() : '?'),
                ),
                title: Text(
                  email.isEmpty ? 'Sem email' : email,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plano: $planId'),
                    const SizedBox(height: 4),
                    Text('Criado em: ${_formatDate(createdAt)}'),
                    Text('Início do plano: ${_formatDate(planStart)}'),
                  ],
                ),
                trailing: _planChip(planId),
              );
            },
          );
        },
      ),
    );
  }

  Widget _planChip(String plan) {
    Color color;

    switch (plan.toLowerCase()) {
      case 'premium':
        color = Colors.green;
        break;
      case 'starter':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }

    return Chip(
      label: Text(
        plan.toUpperCase(),
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: color,
    );
  }
}
