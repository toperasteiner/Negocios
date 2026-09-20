import 'package:flutter/material.dart';

/// Modelo simples utilizado pelo carrossel da Home.
class CursoHome {
  final String id;
  final String titulo;
  final String? descricao;
  final String? imagemUrl;
  final IconData icone;

  const CursoHome({
    required this.id,
    required this.titulo,
    this.descricao,
    this.imagemUrl,
    this.icone = Icons.school_outlined,
  });
}

/// Card de treinamentos para ser apresentado na Home.
///
/// Quando [possuiTreinamentoIniciado] for false, apresenta um carrossel
/// com os cursos informados em [cursosDestaque].
///
/// Quando [possuiTreinamentoIniciado] for true, apresenta o progresso
/// informado em [aulasConcluidas] e [totalAulas].
class TreinamentoHomeCard extends StatefulWidget {
  final bool possuiTreinamentoIniciado;

  final List<CursoHome> cursosDestaque;

  final int aulasConcluidas;
  final int totalAulas;

  final String? tituloCursoAtual;
  final String? tituloProximaAula;

  final VoidCallback onVerTodos;
  final VoidCallback? onContinuar;
  final ValueChanged<CursoHome>? onSelecionarCurso;

  const TreinamentoHomeCard({
    super.key,
    required this.possuiTreinamentoIniciado,
    required this.onVerTodos,
    this.cursosDestaque = const [],
    this.aulasConcluidas = 0,
    this.totalAulas = 0,
    this.tituloCursoAtual,
    this.tituloProximaAula,
    this.onContinuar,
    this.onSelecionarCurso,
  });

  @override
  State<TreinamentoHomeCard> createState() => _TreinamentoHomeCardState();
}

class _TreinamentoHomeCardState extends State<TreinamentoHomeCard> {
  late final PageController _pageController;

  int _paginaAtual = 0;

  static const Color _azulPrincipal = Color(0xFF1565C0);
  static const Color _azulEscuro = Color(0xFF0D47A1);
  static const Color _laranja = Color(0xFFFF9800);
  static const Color _fundoCard = Color(0xFFF8FAFD);

  @override
  void initState() {
    super.initState();

    _pageController = PageController(viewportFraction: 0.91);
  }

  @override
  void didUpdateWidget(covariant TreinamentoHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_paginaAtual >= widget.cursosDestaque.length) {
      _paginaAtual = 0;

      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  double get _percentualProgresso {
    if (widget.totalAulas <= 0) {
      return 0;
    }

    final percentual = widget.aulasConcluidas / widget.totalAulas;

    return percentual.clamp(0.0, 1.0);
  }

  int get _percentualProgressoInteiro {
    return (_percentualProgresso * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.possuiTreinamentoIniciado) {
      return _buildCardProgresso(context);
    }

    return _buildCardCursos(context);
  }

  Widget _buildCardCursos(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _azulPrincipal.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCabecalho(
            icone: Icons.menu_book_rounded,
            titulo: 'Cursos para sua empresa',
          ),
          const SizedBox(height: 16),

          if (widget.cursosDestaque.isEmpty)
            _buildSemCursos()
          else ...[
            SizedBox(
              height: 190,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.cursosDestaque.length,
                onPageChanged: (pagina) {
                  setState(() {
                    _paginaAtual = pagina;
                  });
                },
                itemBuilder: (context, index) {
                  final curso = widget.cursosDestaque[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == widget.cursosDestaque.length - 1 ? 0 : 10,
                    ),
                    child: _buildCursoCarrossel(context, curso),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            _buildIndicadoresCarrossel(),
          ],

          const SizedBox(height: 12),
          _buildBotaoVerTodos(),
        ],
      ),
    );
  }

  Widget _buildCursoCarrossel(BuildContext context, CursoHome curso) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap:
            widget.onSelecionarCurso == null
                ? null
                : () => widget.onSelecionarCurso!(curso),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _azulPrincipal.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              _buildImagemCurso(curso),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      curso.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _azulEscuro,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (curso.descricao != null &&
                        curso.descricao!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        curso.descricao!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        const Text(
                          'Começar curso',
                          style: TextStyle(
                            color: _azulPrincipal,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: _azulPrincipal,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagemCurso(CursoHome curso) {
    if (curso.imagemUrl != null && curso.imagemUrl!.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.network(
          curso.imagemUrl!,
          width: 94,
          height: 132,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildIconeCurso(curso);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }

            return Container(
              width: 94,
              height: 132,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _azulPrincipal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _azulPrincipal,
                ),
              ),
            );
          },
        ),
      );
    }

    return _buildIconeCurso(curso);
  }

  Widget _buildIconeCurso(CursoHome curso) {
    return Container(
      width: 94,
      height: 132,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_azulPrincipal, _azulEscuro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(curso.icone, size: 45, color: Colors.white),
    );
  }

  Widget _buildIndicadoresCarrossel() {
    if (widget.cursosDestaque.length <= 1) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.cursosDestaque.length, (index) {
        final selecionado = index == _paginaAtual;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: selecionado ? 22 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: selecionado ? _azulPrincipal : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }),
    );
  }

  Widget _buildCardProgresso(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, _azulPrincipal.withValues(alpha: 0.055)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _azulPrincipal.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCabecalho(
            icone: Icons.school_rounded,
            titulo: 'Universidade CRUD Negócios',
            paddingHorizontal: 0,
          ),
          const SizedBox(height: 22),
          Text(
            'Seu progresso',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${widget.aulasConcluidas} de '
            '${widget.totalAulas} aulas concluídas',
            style: const TextStyle(
              color: _azulEscuro,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: LinearProgressIndicator(
                    value: _percentualProgresso,
                    minHeight: 11,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(_laranja),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_percentualProgressoInteiro%',
                style: const TextStyle(
                  color: _azulEscuro,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (_possuiInformacaoCursoAtual()) ...[
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _azulPrincipal.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _azulPrincipal.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.play_lesson_outlined,
                      color: _azulPrincipal,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Continue de onde parou',
                          style: TextStyle(
                            color: _laranja,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.tituloCursoAtual != null &&
                            widget.tituloCursoAtual!.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.tituloCursoAtual!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _azulEscuro,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (widget.tituloProximaAula != null &&
                            widget.tituloProximaAula!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.tituloProximaAula!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: widget.onContinuar,
              style: FilledButton.styleFrom(
                backgroundColor: _azulPrincipal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'Continuar treinamento',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: widget.onVerTodos,
              child: const Text(
                'Ver todos os cursos',
                style: TextStyle(
                  color: _azulPrincipal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _possuiInformacaoCursoAtual() {
    return (widget.tituloCursoAtual != null &&
            widget.tituloCursoAtual!.trim().isNotEmpty) ||
        (widget.tituloProximaAula != null &&
            widget.tituloProximaAula!.trim().isNotEmpty);
  }

  Widget _buildCabecalho({
    required IconData icone,
    required String titulo,
    double paddingHorizontal = 18,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: _azulPrincipal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icone, color: _azulPrincipal, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                color: _azulEscuro,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemCursos() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.school_outlined, size: 42, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              'Nenhum curso disponível no momento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoVerTodos() {
    return Center(
      child: TextButton.icon(
        onPressed: widget.onVerTodos,
        icon: const Icon(Icons.grid_view_rounded, size: 19),
        label: const Text(
          'Ver todos os cursos',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: TextButton.styleFrom(foregroundColor: _azulPrincipal),
      ),
    );
  }
}
