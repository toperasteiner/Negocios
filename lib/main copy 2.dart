// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart'; // gerado pelo `flutterfire configure`

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // só depois da linha acima você chama Auth/Firestore
  await FirebaseAuth.instance.signInAnonymously(); // se for usar anônimo
  runApp(const AppTesteInsercao()); // ou MyApp
}

class AppTesteInsercao extends StatelessWidget {
  const AppTesteInsercao({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teste Firestore',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const TelaInsercaoSimples(),
    );
  }
}

class TelaInsercaoSimples extends StatefulWidget {
  const TelaInsercaoSimples({super.key});
  @override
  State<TelaInsercaoSimples> createState() => _TelaInsercaoSimplesState();
}

class _TelaInsercaoSimplesState extends State<TelaInsercaoSimples> {
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _qtdCtrl = TextEditingController(text: '1');

  bool _salvando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _qtdCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance.collection('pedidos').add({
        'titulo': _tituloCtrl.text.trim(),
        'quantidade': int.parse(_qtdCtrl.text),
        'uid': uid,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documento inserido com sucesso ✅')),
        );
      }
      _formKey.currentState!.reset();
      _qtdCtrl.text = '1';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Teste de Inserção')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (user != null)
                    Text(
                      'Logado como: ${user.uid.substring(0, 6)}… (anônimo)',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tituloCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator:
                        (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Informe um título'
                                : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Informe a quantidade';
                      final n = int.tryParse(v);
                      if (n == null || n <= 0) return 'Quantidade inválida';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon:
                          _salvando
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.save),
                      label: Text(
                        _salvando ? 'Salvando...' : 'Salvar no Firestore',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Lista os últimos inseridos só pra visualizar
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Últimos itens:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: StreamBuilder<QuerySnapshot>(
                      stream:
                          FirebaseFirestore.instance
                              .collection('pedidos')
                              .orderBy('criadoEm', descending: true)
                              .limit(10)
                              .snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Center(child: Text('Erro: ${snap.error}'));
                        }
                        final docs = snap.data?.docs ?? [];
                        if (docs.isEmpty)
                          return const Center(
                            child: Text('Nenhum item ainda.'),
                          );
                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final d = docs[i].data() as Map<String, dynamic>;
                            final titulo = d['titulo'] ?? '(sem título)';
                            final qtd = d['quantidade'] ?? 0;
                            return ListTile(
                              leading: const Icon(Icons.shopping_bag_outlined),
                              title: Text('$titulo'),
                              subtitle: Text('Qtd: $qtd'),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
