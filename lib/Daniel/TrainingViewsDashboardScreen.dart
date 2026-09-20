import '../Planos/PlanService.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Atividades/atividades_menu.dart';
import '../Cadastros/cadastros_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Financeiro/Financeiro_menu.dart';
import '../Home/home_screen.dart';
import '../ui/app_menu_sheet.dart';
import '../ui/app_scaffold.dart';

class TrainingViewsDashboardScreen extends StatefulWidget {
  const TrainingViewsDashboardScreen({super.key});

  @override
  State<TrainingViewsDashboardScreen> createState() =>
      _TrainingViewsDashboardScreenState();
}

class _TrainingViewsDashboardScreenState
    extends State<TrainingViewsDashboardScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loadingUser = true;
  bool _isAdmin = false;
  bool _isPremium = false;
  String? _companyId;
  String _userName = '';

  _DashboardPeriod _selectedPeriod = _DashboardPeriod.last30Days;

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
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
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
      setState(() {
        _loadingUser = true;
      });
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
          _userName = '';
        });

        return;
      }

      Map<String, dynamic>? data;

      try {
        final userDocument = await _fs.collection('users').doc(user.uid).get();

        if (userDocument.exists) {
          data = userDocument.data();
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
            debugPrint('Erro ao buscar usuário pelo e-mail: $e');
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
          _userName = user.displayName?.trim() ?? '';
        });

        return;
      }

      final userData = data;

      final role =
          (userData['role'] ?? 'funcionario').toString().trim().toLowerCase();

      final companyId = (userData['companyId'] ?? '').toString().trim();

      final rawPlan =
          (userData['planId'] ??
                  userData['plan'] ??
                  userData['planKey'] ??
                  userData['currentPlan'] ??
                  userData['plano'] ??
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
        _loadingUser = false;
        _isAdmin = role == 'admin';
        _isPremium =
            PlanService.instance.isLoaded
                ? PlanService.instance.isPremium
                : rawPlan == 'premium';
        _companyId = companyId.isEmpty ? null : companyId;
        _userName = userName;
      });
    } catch (e) {
      debugPrint('Erro ao carregar usuário: $e');

      if (!mounted) return;

      setState(() {
        _loadingUser = false;
        _isAdmin = false;
        _isPremium = false;
        _companyId = null;
      });
    }
  }

  Query<Map<String, dynamic>> _viewsQuery() {
    return _fs
        .collection('training_lesson_views')
        .orderBy('viewedAt', descending: true)
        .limit(3000);
  }

  List<_LessonView> _filterViews(List<_LessonView> views) {
    final startDate = _selectedPeriod.startDate;

    if (startDate == null) {
      return views;
    }

    return views.where((view) {
      final viewedAt = view.viewedAt;

      if (viewedAt == null) {
        return false;
      }

      return !viewedAt.isBefore(startDate);
    }).toList();
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
      title: 'Dashboard de Treinamentos',
      useModernHeader: true,
      greetingName: _userName,
      subtitle: 'Acompanhe as visualizações das aulas.',
      currentIndex: 3,
      onOpenMenu: _loadingUser ? null : _openMenu,
      onTabSelected: _onTabSelected,
      body: Container(
        color: const Color(0xFFF7F7FA),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _viewsQuery().snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _DashboardMessage(
                icon: Icons.error_outline_rounded,
                title: 'Erro ao carregar visualizações',
                message: snapshot.error.toString(),
              );
            }

            final documents = snapshot.data?.docs ?? [];

            final allViews =
                documents
                    .map(
                      (document) => _LessonView.fromDocument(
                        document.id,
                        document.data(),
                      ),
                    )
                    .toList();

            final filteredViews = _filterViews(allViews);

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {});
              },
              child: _buildDashboard(filteredViews),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboard(List<_LessonView> views) {
    final statistics = _DashboardStatistics.fromViews(views);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _buildTopBar(),

            const SizedBox(height: 18),

            _buildPeriodSelector(),

            const SizedBox(height: 18),

            if (views.isEmpty)
              const _DashboardMessage(
                icon: Icons.visibility_off_outlined,
                title: 'Nenhuma visualização encontrada',
                message:
                    'Ainda não existem visualizações para o período selecionado.',
              )
            else ...[
              _buildMetrics(statistics, isDesktop),

              const SizedBox(height: 18),

              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _DailyViewsCard(dailyViews: statistics.dailyViews),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _MostViewedLessonsCard(
                        lessons: statistics.lessonRanking,
                      ),
                    ),
                  ],
                )
              else ...[
                _DailyViewsCard(dailyViews: statistics.dailyViews),
                const SizedBox(height: 16),
                _MostViewedLessonsCard(lessons: statistics.lessonRanking),
              ],

              const SizedBox(height: 16),

              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MostActiveUsersCard(
                        users: statistics.userRanking,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _RecentViewsCard(views: statistics.recentViews),
                    ),
                  ],
                )
              else ...[
                _MostActiveUsersCard(users: statistics.userRanking),
                const SizedBox(height: 16),
                _RecentViewsCard(views: statistics.recentViews),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          label: const Text('Voltar'),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Atualizar',
          onPressed: () {
            setState(() {});
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.date_range_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<_DashboardPeriod>(
              value: _selectedPeriod,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Período',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items:
                  _DashboardPeriod.values.map((period) {
                    return DropdownMenuItem(
                      value: period,
                      child: Text(period.label),
                    );
                  }).toList(),
              onChanged: (period) {
                if (period == null) return;

                setState(() {
                  _selectedPeriod = period;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(_DashboardStatistics statistics, bool isDesktop) {
    final cards = [
      _MetricData(
        title: 'Visualizações',
        value: statistics.totalViews.toString(),
        subtitle: 'Acessos registrados',
        icon: Icons.visibility_rounded,
      ),
      _MetricData(
        title: 'Usuários únicos',
        value: statistics.uniqueUsers.toString(),
        subtitle: 'Pessoas que assistiram',
        icon: Icons.people_alt_rounded,
      ),
      _MetricData(
        title: 'Aulas visualizadas',
        value: statistics.uniqueLessons.toString(),
        subtitle: 'Conteúdos acessados',
        icon: Icons.play_lesson_rounded,
      ),
      _MetricData(
        title: 'Média por usuário',
        value: statistics.averagePerUser.toStringAsFixed(1),
        subtitle: 'Visualizações por usuário',
        icon: Icons.analytics_rounded,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: isDesktop ? 1.55 : 1.20,
      ),
      itemBuilder: (context, index) {
        return _MetricCard(data: cards[index]);
      },
    );
  }
}

enum _DashboardPeriod {
  today,
  last7Days,
  last30Days,
  last90Days,
  all;

  String get label {
    switch (this) {
      case _DashboardPeriod.today:
        return 'Hoje';
      case _DashboardPeriod.last7Days:
        return 'Últimos 7 dias';
      case _DashboardPeriod.last30Days:
        return 'Últimos 30 dias';
      case _DashboardPeriod.last90Days:
        return 'Últimos 90 dias';
      case _DashboardPeriod.all:
        return 'Todo o período';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();

    switch (this) {
      case _DashboardPeriod.today:
        return DateTime(now.year, now.month, now.day);

      case _DashboardPeriod.last7Days:
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));

      case _DashboardPeriod.last30Days:
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));

      case _DashboardPeriod.last90Days:
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 89));

      case _DashboardPeriod.all:
        return null;
    }
  }
}

class _LessonView {
  final String id;
  final String courseId;
  final String lessonId;
  final String lessonTitle;
  final String userId;
  final String userName;
  final String userEmail;
  final String? companyId;
  final DateTime? viewedAt;

  const _LessonView({
    required this.id,
    required this.courseId,
    required this.lessonId,
    required this.lessonTitle,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.companyId,
    required this.viewedAt,
  });

  factory _LessonView.fromDocument(String id, Map<String, dynamic> data) {
    DateTime? viewedAt;

    final rawViewedAt = data['viewedAt'];

    if (rawViewedAt is Timestamp) {
      viewedAt = rawViewedAt.toDate();
    } else if (rawViewedAt is DateTime) {
      viewedAt = rawViewedAt;
    }

    final companyId = (data['companyId'] ?? '').toString().trim();

    return _LessonView(
      id: id,
      courseId: (data['courseId'] ?? '').toString().trim(),
      lessonId: (data['lessonId'] ?? '').toString().trim(),
      lessonTitle: (data['lessonTitle'] ?? 'Aula').toString().trim(),
      userId: (data['userId'] ?? '').toString().trim(),
      userName: (data['userName'] ?? '').toString().trim(),
      userEmail: (data['userEmail'] ?? '').toString().trim(),
      companyId: companyId.isEmpty ? null : companyId,
      viewedAt: viewedAt,
    );
  }

  String get displayUser {
    if (userName.isNotEmpty) {
      return userName;
    }

    if (userEmail.isNotEmpty) {
      return userEmail;
    }

    return 'Usuário não identificado';
  }

  String get displayLesson {
    if (lessonTitle.isNotEmpty) {
      return lessonTitle;
    }

    return 'Aula sem título';
  }
}

class _DashboardStatistics {
  final int totalViews;
  final int uniqueUsers;
  final int uniqueLessons;
  final double averagePerUser;
  final List<_DailyViewData> dailyViews;
  final List<_LessonRankingData> lessonRanking;
  final List<_UserRankingData> userRanking;
  final List<_LessonView> recentViews;

  const _DashboardStatistics({
    required this.totalViews,
    required this.uniqueUsers,
    required this.uniqueLessons,
    required this.averagePerUser,
    required this.dailyViews,
    required this.lessonRanking,
    required this.userRanking,
    required this.recentViews,
  });

  factory _DashboardStatistics.fromViews(List<_LessonView> views) {
    final userIds = <String>{};
    final lessonIds = <String>{};

    final dailyMap = <DateTime, int>{};
    final lessonMap = <String, _LessonRankingData>{};
    final userMap = <String, _UserRankingData>{};

    for (final view in views) {
      final userKey = view.userId.isNotEmpty ? view.userId : view.userEmail;

      final lessonKey =
          view.lessonId.isNotEmpty ? view.lessonId : view.lessonTitle;

      if (userKey.isNotEmpty) {
        userIds.add(userKey);
      }

      if (lessonKey.isNotEmpty) {
        lessonIds.add(lessonKey);
      }

      final viewedAt = view.viewedAt;

      if (viewedAt != null) {
        final day = DateTime(viewedAt.year, viewedAt.month, viewedAt.day);

        dailyMap[day] = (dailyMap[day] ?? 0) + 1;
      }

      final existingLesson = lessonMap[lessonKey];

      lessonMap[lessonKey] = _LessonRankingData(
        lessonId: lessonKey,
        lessonTitle: view.displayLesson,
        views: (existingLesson?.views ?? 0) + 1,
      );

      final existingUser = userMap[userKey];

      userMap[userKey] = _UserRankingData(
        userId: userKey,
        userName: view.displayUser,
        userEmail: view.userEmail,
        views: (existingUser?.views ?? 0) + 1,
      );
    }

    final dailyViews =
        dailyMap.entries.map((entry) {
            return _DailyViewData(date: entry.key, views: entry.value);
          }).toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    final lessonRanking =
        lessonMap.values.toList()..sort((a, b) => b.views.compareTo(a.views));

    final userRanking =
        userMap.values.toList()..sort((a, b) => b.views.compareTo(a.views));

    final recentViews = [...views]..sort((a, b) {
      final dateA = a.viewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final dateB = b.viewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return dateB.compareTo(dateA);
    });

    final uniqueUsers = userIds.length;

    final averagePerUser = uniqueUsers == 0 ? 0.0 : views.length / uniqueUsers;

    return _DashboardStatistics(
      totalViews: views.length,
      uniqueUsers: uniqueUsers,
      uniqueLessons: lessonIds.length,
      averagePerUser: averagePerUser,
      dailyViews: dailyViews,
      lessonRanking: lessonRanking.take(10).toList(),
      userRanking: userRanking.take(10).toList(),
      recentViews: recentViews.take(15).toList(),
    );
  }
}

class _DailyViewData {
  final DateTime date;
  final int views;

  const _DailyViewData({required this.date, required this.views});
}

class _LessonRankingData {
  final String lessonId;
  final String lessonTitle;
  final int views;

  const _LessonRankingData({
    required this.lessonId,
    required this.lessonTitle,
    required this.views,
  });
}

class _UserRankingData {
  final String userId;
  final String userName;
  final String userEmail;
  final int views;

  const _UserRankingData({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.views,
  });
}

class _MetricData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _MetricData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, color: cs.onPrimaryContainer),
          ),
          const Spacer(),
          Text(
            data.value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            data.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DailyViewsCard extends StatelessWidget {
  final List<_DailyViewData> dailyViews;

  const _DailyViewsCard({required this.dailyViews});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final visibleData =
        dailyViews.length > 14
            ? dailyViews.sublist(dailyViews.length - 14)
            : dailyViews;

    final maxViews =
        visibleData.isEmpty
            ? 1
            : visibleData
                .map((item) => item.views)
                .reduce((a, b) => a > b ? a : b);

    return _DashboardCard(
      title: 'Visualizações por dia',
      subtitle: 'Últimos dias com atividade',
      icon: Icons.bar_chart_rounded,
      child:
          visibleData.isEmpty
              ? const _EmptyCardText(text: 'Nenhuma atividade no período.')
              : SizedBox(
                height: 240,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children:
                      visibleData.map((item) {
                        final percentage =
                            maxViews == 0 ? 0.0 : item.views / maxViews;

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  item.views.toString(),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 5),
                                Flexible(
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        percentage == 0 ? 0.02 : percentage,
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(8),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  _formatDayMonth(item.date),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
    );
  }
}

class _MostViewedLessonsCard extends StatelessWidget {
  final List<_LessonRankingData> lessons;

  const _MostViewedLessonsCard({required this.lessons});

  @override
  Widget build(BuildContext context) {
    final maxViews = lessons.isEmpty ? 1 : lessons.first.views;

    return _DashboardCard(
      title: 'Aulas mais visualizadas',
      subtitle: 'Ranking por número de acessos',
      icon: Icons.workspace_premium_rounded,
      child:
          lessons.isEmpty
              ? const _EmptyCardText(text: 'Nenhuma aula visualizada.')
              : Column(
                children: [
                  for (int index = 0; index < lessons.length; index++)
                    _RankingRow(
                      position: index + 1,
                      title: lessons[index].lessonTitle,
                      value: '${lessons[index].views} views',
                      percentage: lessons[index].views / maxViews,
                    ),
                ],
              ),
    );
  }
}

class _MostActiveUsersCard extends StatelessWidget {
  final List<_UserRankingData> users;

  const _MostActiveUsersCard({required this.users});

  @override
  Widget build(BuildContext context) {
    final maxViews = users.isEmpty ? 1 : users.first.views;

    return _DashboardCard(
      title: 'Usuários mais ativos',
      subtitle: 'Quem mais acessou os treinamentos',
      icon: Icons.people_alt_rounded,
      child:
          users.isEmpty
              ? const _EmptyCardText(text: 'Nenhum usuário encontrado.')
              : Column(
                children: [
                  for (int index = 0; index < users.length; index++)
                    _RankingRow(
                      position: index + 1,
                      title: users[index].userName,
                      subtitle:
                          users[index].userEmail.isEmpty
                              ? null
                              : users[index].userEmail,
                      value: '${users[index].views} views',
                      percentage: users[index].views / maxViews,
                    ),
                ],
              ),
    );
  }
}

class _RecentViewsCard extends StatelessWidget {
  final List<_LessonView> views;

  const _RecentViewsCard({required this.views});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _DashboardCard(
      title: 'Visualizações recentes',
      subtitle: 'Últimos acessos registrados',
      icon: Icons.history_rounded,
      child:
          views.isEmpty
              ? const _EmptyCardText(text: 'Nenhuma visualização recente.')
              : Column(
                children:
                    views.map((view) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    view.displayLesson,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    view.displayUser,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDateTime(view.viewedAt),
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final int position;
  final String title;
  final String? subtitle;
  final String value;
  final double percentage;

  const _RankingRow({
    required this.position,
    required this.title,
    this.subtitle,
    required this.value,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              position.toString(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: percentage.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: cs.surfaceVariant,
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

class _DashboardCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _DashboardCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _EmptyCardText extends StatelessWidget {
  final String text;

  const _EmptyCardText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _DashboardMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 550),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 42, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDayMonth(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime? date) {
  if (date == null) {
    return 'Processando';
  }

  final day = date.day.toString().padLeft(2, '0');

  final month = date.month.toString().padLeft(2, '0');

  final hour = date.hour.toString().padLeft(2, '0');

  final minute = date.minute.toString().padLeft(2, '0');

  return '$day/$month\n$hour:$minute';
}
