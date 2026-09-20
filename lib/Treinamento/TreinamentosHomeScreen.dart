import '../Planos/PlanService.dart';
// lib/Treinamentos/TreinamentosHomeScreen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Atividades/atividades_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Cadastros/cadastros_menu.dart';
import '../Financeiro/Financeiro_menu.dart';

import 'CursoAulasScreen.dart';
import '../Home/home_screen.dart';

class TreinamentosHomeScreen extends StatefulWidget {
  const TreinamentosHomeScreen({super.key});

  @override
  State<TreinamentosHomeScreen> createState() => _TreinamentosHomeScreenState();
}

class _TreinamentosHomeScreenState extends State<TreinamentosHomeScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchCtrl = TextEditingController();

  String _search = '';

  bool _loadingUser = true;
  bool _isAdmin = false;
  bool _isPremium = false;
  String? _companyId;
  String _userName = '';

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    setState(() => _isPremium = service.isLoaded && service.isPremium);
  }

  Future<void> _loadPlanState() async {
    if (!mounted) return;
    try {
      if (!PlanService.instance.isLoaded) await PlanService.instance.load();
      _onPlanChanged();
    } catch (e) {
      debugPrint('Plan refresh failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlanState());
    _loadUserData();
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (mounted) {
      setState(() => _loadingUser = true);
    }

    try {
      final user = _auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          _loadingUser = false;
          _isAdmin = false;
          _isPremium = false;
          _companyId = null;
        });

        return;
      }

      Map<String, dynamic>? data;

      // Primeiro tenta localizar o usuário pelo UID.
      try {
        final byUid = await _fs.collection('users').doc(user.uid).get();

        if (byUid.exists) {
          data = byUid.data();
        }
      } catch (e) {
        debugPrint('Erro ao buscar usuário pelo UID: $e');
      }

      // Fallback para usuários antigos cadastrados pelo emailKey.
      if (data == null) {
        final emailKey = (user.email ?? '').trim().toLowerCase();

        if (emailKey.isNotEmpty) {
          try {
            final query =
                await _fs
                    .collection('users')
                    .where('emailKey', isEqualTo: emailKey)
                    .limit(1)
                    .get();

            if (query.docs.isNotEmpty) {
              data = query.docs.first.data();
            }
          } catch (e) {
            debugPrint('Erro ao buscar usuário pelo emailKey: $e');
          }
        }
      }

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _loadingUser = false;
          _isAdmin = false;
          _isPremium = false;
          _companyId = null;
        });

        return;
      }

      final role =
          (data['role'] ?? 'funcionario').toString().trim().toLowerCase();

      final companyId = (data['companyId'] ?? '').toString().trim();

      final rawPlan =
          (data['planId'] ??
                  data['plan'] ??
                  data['planKey'] ??
                  data['currentPlan'] ??
                  data['plano'] ??
                  'free')
              .toString()
              .trim()
              .toLowerCase();

      final userData = data!;
      final userName =
          (userData['displayName'] ??
                  userData['name'] ??
                  user.displayName ??
                  '')
              .toString()
              .trim();

      setState(() {
        _isAdmin = role == 'admin';
        _isPremium =
            PlanService.instance.isLoaded
                ? PlanService.instance.isPremium
                : rawPlan == 'premium';
        _companyId = companyId.isEmpty ? null : companyId;
        _userName = userName;
        _loadingUser = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');

      if (!mounted) return;

      setState(() {
        _loadingUser = false;
        _isAdmin = false;
        _isPremium = false;
        _companyId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar as informações do usuário: $e',
          ),
        ),
      );
    }
  }

  Query<Map<String, dynamic>> _queryCourses() {
    return _fs
        .collection('training_courses')
        .orderBy('order', descending: false);
  }

  bool _matchesSearch(_Course course) {
    final texto = _search.trim().toLowerCase();

    if (texto.isEmpty) return true;

    return course.title.toLowerCase().contains(texto) ||
        course.description.toLowerCase().contains(texto) ||
        course.category.toLowerCase().contains(texto);
  }

  void _openMenu() {
    AppMenuSheet.show(
      context,
      isAdmin: _isAdmin,
      isPremium: _isPremium,
      companyId: _companyId,
    );
  }

  void _onTabSelected(int index) {
    if (index == 0) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
      return;
    }

    if (index == 1) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CadastrosMenuScreen()),
      );
      return;
    }

    if (index == 2) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AtividadesMenuScreen()),
      );
      return;
    }

    if (index == 3) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardsMenuScreen()),
      );
      return;
    }

    if (index == 4) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FinanceiroMenuScreen()),
      );
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();

    setState(() {
      _search = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppScaffold(
      title: 'Treinamentos',
      useModernHeader: true,
      greetingName: _userName,
      subtitle: 'Aprenda a utilizar os recursos do aplicativo.',
      currentIndex: 0,
      onOpenMenu: _loadingUser ? null : _openMenu,
      onTabSelected: _onTabSelected,
      body: Container(
        color: const Color(0xFFF7F7FA),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cursos disponíveis',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Escolha um curso para visualizar as aulas.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (value) {
                        setState(() {
                          _search = value;
                        });
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Buscar cursos...',
                        filled: true,
                        fillColor: cs.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                        suffixIcon:
                            _searchCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                  tooltip: 'Limpar busca',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: _clearSearch,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(top: 14)),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _queryCourses().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      child: _InfoBox(
                        icon: Icons.error_outline_rounded,
                        title: 'Erro ao carregar cursos',
                        subtitle: snapshot.error.toString(),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
                      child: _InfoBox(
                        icon: Icons.inbox_outlined,
                        title: 'Nenhum curso cadastrado',
                        subtitle:
                            'Cadastre documentos na coleção '
                            '"training_courses" para exibir os cursos.',
                      ),
                    ),
                  );
                }

                final courses = <_Course>[];

                for (final document in docs) {
                  final course = _Course.fromMap(document.id, document.data());

                  if (course.isActive == false) continue;
                  if (!_matchesSearch(course)) continue;

                  courses.add(course);
                }

                if (courses.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
                      child: _InfoBox(
                        icon: Icons.search_off_rounded,
                        title: 'Nenhum curso encontrado',
                        subtitle: 'Altere o texto da busca e tente novamente.',
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList.separated(
                    itemCount: courses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final course = courses[index];

                      return _CourseCard(
                        course: course,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => CursoAulasScreen(
                                    courseId: course.id,
                                    courseTitle: course.title,
                                  ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Course {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String category;
  final int order;
  final bool? isActive;

  const _Course({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.category,
    required this.order,
    required this.isActive,
  });

  factory _Course.fromMap(String id, Map<String, dynamic> map) {
    String stringValue(String key) {
      return (map[key] ?? '').toString().trim();
    }

    int order = 999999;

    final rawOrder = map['order'];

    if (rawOrder is num) {
      order = rawOrder.toInt();
    }

    bool? isActive;

    final rawActive = map['isActive'];

    if (rawActive is bool) {
      isActive = rawActive;
    }

    final title = stringValue('title');

    return _Course(
      id: id,
      title: title.isEmpty ? 'Curso' : title,
      description: stringValue('description'),
      thumbnailUrl: stringValue('thumbnailUrl'),
      category: stringValue('category'),
      order: order,
      isActive: isActive,
    );
  }
}

class _CourseCard extends StatelessWidget {
  final _Course course;
  final VoidCallback onTap;

  const _CourseCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final thumbnailUrl =
        course.thumbnailUrl.trim().isEmpty ? null : course.thumbnailUrl.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _Thumb(thumbUrl: thumbnailUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      course.description.trim().isEmpty
                          ? 'Toque para visualizar as aulas.'
                          : course.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (course.category.trim().isNotEmpty) ...[
                      const SizedBox(height: 9),
                      _Pill(
                        icon: Icons.category_outlined,
                        label: course.category.trim(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: cs.primary,
                  size: 21,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? thumbUrl;

  const _Thumb({this.thumbUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 92,
        height: 76,
        color: cs.surfaceVariant,
        child:
            thumbUrl == null
                ? Icon(
                  Icons.school_outlined,
                  color: cs.onSurfaceVariant,
                  size: 30,
                )
                : Image.network(
                  thumbUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }

                    return const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder:
                      (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: cs.onSurfaceVariant,
                        size: 30,
                      ),
                ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.60),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoBox({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
