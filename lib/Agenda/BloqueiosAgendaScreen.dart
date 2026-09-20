import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BloqueiosAgendaScreen extends StatefulWidget {
  const BloqueiosAgendaScreen({super.key});

  @override
  State<BloqueiosAgendaScreen> createState() => _BloqueiosAgendaScreenState();
}

class _BloqueiosAgendaScreenState extends State<BloqueiosAgendaScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _carregando = true;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

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

      setState(() => _carregando = false);

      _mensagem('Erro ao identificar empresa: $e');
    }
  }

  Future<String?> _descobrirCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) return null;

    try {
      final doc = await _fs.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final companyId = (doc.data()?['companyId'] ?? '').toString().trim();

        if (companyId.isNotEmpty) return companyId;
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

    final companyId =
        (query.docs.first.data()['companyId'] ?? '').toString().trim();

    return companyId.isEmpty ? null : companyId;
  }

  Query<Map<String, dynamic>> _queryBloqueios() {
    return _fs
        .collection('agenda_bloqueios')
        .where('companyId', isEqualTo: _companyId);
  }

  Future<void> _novoBloqueio() async {
    if (_companyId == null || _companyId!.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CadastroBloqueioAgendaScreen(companyId: _companyId!),
      ),
    );
  }

  Future<void> _editarBloqueio(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_companyId == null || _companyId!.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => CadastroBloqueioAgendaScreen(
              companyId: _companyId!,
              bloqueioId: doc.id,
              dadosIniciais: doc.data(),
            ),
      ),
    );
  }

  Future<void> _alterarAtivo(String id, bool ativo) async {
    try {
      await _fs.collection('agenda_bloqueios').doc(id).update({
        'ativo': ativo,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      });
    } catch (e) {
      _mensagem('Erro ao alterar bloqueio: $e');
    }
  }

  Future<void> _excluir(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir bloqueio?'),
          content: const Text(
            'O bloqueio será removido da agenda. Esta operação não poderá ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await doc.reference.delete();

      _mensagem('Bloqueio excluído.');
    } catch (e) {
      _mensagem('Erro ao excluir bloqueio: $e');
    }
  }

  void _mensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  DateTime? _timestampParaData(dynamic valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is DateTime) return valor;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: AgendaBloqueiosStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AgendaBloqueiosStyle.bg,
      floatingActionButton:
          _companyId == null || _companyId!.isEmpty
              ? null
              : FloatingActionButton.extended(
                backgroundColor: AgendaBloqueiosStyle.orange,
                foregroundColor: Colors.white,
                onPressed: _novoBloqueio,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Novo bloqueio',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      body: Column(
        children: [
          _AgendaBloqueiosHeader(
            title: 'Bloqueios da agenda',
            subtitle:
                'Cadastre folgas, compromissos e outros períodos indisponíveis.',
            icon: Icons.event_busy_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child:
                _companyId == null || _companyId!.isEmpty
                    ? const Center(
                      child: Text(
                        'Não foi possível identificar a empresa.',
                        style: TextStyle(
                          color: AgendaBloqueiosStyle.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                    : _listaBloqueios(),
          ),
        ],
      ),
    );
  }

  Widget _listaBloqueios() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _queryBloqueios().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Erro ao carregar bloqueios:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AgendaBloqueiosStyle.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        final docs = [...(snapshot.data?.docs ?? [])];

        docs.sort((a, b) {
          final inicioA =
              _timestampParaData(a.data()['dataInicio']) ?? DateTime(2100);
          final inicioB =
              _timestampParaData(b.data()['dataInicio']) ?? DateTime(2100);

          return inicioA.compareTo(inicioB);
        });

        if (docs.isEmpty) {
          return _estadoVazio();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, index) => _cardBloqueio(docs[index]),
        );
      },
    );
  }

  Widget _cardBloqueio(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final todosProfissionais = data['todosProfissionais'] == true;

    final profissionalNome =
        todosProfissionais
            ? 'Todos os profissionais'
            : (data['profissionalNome'] ?? 'Profissional').toString();

    final motivo = (data['motivo'] ?? 'Bloqueio').toString();
    final observacao = (data['observacao'] ?? '').toString().trim();

    final diaInteiro = data['diaInteiro'] == true;
    final ativo = (data['ativo'] ?? true) == true;

    final inicio = _timestampParaData(data['dataInicio']);
    final fim = _timestampParaData(data['dataFim']);

    String periodo = 'Período não informado';

    if (inicio != null) {
      if (diaInteiro) {
        periodo = '${DateFormat('dd/MM/yyyy').format(inicio)} • Dia inteiro';
      } else if (fim != null) {
        final mesmaData =
            inicio.year == fim.year &&
            inicio.month == fim.month &&
            inicio.day == fim.day;

        if (mesmaData) {
          periodo =
              '${DateFormat('dd/MM/yyyy').format(inicio)} • '
              '${DateFormat('HH:mm').format(inicio)} - '
              '${DateFormat('HH:mm').format(fim)}';
        } else {
          periodo =
              '${DateFormat('dd/MM HH:mm').format(inicio)} até '
              '${DateFormat('dd/MM HH:mm').format(fim)}';
        }
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _editarBloqueio(doc),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color:
                  ativo
                      ? AgendaBloqueiosStyle.border
                      : AgendaBloqueiosStyle.muted.withOpacity(.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AgendaBloqueioIconBadge(
                icon:
                    todosProfissionais
                        ? Icons.groups_outlined
                        : diaInteiro
                        ? Icons.event_busy_outlined
                        : Icons.schedule_outlined,
                color:
                    ativo
                        ? todosProfissionais
                            ? AgendaBloqueiosStyle.purple
                            : AgendaBloqueiosStyle.orange
                        : AgendaBloqueiosStyle.muted,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            motivo,
                            style: TextStyle(
                              color:
                                  ativo
                                      ? AgendaBloqueiosStyle.text
                                      : AgendaBloqueiosStyle.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _statusBadge(ativo),
                      ],
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        Icon(
                          todosProfissionais
                              ? Icons.groups_outlined
                              : Icons.person_outline,
                          size: 15,
                          color:
                              todosProfissionais
                                  ? AgendaBloqueiosStyle.orange
                                  : AgendaBloqueiosStyle.primary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            profissionalNome,
                            style: TextStyle(
                              color:
                                  todosProfissionais
                                      ? AgendaBloqueiosStyle.orange
                                      : AgendaBloqueiosStyle.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      periodo,
                      style: const TextStyle(
                        color: AgendaBloqueiosStyle.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    if (observacao.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        observacao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AgendaBloqueiosStyle.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              PopupMenuButton<String>(
                tooltip: 'Opções',
                onSelected: (valor) {
                  if (valor == 'editar') {
                    _editarBloqueio(doc);
                  } else if (valor == 'ativo') {
                    _alterarAtivo(doc.id, !ativo);
                  } else if (valor == 'excluir') {
                    _excluir(doc);
                  }
                },
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined),
                            SizedBox(width: 10),
                            Text('Editar'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ativo',
                        child: Row(
                          children: [
                            Icon(
                              ativo
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            const SizedBox(width: 10),
                            Text(ativo ? 'Desativar' : 'Ativar'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red),
                            SizedBox(width: 10),
                            Text(
                              'Excluir',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(bool ativo) {
    final cor = ativo ? AgendaBloqueiosStyle.green : AgendaBloqueiosStyle.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ativo ? 'Ativo' : 'Inativo',
        style: TextStyle(
          color: cor,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _estadoVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AgendaBloqueioIconBadgeLarge(
              icon: Icons.event_available_outlined,
              color: AgendaBloqueiosStyle.green,
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhum bloqueio cadastrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaBloqueiosStyle.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Use bloqueios para impedir agendamentos em folgas, reuniões ou outros períodos indisponíveis.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AgendaBloqueiosStyle.muted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _novoBloqueio,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo bloqueio'),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   CADASTRO / EDIÇÃO
   ============================================================ */

class CadastroBloqueioAgendaScreen extends StatefulWidget {
  final String companyId;
  final String? bloqueioId;
  final Map<String, dynamic>? dadosIniciais;

  const CadastroBloqueioAgendaScreen({
    super.key,
    required this.companyId,
    this.bloqueioId,
    this.dadosIniciais,
  });

  bool get editando => bloqueioId != null;

  @override
  State<CadastroBloqueioAgendaScreen> createState() =>
      _CadastroBloqueioAgendaScreenState();
}

class _CadastroBloqueioAgendaScreenState
    extends State<CadastroBloqueioAgendaScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _motivoCtrl = TextEditingController();
  final TextEditingController _observacaoCtrl = TextEditingController();

  static const String _todosProfissionaisId = '__TODOS__';

  bool _carregando = true;
  bool _salvando = false;
  bool _diaInteiro = false;
  bool _ativo = true;

  String? _profissionalId;
  String _profissionalNome = '';

  DateTime _data = DateTime.now();
  TimeOfDay _horaInicio = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _horaFim = const TimeOfDay(hour: 9, minute: 0);

  List<Map<String, dynamic>> _profissionais = [];

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _observacaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    try {
      await _carregarProfissionais();
      _carregarDadosIniciais();

      if (!mounted) return;

      setState(() => _carregando = false);
    } catch (e) {
      if (!mounted) return;

      setState(() => _carregando = false);

      _mensagem('Erro ao carregar cadastro: $e');
    }
  }

  Future<void> _carregarProfissionais() async {
    final snapshot =
        await _fs
            .collection('users')
            .where('companyId', isEqualTo: widget.companyId)
            .where('profissionalAgenda', isEqualTo: true)
            .get();

    final lista =
        snapshot.docs
            .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
            .where((data) {
              final ativo = (data['active'] ?? true) == true;
              final ativoAgenda = (data['ativoAgendamento'] ?? false) == true;

              return ativo && ativoAgenda;
            })
            .toList();

    lista.sort((a, b) {
      final aNome = (a['displayName'] ?? '').toString().toLowerCase();

      final bNome = (b['displayName'] ?? '').toString().toLowerCase();

      return aNome.compareTo(bNome);
    });

    _profissionais = lista;
  }

  void _carregarDadosIniciais() {
    final dados = widget.dadosIniciais;

    if (dados == null) return;

    final todosProfissionais = dados['todosProfissionais'] == true;

    if (todosProfissionais) {
      _profissionalId = _todosProfissionaisId;
      _profissionalNome = 'Todos os profissionais';
    } else {
      _profissionalId = (dados['profissionalId'] ?? '').toString();

      _profissionalNome = (dados['profissionalNome'] ?? '').toString();
    }

    _motivoCtrl.text = (dados['motivo'] ?? '').toString();

    _observacaoCtrl.text = (dados['observacao'] ?? '').toString();

    _diaInteiro = dados['diaInteiro'] == true;
    _ativo = (dados['ativo'] ?? true) == true;

    final inicio = _paraDateTime(dados['dataInicio']);
    final fim = _paraDateTime(dados['dataFim']);

    if (inicio != null) {
      _data = DateTime(inicio.year, inicio.month, inicio.day);

      _horaInicio = TimeOfDay(hour: inicio.hour, minute: inicio.minute);
    }

    if (fim != null && !_diaInteiro) {
      _horaFim = TimeOfDay(hour: fim.hour, minute: fim.minute);
    }
  }

  DateTime? _paraDateTime(dynamic valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is DateTime) return valor;
    return null;
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      locale: const Locale('pt', 'BR'),
    );

    if (data == null) return;

    setState(() => _data = data);
  }

  Future<void> _selecionarHoraInicio() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaInicio,
    );

    if (hora == null) return;

    setState(() => _horaInicio = hora);
  }

  Future<void> _selecionarHoraFim() async {
    final hora = await showTimePicker(context: context, initialTime: _horaFim);

    if (hora == null) return;

    setState(() => _horaFim = hora);
  }

  DateTime _combinar(DateTime data, TimeOfDay hora) {
    return DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    if (_profissionalId == null || _profissionalId!.trim().isEmpty) {
      _mensagem('Selecione o profissional ou todos os profissionais.');
      return;
    }

    if (_motivoCtrl.text.trim().isEmpty) {
      _mensagem('Informe o motivo do bloqueio.');
      return;
    }

    late DateTime inicio;
    late DateTime fim;

    if (_diaInteiro) {
      inicio = DateTime(_data.year, _data.month, _data.day);

      /*
       * O final é exclusivo.
       *
       * Exemplo:
       *
       * início = 09/09/2026 00:00
       * fim    = 10/09/2026 00:00
       *
       * Isso facilita bastante a validação de
       * sobreposição no motor de disponibilidade.
       */
      fim = inicio.add(const Duration(days: 1));
    } else {
      inicio = _combinar(_data, _horaInicio);

      fim = _combinar(_data, _horaFim);

      if (!fim.isAfter(inicio)) {
        _mensagem('O horário final deve ser posterior ao horário inicial.');
        return;
      }
    }

    final todosProfissionais = _profissionalId == _todosProfissionaisId;

    final profissionalIdBanco = todosProfissionais ? null : _profissionalId;

    final profissionalNomeBanco =
        todosProfissionais ? 'Todos os profissionais' : _profissionalNome;

    setState(() => _salvando = true);

    try {
      final dados = <String, dynamic>{
        'companyId': widget.companyId,

        /*
         * Informa explicitamente se o bloqueio
         * deve valer para toda a equipe.
         */
        'todosProfissionais': todosProfissionais,

        /*
         * Quando for bloqueio geral, não gravamos
         * um profissional específico.
         */
        'profissionalId': profissionalIdBanco,

        'profissionalNome': profissionalNomeBanco,

        'dataInicio': Timestamp.fromDate(inicio),
        'dataFim': Timestamp.fromDate(fim),

        'diaInteiro': _diaInteiro,

        'motivo': _motivoCtrl.text.trim(),
        'observacao': _observacaoCtrl.text.trim(),

        'ativo': _ativo,

        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      };

      final CollectionReference<Map<String, dynamic>> colecao = _fs.collection(
        'agenda_bloqueios',
      );

      if (widget.editando) {
        await colecao
            .doc(widget.bloqueioId)
            .set(dados, SetOptions(merge: true));
      } else {
        dados['createdAt'] = FieldValue.serverTimestamp();

        dados['createdBy'] = _auth.currentUser?.uid;

        await colecao.add(dados);
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      _mensagem('Erro ao salvar bloqueio: $e');
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  void _mensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgendaBloqueiosStyle.bg,
      body: Column(
        children: [
          _AgendaBloqueiosHeader(
            title: widget.editando ? 'Editar bloqueio' : 'Novo bloqueio',
            subtitle:
                widget.editando
                    ? 'Altere o período indisponível.'
                    : 'Informe quando um profissional ou toda a equipe não poderá receber agendamentos.',
            icon: Icons.event_busy_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child:
                _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _formulario(),
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        _card(
          titulo: 'Quem será bloqueado?',
          icone: Icons.people_alt_outlined,
          child: DropdownButtonFormField<String>(
            value: _profissionalId,
            isExpanded: true,
            decoration: _decoracao(
              'Selecione',
              hint: 'Todos os profissionais ou um profissional',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: _todosProfissionaisId,
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      color: AgendaBloqueiosStyle.orange,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Todos os profissionais',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),

              ..._profissionais.map((profissional) {
                final id = profissional['id'].toString();

                final nome =
                    (profissional['displayName'] ?? 'Profissional').toString();

                return DropdownMenuItem<String>(
                  value: id,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: AgendaBloqueiosStyle.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(nome, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                );
              }),
            ],
            onChanged: (id) {
              if (id == null) return;

              setState(() {
                _profissionalId = id;

                if (id == _todosProfissionaisId) {
                  _profissionalNome = 'Todos os profissionais';
                } else {
                  final profissional = _profissionais.firstWhere(
                    (p) => p['id'] == id,
                  );

                  _profissionalNome =
                      (profissional['displayName'] ?? 'Profissional')
                          .toString();
                }
              });
            },
          ),
        ),

        const SizedBox(height: 12),

        _card(
          titulo: 'Período do bloqueio',
          icone: Icons.calendar_month_outlined,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Dia inteiro',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Impede qualquer agendamento neste dia.'),
                value: _diaInteiro,
                onChanged: (value) {
                  setState(() => _diaInteiro = value);
                },
              ),

              const SizedBox(height: 10),

              _campoSelecao(
                label: 'Data',
                valor: DateFormat('dd/MM/yyyy').format(_data),
                icon: Icons.calendar_today_outlined,
                onTap: _selecionarData,
              ),

              if (!_diaInteiro) ...[
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _campoSelecao(
                        label: 'Início',
                        valor: _horaInicio.format(context),
                        icon: Icons.schedule_outlined,
                        onTap: _selecionarHoraInicio,
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: _campoSelecao(
                        label: 'Fim',
                        valor: _horaFim.format(context),
                        icon: Icons.schedule_outlined,
                        onTap: _selecionarHoraFim,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        _card(
          titulo: 'Informações',
          icone: Icons.notes_outlined,
          child: Column(
            children: [
              TextFormField(
                controller: _motivoCtrl,
                decoration: _decoracao(
                  'Motivo',
                  hint: 'Ex.: Folga, reunião, feriado, compromisso pessoal',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _observacaoCtrl,
                minLines: 3,
                maxLines: 5,
                decoration: _decoracao(
                  'Observação',
                  hint: 'Informações adicionais (opcional)',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),

        if (widget.editando) ...[
          const SizedBox(height: 12),

          _card(
            titulo: 'Situação',
            icone: Icons.toggle_on_outlined,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Bloqueio ativo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Bloqueios inativos não interferem na disponibilidade.',
              ),
              value: _ativo,
              onChanged: (value) {
                setState(() => _ativo = value);
              },
            ),
          ),
        ],

        const SizedBox(height: 22),

        SizedBox(
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AgendaBloqueiosStyle.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _salvando ? null : _salvar,
            icon:
                _salvando
                    ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.save_outlined),
            label: Text(
              _salvando
                  ? 'Salvando...'
                  : widget.editando
                  ? 'Salvar alterações'
                  : 'Salvar bloqueio',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({
    required String titulo,
    required IconData icone,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaBloqueiosStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: AgendaBloqueiosStyle.primary, size: 21),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(
                  color: AgendaBloqueiosStyle.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }

  Widget _campoSelecao({
    required String label,
    required String valor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoracao(label),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AgendaBloqueiosStyle.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                valor,
                style: const TextStyle(
                  color: AgendaBloqueiosStyle.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoracao(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFAFAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AgendaBloqueiosStyle.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AgendaBloqueiosStyle.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AgendaBloqueiosStyle.primary,
          width: 1.5,
        ),
      ),
    );
  }
}

/* ============================================================
   HEADER
   ============================================================ */

class _AgendaBloqueiosHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  const _AgendaBloqueiosHeader({
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
        gradient: AgendaBloqueiosStyle.gradient,
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
              Material(
                color: Colors.white.withOpacity(.16),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onBack,
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                ),
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
              Icon(icon, color: Colors.white.withOpacity(.92), size: 19),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.92),
                    fontSize: 13.5,
                    height: 1.3,
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

class _AgendaBloqueioIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaBloqueioIconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 25),
    );
  }
}

class _AgendaBloqueioIconBadgeLarge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AgendaBloqueioIconBadgeLarge({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(icon, color: color, size: 34),
    );
  }
}

/* ============================================================
   ESTILO
   ============================================================ */

class AgendaBloqueiosStyle {
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
