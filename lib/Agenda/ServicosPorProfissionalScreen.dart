import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/* ============================================================
   SERVIÇOS POR PROFISSIONAL
   ============================================================ */

class ServicosPorProfissionalScreen extends StatefulWidget {
  const ServicosPorProfissionalScreen({super.key});

  @override
  State<ServicosPorProfissionalScreen> createState() =>
      _ServicosPorProfissionalScreenState();
}

class _ServicosPorProfissionalScreenState
    extends State<ServicosPorProfissionalScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _carregando = true;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> _inicializar() async {
    try {
      final companyId = await _descobrirCompanyId();

      if (!mounted) return;

      setState(() {
        _companyId = companyId;
        _carregando = false;
      });

      if (companyId == null || companyId.isEmpty) {
        _mensagem('Não foi possível identificar a empresa.');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem('Erro ao identificar empresa: $e');
    }
  }

  /* ==========================================================
     IDENTIFICAR EMPRESA
     ========================================================== */

  Future<String?> _descobrirCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) return null;

    try {
      final doc = await _fs.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        final companyId = (data['companyId'] ?? '').toString().trim();

        if (companyId.isNotEmpty) {
          return companyId;
        }
      }
    } catch (_) {}

    final email = (user.email ?? '').trim().toLowerCase();

    if (email.isEmpty) return null;

    final query =
        await _fs
            .collection('users')
            .where('emailKey', isEqualTo: email)
            .limit(1)
            .get();

    if (query.docs.isEmpty) return null;

    final data = query.docs.first.data();

    final companyId = (data['companyId'] ?? '').toString().trim();

    return companyId.isEmpty ? null : companyId;
  }

  /* ==========================================================
     CONSULTA DOS PROFISSIONAIS
     ========================================================== */

  Query<Map<String, dynamic>> _queryProfissionais() {
    return _fs
        .collection('users')
        .where('companyId', isEqualTo: _companyId)
        .where('profissionalAgenda', isEqualTo: true);
  }

  /* ==========================================================
     ABRIR SERVIÇOS
     ========================================================== */

  Future<void> _abrirServicos(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_companyId == null || _companyId!.isEmpty) {
      return;
    }

    final data = doc.data();

    final nome = (data['displayName'] ?? 'Profissional').toString().trim();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SelecionarServicosProfissionalScreen(
              companyId: _companyId!,
              profissionalId: doc.id,
              profissionalNome: nome.isEmpty ? 'Profissional' : nome,
            ),
      ),
    );
  }

  void _mensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: AgendaServicosStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AgendaServicosStyle.bg,
      body: Column(
        children: [
          _AgendaPageHeader(
            title: 'Serviços por profissional',
            subtitle:
                'Defina quais serviços cada profissional poderá realizar na Agenda Online.',
            icon: Icons.design_services_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),

          Expanded(
            child:
                _companyId == null || _companyId!.isEmpty
                    ? _empresaNaoIdentificada()
                    : Column(
                      children: [
                        _cabecalho(),

                        Expanded(
                          child: StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: _queryProfissionais().snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              if (snapshot.hasError) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Erro ao carregar profissionais:\n${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AgendaServicosStyle.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final profissionais =
                                  (snapshot.data?.docs ?? []).where((doc) {
                                    final data = doc.data();

                                    final ativo =
                                        (data['active'] ?? true) == true;

                                    final ativoAgenda =
                                        (data['ativoAgendamento'] ?? false) ==
                                        true;

                                    return ativo && ativoAgenda;
                                  }).toList();

                              profissionais.sort((a, b) {
                                final nomeA =
                                    (a.data()['displayName'] ?? '')
                                        .toString()
                                        .toLowerCase();

                                final nomeB =
                                    (b.data()['displayName'] ?? '')
                                        .toString()
                                        .toLowerCase();

                                return nomeA.compareTo(nomeB);
                              });

                              if (profissionais.isEmpty) {
                                return _estadoVazio();
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  32,
                                ),
                                itemCount: profissionais.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  return _cardProfissional(
                                    profissionais[index],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     CABEÇALHO
     ========================================================== */

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaServicosStyle.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AgendaIconBadge(
            icon: Icons.people_alt_outlined,
            color: AgendaServicosStyle.orange,
          ),

          SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selecione o profissional',
                  style: TextStyle(
                    color: AgendaServicosStyle.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Escolha um profissional para definir os serviços que ele poderá executar.',
                  style: TextStyle(
                    color: AgendaServicosStyle.muted,
                    fontSize: 13,
                    height: 1.35,
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

  /* ==========================================================
     CARD PROFISSIONAL
     ========================================================== */

  Widget _cardProfissional(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final nome = (data['displayName'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          _fs
              .collection('agenda_profissional_servicos')
              .doc(_idDocumentoVinculo(doc.id))
              .snapshots(),
      builder: (context, snapshot) {
        int quantidade = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final vinculo = snapshot.data!.data();
          final ids = vinculo?['servicosIds'];

          if (ids is List) {
            quantidade = ids.length;
          }
        }

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _abrirServicos(doc),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AgendaServicosStyle.border),
              ),
              child: Row(
                children: [
                  _AgendaIconBadge(
                    icon: Icons.person_outline,
                    color:
                        quantidade > 0
                            ? AgendaServicosStyle.primary
                            : AgendaServicosStyle.orange,
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nome.isEmpty ? 'Sem nome' : nome,
                          style: const TextStyle(
                            color: AgendaServicosStyle.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AgendaServicosStyle.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        _statusServicos(quantidade),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AgendaServicosStyle.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusServicos(int quantidade) {
    final configurado = quantidade > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color:
            configurado
                ? AgendaServicosStyle.green.withOpacity(0.10)
                : AgendaServicosStyle.muted.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        quantidade == 0
            ? 'Nenhum serviço configurado'
            : quantidade == 1
            ? '1 serviço configurado'
            : '$quantidade serviços configurados',
        style: TextStyle(
          color:
              configurado
                  ? AgendaServicosStyle.green
                  : AgendaServicosStyle.muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _idDocumentoVinculo(String profissionalId) {
    return '${_companyId}_$profissionalId';
  }

  /* ==========================================================
     ESTADOS
     ========================================================== */

  Widget _estadoVazio() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AgendaIconBadgeLarge(
              icon: Icons.people_outline,
              color: AgendaServicosStyle.primary,
            ),
            SizedBox(height: 18),
            Text(
              'Nenhum profissional disponível',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaServicosStyle.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Cadastre um profissional e ative a opção "Ativo para agendamento".',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaServicosStyle.muted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empresaNaoIdentificada() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Não foi possível identificar a empresa.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AgendaServicosStyle.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/* ============================================================
   SELECIONAR SERVIÇOS
   ============================================================ */

class SelecionarServicosProfissionalScreen extends StatefulWidget {
  final String companyId;
  final String profissionalId;
  final String profissionalNome;

  const SelecionarServicosProfissionalScreen({
    super.key,
    required this.companyId,
    required this.profissionalId,
    required this.profissionalNome,
  });

  @override
  State<SelecionarServicosProfissionalScreen> createState() =>
      _SelecionarServicosProfissionalScreenState();
}

class _SelecionarServicosProfissionalScreenState
    extends State<SelecionarServicosProfissionalScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _carregando = true;
  bool _salvando = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _servicos = [];

  final Set<String> _servicosSelecionados = {};

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> _inicializar() async {
    try {
      await Future.wait([_carregarServicos(), _carregarVinculos()]);

      if (!mounted) return;

      setState(() {
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem('Erro ao carregar serviços: $e');
    }
  }

  /* ==========================================================
     SERVIÇOS
     ========================================================== */

  Future<void> _carregarServicos() async {
    final query =
        await _fs
            .collection('servicos')
            .where('companyId', isEqualTo: widget.companyId)
            .get();

    final servicos =
        query.docs.where((doc) {
          final data = doc.data();

          return (data['disponivelAgendamento'] ?? false) == true;
        }).toList();

    servicos.sort((a, b) {
      final nomeA = (a.data()['nome'] ?? '').toString().toLowerCase();

      final nomeB = (b.data()['nome'] ?? '').toString().toLowerCase();

      return nomeA.compareTo(nomeB);
    });

    _servicos = servicos;
  }

  Future<void> _carregarVinculos() async {
    final doc =
        await _fs
            .collection('agenda_profissional_servicos')
            .doc(_idDocumentoVinculo())
            .get();

    if (!doc.exists) return;

    final data = doc.data();

    if (data == null) return;

    final ids = data['servicosIds'];

    if (ids is List) {
      _servicosSelecionados.addAll(ids.map((e) => e.toString()));
    }
  }

  /* ==========================================================
     SALVAR
     ========================================================== */

  Future<void> _salvar() async {
    debugPrint('>>>>>>>> ENTROU NO NOVO _salvar() <<<<<<<<');
    if (_salvando) return;

    setState(() {
      _salvando = true;
    });

    try {
      /*
       * 1. Lê o cadastro atual do profissional.
       *
       * Não usamos apenas widget.profissionalNome porque queremos
       * publicar o nome e o status atuais existentes em "users".
       */
      final profissionalRef = _fs
          .collection('users')
          .doc(widget.profissionalId);

      final profissionalDoc = await profissionalRef.get();

      if (!profissionalDoc.exists) {
        throw Exception('O cadastro do profissional não foi encontrado.');
      }

      final profissionalData = profissionalDoc.data() ?? <String, dynamic>{};

      /*
       * Segurança adicional:
       * confirma que o profissional pertence à empresa atual.
       */
      final companyIdProfissional =
          (profissionalData['companyId'] ?? '').toString().trim();

      if (companyIdProfissional != widget.companyId) {
        throw Exception('O profissional não pertence à empresa informada.');
      }

      final nomeProfissional =
          (profissionalData['displayName'] ?? widget.profissionalNome)
              .toString()
              .trim();

      /*
       * Mantemos a mesma regra usada na tela:
       *
       * - active ausente é tratado como true;
       * - ativoAgendamento precisa ser true;
       * - profissionalAgenda precisa ser true.
       */
      final ativo = (profissionalData['active'] ?? true) == true;

      final ativoAgendamento =
          (profissionalData['ativoAgendamento'] ?? false) == true;

      final profissionalAgenda =
          (profissionalData['profissionalAgenda'] ?? false) == true;

      /*
       * Ordenamos os IDs antes de salvar para manter o documento
       * previsível e facilitar conferência no Firestore.
       */
      final servicosIds = _servicosSelecionados.toList()..sort();

      /*
       * Documento interno já utilizado pelo sistema.
       */
      final vinculoRef = _fs
          .collection('agenda_profissional_servicos')
          .doc(_idDocumentoVinculo());

      final vinculoAtual = await vinculoRef.get();

      /*
       * Documento público utilizado pela página de agendamento.
       *
       * Estrutura:
       *
       * agenda_profissionais_publicos
       *   /{companyId}
       *     /profissionais
       *       /{profissionalId}
       */
      final publicoRef = _fs
          .collection('agenda_profissionais_publicos')
          .doc(widget.companyId)
          .collection('profissionais')
          .doc(widget.profissionalId);

      final publicoAtual = await publicoRef.get();

      final batch = _fs.batch();

      /* --------------------------------------------------------
         VÍNCULO INTERNO
         -------------------------------------------------------- */

      final dadosVinculo = <String, dynamic>{
        'companyId': widget.companyId,
        'profissionalId': widget.profissionalId,
        'servicosIds': servicosIds,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      };

      if (!vinculoAtual.exists) {
        dadosVinculo['createdAt'] = FieldValue.serverTimestamp();
      }

      batch.set(vinculoRef, dadosVinculo, SetOptions(merge: true));

      /* --------------------------------------------------------
         PROJEÇÃO PÚBLICA
         -------------------------------------------------------- */

      debugPrint('==========================================');
      debugPrint('AGENDA - PUBLICAÇÃO DO PROFISSIONAL');
      debugPrint('companyId: ${widget.companyId}');
      debugPrint('profissionalId: ${widget.profissionalId}');
      debugPrint('nome: $nomeProfissional');
      debugPrint('active bruto: ${profissionalData['active']}');
      debugPrint('ativo calculado: $ativo');
      debugPrint(
        'ativoAgendamento bruto: ${profissionalData['ativoAgendamento']}',
      );
      debugPrint('ativoAgendamento calculado: $ativoAgendamento');
      debugPrint(
        'profissionalAgenda bruto: ${profissionalData['profissionalAgenda']}',
      );
      debugPrint('profissionalAgenda calculado: $profissionalAgenda');
      debugPrint('servicosIds: $servicosIds');
      debugPrint('quantidade serviços: ${servicosIds.length}');
      debugPrint('==========================================');

      final devePublicar =
          ativo &&
          ativoAgendamento &&
          profissionalAgenda &&
          servicosIds.isNotEmpty;

      if (devePublicar) {
        debugPrint('>>> CRIANDO/ATUALIZANDO PROFISSIONAL PÚBLICO');
        final dadosPublicos = <String, dynamic>{
          'companyId': widget.companyId,
          'profissionalId': widget.profissionalId,
          'nome': nomeProfissional.isEmpty ? 'Profissional' : nomeProfissional,
          'servicosIds': servicosIds,
          'ativo': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (!publicoAtual.exists) {
          dadosPublicos['createdAt'] = FieldValue.serverTimestamp();
        }

        batch.set(publicoRef, dadosPublicos, SetOptions(merge: true));
      } else {
        /*
         * Se:
         *
         * - o profissional estiver inativo;
         * - não estiver ativo para agendamento;
         * - não for mais profissional da agenda;
         * - ou ficar sem nenhum serviço;
         *
         * ele não deve continuar disponível publicamente.
         */
        debugPrint('>>> NÃO PUBLICANDO PROFISSIONAL');
        debugPrint('>>> Documento público será excluído.');

        batch.delete(publicoRef);
      }

      /*
       * As duas alterações são confirmadas juntas.
       */
      debugPrint('>>> Executando batch.commit()...');
      await batch.commit();
      debugPrint('>>> batch.commit() CONCLUÍDO');

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      _mensagem('Erro ao salvar serviços: $e');
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  String _idDocumentoVinculo() {
    return '${widget.companyId}_${widget.profissionalId}';
  }

  void _selecionarTodos() {
    setState(() {
      _servicosSelecionados.clear();

      _servicosSelecionados.addAll(_servicos.map((doc) => doc.id));
    });
  }

  void _limparSelecao() {
    setState(() {
      _servicosSelecionados.clear();
    });
  }

  void _mensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgendaServicosStyle.bg,
      body: Column(
        children: [
          _AgendaPageHeader(
            title: 'Serviços do profissional',
            subtitle:
                'Selecione os serviços realizados por ${widget.profissionalNome}.',
            icon: Icons.design_services_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),

          Expanded(
            child:
                _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _buildConteudo(),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudo() {
    return Column(
      children: [
        _cabecalhoProfissional(),

        if (_servicos.isNotEmpty) _barraSelecao(),

        Expanded(
          child:
              _servicos.isEmpty
                  ? _estadoSemServicos()
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                    itemCount: _servicos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _cardServico(_servicos[index]);
                    },
                  ),
        ),

        if (_servicos.isNotEmpty) _barraSalvar(),
      ],
    );
  }

  /* ==========================================================
     PROFISSIONAL
     ========================================================== */

  Widget _cabecalhoProfissional() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaServicosStyle.border),
      ),
      child: Row(
        children: [
          const _AgendaIconBadge(
            icon: Icons.person_outline,
            color: AgendaServicosStyle.primary,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.profissionalNome,
                  style: const TextStyle(
                    color: AgendaServicosStyle.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '${_servicosSelecionados.length} de ${_servicos.length} serviços selecionados',
                  style: const TextStyle(
                    color: AgendaServicosStyle.muted,
                    fontSize: 13,
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

  /* ==========================================================
     BARRA DE AÇÕES
     ========================================================== */

  Widget _barraSelecao() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Selecione os serviços realizados:',
              style: TextStyle(
                color: AgendaServicosStyle.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          PopupMenuButton<String>(
            tooltip: 'Opções',
            color: Colors.white,
            onSelected: (value) {
              if (value == 'todos') {
                _selecionarTodos();
              }

              if (value == 'limpar') {
                _limparSelecao();
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(
                    value: 'todos',
                    child: Row(
                      children: [
                        Icon(
                          Icons.done_all_outlined,
                          color: AgendaServicosStyle.primary,
                        ),
                        SizedBox(width: 10),
                        Text('Selecionar todos'),
                      ],
                    ),
                  ),

                  PopupMenuItem(
                    value: 'limpar',
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_done_outlined,
                          color: AgendaServicosStyle.muted,
                        ),
                        SizedBox(width: 10),
                        Text('Limpar seleção'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     SERVIÇO
     ========================================================== */

  Widget _cardServico(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final nome = (data['nome'] ?? 'Serviço').toString();

    final descricao = (data['descricao'] ?? '').toString().trim();

    final selecionado = _servicosSelecionados.contains(doc.id);

    final valor = _numero(data['valorUnitario']);

    final duracao = _inteiro(data['duracaoMinutos'], padrao: 60);

    final intervalo = _inteiro(
      data['intervaloAposAtendimentoMinutos'],
      padrao: 0,
    );

    final exibirPreco = (data['exibirPrecoAgenda'] ?? true) == true;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          setState(() {
            if (selecionado) {
              _servicosSelecionados.remove(doc.id);
            } else {
              _servicosSelecionados.add(doc.id);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                selecionado
                    ? AgendaServicosStyle.primary.withOpacity(0.035)
                    : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color:
                  selecionado
                      ? AgendaServicosStyle.primary
                      : AgendaServicosStyle.border,
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selecionado,
                activeColor: AgendaServicosStyle.primary,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _servicosSelecionados.add(doc.id);
                    } else {
                      _servicosSelecionados.remove(doc.id);
                    }
                  });
                },
              ),

              const SizedBox(width: 5),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        color: AgendaServicosStyle.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 4),

                      Text(
                        descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AgendaServicosStyle.muted,
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 9),

                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _infoTag(
                          Icons.schedule_outlined,
                          '$duracao min',
                          AgendaServicosStyle.blue,
                        ),

                        if (intervalo > 0)
                          _infoTag(
                            Icons.hourglass_bottom_outlined,
                            '+$intervalo min',
                            AgendaServicosStyle.orange,
                          ),

                        if (exibirPreco)
                          _infoTag(
                            Icons.payments_outlined,
                            _formatarMoeda(valor),
                            AgendaServicosStyle.green,
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

  Widget _infoTag(IconData icon, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cor),

          const SizedBox(width: 5),

          Text(
            texto,
            style: TextStyle(
              color: cor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     SALVAR
     ========================================================== */

  Widget _barraSalvar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AgendaServicosStyle.bg,
          border: Border(top: BorderSide(color: AgendaServicosStyle.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AgendaServicosStyle.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _salvando ? null : _salvar,
            icon:
                _salvando
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.save_outlined),
            label: Text(
              _salvando ? 'Salvando...' : 'Salvar serviços',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     SEM SERVIÇOS
     ========================================================== */

  Widget _estadoSemServicos() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AgendaIconBadgeLarge(
              icon: Icons.design_services_outlined,
              color: AgendaServicosStyle.orange,
            ),

            SizedBox(height: 18),

            Text(
              'Nenhum serviço disponível',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaServicosStyle.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),

            SizedBox(height: 7),

            Text(
              'Cadastre um serviço e marque a opção "Disponível para agendamento".',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaServicosStyle.muted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ==========================================================
     AUXILIARES
     ========================================================== */

  double _numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    if (valor is String) {
      return double.tryParse(valor.replaceAll('.', '').replaceAll(',', '.')) ??
          0;
    }

    return 0;
  }

  int _inteiro(dynamic valor, {required int padrao}) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? padrao;
  }

  String _formatarMoeda(double valor) {
    final partes = valor.toStringAsFixed(2).split('.');

    final inteiro = partes[0];
    final decimal = partes[1];

    final buffer = StringBuffer();

    for (int i = 0; i < inteiro.length; i++) {
      if (i > 0 && (inteiro.length - i) % 3 == 0) {
        buffer.write('.');
      }

      buffer.write(inteiro[i]);
    }

    return 'R\$ ${buffer.toString()},$decimal';
  }
}

/* ============================================================
   HEADER PADRÃO DA AGENDA
   ============================================================ */

class _AgendaPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  const _AgendaPageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AgendaServicosStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        20,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _AgendaHeaderButton(
                icon: Icons.arrow_back_rounded,
                onTap: onBack,
              ),

              Expanded(
                child: Center(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 42),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.92), size: 19),

              const SizedBox(width: 7),

              Flexible(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 13.5,
                    height: 1.30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   COMPONENTES VISUAIS
   ============================================================ */

class _AgendaHeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AgendaHeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _AgendaIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 25),
    );
  }
}

class _AgendaIconBadgeLarge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaIconBadgeLarge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(icon, color: color, size: 34),
    );
  }
}

/* ============================================================
   STYLE
   ============================================================ */

class AgendaServicosStyle {
  static const Color primary = Color(0xFF5B21B6);

  static const Color primaryDark = Color(0xFF3B0CA3);

  static const Color orange = Color(0xFFF97316);

  static const Color green = Color(0xFF16A34A);

  static const Color blue = Color(0xFF2563EB);

  static const Color purple = Color(0xFF7C3AED);

  static const Color bg = Color(0xFFF8FAFC);

  static const Color text = Color(0xFF111827);

  static const Color muted = Color(0xFF64748B);

  static const Color border = Color(0xFFE5E7EB);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
