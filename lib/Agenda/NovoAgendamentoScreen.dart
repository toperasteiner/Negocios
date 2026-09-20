import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Seletores/SelecionarClienteSheet.dart';
import 'agenda_controller.dart';

class NovoAgendamentoScreen extends StatefulWidget {
  final AgendaAgendamento? agendamentoEdicao;

  const NovoAgendamentoScreen({super.key, this.agendamentoEdicao});

  @override
  State<NovoAgendamentoScreen> createState() => _NovoAgendamentoScreenState();
}

class _NovoAgendamentoScreenState extends State<NovoAgendamentoScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _observacaoCtrl = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  bool get _modoEdicao => widget.agendamentoEdicao != null;

  String? _companyId;

  // ==========================================================
  // CLIENTE
  // ==========================================================

  String? _clienteId;

  String _clienteNome = '';
  String _clienteTelefone = '';
  String _clienteWhatsapp = '';
  String _clienteEmail = '';

  // ==========================================================
  // SERVIÇO
  // ==========================================================

  List<Map<String, dynamic>> _servicos = [];

  String? _servicoId;
  String _servicoNome = '';

  double _valorServico = 0;

  int _duracaoMinutos = 60;
  int _intervaloAposAtendimentoMinutos = 0;

  // ==========================================================
  // PROFISSIONAL
  // ==========================================================

  List<Map<String, dynamic>> _profissionais = [];

  String? _profissionalId;
  String _profissionalNome = '';

  // ==========================================================
  // DATA / HORÁRIO
  // ==========================================================

  DateTime _data = DateTime.now();

  TimeOfDay? _horaInicio;

  static const int _intervaloGradeMinutos = 15;

  List<DateTime> _horariosDisponiveis = [];

  bool _carregandoHorarios = false;

  String? _mensagemHorarios;

  // ==========================================================
  // CARREGAMENTOS
  // ==========================================================

  bool _carregandoServicos = false;
  bool _carregandoProfissionais = false;

  // ==========================================================
  // CICLO DE VIDA
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _inicializar();
  }

  @override
  void dispose() {
    _observacaoCtrl.dispose();

    super.dispose();
  }

  // ==========================================================
  // INICIALIZAÇÃO
  // ==========================================================

  Future<void> _inicializar() async {
    try {
      final companyId = await _descobrirCompanyId();

      if (!mounted) {
        return;
      }

      if (companyId == null || companyId.isEmpty) {
        setState(() {
          _carregando = false;
        });

        _mensagem('Não foi possível identificar a empresa.');

        return;
      }

      _companyId = companyId;

      await _carregarServicos();

      /*
       * Se recebeu um agendamento,
       * estamos no modo de edição.
       */
      if (_modoEdicao) {
        await _carregarAgendamentoEdicao();
      }
    } catch (e) {
      _mensagem(
        _modoEdicao
            ? 'Erro ao carregar o agendamento: $e'
            : 'Erro ao carregar novo agendamento: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  // ==========================================================
  // CARREGAR DADOS DA EDIÇÃO
  // ==========================================================

  Future<void> _carregarAgendamentoEdicao() async {
    final agendamento = widget.agendamentoEdicao;

    if (agendamento == null) {
      return;
    }

    /*
     * Segurança:
     * não permite editar agendamento
     * pertencente a outra empresa.
     */
    if (agendamento.companyId.isNotEmpty &&
        agendamento.companyId != _companyId) {
      throw Exception('Este agendamento não pertence à empresa atual.');
    }

    // --------------------------------------------------------
    // CLIENTE
    // --------------------------------------------------------

    _clienteId = agendamento.clienteId;
    _clienteNome = agendamento.clienteNome;
    _clienteTelefone = agendamento.clienteTelefone;
    _clienteWhatsapp = agendamento.clienteWhatsapp;
    _clienteEmail = agendamento.clienteEmail;

    // --------------------------------------------------------
    // DATA
    // --------------------------------------------------------

    _data = DateTime(
      agendamento.inicio.year,
      agendamento.inicio.month,
      agendamento.inicio.day,
    );

    // --------------------------------------------------------
    // OBSERVAÇÃO
    // --------------------------------------------------------

    _observacaoCtrl.text = agendamento.observacao;

    // --------------------------------------------------------
    // SERVIÇO
    // --------------------------------------------------------

    final servicoExiste = _servicos.any(
      (item) => item['id'].toString() == agendamento.servicoId,
    );

    if (!servicoExiste) {
      throw Exception('O serviço deste agendamento não está mais disponível.');
    }

    await _selecionarServico(agendamento.servicoId);

    // --------------------------------------------------------
    // PROFISSIONAL
    // --------------------------------------------------------

    final profissionalExiste = _profissionais.any(
      (item) => item['id'].toString() == agendamento.profissionalId,
    );

    if (!profissionalExiste) {
      throw Exception(
        'O profissional deste agendamento não está mais '
        'disponível para o serviço.',
      );
    }

    await _selecionarProfissional(agendamento.profissionalId);

    if (!mounted) {
      return;
    }

    /*
     * Restauramos o horário original depois que
     * os horários disponíveis foram recalculados.
     */
    setState(() {
      _horaInicio = TimeOfDay(
        hour: agendamento.inicio.hour,
        minute: agendamento.inicio.minute,
      );
    });
  }

  // ==========================================================
  // EMPRESA
  // ==========================================================

  Future<String?> _descobrirCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    try {
      final doc = await _fs.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final companyId = (doc.data()?['companyId'] ?? '').toString().trim();

        if (companyId.isNotEmpty) {
          return companyId;
        }
      }
    } catch (_) {
      // tenta localização por e-mail
    }

    final email = (user.email ?? '').trim().toLowerCase();

    if (email.isEmpty) {
      return null;
    }

    final query =
        await _fs
            .collection('users')
            .where('emailKey', isEqualTo: email)
            .limit(1)
            .get();

    if (query.docs.isEmpty) {
      return null;
    }

    final companyId =
        (query.docs.first.data()['companyId'] ?? '').toString().trim();

    if (companyId.isEmpty) {
      return null;
    }

    return companyId;
  }

  // ==========================================================
  // CLIENTES
  // ==========================================================

  Future<void> _selecionarCliente() async {
    final escolhido = await showModalBottomSheet<ClienteSelecionado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SelecionarClienteSheet(),
    );

    if (escolhido == null) {
      return;
    }

    await _carregarClienteSelecionado(escolhido);
  }

  Future<void> _carregarClienteSelecionado(ClienteSelecionado escolhido) async {
    try {
      final doc = await _fs.collection('clientes').doc(escolhido.id).get();

      if (!doc.exists) {
        _mensagem('Cliente não encontrado.');

        return;
      }

      final dados = doc.data() ?? <String, dynamic>{};

      final clienteCompanyId = (dados['companyId'] ?? '').toString().trim();

      if (clienteCompanyId != _companyId) {
        _mensagem('Este cliente não pertence à empresa atual.');

        return;
      }

      if (!mounted) {
        return;
      }

      final nome = (dados['nome'] ?? escolhido.nome).toString().trim();

      setState(() {
        _clienteId = escolhido.id;

        _clienteNome = nome.isEmpty ? escolhido.nome : nome;

        _clienteTelefone = (dados['telefone'] ?? '').toString().trim();

        _clienteWhatsapp = (dados['whatsapp'] ?? '').toString().trim();

        _clienteEmail = (dados['email'] ?? '').toString().trim();
      });
    } catch (e) {
      _mensagem('Erro ao carregar cliente: $e');
    }
  }

  // ==========================================================
  // SERVIÇOS
  // ==========================================================

  Future<void> _carregarServicos() async {
    final companyId = _companyId;

    if (companyId == null || companyId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _carregandoServicos = true;
      });
    }

    try {
      final snapshot =
          await _fs
              .collection('servicos')
              .where('companyId', isEqualTo: companyId)
              .get();

      final lista =
          snapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .where((servico) {
                return servico['disponivelAgendamento'] == true;
              })
              .toList();

      lista.sort((a, b) {
        final nomeA = (a['nome'] ?? '').toString().toLowerCase();

        final nomeB = (b['nome'] ?? '').toString().toLowerCase();

        return nomeA.compareTo(nomeB);
      });

      _servicos = lista;
    } catch (e) {
      _mensagem('Erro ao carregar serviços: $e');
    } finally {
      if (mounted) {
        setState(() {
          _carregandoServicos = false;
        });
      }
    }
  }

  Future<void> _selecionarServico(String? id) async {
    if (id == null) {
      return;
    }

    final servico = _servicos.firstWhere((item) => item['id'].toString() == id);

    final valor = _converterDouble(
      servico['precoVenda'] ??
          servico['valorVenda'] ??
          servico['valorUnitario'] ??
          servico['preco'] ??
          servico['valor'],
    );

    final duracao = _converterInt(servico['duracaoMinutos'], padrao: 60);

    final intervalo = _converterInt(
      servico['intervaloAposAtendimentoMinutos'],
      padrao: 0,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _servicoId = id;

      _servicoNome = (servico['nome'] ?? '').toString().trim();

      _valorServico = valor;
      _duracaoMinutos = duracao;

      _intervaloAposAtendimentoMinutos = intervalo;

      /*
       * Ao alterar o serviço,
       * o profissional anterior pode não
       * executar o novo serviço.
       */
      _profissionalId = null;
      _profissionalNome = '';

      _profissionais = [];

      _horaInicio = null;

      _horariosDisponiveis = [];

      _mensagemHorarios = null;
    });

    await _carregarProfissionais();
  }

  // ==========================================================
  // PROFISSIONAIS
  // ==========================================================

  Future<void> _carregarProfissionais() async {
    final companyId = _companyId;
    final servicoId = _servicoId;

    if (companyId == null ||
        companyId.isEmpty ||
        servicoId == null ||
        servicoId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _carregandoProfissionais = true;
      });
    }

    try {
      final snapshot =
          await _fs
              .collection('agenda_profissional_servicos')
              .where('companyId', isEqualTo: companyId)
              .get();

      final ids = <String>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final servicosIds = List<String>.from(data['servicosIds'] ?? const []);

        if (servicosIds.contains(servicoId)) {
          final profissionalId =
              (data['profissionalId'] ?? '').toString().trim();

          if (profissionalId.isNotEmpty) {
            ids.add(profissionalId);
          }
        }
      }

      if (ids.isEmpty) {
        if (mounted) {
          setState(() {
            _profissionais = [];
          });
        }

        return;
      }

      final usersSnapshot =
          await _fs
              .collection('users')
              .where('companyId', isEqualTo: companyId)
              .where('profissionalAgenda', isEqualTo: true)
              .get();

      final lista =
          usersSnapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .where((profissional) {
                final id = profissional['id'].toString();

                final ativo = (profissional['active'] ?? true) == true;

                final ativoAgenda =
                    (profissional['ativoAgendamento'] ?? false) == true;

                return ids.contains(id) && ativo && ativoAgenda;
              })
              .toList();

      lista.sort((a, b) {
        final nomeA = _nomeProfissional(a).toLowerCase();

        final nomeB = _nomeProfissional(b).toLowerCase();

        return nomeA.compareTo(nomeB);
      });

      if (mounted) {
        setState(() {
          _profissionais = lista;
        });
      }
    } catch (e) {
      _mensagem('Erro ao carregar profissionais: $e');
    } finally {
      if (mounted) {
        setState(() {
          _carregandoProfissionais = false;
        });
      }
    }
  }

  Future<void> _selecionarProfissional(String? id) async {
    if (id == null) {
      return;
    }

    final profissional = _profissionais.firstWhere(
      (item) => item['id'].toString() == id,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _profissionalId = id;

      _profissionalNome = _nomeProfissional(profissional);

      _horaInicio = null;
      _horariosDisponiveis = [];
      _mensagemHorarios = null;
    });

    await _carregarHorariosDisponiveis();
  }

  String _nomeProfissional(Map<String, dynamic> profissional) {
    final nome = (profissional['nome'] ?? '').toString().trim();

    if (nome.isNotEmpty) {
      return nome;
    }

    final displayName = (profissional['displayName'] ?? '').toString().trim();

    if (displayName.isNotEmpty) {
      return displayName;
    }

    return 'Profissional';
  }

  // ==========================================================
  // DATA
  // ==========================================================

  Future<void> _selecionarData() async {
    final agora = DateTime.now();

    final hoje = DateTime(agora.year, agora.month, agora.day);

    final selecionada = await showDatePicker(
      context: context,
      initialDate: _data.isBefore(hoje) ? hoje : _data,
      firstDate: hoje,
      lastDate: hoje.add(const Duration(days: 3650)),
      locale: const Locale('pt', 'BR'),
    );

    if (selecionada == null) {
      return;
    }

    setState(() {
      _data = selecionada;

      _horaInicio = null;

      _horariosDisponiveis = [];

      _mensagemHorarios = null;
    });

    if (_profissionalId != null && _servicoId != null) {
      await _carregarHorariosDisponiveis();
    }
  }

  String _chaveDiaSemana(DateTime data) {
    switch (data.weekday) {
      case DateTime.monday:
        return 'segunda';

      case DateTime.tuesday:
        return 'terca';

      case DateTime.wednesday:
        return 'quarta';

      case DateTime.thursday:
        return 'quinta';

      case DateTime.friday:
        return 'sexta';

      case DateTime.saturday:
        return 'sabado';

      case DateTime.sunday:
        return 'domingo';

      default:
        return '';
    }
  }

  DateTime? _dataComHorario(DateTime data, String horario) {
    final partes = horario.split(':');

    if (partes.length != 2) {
      return null;
    }

    final hora = int.tryParse(partes[0]);

    final minuto = int.tryParse(partes[1]);

    if (hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      return null;
    }

    return DateTime(data.year, data.month, data.day, hora, minuto);
  }

  // ==========================================================
  // HORÁRIO DO PROFISSIONAL
  // ==========================================================

  Future<Map<String, dynamic>?> _carregarHorarioEfetivoProfissional() async {
    final companyId = _companyId;

    final profissionalId = _profissionalId;

    if (companyId == null ||
        companyId.isEmpty ||
        profissionalId == null ||
        profissionalId.isEmpty) {
      return null;
    }

    final profissionalDoc =
        await _fs
            .collection('agenda_profissionais_horarios')
            .doc(profissionalId)
            .get();

    if (profissionalDoc.exists) {
      final dados = profissionalDoc.data() ?? <String, dynamic>{};

      final documentoCompanyId = (dados['companyId'] ?? '').toString().trim();

      if (documentoCompanyId.isNotEmpty && documentoCompanyId != companyId) {
        return null;
      }

      final usaPadrao = (dados['usaHorarioPadraoEmpresa'] ?? true) == true;

      if (!usaPadrao) {
        final horarios = dados['horarios'];

        if (horarios is Map) {
          return Map<String, dynamic>.from(horarios);
        }

        return null;
      }
    }

    final empresaDoc =
        await _fs.collection('agenda_configuracoes').doc(companyId).get();

    if (!empresaDoc.exists) {
      return null;
    }

    final horarios = empresaDoc.data()?['horariosFuncionamento'];

    if (horarios is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(horarios);
  }

  // ==========================================================
  // BLOQUEIOS DO PROFISSIONAL
  // ==========================================================

  Future<List<Map<String, dynamic>>> _carregarBloqueiosProfissional() async {
    final companyId = _companyId;

    final profissionalId = _profissionalId;

    if (companyId == null ||
        companyId.isEmpty ||
        profissionalId == null ||
        profissionalId.isEmpty) {
      return [];
    }

    final snapshot =
        await _fs
            .collection('agenda_bloqueios')
            .where('companyId', isEqualTo: companyId)
            .get();

    return snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .where((data) {
          if ((data['ativo'] ?? true) != true) {
            return false;
          }

          if (data['todosProfissionais'] == true) {
            return true;
          }

          return (data['profissionalId'] ?? '').toString().trim() ==
              profissionalId;
        })
        .toList();
  }

  // ==========================================================
  // AGENDAMENTOS DO PROFISSIONAL
  // ==========================================================

  Future<List<Map<String, dynamic>>> _carregarAgendamentosProfissional() async {
    final companyId = _companyId;

    final profissionalId = _profissionalId;

    if (companyId == null ||
        companyId.isEmpty ||
        profissionalId == null ||
        profissionalId.isEmpty) {
      return [];
    }

    final snapshot =
        await _fs
            .collection('agenda_agendamentos')
            .where('companyId', isEqualTo: companyId)
            .where('profissionalId', isEqualTo: profissionalId)
            .get();

    final idEmEdicao = widget.agendamentoEdicao?.id;

    return snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .where((data) {
          /*
           * Na edição o próprio registro
           * não deve bloquear seu horário.
           */
          if (_modoEdicao && data['id'].toString() == idEmEdicao) {
            return false;
          }

          final status = (data['status'] ?? '').toString().trim().toLowerCase();

          return status != 'cancelado' && status != 'nao_compareceu';
        })
        .toList();
  }

  // ==========================================================
  // HORÁRIOS DISPONÍVEIS
  // ==========================================================

  Future<void> _carregarHorariosDisponiveis() async {
    final profissionalId = _profissionalId;

    final servicoId = _servicoId;

    if (profissionalId == null ||
        profissionalId.isEmpty ||
        servicoId == null ||
        servicoId.isEmpty) {
      if (mounted) {
        setState(() {
          _horariosDisponiveis = [];

          _horaInicio = null;

          _mensagemHorarios = 'Selecione o serviço e o profissional.';
        });
      }

      return;
    }

    if (mounted) {
      setState(() {
        _carregandoHorarios = true;

        _horariosDisponiveis = [];

        _horaInicio = null;

        _mensagemHorarios = null;
      });
    }

    try {
      final horarios = await _carregarHorarioEfetivoProfissional();

      if (horarios == null) {
        if (mounted) {
          setState(() {
            _mensagemHorarios =
                'Nenhum horário de atendimento foi configurado '
                'para este profissional.';
          });
        }

        return;
      }

      final chaveDia = _chaveDiaSemana(_data);

      final diaRaw = horarios[chaveDia];

      if (diaRaw is! Map || (diaRaw['ativo'] ?? false) != true) {
        if (mounted) {
          setState(() {
            _mensagemHorarios = 'O profissional não atende nesta data.';
          });
        }

        return;
      }

      final periodosRaw = diaRaw['periodos'];

      if (periodosRaw is! List || periodosRaw.isEmpty) {
        if (mounted) {
          setState(() {
            _mensagemHorarios = 'Nenhum horário disponível nesta data.';
          });
        }

        return;
      }

      final resultados = await Future.wait([
        _carregarBloqueiosProfissional(),
        _carregarAgendamentosProfissional(),
      ]);

      final bloqueios = resultados[0];

      final agendamentos = resultados[1];

      final disponiveis = <DateTime>[];

      final agora = DateTime.now();

      final ocupacaoMinutos =
          _duracaoMinutos + _intervaloAposAtendimentoMinutos;

      for (final periodoRaw in periodosRaw) {
        if (periodoRaw is! Map) {
          continue;
        }

        final inicioTexto = (periodoRaw['inicio'] ?? '').toString().trim();

        final fimTexto = (periodoRaw['fim'] ?? '').toString().trim();

        final inicioPeriodo = _dataComHorario(_data, inicioTexto);

        final fimPeriodo = _dataComHorario(_data, fimTexto);

        if (inicioPeriodo == null ||
            fimPeriodo == null ||
            !fimPeriodo.isAfter(inicioPeriodo)) {
          continue;
        }

        var candidato = inicioPeriodo;

        while (true) {
          final fimCandidato = candidato.add(
            Duration(minutes: ocupacaoMinutos),
          );

          if (fimCandidato.isAfter(fimPeriodo)) {
            break;
          }

          /*
           * Não apresenta horários
           * que já passaram.
           */
          if (!candidato.isBefore(agora)) {
            var indisponivel = false;

            // -----------------------------------------------
            // BLOQUEIOS
            // -----------------------------------------------

            for (final bloqueio in bloqueios) {
              final inicioBloqueio = _paraDateTime(bloqueio['dataInicio']);

              final fimBloqueio = _paraDateTime(bloqueio['dataFim']);

              if (inicioBloqueio == null || fimBloqueio == null) {
                continue;
              }

              final sobrepoe =
                  candidato.isBefore(fimBloqueio) &&
                  fimCandidato.isAfter(inicioBloqueio);

              if (sobrepoe) {
                indisponivel = true;
                break;
              }
            }

            // -----------------------------------------------
            // OUTROS AGENDAMENTOS
            // -----------------------------------------------

            if (!indisponivel) {
              for (final agendamento in agendamentos) {
                final inicioExistente = _paraDateTime(agendamento['inicio']);

                final fimExistente =
                    _paraDateTime(agendamento['fimOcupacao']) ??
                    _paraDateTime(agendamento['fim']);

                if (inicioExistente == null || fimExistente == null) {
                  continue;
                }

                final sobrepoe =
                    candidato.isBefore(fimExistente) &&
                    fimCandidato.isAfter(inicioExistente);

                if (sobrepoe) {
                  indisponivel = true;
                  break;
                }
              }
            }

            if (!indisponivel) {
              disponiveis.add(candidato);
            }
          }

          candidato = candidato.add(
            const Duration(minutes: _intervaloGradeMinutos),
          );
        }
      }

      disponiveis.sort();

      if (!mounted) {
        return;
      }

      setState(() {
        _horariosDisponiveis = disponiveis;

        _mensagemHorarios =
            disponiveis.isEmpty
                ? 'Nenhum horário disponível para esta data.'
                : null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _horariosDisponiveis = [];

        _horaInicio = null;

        _mensagemHorarios = 'Erro ao calcular os horários disponíveis.';
      });

      _mensagem('Erro ao carregar horários: $e');
    } finally {
      if (mounted) {
        setState(() {
          _carregandoHorarios = false;
        });
      }
    }
  }

  // ==========================================================
  // DATAS CALCULADAS
  // ==========================================================

  DateTime? get _inicioAgendamento {
    final hora = _horaInicio;

    if (hora == null) {
      return null;
    }

    return DateTime(_data.year, _data.month, _data.day, hora.hour, hora.minute);
  }

  DateTime? get _fimAgendamento {
    final inicio = _inicioAgendamento;

    if (inicio == null) {
      return null;
    }

    return inicio.add(Duration(minutes: _duracaoMinutos));
  }

  DateTime? get _fimOcupacao {
    final fim = _fimAgendamento;

    if (fim == null) {
      return null;
    }

    return fim.add(Duration(minutes: _intervaloAposAtendimentoMinutos));
  }

  // ==========================================================
  // VERIFICAR BLOQUEIO
  // ==========================================================

  Future<String?> _verificarBloqueio({
    required DateTime inicio,
    required DateTime fimOcupacao,
  }) async {
    final companyId = _companyId;

    final profissionalId = _profissionalId;

    if (companyId == null || profissionalId == null) {
      return null;
    }

    final snapshot =
        await _fs
            .collection('agenda_bloqueios')
            .where('companyId', isEqualTo: companyId)
            .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final ativo = (data['ativo'] ?? true) == true;

      if (!ativo) {
        continue;
      }

      final todosProfissionais = data['todosProfissionais'] == true;

      final bloqueioProfissionalId = (data['profissionalId'] ?? '').toString();

      final afetaProfissional =
          todosProfissionais || bloqueioProfissionalId == profissionalId;

      if (!afetaProfissional) {
        continue;
      }

      final dataInicio = _paraDateTime(data['dataInicio']);

      final dataFim = _paraDateTime(data['dataFim']);

      if (dataInicio == null || dataFim == null) {
        continue;
      }

      final sobrepoe =
          inicio.isBefore(dataFim) && fimOcupacao.isAfter(dataInicio);

      if (sobrepoe) {
        final motivo = (data['motivo'] ?? 'Bloqueio').toString();

        return motivo;
      }
    }

    return null;
  }

  // ==========================================================
  // VERIFICAR CONFLITO
  // ==========================================================

  Future<Map<String, dynamic>?> _verificarConflitoAgendamento({
    required DateTime inicio,
    required DateTime fimOcupacao,
  }) async {
    final companyId = _companyId;

    final profissionalId = _profissionalId;

    if (companyId == null || profissionalId == null) {
      return null;
    }

    final snapshot =
        await _fs
            .collection('agenda_agendamentos')
            .where('companyId', isEqualTo: companyId)
            .where('profissionalId', isEqualTo: profissionalId)
            .get();

    for (final doc in snapshot.docs) {
      /*
       * Na edição, ignora o próprio
       * agendamento.
       */
      if (_modoEdicao && doc.id == widget.agendamentoEdicao?.id) {
        continue;
      }

      final data = doc.data();

      final status = (data['status'] ?? '').toString().trim().toLowerCase();

      if (status == 'cancelado' || status == 'nao_compareceu') {
        continue;
      }

      final existenteInicio = _paraDateTime(data['inicio']);

      final existenteFimOcupacao =
          _paraDateTime(data['fimOcupacao']) ?? _paraDateTime(data['fim']);

      if (existenteInicio == null || existenteFimOcupacao == null) {
        continue;
      }

      final sobrepoe =
          inicio.isBefore(existenteFimOcupacao) &&
          fimOcupacao.isAfter(existenteInicio);

      if (sobrepoe) {
        return <String, dynamic>{'id': doc.id, ...data};
      }
    }

    return null;
  }

  // ==========================================================
  // SALVAR
  // ==========================================================

  Future<void> _salvar() async {
    if (_salvando) {
      return;
    }

    if (_clienteId == null || _clienteId!.isEmpty) {
      _mensagem('Selecione o cliente.');

      return;
    }

    if (_servicoId == null || _servicoId!.isEmpty) {
      _mensagem('Selecione o serviço.');

      return;
    }

    if (_profissionalId == null || _profissionalId!.isEmpty) {
      _mensagem('Selecione o profissional.');

      return;
    }

    if (_horaInicio == null) {
      _mensagem('Selecione um horário disponível.');

      return;
    }

    final inicio = _inicioAgendamento;

    final fim = _fimAgendamento;

    final fimOcupacao = _fimOcupacao;

    if (inicio == null || fim == null || fimOcupacao == null) {
      _mensagem('Não foi possível calcular o horário do agendamento.');

      return;
    }

    /*
     * Não permite cadastrar nem mover
     * o agendamento para horário passado.
     */
    if (inicio.isBefore(DateTime.now())) {
      _mensagem(
        _modoEdicao
            ? 'Não é possível mover o agendamento para um horário que já passou.'
            : 'Não é possível criar um agendamento em um horário que já passou.',
      );

      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      // ------------------------------------------------------
      // 1. BLOQUEIO
      // ------------------------------------------------------

      final bloqueio = await _verificarBloqueio(
        inicio: inicio,
        fimOcupacao: fimOcupacao,
      );

      if (bloqueio != null) {
        _mensagem('Este horário está bloqueado: $bloqueio.');

        return;
      }

      // ------------------------------------------------------
      // 2. CONFLITO
      // ------------------------------------------------------

      final conflito = await _verificarConflitoAgendamento(
        inicio: inicio,
        fimOcupacao: fimOcupacao,
      );

      if (conflito != null) {
        final cliente = (conflito['clienteNome'] ?? 'outro cliente').toString();

        final inicioExistente = _paraDateTime(conflito['inicio']);

        final horario =
            inicioExistente == null
                ? ''
                : DateFormat('HH:mm').format(inicioExistente);

        _mensagem(
          horario.isEmpty
              ? 'O profissional já possui outro agendamento neste período.'
              : 'O profissional já possui um agendamento às '
                  '$horario para $cliente.',
        );

        return;
      }

      // ------------------------------------------------------
      // 3. DADOS
      // ------------------------------------------------------

      final dados = <String, dynamic>{
        'companyId': _companyId,

        // Cliente
        'clienteId': _clienteId,

        'clienteNome': _clienteNome,

        'clienteTelefone': _clienteTelefone.isEmpty ? null : _clienteTelefone,

        'clienteWhatsapp': _clienteWhatsapp.isEmpty ? null : _clienteWhatsapp,

        'clienteEmail': _clienteEmail.isEmpty ? null : _clienteEmail,

        // Serviço
        'servicoId': _servicoId,

        'servicoNome': _servicoNome,

        'valorServico': _valorServico,

        'duracaoMinutos': _duracaoMinutos,

        'intervaloAposAtendimentoMinutos': _intervaloAposAtendimentoMinutos,

        // Profissional
        'profissionalId': _profissionalId,

        'profissionalNome': _profissionalNome,

        // Datas
        'inicio': Timestamp.fromDate(inicio),

        'fim': Timestamp.fromDate(fim),

        'fimOcupacao': Timestamp.fromDate(fimOcupacao),

        'observacao':
            _observacaoCtrl.text.trim().isEmpty
                ? null
                : _observacaoCtrl.text.trim(),

        'updatedAt': FieldValue.serverTimestamp(),

        'updatedBy': _auth.currentUser?.uid,
      };

      String agendamentoId;

      // ------------------------------------------------------
      // 4. EDIÇÃO
      // ------------------------------------------------------

      if (_modoEdicao) {
        final agendamento = widget.agendamentoEdicao!;

        agendamentoId = agendamento.id;

        /*
         * Mantemos do registro original:
         *
         * - status
         * - origem
         * - createdAt
         * - createdBy
         */

        await _fs.collection('agenda_agendamentos').doc(agendamento.id).update({
          ...dados,

          'editadoEm': FieldValue.serverTimestamp(),

          'editadoPor': _auth.currentUser?.uid,
        });
      }
      // ------------------------------------------------------
      // 5. NOVO AGENDAMENTO
      // ------------------------------------------------------
      else {
        final doc = await _fs.collection('agenda_agendamentos').add({
          ...dados,

          'status': 'agendado',

          'origem': 'interno',

          'createdAt': FieldValue.serverTimestamp(),

          'createdBy': _auth.currentUser?.uid,
        });

        agendamentoId = doc.id;
      }

      if (!mounted) {
        return;
      }

      await _mostrarSucesso(
        agendamentoId: agendamentoId,
        inicio: inicio,
        fim: fim,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      _mensagem(
        _modoEdicao
            ? 'Erro ao atualizar agendamento: $e'
            : 'Erro ao criar agendamento: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  // ==========================================================
  // SUCESSO
  // ==========================================================

  Future<void> _mostrarSucesso({
    required String agendamentoId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: NovoAgendamentoStyle.green,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  _modoEdicao ? 'Agendamento atualizado' : 'Agendamento criado',
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _clienteNome,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 10),

              Text(_servicoNome),

              const SizedBox(height: 4),

              Text(_profissionalNome),

              const SizedBox(height: 10),

              Text(
                '${DateFormat('dd/MM/yyyy').format(inicio)} • '
                '${DateFormat('HH:mm').format(inicio)} - '
                '${DateFormat('HH:mm').format(fim)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  DateTime? _paraDateTime(dynamic valor) {
    if (valor is Timestamp) {
      return valor.toDate();
    }

    if (valor is DateTime) {
      return valor;
    }

    return null;
  }

  int _converterInt(dynamic valor, {required int padrao}) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? padrao;
  }

  double _converterDouble(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    var texto = valor.toString().trim();

    if (texto.isEmpty) {
      return 0;
    }

    texto = texto.replaceAll('R\$', '').replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else if (texto.contains(',')) {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  String _formatarMoeda(double valor) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
  }

  String _formatarTelefone(String valor) {
    final d = valor.replaceAll(RegExp(r'\D'), '');

    if (d.length == 11) {
      return '(${d.substring(0, 2)}) '
          '${d.substring(2, 7)}-'
          '${d.substring(7)}';
    }

    if (d.length == 10) {
      return '(${d.substring(0, 2)}) '
          '${d.substring(2, 6)}-'
          '${d.substring(6)}';
    }

    return valor;
  }

  void _mensagem(String texto) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: NovoAgendamentoStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: NovoAgendamentoStyle.bg,
      body: Column(
        children: [
          _NovoAgendamentoHeader(
            title: _modoEdicao ? 'Editar agendamento' : 'Novo agendamento',
            subtitle:
                _modoEdicao
                    ? 'Altere os dados do atendimento.'
                    : 'Cadastre um atendimento diretamente na agenda.',
            icon:
                _modoEdicao
                    ? Icons.edit_calendar_outlined
                    : Icons.event_available_outlined,
            onBack: () {
              Navigator.of(context).maybePop();
            },
          ),

          Expanded(child: _formulario()),
        ],
      ),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        // ====================================================
        // CLIENTE
        // ====================================================
        _card(
          titulo: 'Cliente',
          icone: Icons.person_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_clienteId == null)
                Material(
                  color: const Color(0xFFFAFAFC),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _selecionarCliente,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: NovoAgendamentoStyle.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: NovoAgendamentoStyle.primary.withOpacity(
                                .08,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.person_search_outlined,
                              color: NovoAgendamentoStyle.primary,
                            ),
                          ),

                          const SizedBox(width: 12),

                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selecionar cliente',
                                  style: TextStyle(
                                    color: NovoAgendamentoStyle.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Busque um cliente existente ou cadastre um novo',
                                  style: TextStyle(
                                    color: NovoAgendamentoStyle.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Icon(
                            Icons.chevron_right_rounded,
                            color: NovoAgendamentoStyle.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                _clienteSelecionado(),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ====================================================
        // SERVIÇO
        // ====================================================
        _card(
          titulo: 'Serviço',
          icone: Icons.design_services_outlined,
          child:
              _carregandoServicos
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                    value: _servicoId,
                    isExpanded: true,
                    decoration: _decoracao(
                      'Serviço',
                      hint: 'Selecione o serviço',
                    ),
                    items:
                        _servicos.map((servico) {
                          final id = servico['id'].toString();

                          final nome =
                              (servico['nome'] ?? 'Serviço').toString();

                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(nome, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                    onChanged: _selecionarServico,
                  ),
        ),

        if (_servicoId != null) ...[
          const SizedBox(height: 12),
          _resumoServico(),
        ],

        const SizedBox(height: 12),

        // ====================================================
        // PROFISSIONAL
        // ====================================================
        _card(
          titulo: 'Profissional',
          icone: Icons.badge_outlined,
          child:
              _servicoId == null
                  ? _aviso('Selecione primeiro o serviço.')
                  : _carregandoProfissionais
                  ? const Center(child: CircularProgressIndicator())
                  : _profissionais.isEmpty
                  ? _estadoVazio(
                    icon: Icons.person_off_outlined,
                    titulo: 'Nenhum profissional disponível',
                    descricao:
                        'Nenhum profissional está vinculado a este serviço.',
                  )
                  : DropdownButtonFormField<String>(
                    value: _profissionalId,
                    isExpanded: true,
                    decoration: _decoracao(
                      'Profissional',
                      hint: 'Selecione o profissional',
                    ),
                    items:
                        _profissionais.map((profissional) {
                          final id = profissional['id'].toString();

                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              _nomeProfissional(profissional),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                    onChanged: _selecionarProfissional,
                  ),
        ),

        const SizedBox(height: 12),

        // ====================================================
        // DATA / HORÁRIO
        // ====================================================
        _card(
          titulo: 'Data e horário',
          icone: Icons.calendar_month_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _campoSelecao(
                label: 'Data',
                valor: DateFormat('dd/MM/yyyy').format(_data),
                icon: Icons.calendar_today_outlined,
                onTap: _selecionarData,
              ),

              const SizedBox(height: 16),

              const Text(
                'Horários disponíveis',
                style: TextStyle(
                  color: NovoAgendamentoStyle.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 4),

              const Text(
                'Os horários consideram a duração do serviço, '
                'o intervalo, os bloqueios e outros agendamentos.',
                style: TextStyle(
                  color: NovoAgendamentoStyle.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 12),

              if (_servicoId == null)
                _aviso('Selecione primeiro o serviço.')
              else if (_profissionalId == null)
                _aviso('Selecione primeiro o profissional.')
              else if (_carregandoHorarios)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_mensagemHorarios != null)
                _estadoVazio(
                  icon: Icons.event_busy_outlined,
                  titulo: 'Sem horários disponíveis',
                  descricao: _mensagemHorarios!,
                )
              else
                _gradeHorarios(),

              if (_horaInicio != null &&
                  _inicioAgendamento != null &&
                  _fimAgendamento != null &&
                  _fimOcupacao != null) ...[
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NovoAgendamentoStyle.primary.withOpacity(.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Atendimento: '
                        '${DateFormat('HH:mm').format(_inicioAgendamento!)} - '
                        '${DateFormat('HH:mm').format(_fimAgendamento!)}',
                        style: const TextStyle(
                          color: NovoAgendamentoStyle.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      if (_intervaloAposAtendimentoMinutos > 0) ...[
                        const SizedBox(height: 5),

                        Text(
                          'Profissional ocupado até '
                          '${DateFormat('HH:mm').format(_fimOcupacao!)} '
                          '(inclui $_intervaloAposAtendimentoMinutos min de intervalo).',
                          style: const TextStyle(
                            color: NovoAgendamentoStyle.muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ====================================================
        // OBSERVAÇÃO
        // ====================================================
        _card(
          titulo: 'Observação',
          icone: Icons.notes_outlined,
          child: TextFormField(
            controller: _observacaoCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: _decoracao(
              'Observação',
              hint: 'Informações adicionais sobre o atendimento',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
        ),

        const SizedBox(height: 22),

        // ====================================================
        // SALVAR
        // ====================================================
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: NovoAgendamentoStyle.primary,
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
                    : Icon(
                      _modoEdicao
                          ? Icons.save_outlined
                          : Icons.event_available_outlined,
                    ),
            label: Text(
              _salvando
                  ? (_modoEdicao
                      ? 'Salvando alterações...'
                      : 'Criando agendamento...')
                  : (_modoEdicao ? 'Salvar alterações' : 'Criar agendamento'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // GRADE DE HORÁRIOS
  // ==========================================================

  Widget _gradeHorarios() {
    if (_horariosDisponiveis.isEmpty) {
      return _estadoVazio(
        icon: Icons.event_busy_outlined,
        titulo: 'Sem horários disponíveis',
        descricao: 'Nenhum horário disponível para esta data.',
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          _horariosDisponiveis.map((horario) {
            final selecionado =
                _horaInicio?.hour == horario.hour &&
                _horaInicio?.minute == horario.minute;

            return ChoiceChip(
              label: Text(DateFormat('HH:mm').format(horario)),
              selected: selecionado,
              showCheckmark: false,
              backgroundColor: const Color(0xFFFAFAFC),
              selectedColor: NovoAgendamentoStyle.primary.withOpacity(.12),
              side: BorderSide(
                color:
                    selecionado
                        ? NovoAgendamentoStyle.primary
                        : NovoAgendamentoStyle.border,
              ),
              labelStyle: TextStyle(
                color:
                    selecionado
                        ? NovoAgendamentoStyle.primary
                        : NovoAgendamentoStyle.text,
                fontWeight: FontWeight.w800,
              ),
              onSelected: (_) {
                setState(() {
                  _horaInicio = TimeOfDay.fromDateTime(horario);
                });
              },
            );
          }).toList(),
    );
  }

  // ==========================================================
  // CLIENTE SELECIONADO
  // ==========================================================

  Widget _clienteSelecionado() {
    final contato =
        _clienteWhatsapp.isNotEmpty ? _clienteWhatsapp : _clienteTelefone;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NovoAgendamentoStyle.primary.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NovoAgendamentoStyle.primary.withOpacity(.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: NovoAgendamentoStyle.primary,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _clienteNome,
                  style: const TextStyle(
                    color: NovoAgendamentoStyle.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                if (contato.isNotEmpty) ...[
                  const SizedBox(height: 4),

                  Text(
                    _formatarTelefone(contato),
                    style: const TextStyle(
                      color: NovoAgendamentoStyle.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],

                if (_clienteEmail.isNotEmpty) ...[
                  const SizedBox(height: 2),

                  Text(
                    _clienteEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NovoAgendamentoStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          TextButton.icon(
            onPressed: _selecionarCliente,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text(
              'Trocar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // RESUMO SERVIÇO
  // ==========================================================

  Widget _resumoServico() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NovoAgendamentoStyle.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: NovoAgendamentoStyle.orange),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_duracaoMinutos minutos',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: NovoAgendamentoStyle.text,
                  ),
                ),

                if (_intervaloAposAtendimentoMinutos > 0)
                  Text(
                    '+ $_intervaloAposAtendimentoMinutos min de intervalo',
                    style: const TextStyle(
                      color: NovoAgendamentoStyle.muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

          Text(
            _formatarMoeda(_valorServico),
            style: const TextStyle(
              color: NovoAgendamentoStyle.green,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CARD
  // ==========================================================

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
        border: Border.all(color: NovoAgendamentoStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: NovoAgendamentoStyle.primary, size: 21),

              const SizedBox(width: 8),

              Text(
                titulo,
                style: const TextStyle(
                  color: NovoAgendamentoStyle.text,
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

  // ==========================================================
  // CAMPO SELEÇÃO
  // ==========================================================

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
            Icon(icon, size: 19, color: NovoAgendamentoStyle.primary),

            const SizedBox(width: 9),

            Expanded(
              child: Text(
                valor,
                style: const TextStyle(
                  color: NovoAgendamentoStyle.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // AVISO
  // ==========================================================

  Widget _aviso(String texto) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NovoAgendamentoStyle.primary.withOpacity(.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: NovoAgendamentoStyle.primary),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: NovoAgendamentoStyle.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ESTADO VAZIO
  // ==========================================================

  Widget _estadoVazio({
    required IconData icon,
    required String titulo,
    required String descricao,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 38, color: NovoAgendamentoStyle.muted),

          const SizedBox(height: 10),

          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NovoAgendamentoStyle.text,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            descricao,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NovoAgendamentoStyle.muted,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DECORAÇÃO
  // ==========================================================

  InputDecoration _decoracao(
    String label, {
    String? hint,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon:
          prefixIcon == null
              ? null
              : Icon(prefixIcon, color: NovoAgendamentoStyle.primary),
      filled: true,
      fillColor: const Color(0xFFFAFAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NovoAgendamentoStyle.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NovoAgendamentoStyle.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: NovoAgendamentoStyle.primary,
          width: 1.5,
        ),
      ),
    );
  }
}

// ============================================================
// HEADER
// ============================================================

class _NovoAgendamentoHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;

  const _NovoAgendamentoHeader({
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
        gradient: NovoAgendamentoStyle.gradient,
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

// ============================================================
// ESTILO
// ============================================================

class NovoAgendamentoStyle {
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
