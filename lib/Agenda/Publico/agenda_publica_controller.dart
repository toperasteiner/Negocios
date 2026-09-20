import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AgendaPublicaController extends ChangeNotifier {
  final String slug;

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

  AgendaPublicaController({required this.slug});

  /* ==========================================================
     CONFIGURAÇÃO DA PÁGINA
     ========================================================== */

  bool carregandoPagina = true;
  String? erroPagina;

  String companyId = '';

  String tituloPagina = '';
  String descricaoPagina = '';

  String whatsapp = '';
  String instagram = '';
  String endereco = '';

  bool exibirEndereco = false;

  /* ==========================================================
     ETAPAS

     0 = Serviço
     1 = Profissional
     2 = Data e horário
     3 = Dados do cliente
     4 = Confirmação
     ========================================================== */

  int etapaAtual = 0;

  /* ==========================================================
     SERVIÇOS
     ========================================================== */

  bool carregandoServicos = false;

  List<Map<String, dynamic>> servicos = [];

  String? servicoId;
  Map<String, dynamic>? servicoSelecionado;

  /* ==========================================================
     PROFISSIONAIS
     ========================================================== */

  bool carregandoProfissionais = false;

  List<Map<String, dynamic>> profissionais = [];

  String? profissionalId;
  Map<String, dynamic>? profissionalSelecionado;

  /* ==========================================================
     DATA / HORÁRIO
     ========================================================== */

  bool carregandoDatas = false;
  bool carregandoHorarios = false;

  DateTime? dataSelecionada;
  String? horarioSelecionado;

  List<DateTime> datasDisponiveis = [];
  List<String> horariosDisponiveis = [];

  /* ==========================================================
     DADOS DO CLIENTE
     ========================================================== */

  final TextEditingController nomeClienteCtrl = TextEditingController();

  final TextEditingController telefoneClienteCtrl = TextEditingController();

  final TextEditingController emailClienteCtrl = TextEditingController();

  final TextEditingController observacaoCtrl = TextEditingController();

  /* ==========================================================
     CONFIRMAÇÃO
     ========================================================== */

  bool confirmandoAgendamento = false;
  bool agendamentoConcluido = false;

  String protocoloAgendamento = '';

  /* ==========================================================
     GETTERS - PÁGINA
     ========================================================== */

  bool get possuiContato {
    return whatsapp.trim().isNotEmpty || instagram.trim().isNotEmpty;
  }

  bool get exibirLocalizacao {
    return exibirEndereco && endereco.trim().isNotEmpty;
  }

  /* ==========================================================
     GETTERS - SERVIÇO
     ========================================================== */

  String get servicoNome {
    if (servicoSelecionado == null) {
      return '';
    }

    return (servicoSelecionado!['nome'] ??
            servicoSelecionado!['descricao'] ??
            '')
        .toString();
  }

  int get duracaoServicoMinutos {
    if (servicoSelecionado == null) {
      return 0;
    }

    final valor = servicoSelecionado!['duracaoMinutos'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  int get intervaloAposAtendimentoMinutos {
    if (servicoSelecionado == null) {
      return 0;
    }

    final valor = servicoSelecionado!['intervaloAposAtendimentoMinutos'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  bool get exibirPrecoServico {
    if (servicoSelecionado == null) {
      return false;
    }

    return servicoSelecionado!['exibirPrecoAgenda'] == true;
  }

  double get precoServico {
    if (servicoSelecionado == null) {
      return 0;
    }

    final data = servicoSelecionado!;

    /*
     * O cadastro atual de serviços do CRUD Negócios utiliza
     * "valorUnitario".
     *
     * Mantemos os outros nomes apenas como compatibilidade
     * para possíveis registros antigos.
     */
    final valor =
        data['valorUnitario'] ??
        data['valor'] ??
        data['preco'] ??
        data['price'];

    if (valor is num) {
      return valor.toDouble();
    }

    if (valor is String) {
      var texto = valor.trim();

      if (texto.contains(',') && texto.contains('.')) {
        texto = texto.replaceAll('.', '').replaceAll(',', '.');
      } else if (texto.contains(',')) {
        texto = texto.replaceAll(',', '.');
      }

      return double.tryParse(texto) ?? 0;
    }

    return 0;
  }

  String get precoServicoFormatado {
    return NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(precoServico);
  }

  /* ==========================================================
     GETTERS - PROFISSIONAL
     ========================================================== */

  String get profissionalNome {
    if (profissionalSelecionado == null) {
      return '';
    }

    return (profissionalSelecionado!['displayName'] ??
            profissionalSelecionado!['nome'] ??
            '')
        .toString();
  }

  /* ==========================================================
     GETTERS - DATA
     ========================================================== */

  String get dataFormatada {
    if (dataSelecionada == null) {
      return '';
    }

    return DateFormat('dd/MM/yyyy', 'pt_BR').format(dataSelecionada!);
  }

  String get dataFormatadaCompleta {
    if (dataSelecionada == null) {
      return '';
    }

    return DateFormat(
      "EEEE, dd 'de' MMMM 'de' yyyy",
      'pt_BR',
    ).format(dataSelecionada!);
  }

  /* ==========================================================
     GETTERS - CLIENTE
     ========================================================== */

  String get nomeCliente => nomeClienteCtrl.text.trim();

  String get telefoneCliente => telefoneClienteCtrl.text.trim();

  String get emailCliente => emailClienteCtrl.text.trim();

  String get observacao => observacaoCtrl.text.trim();

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> inicializar() async {
    carregandoPagina = true;
    erroPagina = null;

    notifyListeners();

    try {
      final slugNormalizado = slug.trim().toLowerCase();

      if (slugNormalizado.isEmpty) {
        erroPagina = 'Página de agendamento não encontrada.';
        return;
      }

      final doc =
          await _fs
              .collection('agenda_paginas_publicas')
              .doc(slugNormalizado)
              .get();

      if (!doc.exists) {
        erroPagina = 'Página de agendamento não encontrada.';
        return;
      }

      final data = doc.data();

      if (data == null) {
        erroPagina = 'Página de agendamento não encontrada.';
        return;
      }

      companyId = (data['companyId'] ?? '').toString().trim();

      tituloPagina = (data['titulo'] ?? 'Agenda Online').toString().trim();

      descricaoPagina = (data['descricao'] ?? '').toString().trim();

      whatsapp = (data['whatsapp'] ?? '').toString().trim();

      instagram = (data['instagram'] ?? '').toString().trim();

      endereco = (data['endereco'] ?? '').toString().trim();

      exibirEndereco = data['exibirEndereco'] == true;

      final ativo = data['ativo'] == true;

      if (tituloPagina.isEmpty) {
        tituloPagina = 'Agenda Online';
      }

      if (!ativo) {
        erroPagina = 'Esta agenda está temporariamente indisponível.';
        return;
      }

      if (companyId.isEmpty) {
        erroPagina = 'Não foi possível identificar a empresa desta agenda.';
        return;
      }

      /*
       * Depois de carregar a configuração pública da empresa,
       * carregamos somente a projeção pública dos serviços.
       *
       * A coleção interna "servicos" NÃO é acessada pela
       * página pública.
       */
      await carregarServicos();
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '❌ Firebase - Agenda pública: '
          '${e.code} - ${e.message}',
        );
      }

      erroPagina = 'Não foi possível carregar esta página de agendamento.';
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar agenda pública: $e');

        debugPrintStack(stackTrace: stack);
      }

      erroPagina = 'Não foi possível carregar esta página de agendamento.';
    } finally {
      carregandoPagina = false;
      notifyListeners();
    }
  }

  /* ==========================================================
     SERVIÇOS
     ========================================================== */

  Future<void> carregarServicos() async {
    carregandoServicos = true;
    servicos = [];

    notifyListeners();

    try {
      final empresa = companyId.trim();

      if (empresa.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ carregarServicos: companyId vazio.');
        }

        return;
      }

      /*
       * IMPORTANTE:
       *
       * A página pública NÃO consulta:
       *
       * servicos/{servicoId}
       *
       * Ela consulta exclusivamente:
       *
       * agenda_servicos_publicos
       *   /{companyId}
       *     /servicos
       *       /{servicoId}
       *
       * Essa coleção deve possuir somente dados que podem
       * ser expostos ao cliente.
       */
      final snapshot =
          await _fs
              .collection('agenda_servicos_publicos')
              .doc(empresa)
              .collection('servicos')
              .get();

      final lista =
          snapshot.docs
              .map((doc) {
                return <String, dynamic>{'id': doc.id, ...doc.data()};
              })
              .where((servico) {
                /*
         * Atualmente somente serviços disponíveis para
         * agendamento são gravados nessa projeção.
         *
         * Mesmo assim mantemos esta validação como uma
         * segunda camada de proteção.
         */
                return servico['ativo'] == true;
              })
              .toList();

      /*
       * Ordenamos localmente.
       *
       * Dessa forma não precisamos criar um índice adicional
       * somente para ordenar os serviços por nome.
       */
      lista.sort((a, b) {
        final nomeA = (a['nome'] ?? '').toString().trim().toLowerCase();

        final nomeB = (b['nome'] ?? '').toString().trim().toLowerCase();

        return nomeA.compareTo(nomeB);
      });

      servicos = lista;

      if (kDebugMode) {
        debugPrint(
          '✅ Agenda pública: ${servicos.length} '
          'serviço(s) carregado(s).',
        );

        debugPrint('🏢 companyId: $empresa');
      }
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Firebase - serviços públicos: '
          '${e.code} - ${e.message}',
        );

        debugPrintStack(stackTrace: stack);
      }

      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar serviços públicos: $e');

        debugPrintStack(stackTrace: stack);
      }

      rethrow;
    } finally {
      carregandoServicos = false;
      notifyListeners();
    }
  }

  Future<void> selecionarServico(Map<String, dynamic> servico) async {
    final id = (servico['id'] ?? '').toString();

    if (id.isEmpty) {
      return;
    }

    servicoId = id;
    servicoSelecionado = servico;

    /*
     * Ao trocar o serviço, todas as escolhas
     * posteriores precisam ser descartadas.
     */

    profissionalId = null;
    profissionalSelecionado = null;

    dataSelecionada = null;
    horarioSelecionado = null;

    profissionais = [];
    datasDisponiveis = [];
    horariosDisponiveis = [];

    etapaAtual = 1;

    notifyListeners();

    await carregarProfissionais();
  }

  void voltarParaServico() {
    etapaAtual = 0;

    /*
     * Mantemos o serviço selecionado para que ele possa
     * aparecer marcado quando o cliente voltar.
     */

    profissionalId = null;
    profissionalSelecionado = null;

    dataSelecionada = null;
    horarioSelecionado = null;

    profissionais = [];
    datasDisponiveis = [];
    horariosDisponiveis = [];

    notifyListeners();
  }

  /* ==========================================================
     PROFISSIONAIS
     ========================================================== */

  Future<void> carregarProfissionais() async {
    carregandoProfissionais = true;
    profissionais = [];

    notifyListeners();

    try {
      final empresa = companyId.trim();
      final servico = servicoId?.trim() ?? '';

      if (empresa.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ carregarProfissionais: companyId vazio.');
        }
        return;
      }

      if (servico.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ carregarProfissionais: servicoId vazio.');
        }
        return;
      }

      /*
     * ========================================================
     * PROFISSIONAIS PÚBLICOS
     * ========================================================
     *
     * A página pública NÃO consulta:
     *
     * users
     *
     * nem:
     *
     * agenda_profissional_servicos
     *
     * Ela consulta exclusivamente a projeção pública:
     *
     * agenda_profissionais_publicos
     *   /{companyId}
     *     /profissionais
     *       /{profissionalId}
     *
     * Cada documento público possui:
     *
     * companyId
     * profissionalId
     * nome
     * servicosIds
     * ativo
     * updatedAt
     *
     * O arrayContains garante que sejam carregados somente
     * profissionais vinculados ao serviço selecionado.
     */
      final snapshot =
          await _fs
              .collection('agenda_profissionais_publicos')
              .doc(empresa)
              .collection('profissionais')
              .where('servicosIds', arrayContains: servico)
              .get();

      final lista =
          snapshot.docs
              .map((doc) {
                return <String, dynamic>{'id': doc.id, ...doc.data()};
              })
              .where((profissional) {
                /*
               * Mesmo que somente profissionais ativos devam
               * existir na projeção pública, fazemos uma segunda
               * validação antes de exibi-los.
               */
                return profissional['ativo'] == true;
              })
              .toList();

      /*
     * Ordenação local para não exigir índice adicional
     * apenas para ordenar pelo nome.
     */
      lista.sort((a, b) {
        final nomeA = (a['nome'] ?? '').toString().trim().toLowerCase();

        final nomeB = (b['nome'] ?? '').toString().trim().toLowerCase();

        return nomeA.compareTo(nomeB);
      });

      profissionais = lista;

      if (kDebugMode) {
        debugPrint(
          '✅ Agenda pública: ${profissionais.length} '
          'profissional(is) carregado(s).',
        );

        debugPrint('🏢 companyId: $empresa');
        debugPrint('🛠️ servicoId: $servico');

        for (final profissional in profissionais) {
          debugPrint(
            '👤 ${profissional['nome']} '
            '- ${profissional['id']}',
          );
        }
      }
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Firebase - profissionais públicos: '
          '${e.code} - ${e.message}',
        );

        debugPrintStack(stackTrace: stack);
      }

      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar profissionais públicos: $e');

        debugPrintStack(stackTrace: stack);
      }

      rethrow;
    } finally {
      carregandoProfissionais = false;
      notifyListeners();
    }
  }

  Future<void> selecionarProfissional(Map<String, dynamic> profissional) async {
    final id = (profissional['id'] ?? '').toString();

    if (id.isEmpty) {
      return;
    }

    profissionalId = id;
    profissionalSelecionado = profissional;

    dataSelecionada = null;
    horarioSelecionado = null;

    datasDisponiveis = [];
    horariosDisponiveis = [];

    etapaAtual = 2;

    notifyListeners();

    await carregarDatasDisponiveis();
  }

  void voltarParaProfissional() {
    etapaAtual = 1;

    dataSelecionada = null;
    horarioSelecionado = null;

    datasDisponiveis = [];
    horariosDisponiveis = [];

    notifyListeners();
  }

  /* ==========================================================
     DATAS DISPONÍVEIS
     ========================================================== */

  Future<void> carregarDatasDisponiveis() async {
    carregandoDatas = true;
    datasDisponiveis = [];
    notifyListeners();

    try {
      final servico = servicoId?.trim() ?? '';
      final profissional = profissionalId?.trim() ?? '';
      final slugNormalizado = slug.trim().toLowerCase();

      if (slugNormalizado.isEmpty ||
          companyId.isEmpty ||
          servico.isEmpty ||
          profissional.isEmpty) {
        return;
      }

      final callable = _functions.httpsCallable(
        'consultarDisponibilidadeAgenda',
      );

      final resultado = await callable.call(<String, dynamic>{
        'slug': slugNormalizado,
        'servicoId': servico,
        'profissionalId': profissional,
        'modo': 'datas',
        'dias': 30,
      });

      final dados = resultado.data;
      if (dados is! Map) {
        throw Exception('Resposta inválida ao consultar datas disponíveis.');
      }

      final datasRaw = dados['datas'];
      if (datasRaw is! List) {
        datasDisponiveis = [];
        return;
      }

      final lista = <DateTime>[];

      for (final item in datasRaw) {
        final texto = item?.toString().trim() ?? '';
        if (texto.isEmpty) continue;

        try {
          final data = DateFormat('yyyy-MM-dd').parseStrict(texto);
          lista.add(DateTime(data.year, data.month, data.day));
        } catch (_) {
          if (kDebugMode) {
            debugPrint('⚠️ Data inválida recebida da Function: $texto');
          }
        }
      }

      lista.sort();
      datasDisponiveis = lista;

      if (kDebugMode) {
        debugPrint('✅ ${datasDisponiveis.length} data(s) disponível(is).');
        for (final data in datasDisponiveis) {
          debugPrint('📅 ${DateFormat('dd/MM/yyyy').format(data)}');
        }
      }
    } on FirebaseFunctionsException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Function carregarDatasDisponiveis: ${e.code} - ${e.message}',
        );
        debugPrintStack(stackTrace: stack);
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar datas disponíveis: $e');
        debugPrintStack(stackTrace: stack);
      }
      rethrow;
    } finally {
      carregandoDatas = false;
      notifyListeners();
    }
  }

  Future<void> selecionarData(DateTime data) async {
    dataSelecionada = DateTime(data.year, data.month, data.day);

    horarioSelecionado = null;
    horariosDisponiveis = [];

    notifyListeners();

    await carregarHorariosDisponiveis();
  }

  void alterarDataSelecionada() {
    dataSelecionada = null;
    horarioSelecionado = null;
    horariosDisponiveis = [];

    notifyListeners();
  }

  /* ==========================================================
     HORÁRIOS DISPONÍVEIS
     ========================================================== */

  Future<void> carregarHorariosDisponiveis() async {
    carregandoHorarios = true;
    horariosDisponiveis = [];
    notifyListeners();

    try {
      final data = dataSelecionada;
      final servico = servicoId?.trim() ?? '';
      final profissional = profissionalId?.trim() ?? '';
      final slugNormalizado = slug.trim().toLowerCase();

      if (data == null ||
          slugNormalizado.isEmpty ||
          servico.isEmpty ||
          profissional.isEmpty) {
        return;
      }

      final dataTexto = DateFormat('yyyy-MM-dd').format(data);

      final callable = _functions.httpsCallable(
        'consultarDisponibilidadeAgenda',
      );

      final resultado = await callable.call(<String, dynamic>{
        'slug': slugNormalizado,
        'servicoId': servico,
        'profissionalId': profissional,
        'modo': 'horarios',
        'data': dataTexto,
      });

      final dados = resultado.data;
      if (dados is! Map) {
        throw Exception('Resposta inválida ao consultar horários disponíveis.');
      }

      final horariosRaw = dados['horarios'];
      if (horariosRaw is! List) {
        horariosDisponiveis = [];
        return;
      }

      final lista =
          horariosRaw
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList();

      lista.sort();
      horariosDisponiveis = lista;

      if (horarioSelecionado != null &&
          !horariosDisponiveis.contains(horarioSelecionado)) {
        horarioSelecionado = null;
      }

      if (kDebugMode) {
        debugPrint(
          '✅ ${horariosDisponiveis.length} horário(s) disponível(is) em $dataTexto.',
        );
        for (final horario in horariosDisponiveis) {
          debugPrint('🕐 $horario');
        }
      }
    } on FirebaseFunctionsException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Function carregarHorariosDisponiveis: ${e.code} - ${e.message}',
        );
        debugPrintStack(stackTrace: stack);
      }
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar horários disponíveis: $e');
        debugPrintStack(stackTrace: stack);
      }
      rethrow;
    } finally {
      carregandoHorarios = false;
      notifyListeners();
    }
  }

  void selecionarHorario(String horario) {
    final valor = horario.trim();

    if (valor.isEmpty) {
      return;
    }

    horarioSelecionado = valor;

    notifyListeners();
  }

  void voltarParaDataHorario() {
    etapaAtual = 2;

    notifyListeners();
  }

  /* ==========================================================
     IR PARA DADOS DO CLIENTE
     ========================================================== */

  void irParaDadosCliente() {
    if (dataSelecionada == null) {
      return;
    }

    if (horarioSelecionado == null || horarioSelecionado!.trim().isEmpty) {
      return;
    }

    etapaAtual = 3;

    notifyListeners();
  }

  /* ==========================================================
     VALIDAÇÃO DOS DADOS DO CLIENTE
     ========================================================== */

  String? validarDadosCliente() {
    if (nomeCliente.isEmpty) {
      return 'Informe seu nome.';
    }

    if (nomeCliente.length < 2) {
      return 'Informe um nome válido.';
    }

    if (telefoneCliente.isEmpty) {
      return 'Informe seu WhatsApp ou telefone.';
    }

    final telefoneNumeros = telefoneCliente.replaceAll(RegExp(r'[^0-9]'), '');

    if (telefoneNumeros.length < 10) {
      return 'Informe um telefone válido com DDD.';
    }

    if (emailCliente.isNotEmpty && !_emailValido(emailCliente)) {
      return 'Informe um e-mail válido.';
    }

    return null;
  }

  bool _emailValido(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  }

  /* ==========================================================
     CONFIRMAÇÃO
     ========================================================== */

  void irParaConfirmacao() {
    final erro = validarDadosCliente();

    if (erro != null) {
      return;
    }

    if (servicoId == null ||
        profissionalId == null ||
        dataSelecionada == null ||
        horarioSelecionado == null) {
      return;
    }

    etapaAtual = 4;

    notifyListeners();
  }

  void voltarParaDadosCliente() {
    etapaAtual = 3;

    notifyListeners();
  }

  /* ==========================================================
     CONFIRMAR AGENDAMENTO
     ========================================================== */

  Future<ResultadoAgendamento> confirmarAgendamento() async {
    /* ==========================================================
     EVITA DUPLO CLIQUE / DUPLA REQUISIÇÃO
     ========================================================== */

    if (confirmandoAgendamento) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Aguarde. O agendamento já está sendo processado.',
      );
    }

    /* ==========================================================
     VALIDA DADOS DO CLIENTE
     ========================================================== */

    final erroCliente = validarDadosCliente();

    if (erroCliente != null) {
      return ResultadoAgendamento(sucesso: false, mensagem: erroCliente);
    }

    /* ==========================================================
     VALIDA DADOS DA EMPRESA
     ========================================================== */

    final slugNormalizado = slug.trim().toLowerCase();

    if (slugNormalizado.isEmpty) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Não foi possível identificar a página de agendamento.',
      );
    }

    if (companyId.trim().isEmpty) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Não foi possível identificar a empresa.',
      );
    }

    /* ==========================================================
     VALIDA SERVIÇO
     ========================================================== */

    final servico = servicoId?.trim() ?? '';

    if (servico.isEmpty || servicoSelecionado == null) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Selecione o serviço novamente.',
      );
    }

    /* ==========================================================
     VALIDA PROFISSIONAL
     ========================================================== */

    final profissional = profissionalId?.trim() ?? '';

    if (profissional.isEmpty || profissionalSelecionado == null) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Selecione o profissional novamente.',
      );
    }

    /* ==========================================================
     VALIDA DATA
     ========================================================== */

    final data = dataSelecionada;

    if (data == null) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Selecione a data novamente.',
      );
    }

    /* ==========================================================
     VALIDA HORÁRIO
     ========================================================== */

    final horario = horarioSelecionado?.trim() ?? '';

    if (horario.isEmpty) {
      return const ResultadoAgendamento(
        sucesso: false,
        mensagem: 'Selecione o horário novamente.',
      );
    }

    /* ==========================================================
     INICIA PROCESSAMENTO
     ========================================================== */

    confirmandoAgendamento = true;

    notifyListeners();

    try {
      final callable = _functions.httpsCallable('confirmarAgendamentoPublico');

      final dataTexto = DateFormat('yyyy-MM-dd').format(data);

      /*
     * O telefone é enviado como foi digitado.
     *
     * O backend é responsável por normalizá-lo,
     * removendo parênteses, espaços, hífen etc.
     */
      final resultado = await callable.call(<String, dynamic>{
        'slug': slugNormalizado,
        'servicoId': servico,
        'profissionalId': profissional,
        'data': dataTexto,
        'horario': horario,
        'nome': nomeCliente,
        'telefone': telefoneCliente,
        'email': emailCliente,
        'observacao': observacao,
      });

      /* ========================================================
       VALIDA RESPOSTA DA FUNCTION
       ======================================================== */

      final dados = resultado.data;

      if (dados is! Map) {
        if (kDebugMode) {
          debugPrint(
            '❌ confirmarAgendamentoPublico retornou '
            'uma resposta inválida.',
          );

          debugPrint('Resposta: $dados');
        }

        return const ResultadoAgendamento(
          sucesso: false,
          mensagem:
              'Não foi possível confirmar o agendamento. '
              'Tente novamente.',
        );
      }

      final sucesso = dados['ok'] == true;

      if (!sucesso) {
        return const ResultadoAgendamento(
          sucesso: false,
          mensagem:
              'Não foi possível confirmar o agendamento. '
              'Tente novamente.',
        );
      }

      /* ========================================================
       AGENDAMENTO CRIADO
       ======================================================== */

      final agendamentoId = dados['agendamentoId']?.toString().trim() ?? '';

      if (agendamentoId.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '❌ Function retornou sucesso, mas '
            'agendamentoId está vazio.',
          );

          debugPrint('Resposta: $dados');
        }

        return const ResultadoAgendamento(
          sucesso: false,
          mensagem:
              'O agendamento foi processado, mas não foi possível '
              'obter a confirmação.',
        );
      }

      protocoloAgendamento = agendamentoId;

      agendamentoConcluido = true;

      if (kDebugMode) {
        debugPrint('========================================');

        debugPrint('✅ AGENDAMENTO CONFIRMADO');

        debugPrint('🆔 Agendamento: $agendamentoId');

        debugPrint('👤 Cliente: ${dados['clienteId'] ?? ''}');

        debugPrint('🆕 Cliente novo: ${dados['clienteNovo'] ?? false}');

        debugPrint('📅 Data: $dataTexto');

        debugPrint('🕐 Horário: $horario');

        debugPrint('========================================');
      }

      notifyListeners();

      return const ResultadoAgendamento(
        sucesso: true,
        mensagem: 'Agendamento confirmado com sucesso!',
      );
    }
    /* ==========================================================
     ERROS DA CLOUD FUNCTION
     ========================================================== */
    on FirebaseFunctionsException catch (e, stack) {
      if (kDebugMode) {
        debugPrint('========================================');

        debugPrint('❌ confirmarAgendamentoPublico');

        debugPrint('Código: ${e.code}');

        debugPrint('Mensagem: ${e.message}');

        debugPrint('Detalhes: ${e.details}');

        debugPrintStack(stackTrace: stack);

        debugPrint('========================================');
      }

      /*
     * O horário estava disponível quando o cliente
     * visualizou a agenda, mas deixou de estar disponível
     * antes da confirmação.
     */
      if (e.code == 'already-exists') {
        /*
       * Retiramos o horário selecionado para impedir que
       * o usuário tente confirmar novamente o mesmo horário.
       */

        horarioSelecionado = null;

        /*
       * Atualizamos os horários disponíveis da data.
       *
       * Não usamos await aqui dentro antes da mensagem porque
       * queremos garantir que o estado de confirmação seja
       * finalizado corretamente no finally.
       */

        try {
          await carregarHorariosDisponiveis();
        } catch (_) {
          // A mensagem principal continua sendo a indisponibilidade.
        }

        return ResultadoAgendamento(
          sucesso: false,
          mensagem:
              e.message ??
              'Este horário não está mais disponível. '
                  'Escolha outro horário.',
        );
      }

      if (e.code == 'not-found') {
        return ResultadoAgendamento(
          sucesso: false,
          mensagem:
              e.message ??
              'Não foi possível localizar os dados do agendamento.',
        );
      }

      if (e.code == 'failed-precondition') {
        return ResultadoAgendamento(
          sucesso: false,
          mensagem:
              e.message ?? 'Este agendamento não pode mais ser confirmado.',
        );
      }

      if (e.code == 'invalid-argument') {
        return ResultadoAgendamento(
          sucesso: false,
          mensagem: e.message ?? 'Existem dados inválidos no agendamento.',
        );
      }

      if (e.code == 'unavailable') {
        return const ResultadoAgendamento(
          sucesso: false,
          mensagem:
              'O serviço de agendamento está temporariamente '
              'indisponível. Tente novamente em alguns instantes.',
        );
      }

      return ResultadoAgendamento(
        sucesso: false,
        mensagem:
            e.message ??
            'Não foi possível confirmar o agendamento. '
                'Tente novamente.',
      );
    }
    /* ==========================================================
     OUTROS ERROS
     ========================================================== */
    catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro inesperado ao confirmar agendamento: $e');

        debugPrintStack(stackTrace: stack);
      }

      return const ResultadoAgendamento(
        sucesso: false,
        mensagem:
            'Não foi possível confirmar o agendamento. '
            'Tente novamente.',
      );
    }
    /* ==========================================================
     FINALIZA PROCESSAMENTO
     ========================================================== */
    finally {
      confirmandoAgendamento = false;

      notifyListeners();
    }
  }

  /* ==========================================================
     NOVO AGENDAMENTO
     ========================================================== */

  void novoAgendamento() {
    etapaAtual = 0;

    servicoId = null;
    servicoSelecionado = null;

    profissionalId = null;
    profissionalSelecionado = null;

    dataSelecionada = null;
    horarioSelecionado = null;

    profissionais = [];
    datasDisponiveis = [];
    horariosDisponiveis = [];

    nomeClienteCtrl.clear();
    telefoneClienteCtrl.clear();
    emailClienteCtrl.clear();
    observacaoCtrl.clear();

    confirmandoAgendamento = false;
    agendamentoConcluido = false;

    protocoloAgendamento = '';

    notifyListeners();
  }

  /* ==========================================================
     DISPOSE
     ========================================================== */

  @override
  void dispose() {
    nomeClienteCtrl.dispose();
    telefoneClienteCtrl.dispose();
    emailClienteCtrl.dispose();
    observacaoCtrl.dispose();

    super.dispose();
  }
}

/* ============================================================
   RESULTADO DO AGENDAMENTO
   ============================================================ */

class ResultadoAgendamento {
  final bool sucesso;
  final String? mensagem;

  const ResultadoAgendamento({required this.sucesso, this.mensagem});
}
