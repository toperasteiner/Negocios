// lib/Admin/ImagensPendentesScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class ImagensPendentesScreen extends StatefulWidget {
  const ImagensPendentesScreen({super.key});

  @override
  State<ImagensPendentesScreen> createState() => _ImagensPendentesScreenState();
}

class _ImagensPendentesScreenState extends State<ImagensPendentesScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

  bool _processando = false;

  bool get _isAdminImagem {
    final email = _auth.currentUser?.email?.trim().toLowerCase();
    return email == 'dani@dani.com';
  }

  Future<String> _downloadUrl(String valor) async {
    final path = valor.trim();

    if (path.isEmpty) {
      throw Exception('Caminho da imagem não informado.');
    }

    // A imagem já está salva como URL completa.
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // A imagem está salva como URL gs://.
    if (path.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(path).getDownloadURL();
    }

    // Caminho relativo do Firebase Storage.
    return FirebaseStorage.instance.ref().child(path).getDownloadURL();
  }

  Future<void> _aprovar({
    required String produtoId,
    required String pathOriginal,
  }) async {
    setState(() => _processando = true);

    try {
      final callable = _functions.httpsCallable('aprovarImagemProdutoManual');

      await callable.call({
        'produtoId': produtoId,
        'pathOriginal': pathOriginal,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem aprovada com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao aprovar imagem: $e')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _recusar({
    required String produtoId,
    required String pathOriginal,
  }) async {
    final motivoCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Recusar imagem'),
          content: TextField(
            controller: motivoCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo da recusa',
              hintText: 'Ex.: imagem inadequada, baixa qualidade...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.block_outlined),
              label: const Text('Recusar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    setState(() => _processando = true);

    try {
      final callable = _functions.httpsCallable('recusarImagemProdutoManual');

      await callable.call({
        'produtoId': produtoId,
        'pathOriginal': pathOriginal,
        'motivo': motivoCtrl.text.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Imagem recusada.')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao recusar imagem: $e')));
    } finally {
      motivoCtrl.dispose();
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminImagem) {
      return Scaffold(
        appBar: AppBar(title: const Text('Imagens Pendentes')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Você não tem permissão para acessar esta tela.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Imagens Pendentes'), centerTitle: true),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                _fs
                    .collection('produtos')
                    .where(
                      'imagemStatus',
                      whereIn: ['pendente', 'recusada', 'revisao_manual'],
                    )
                    .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Erro ao carregar imagens pendentes:\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final produtos =
                  (snap.data?.docs ?? []).where((doc) {
                    final data = doc.data();

                    final status = (data['imagemStatus'] ?? '').toString();

                    final fotosPendentes = data['fotosPendentes'];
                    final fotosRecusadas = data['fotosRecusadas'];

                    final temPendentes =
                        fotosPendentes is List && fotosPendentes.isNotEmpty;

                    final temRecusadas =
                        fotosRecusadas is List && fotosRecusadas.isNotEmpty;

                    return (status == 'pendente' ||
                                status == 'revisao_manual') &&
                            temPendentes ||
                        status == 'recusada' && temRecusadas;
                  }).toList();

              if (produtos.isEmpty) {
                return const Center(
                  child: Text('Nenhuma imagem pendente encontrada.'),
                );
              }

              final itens = <_ImagemPendenteItem>[];

              for (final doc in produtos) {
                final data = doc.data();
                final status = (data['imagemStatus'] ?? '').toString();

                final fotosPendentes =
                    (data['fotosPendentes'] as List?)
                        ?.map((e) => e.toString())
                        .where((e) => e.trim().isNotEmpty)
                        .toList() ??
                    [];

                final fotosRecusadas =
                    (data['fotosRecusadas'] as List?)
                        ?.map((e) => e.toString())
                        .where((e) => e.trim().isNotEmpty)
                        .toList() ??
                    [];

                final fotosParaExibir =
                    status == 'recusada' ? fotosRecusadas : fotosPendentes;

                for (final path in fotosParaExibir) {
                  itens.add(
                    _ImagemPendenteItem(
                      produtoId: doc.id,
                      produtoNome:
                          (data['nome'] ?? 'Produto sem nome').toString(),
                      path: path,
                      status: (data['imagemStatus'] ?? '').toString(),
                      motivo: (data['imagemMotivoRecusa'] ?? '').toString(),
                    ),
                  );
                }
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = itens[index];

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 96,
                              height: 96,
                              child: FutureBuilder<String>(
                                future: _downloadUrl(item.path),
                                builder: (context, urlSnap) {
                                  if (urlSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    );
                                  }

                                  if (urlSnap.hasError) {
                                    debugPrint(
                                      '[ImagensPendentes] Erro ao obter imagem.\n'
                                      'Produto: ${item.produtoId}\n'
                                      'Caminho: ${item.path}\n'
                                      'Erro: ${urlSnap.error}',
                                    );

                                    return _ImagemErro(
                                      mensagem: urlSnap.error.toString(),
                                    );
                                  }

                                  final url = urlSnap.data?.trim() ?? '';

                                  if (url.isEmpty) {
                                    return const _ImagemErro(
                                      mensagem: 'URL da imagem vazia.',
                                    );
                                  }

                                  return Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (
                                      context,
                                      child,
                                      loadingProgress,
                                    ) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }

                                      return const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      debugPrint(
                                        '[ImagensPendentes] Erro no Image.network.\n'
                                        'Produto: ${item.produtoId}\n'
                                        'URL: $url\n'
                                        'Erro: $error',
                                      );

                                      return _ImagemErro(
                                        mensagem: error.toString(),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.produtoNome,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.path,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Chip(
                                      label: Text(
                                        item.status.isEmpty
                                            ? 'pendente'
                                            : item.status,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                if (item.motivo.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    item.motivo,
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      onPressed:
                                          _processando
                                              ? null
                                              : () => _aprovar(
                                                produtoId: item.produtoId,
                                                pathOriginal: item.path,
                                              ),
                                      icon: const Icon(Icons.check),
                                      label: const Text('Aprovar'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed:
                                          _processando
                                              ? null
                                              : () => _recusar(
                                                produtoId: item.produtoId,
                                                pathOriginal: item.path,
                                              ),
                                      icon: const Icon(Icons.close),
                                      label: const Text('Recusar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_processando)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagemPendenteItem {
  final String produtoId;
  final String produtoNome;
  final String path;
  final String status;
  final String motivo;

  const _ImagemPendenteItem({
    required this.produtoId,
    required this.produtoNome,
    required this.path,
    required this.status,
    required this.motivo,
  });
}

class _ImagemErro extends StatelessWidget {
  final String mensagem;

  const _ImagemErro({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: mensagem,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: cs.surfaceVariant,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: cs.error, size: 32),
      ),
    );
  }
}
