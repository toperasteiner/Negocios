import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TrainingLessonFormScreen extends StatefulWidget {
  const TrainingLessonFormScreen({super.key});

  @override
  State<TrainingLessonFormScreen> createState() =>
      _TrainingLessonFormScreenState();
}

class _TrainingLessonFormScreenState extends State<TrainingLessonFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _courseIdController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationMinController = TextEditingController();
  final _orderController = TextEditingController();
  final _youtubeUrlController = TextEditingController();

  bool _isActive = true;
  bool _isPremium = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _orderController.text = '0';
  }

  @override
  void dispose() {
    _courseIdController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _durationMinController.dispose();
    _orderController.dispose();
    _youtubeUrlController.dispose();

    super.dispose();
  }

  Future<void> _saveLesson() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final order = int.tryParse(_orderController.text.trim()) ?? 0;

      await FirebaseFirestore.instance.collection('training_lessons').add({
        'courseId': _courseIdController.text.trim(),
        'description': _descriptionController.text.trim(),
        'durationMin': _durationMinController.text.trim(),
        'isActive': _isActive,
        'isPremium': _isPremium,
        'order': order,
        'title': _titleController.text.trim(),
        'youtubeUrl': _youtubeUrlController.text.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aula cadastrada com sucesso.'),
          backgroundColor: Colors.green,
        ),
      );

      _clearForm();
    } on FirebaseException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível cadastrar a aula: ${error.message ?? error.code}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao cadastrar aula: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _clearForm() {
    _courseIdController.clear();
    _titleController.clear();
    _descriptionController.clear();
    _durationMinController.clear();
    _youtubeUrlController.clear();
    _orderController.text = '0';

    setState(() {
      _isActive = true;
      _isPremium = false;
    });
  }

  bool _isValidYoutubeUrl(String value) {
    if (value.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(value);

    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }

    final host = uri.host.toLowerCase();

    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF7F7FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE4E2EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6750A4), width: 1.5),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8E6F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF292631),
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        title: const Text('Nova aula'),
        backgroundColor: const Color(0xFF6750A4),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSection(
                title: 'Informações da aula',
                children: [
                  TextFormField(
                    controller: _courseIdController,
                    decoration: _inputDecoration(
                      label: 'Código do curso',
                      icon: Icons.school_outlined,
                      hint: 'Exemplo: curso_pedidos',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o código do curso.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _titleController,
                    decoration: _inputDecoration(
                      label: 'Título da aula',
                      icon: Icons.title,
                      hint: 'Exemplo: Cadastro de pedidos',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o título da aula.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'Organização',
                children: [
                  TextFormField(
                    controller: _durationMinController,
                    decoration: _inputDecoration(
                      label: 'Duração',
                      icon: Icons.schedule,
                      hint: 'Exemplo: 10 minutos',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe a duração da aula.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _orderController,
                    decoration: _inputDecoration(
                      label: 'Ordem',
                      icon: Icons.format_list_numbered,
                      hint: 'Exemplo: 1',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe a ordem da aula.';
                      }

                      final order = int.tryParse(value);

                      if (order == null || order < 0) {
                        return 'Informe uma ordem válida.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    value: _isActive,
                    onChanged: (value) {
                      setState(() {
                        _isActive = value;
                      });
                    },
                    activeColor: const Color(0xFF6750A4),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Aula ativa',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isActive
                          ? 'A aula ficará disponível para os usuários.'
                          : 'A aula ficará oculta para os usuários.',
                    ),
                  ),
                  const Divider(height: 28),
                  SwitchListTile(
                    value: _isPremium,
                    onChanged: (value) {
                      setState(() {
                        _isPremium = value;
                      });
                    },
                    activeColor: const Color(0xFF6750A4),
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      _isPremium
                          ? Icons.workspace_premium_rounded
                          : Icons.workspace_premium_outlined,
                      color:
                          _isPremium
                              ? const Color(0xFF6750A4)
                              : const Color(0xFF6C6875),
                    ),
                    title: const Text(
                      'Conteúdo Premium',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isPremium
                          ? 'A aula será exclusiva para usuários Premium.'
                          : 'A aula ficará disponível para todos os usuários.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'Vídeo',
                children: [
                  TextFormField(
                    controller: _youtubeUrlController,
                    decoration: _inputDecoration(
                      label: 'Link do YouTube',
                      icon: Icons.play_circle_outline,
                      hint: 'https://www.youtube.com/watch?v=...',
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: (value) {
                      final url = value?.trim() ?? '';

                      if (url.isEmpty) {
                        return 'Informe o link do vídeo.';
                      }

                      if (!_isValidYoutubeUrl(url)) {
                        return 'Informe um link válido do YouTube.';
                      }

                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveLesson,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6750A4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon:
                      _isSaving
                          ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.save_outlined),
                  label: Text(
                    _isSaving ? 'Salvando...' : 'Salvar aula',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
