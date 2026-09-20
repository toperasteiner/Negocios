/*import 'dart:convert';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmailMarketingScreen extends StatefulWidget {
  const EmailMarketingScreen({super.key});

  @override
  State<EmailMarketingScreen> createState() => _EmailMarketingScreenState();
}

enum FiltroPlano { todosNaoPremium, free, starter, semPlano }

class _EmailMarketingScreenState extends State<EmailMarketingScreen> {
  FiltroPlano filtro = FiltroPlano.todosNaoPremium;

  static const Color purple = Color(0xFF4A18B8);
  static const Color orange = Color(0xFFFF6A21);
  static const Color green = Color(0xFF08A64B);
  static const Color blue = Color(0xFF2F80ED);
  static const Color background = Color(0xFFFBFAFF);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamUsers() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('active', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(290)
        .snapshots();
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  bool _isPremium(Map<String, dynamic> data) {
    final planId = (data['planId'] ?? '').toString().toLowerCase().trim();
    final subscriptionActive = data['subscriptionActive'] == true;
    final planStatus =
        (data['planStatus'] ?? '').toString().toLowerCase().trim();

    return planId == 'premium' &&
        (subscriptionActive == true || planStatus == 'active');
  }

  bool _passaFiltro(Map<String, dynamic> data) {
    if (_isPremium(data)) return false;

    final planId = (data['planId'] ?? '').toString().toLowerCase().trim();

    switch (filtro) {
      case FiltroPlano.todosNaoPremium:
        return true;

      case FiltroPlano.free:
        return planId == 'free';

      case FiltroPlano.starter:
        return planId == 'starter';

      case FiltroPlano.semPlano:
        return planId.isEmpty || planId == 'null';
    }
  }

  List<Map<String, dynamic>> _filtrarUsuarios(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final emailsUsados = <String>{};

    final usuarios =
        docs
            .where((doc) {
              final data = doc.data();

              final email =
                  (data['email'] ?? '').toString().toLowerCase().trim();

              if (email.isEmpty) return false;
              if (!email.contains('@')) return false;
              if (!_passaFiltro(data)) return false;
              if (emailsUsados.contains(email)) return false;

              emailsUsados.add(email);
              return true;
            })
            .map((doc) {
              final data = doc.data();

              return {
                'displayName': (data['displayName'] ?? 'Sem nome').toString(),
                'email': (data['email'] ?? '').toString().toLowerCase().trim(),
                'planId': (data['planId'] ?? 'sem_plano').toString(),
                'updatedAt': _toDate(data['updatedAt']),
              };
            })
            .toList();

    return usuarios;
  }

  Future<void> _copiarEmails(List<Map<String, dynamic>> usuarios) async {
    final emails = usuarios.map((u) => u['email'].toString()).join(',');

    await Clipboard.setData(ClipboardData(text: emails));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${usuarios.length} emails copiados para a área de transferência.',
        ),
      ),
    );
  }

  void _baixarCsv(List<Map<String, dynamic>> usuarios) {
    final buffer = StringBuffer();

    buffer.writeln('nome,email,plano,ultimo_acesso');

    for (final usuario in usuarios) {
      final nome = _csv(usuario['displayName'].toString());
      final email = _csv(usuario['email'].toString());
      final plano = _csv(usuario['planId'].toString());
      final ultimoAcesso = _csv(_formatDate(usuario['updatedAt'] as DateTime?));

      buffer.writeln('$nome,$email,$plano,$ultimoAcesso');
    }

    final bytes = utf8.encode(buffer.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor =
        html.AnchorElement(href: url)
          ..setAttribute('download', 'emails_nao_premium_brevo.csv')
          ..click();

    html.Url.revokeObjectUrl(url);
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text(
          'Emails - Não Premium',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: purple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _streamUsers(),
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

          final totalAtivos = docs.length;

          final totalPremium =
              docs.where((doc) => _isPremium(doc.data())).length;

          final usuarios = _filtrarUsuarios(docs);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ResumoCard(
                totalAtivos: totalAtivos,
                totalPremium: totalPremium,
                totalNaoPremium: totalAtivos - totalPremium,
                emailsValidos: usuarios.length,
              ),

              const SizedBox(height: 14),

              _AcoesCard(
                totalEmails: usuarios.length,
                onCopiar:
                    usuarios.isEmpty ? null : () => _copiarEmails(usuarios),
                onExportar:
                    usuarios.isEmpty ? null : () => _baixarCsv(usuarios),
              ),

              const SizedBox(height: 14),

              _FiltroCard(
                filtroAtual: filtro,
                onChanged: (value) {
                  setState(() {
                    filtro = value;
                  });
                },
              ),

              const SizedBox(height: 16),

              if (usuarios.isEmpty)
                const _EmptyCard()
              else
                ...usuarios.map((usuario) {
                  return _EmailUsuarioCard(
                    nome: usuario['displayName'].toString(),
                    email: usuario['email'].toString(),
                    plano: usuario['planId'].toString(),
                    ultimoAcesso: _formatDate(
                      usuario['updatedAt'] as DateTime?,
                    ),
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
  final int totalAtivos;
  final int totalPremium;
  final int totalNaoPremium;
  final int emailsValidos;

  const _ResumoCard({
    required this.totalAtivos,
    required this.totalPremium,
    required this.totalNaoPremium,
    required this.emailsValidos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_EmailMarketingScreenState.purple, Color(0xFF2F148C)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Base para campanha Brevo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _ResumoLinha(label: 'Usuários ativos', value: totalAtivos),
          _ResumoLinha(label: 'Premium', value: totalPremium),
          _ResumoLinha(label: 'Não premium', value: totalNaoPremium),
          _ResumoLinha(label: 'Emails válidos', value: emailsValidos),
        ],
      ),
    );
  }
}

class _ResumoLinha extends StatelessWidget {
  final String label;
  final int value;

  const _ResumoLinha({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcoesCard extends StatelessWidget {
  final int totalEmails;
  final VoidCallback? onCopiar;
  final VoidCallback? onExportar;

  const _AcoesCard({
    required this.totalEmails,
    required this.onCopiar,
    required this.onExportar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onCopiar,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar emails'),
            style: FilledButton.styleFrom(
              backgroundColor: _EmailMarketingScreenState.orange,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: onExportar,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Baixar CSV'),
            style: FilledButton.styleFrom(
              backgroundColor: _EmailMarketingScreenState.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _FiltroCard extends StatelessWidget {
  final FiltroPlano filtroAtual;
  final ValueChanged<FiltroPlano> onChanged;

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
      child: DropdownButtonFormField<FiltroPlano>(
        value: filtroAtual,
        decoration: const InputDecoration(
          labelText: 'Filtro',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.filter_alt_outlined),
        ),
        items: const [
          DropdownMenuItem(
            value: FiltroPlano.todosNaoPremium,
            child: Text('Todos não premium'),
          ),
          DropdownMenuItem(value: FiltroPlano.free, child: Text('Apenas Free')),
          DropdownMenuItem(
            value: FiltroPlano.starter,
            child: Text('Apenas Starter'),
          ),
          DropdownMenuItem(
            value: FiltroPlano.semPlano,
            child: Text('Sem plano definido'),
          ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _EmailUsuarioCard extends StatelessWidget {
  final String nome;
  final String email;
  final String plano;
  final String ultimoAcesso;

  const _EmailUsuarioCard({
    required this.nome,
    required this.email,
    required this.plano,
    required this.ultimoAcesso,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0x144A18B8),
            child: Icon(
              Icons.email_outlined,
              color: _EmailMarketingScreenState.purple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _EmailMarketingScreenState.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _EmailMarketingScreenState.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Plano: $plano  •  Último acesso: $ultimoAcesso',
                  style: const TextStyle(
                    color: _EmailMarketingScreenState.textMuted,
                    fontSize: 11,
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
            color: _EmailMarketingScreenState.textMuted,
          ),
          SizedBox(height: 10),
          Text(
            'Nenhum email encontrado para este filtro.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _EmailMarketingScreenState.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}*/
