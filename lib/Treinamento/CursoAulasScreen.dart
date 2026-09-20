import '../Planos/PlanService.dart';
// lib/Treinamentos/CursoAulasScreen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Atividades/atividades_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Cadastros/cadastros_menu.dart';
import '../Financeiro/Financeiro_menu.dart';

import 'AulaPlayerScreen.dart';
import '../Home/home_screen.dart';
import '../Planos/PlanosScreen.dart';

class CursoAulasScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;

  const CursoAulasScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  State<CursoAulasScreen> createState() => _CursoAulasScreenState();
}

class _CursoAulasScreenState extends State<CursoAulasScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loadingUser = true;
  bool _isAdmin = false;
  bool _isPremium = false;
  String? _companyId;
  String _userName = '';

  void _openLesson(_Lesson lesson) {
    if (_loadingUser) {
      return;
    }

    final requiresPremium = lesson.isPremium;
    final accessBlocked = requiresPremium && !_isPremium;

    if (accessBlocked) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PlanosScreen()));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => AulaPlayerScreen(
              courseId: widget.courseId,
              lessonId: lesson.id,
              lessonTitle: lesson.title,
              youtubeUrl: lesson.youtubeUrl,
            ),
      ),
    );
  }

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

      try {
        final byUid = await _fs.collection('users').doc(user.uid).get();

        if (byUid.exists) {
          data = byUid.data();
        }
      } catch (e) {
        debugPrint('Erro ao buscar usuário pelo UID: $e');
      }

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

      final userData = data!;

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _loadingUser = false;
          _isAdmin = false;
          _isPremium = false;
          _companyId = null;
          _userName = user.displayName?.trim() ?? '';
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

  Query<Map<String, dynamic>> _queryLessons() {
    return _fs
        .collection('training_lessons')
        .where('courseId', isEqualTo: widget.courseId)
        .orderBy('order', descending: false);
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.courseTitle,
      useModernHeader: true,
      greetingName: _userName,
      subtitle: 'Escolha uma aula para assistir.',
      currentIndex: 0,
      onOpenMenu: _loadingUser ? null : _openMenu,
      onTabSelected: _onTabSelected,
      body: Container(
        color: const Color(0xFFF7F7FA),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _queryLessons().snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: _InfoBox(
                  icon: Icons.error_outline_rounded,
                  title: 'Erro ao carregar aulas',
                  subtitle:
                      'Pode ser necessário criar um índice composto para '
                      'courseId e order.\n\n'
                      'Detalhe: ${snapshot.error}',
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            final lessons = <_Lesson>[];

            for (final document in docs) {
              final lesson = _Lesson.fromMap(document.id, document.data());

              if (lesson.isActive == false) continue;

              lessons.add(lesson);
            }

            if (lessons.isEmpty) {
              return const SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: _InfoBox(
                  icon: Icons.inbox_outlined,
                  title: 'Nenhuma aula encontrada',
                  subtitle:
                      'Cadastre aulas na coleção "training_lessons" '
                      'informando o courseId deste curso.',
                ),
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              itemCount: lessons.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                      ),
                      label: const Text('Voltar'),
                    ),
                  );
                }

                final lesson = lessons[index - 1];

                final premiumBlocked = lesson.isPremium && !_isPremium;

                return _LessonCard(
                  lesson: lesson,
                  lessonNumber: index,
                  premiumBlocked: premiumBlocked,
                  onTap: () => _openLesson(lesson),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }
}

class _Lesson {
  final String id;
  final String title;
  final String description;
  final String youtubeUrl;
  final int? durationMin;
  final int order;
  final bool? isActive;
  final bool isPremium;

  const _Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.youtubeUrl,
    required this.durationMin,
    required this.order,
    required this.isActive,
    required this.isPremium,
  });

  factory _Lesson.fromMap(String id, Map<String, dynamic> map) {
    String stringValue(String key) {
      return (map[key] ?? '').toString().trim();
    }

    int? durationMin;

    final rawDuration = map['durationMin'];

    if (rawDuration is num) {
      durationMin = rawDuration.toInt();
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
    final rawIsPremium = map['isPremium'];

    final isPremium = rawIsPremium is bool ? rawIsPremium : false;

    return _Lesson(
      id: id,
      title: title.isEmpty ? 'Aula' : title,
      description: stringValue('description'),
      youtubeUrl: stringValue('youtubeUrl'),
      durationMin: durationMin,
      order: order,
      isActive: isActive,
      isPremium: isPremium,
    );
  }
}

class _LessonCard extends StatelessWidget {
  final _Lesson lesson;
  final int lessonNumber;
  final bool premiumBlocked;
  final VoidCallback onTap;

  const _LessonCard({
    required this.lesson,
    required this.lessonNumber,
    required this.premiumBlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasVideo = lesson.youtubeUrl.trim().isNotEmpty;
    final isPremiumLesson = lesson.isPremium;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: hasVideo ? onTap : null,
        child: Opacity(
          opacity: hasVideo ? 1 : 0.65,
          child: Container(
            padding: const EdgeInsets.all(13),
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
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color:
                        !hasVideo
                            ? cs.surfaceVariant
                            : premiumBlocked
                            ? Colors.orange.withOpacity(0.12)
                            : cs.primary.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        !hasVideo
                            ? Icons.link_off_rounded
                            : premiumBlocked
                            ? Icons.lock_outline_rounded
                            : Icons.play_arrow_rounded,
                        color:
                            !hasVideo
                                ? cs.onSurfaceVariant
                                : premiumBlocked
                                ? Colors.orange.shade800
                                : cs.onPrimaryContainer,
                        size: 32,
                      ),
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                            lessonNumber.toString(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        premiumBlocked
                            ? 'Conteúdo exclusivo para usuários Premium. Toque para conhecer os planos.'
                            : lesson.description.trim().isEmpty
                            ? hasVideo
                                ? 'Toque para assistir à aula.'
                                : 'Link do vídeo não informado.'
                            : lesson.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (lesson.durationMin != null &&
                              lesson.durationMin! > 0)
                            _Pill(
                              icon: Icons.schedule_rounded,
                              label: '${lesson.durationMin} min',
                            ),

                          if (isPremiumLesson)
                            _Pill(
                              icon:
                                  premiumBlocked
                                      ? Icons.lock_outline_rounded
                                      : Icons.workspace_premium_outlined,
                              label:
                                  premiumBlocked
                                      ? 'Premium bloqueado'
                                      : 'Premium',
                            ),

                          if (!hasVideo)
                            const _Pill(
                              icon: Icons.error_outline_rounded,
                              label: 'Link não informado',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color:
                        hasVideo
                            ? cs.primary.withOpacity(0.10)
                            : cs.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    !hasVideo
                        ? Icons.link_off_rounded
                        : premiumBlocked
                        ? Icons.lock_outline_rounded
                        : Icons.arrow_forward_rounded,
                    color:
                        !hasVideo
                            ? cs.onSurfaceVariant
                            : premiumBlocked
                            ? Colors.orange.shade800
                            : cs.primary,
                    size: 21,
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
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
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
