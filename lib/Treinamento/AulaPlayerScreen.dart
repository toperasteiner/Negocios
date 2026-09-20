import '../Planos/PlanService.dart';
// lib/Treinamentos/AulaPlayerScreen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../ui/app_scaffold.dart';
import '../ui/app_menu_sheet.dart';

import '../Atividades/atividades_menu.dart';
import '../Cadastros/cadastros_menu.dart';
import '../Dashboards/dashboards_menu.dart';
import '../Financeiro/Financeiro_menu.dart';

class AulaPlayerScreen extends StatefulWidget {
  final String courseId;
  final String lessonId;
  final String lessonTitle;
  final String youtubeUrl;

  const AulaPlayerScreen({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.lessonTitle,
    required this.youtubeUrl,
  });

  @override
  State<AulaPlayerScreen> createState() => _AulaPlayerScreenState();
}

class _AulaPlayerScreenState extends State<AulaPlayerScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _visualizacaoRegistrada = false;

  YoutubePlayerController? _controller;

  String? _videoId;
  String? _error;

  bool _loadingUser = true;
  bool _isAdmin = false;
  bool _isPremium = false;
  String? _companyId;
  String _userName = '';

  bool _playerReady = false;
  bool _playerHasError = false;
  int? _youtubeErrorCode;

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

    _initializePlayer();
    _loadUserData();
  }

  void _initializePlayer() {
    final videoId = YoutubePlayer.convertUrlToId(widget.youtubeUrl.trim());

    if (videoId == null || videoId.trim().isEmpty) {
      _error = 'Link do YouTube inválido.';
      return;
    }

    _videoId = videoId;

    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        enableCaption: true,
        controlsVisibleAtStart: true,
        hideControls: false,
        hideThumbnail: false,
        forceHD: false,
        loop: false,
        disableDragSeek: false,
        isLive: false,
        useHybridComposition: true,
      ),
    );

    _controller!.addListener(_youtubeListener);
  }

  void _youtubeListener() {
    final controller = _controller;

    if (controller == null || !mounted) return;

    final value = controller.value;

    final errorCode = value.errorCode;

    if (errorCode != 0) {
      if (!_playerHasError || _youtubeErrorCode != errorCode) {
        setState(() {
          _playerHasError = true;
          _youtubeErrorCode = errorCode;
        });
      }

      return;
    }

    if (!_playerReady && value.isReady) {
      setState(() {
        _playerReady = true;
        _playerHasError = false;
        _youtubeErrorCode = null;
      });
    }
  }

  Future<void> _tentarRegistrarVisualizacao() async {
    debugPrint('=== INICIANDO REGISTRO DE VISUALIZAÇÃO ===');
    debugPrint('Já registrada: $_visualizacaoRegistrada');
    debugPrint('Carregando usuário: $_loadingUser');
    debugPrint('courseId: ${widget.courseId}');
    debugPrint('lessonId: ${widget.lessonId}');

    if (_visualizacaoRegistrada) {
      debugPrint('Registro cancelado: visualização já registrada.');
      return;
    }

    if (_loadingUser) {
      debugPrint('Registro aguardando: usuário ainda está carregando.');
      return;
    }

    final user = _auth.currentUser;

    if (user == null) {
      debugPrint('Registro cancelado: usuário não autenticado.');
      return;
    }

    final lessonId = widget.lessonId.trim();
    final courseId = widget.courseId.trim();
    final lessonTitle = widget.lessonTitle.trim();

    if (lessonId.isEmpty) {
      debugPrint('Registro cancelado: lessonId vazio.');
      return;
    }

    if (courseId.isEmpty) {
      debugPrint('Registro cancelado: courseId vazio.');
      return;
    }

    _visualizacaoRegistrada = true;

    try {
      final document = await _fs.collection('training_lesson_views').add({
        'lessonId': lessonId,
        'courseId': courseId,
        'lessonTitle': lessonTitle,
        'userId': user.uid,
        'userEmail': (user.email ?? '').trim().toLowerCase(),
        'userName': _userName.trim(),
        'companyId': _companyId,
        'viewedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Visualização registrada com sucesso.');
      debugPrint('Documento criado: ${document.id}');
    } on FirebaseException catch (e) {
      _visualizacaoRegistrada = false;

      debugPrint('ERRO FIREBASE AO REGISTRAR VISUALIZAÇÃO');
      debugPrint('Código: ${e.code}');
      debugPrint('Mensagem: ${e.message}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao registrar visualização: ${e.code}')),
        );
      }
    } catch (e, stackTrace) {
      _visualizacaoRegistrada = false;

      debugPrint('ERRO GERAL AO REGISTRAR VISUALIZAÇÃO: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _abrirNoYouTube() async {
    final texto = widget.youtubeUrl.trim();

    if (texto.isEmpty) {
      _mostrarMensagem('Link do YouTube não informado.');
      return;
    }

    Uri? uri = Uri.tryParse(texto);

    if (uri == null || !uri.hasScheme) {
      if (_videoId == null || _videoId!.isEmpty) {
        _mostrarMensagem('Link do YouTube inválido.');
        return;
      }

      uri = Uri.parse('https://www.youtube.com/watch?v=$_videoId');
    }

    try {
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!abriu && mounted) {
        _mostrarMensagem('Não foi possível abrir o vídeo no YouTube.');
      }
    } catch (e) {
      if (!mounted) return;

      _mostrarMensagem('Não foi possível abrir o YouTube: $e');
    }
  }

  void _mostrarMensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
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
      _tentarRegistrarVisualizacao();
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
      Navigator.of(context).popUntil((route) => route.isFirst);
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
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _controller?.removeListener(_youtubeListener);
    _controller?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || _controller == null) {
      return _buildAppScaffold(body: _buildInitialError());
    }

    return YoutubePlayerBuilder(
      //controller: _controller!,
      onEnterFullScreen: () {
        debugPrint('Player entrou em tela cheia.');
      },
      onExitFullScreen: () {
        debugPrint('Player saiu da tela cheia.');
      },
      player: YoutubePlayer(
        controller: _controller!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Theme.of(context).colorScheme.primary,
        progressColors: ProgressBarColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          bufferedColor: Colors.white54,
          backgroundColor: Colors.white24,
        ),
        onReady: () {
          if (!mounted) return;

          setState(() {
            _playerReady = true;
          });

          _tentarRegistrarVisualizacao();
        },
      ),
      builder: (context, player) {
        return _buildAppScaffold(body: _buildBody(player));
      },
    );
  }

  Widget _buildAppScaffold({required Widget body}) {
    return AppScaffold(
      title: widget.lessonTitle,
      useModernHeader: true,
      greetingName: _userName,
      subtitle: 'Assista à aula e acompanhe o conteúdo.',
      currentIndex: 0,
      onOpenMenu: _loadingUser ? null : _openMenu,
      onTabSelected: _onTabSelected,
      body: body,
    );
  }

  Widget _buildBody(Widget player) {
    return Container(
      color: const Color(0xFFF7F7FA),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final playerHeight = (width * 9 / 16).clamp(180.0, 420.0);

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Voltar'),
                  ),
                ),

                const SizedBox(height: 16),

                _buildPlayerContainer(
                  player: player,
                  playerHeight: playerHeight,
                ),

                const SizedBox(height: 14),

                _buildLessonContent(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerContainer({
    required Widget player,
    required double playerHeight,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: playerHeight,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: player,
          ),
        ),

        if (!_playerReady && !_playerHasError) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],

        if (_playerHasError) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.error.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'O YouTube não permitiu reproduzir este vídeo '
                        'dentro do aplicativo'
                        '${_youtubeErrorCode == null ? '.' : ' (erro $_youtubeErrorCode).'}',
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _abrirNoYouTube,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Assistir no YouTube'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInitialError() {
    return Container(
      color: const Color(0xFFF7F7FA),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          child: _InfoBox(
            icon: Icons.error_outline_rounded,
            title: 'Não foi possível carregar a aula',
            subtitle: _error ?? 'Ocorreu um erro ao carregar o vídeo.',
            actionLabel:
                widget.youtubeUrl.trim().isEmpty ? null : 'Abrir no YouTube',
            onAction: widget.youtubeUrl.trim().isEmpty ? null : _abrirNoYouTube,
          ),
        ),
      ),
    );
  }

  Widget _buildLessonContent() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.play_lesson_outlined,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.lessonTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Assista ao vídeo acima para acompanhar esta aula.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _abrirNoYouTube,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Abrir vídeo no YouTube'),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.50),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: cs.primary, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Se o vídeo não puder ser reproduzido dentro do '
                    'aplicativo, utilize o botão para assistir diretamente '
                    'no YouTube.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
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

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoBox({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.onSurfaceVariant, size: 26),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
