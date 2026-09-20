import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum AgendaDashboardPeriodo {
  hoje,
  seteDias,
  trintaDias,
  esteMes,
  personalizado,
}

class AgendaDashboardController extends ChangeNotifier {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool carregando = false;
  String? erro;

  String companyId = '';

  AgendaDashboardPeriodo periodo = AgendaDashboardPeriodo.esteMes;

  late DateTime dataInicial;
  late DateTime dataFinal;

  String profissionalFiltroId = '';
  String servicoFiltroId = '';

  List<AgendaDashboardAgendamento> agendamentos = [];
  List<AgendaDashboardProfissional> profissionais = [];
  List<AgendaDashboardServico> servicos = [];

  AgendaDashboardController() {
    final intervalo = _intervaloEsteMes();
    dataInicial = intervalo.inicio;
    dataFinal = intervalo.fim;
  }

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> inicializar() async {
    carregando = true;
    erro = null;
    notifyListeners();

    try {
      await _carregarCompanyId();
      await carregarDados();
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao inicializar dashboard da agenda: $e');
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível carregar os resultados da agenda.';
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  Future<void> _carregarCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    final uid = user.uid;
    final userSnap = await _fs.collection('users').doc(uid).get();

    if (!userSnap.exists) {
      companyId = uid;
      return;
    }

    final data = userSnap.data() ?? <String, dynamic>{};

    companyId = (data['companyId'] ?? uid).toString().trim();

    if (companyId.isEmpty) {
      companyId = uid;
    }
  }

  /* ==========================================================
     CARREGAMENTO
     ========================================================== */

  Future<void> carregarDados() async {
    if (companyId.isEmpty) {
      return;
    }

    carregando = true;
    erro = null;
    notifyListeners();

    try {
      final inicio = _inicioDoDia(dataInicial);
      final fimExclusivo = _inicioDoDia(dataFinal).add(const Duration(days: 1));

      /*
       * Consulta principal.
       *
       * Índice que pode ser solicitado pelo Firestore:
       * agenda_agendamentos:
       *   companyId ASC
       *   inicio ASC
       */
      final snapshot =
          await _fs
              .collection('agenda_agendamentos')
              .where('companyId', isEqualTo: companyId)
              .where(
                'inicio',
                isGreaterThanOrEqualTo: Timestamp.fromDate(inicio),
              )
              .where('inicio', isLessThan: Timestamp.fromDate(fimExclusivo))
              .get();

      agendamentos =
          snapshot.docs
              .map(
                (doc) => AgendaDashboardAgendamento.fromFirestore(
                  doc.id,
                  doc.data(),
                ),
              )
              .toList()
            ..sort((a, b) => a.inicio.compareTo(b.inicio));

      _montarFiltros();

      if (kDebugMode) {
        debugPrint(
          '📊 Dashboard Agenda: ${agendamentos.length} agendamento(s) '
          'de ${_formatarData(inicio)} até ${_formatarData(dataFinal)}.',
        );
      }
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Firebase Dashboard Agenda: ${e.code} - ${e.message}');
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível carregar os resultados da agenda.';
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro Dashboard Agenda: $e');
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível carregar os resultados da agenda.';
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  void _montarFiltros() {
    final mapaProfissionais = <String, AgendaDashboardProfissional>{};
    final mapaServicos = <String, AgendaDashboardServico>{};

    for (final item in agendamentos) {
      /*
       * Para o filtro geral usamos o profissional atualmente
       * associado ao agendamento. Nos indicadores financeiros
       * de concluídos usamos o profissional executante.
       */
      if (item.profissionalId.isNotEmpty) {
        mapaProfissionais[item.profissionalId] = AgendaDashboardProfissional(
          id: item.profissionalId,
          nome:
              item.profissionalNome.isEmpty
                  ? 'Profissional'
                  : item.profissionalNome,
        );
      }

      if (item.profissionalExecutanteId.isNotEmpty) {
        mapaProfissionais[item
            .profissionalExecutanteId] = AgendaDashboardProfissional(
          id: item.profissionalExecutanteId,
          nome:
              item.profissionalExecutanteNome.isEmpty
                  ? 'Profissional'
                  : item.profissionalExecutanteNome,
        );
      }

      if (item.servicoId.isNotEmpty) {
        mapaServicos[item.servicoId] = AgendaDashboardServico(
          id: item.servicoId,
          nome: item.servicoNome.isEmpty ? 'Serviço' : item.servicoNome,
        );
      }
    }

    profissionais =
        mapaProfissionais.values.toList()..sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
        );

    servicos =
        mapaServicos.values.toList()..sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
        );

    if (profissionalFiltroId.isNotEmpty &&
        !mapaProfissionais.containsKey(profissionalFiltroId)) {
      profissionalFiltroId = '';
    }

    if (servicoFiltroId.isNotEmpty &&
        !mapaServicos.containsKey(servicoFiltroId)) {
      servicoFiltroId = '';
    }
  }

  /* ==========================================================
     FILTROS
     ========================================================== */

  List<AgendaDashboardAgendamento> get agendamentosFiltrados {
    var lista = List<AgendaDashboardAgendamento>.from(agendamentos);

    if (profissionalFiltroId.isNotEmpty) {
      lista =
          lista.where((item) {
            /*
             * Se o atendimento foi concluído, o profissional
             * executante é a referência correta para resultado
             * e futura comissão.
             */
            final profissionalResultado =
                item.status == 'concluido' &&
                        item.profissionalExecutanteId.isNotEmpty
                    ? item.profissionalExecutanteId
                    : item.profissionalId;

            return profissionalResultado == profissionalFiltroId;
          }).toList();
    }

    if (servicoFiltroId.isNotEmpty) {
      lista = lista.where((item) => item.servicoId == servicoFiltroId).toList();
    }

    return lista;
  }

  void selecionarProfissional(String? profissionalId) {
    profissionalFiltroId = (profissionalId ?? '').trim();
    notifyListeners();
  }

  void selecionarServico(String? servicoId) {
    servicoFiltroId = (servicoId ?? '').trim();
    notifyListeners();
  }

  Future<void> selecionarPeriodo(AgendaDashboardPeriodo novoPeriodo) async {
    periodo = novoPeriodo;

    switch (novoPeriodo) {
      case AgendaDashboardPeriodo.hoje:
        final hoje = _inicioDoDia(DateTime.now());
        dataInicial = hoje;
        dataFinal = hoje;
        break;

      case AgendaDashboardPeriodo.seteDias:
        final hoje = _inicioDoDia(DateTime.now());
        dataInicial = hoje.subtract(const Duration(days: 6));
        dataFinal = hoje;
        break;

      case AgendaDashboardPeriodo.trintaDias:
        final hoje = _inicioDoDia(DateTime.now());
        dataInicial = hoje.subtract(const Duration(days: 29));
        dataFinal = hoje;
        break;

      case AgendaDashboardPeriodo.esteMes:
        final intervalo = _intervaloEsteMes();
        dataInicial = intervalo.inicio;
        dataFinal = intervalo.fim;
        break;

      case AgendaDashboardPeriodo.personalizado:
        // A tela deve chamar selecionarPeriodoPersonalizado().
        notifyListeners();
        return;
    }

    await carregarDados();
  }

  Future<void> selecionarPeriodoPersonalizado({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final inicioNormalizado = _inicioDoDia(inicio);
    final fimNormalizado = _inicioDoDia(fim);

    if (fimNormalizado.isBefore(inicioNormalizado)) {
      erro = 'A data final não pode ser anterior à data inicial.';
      notifyListeners();
      return;
    }

    periodo = AgendaDashboardPeriodo.personalizado;
    dataInicial = inicioNormalizado;
    dataFinal = fimNormalizado;

    await carregarDados();
  }

  /* ==========================================================
     INDICADORES PRINCIPAIS
     ========================================================== */

  int get totalAgendamentos => agendamentosFiltrados.length;

  int get totalAgendados =>
      _quantidadePorStatus({'agendado', 'confirmado', 'em_atendimento'});

  int get totalConcluidos => _quantidadePorStatus({'concluido'});

  int get totalCancelados => _quantidadePorStatus({'cancelado'});

  int get totalNaoCompareceram => _quantidadePorStatus({'nao_compareceu'});

  int _quantidadePorStatus(Set<String> status) {
    return agendamentosFiltrados
        .where((item) => status.contains(item.status))
        .length;
  }

  /*
   * Faturamento = valor final dos atendimentos concluídos.
   *
   * Isso representa o valor vendido/realizado pela agenda,
   * independentemente de o título financeiro já ter sido pago.
   */
  double get faturamento {
    return agendamentosFiltrados
        .where((item) => item.status == 'concluido')
        .fold<double>(0, (total, item) => total + item.valorResultado);
  }

  /*
   * Valor efetivamente recebido no momento da conclusão.
   * Não confundir com faturamento.
   */
  double get valorRecebido {
    return agendamentosFiltrados
        .where((item) => item.status == 'concluido' && item.pagamentoRecebido)
        .fold<double>(0, (total, item) => total + item.valorPagoResultado);
  }

  double get valorEmAberto {
    final valor = faturamento - valorRecebido;
    return valor < 0 ? 0 : valor;
  }

  double get ticketMedio {
    if (totalConcluidos == 0) {
      return 0;
    }

    return faturamento / totalConcluidos;
  }

  /*
   * Cancelados não entram na taxa de comparecimento.
   *
   * Comparecimento =
   * concluídos / (concluídos + não compareceram)
   */
  double get taxaComparecimento {
    final base = totalConcluidos + totalNaoCompareceram;

    if (base == 0) {
      return 0;
    }

    return totalConcluidos / base;
  }

  double get taxaNaoComparecimento {
    final base = totalConcluidos + totalNaoCompareceram;

    if (base == 0) {
      return 0;
    }

    return totalNaoCompareceram / base;
  }

  double get taxaCancelamento {
    if (totalAgendamentos == 0) {
      return 0;
    }

    return totalCancelados / totalAgendamentos;
  }

  double get totalDescontos {
    return agendamentosFiltrados
        .where((item) => item.status == 'concluido')
        .fold<double>(0, (total, item) => total + item.desconto);
  }

  double get totalAcrescimos {
    return agendamentosFiltrados
        .where((item) => item.status == 'concluido')
        .fold<double>(0, (total, item) => total + item.acrescimo);
  }

  /*
   * Valor potencial não realizado.
   *
   * Usa o valor cadastrado no serviço para cancelamentos e
   * não comparecimentos, pois nesses casos não existe valorFinal
   * de um atendimento concluído.
   */
  double get valorPotencialCancelamentos {
    return agendamentosFiltrados
        .where((item) => item.status == 'cancelado')
        .fold<double>(0, (total, item) => total + item.valorServico);
  }

  double get valorPotencialNaoComparecimento {
    return agendamentosFiltrados
        .where((item) => item.status == 'nao_compareceu')
        .fold<double>(0, (total, item) => total + item.valorServico);
  }

  double get valorPotencialNaoRealizado =>
      valorPotencialCancelamentos + valorPotencialNaoComparecimento;

  /* ==========================================================
     RESULTADO POR PROFISSIONAL
     ========================================================== */

  List<AgendaDashboardResultadoProfissional> get resultadoPorProfissional {
    final mapa = <String, _AcumuladorProfissional>{};

    for (final item in agendamentosFiltrados) {
      if (item.status != 'concluido') {
        continue;
      }

      final id =
          item.profissionalExecutanteId.isNotEmpty
              ? item.profissionalExecutanteId
              : item.profissionalId;

      final nome =
          item.profissionalExecutanteNome.isNotEmpty
              ? item.profissionalExecutanteNome
              : item.profissionalNome;

      final chave = id.isNotEmpty ? id : 'sem_profissional';

      final acumulador = mapa.putIfAbsent(
        chave,
        () => _AcumuladorProfissional(
          id: id,
          nome: nome.isEmpty ? 'Profissional não informado' : nome,
        ),
      );

      acumulador.atendimentos++;
      acumulador.faturamento += item.valorResultado;

      if (item.pagamentoRecebido) {
        acumulador.valorRecebido += item.valorPagoResultado;
      }
    }

    final resultado =
        mapa.values.map((item) {
          return AgendaDashboardResultadoProfissional(
            profissionalId: item.id,
            profissionalNome: item.nome,
            atendimentos: item.atendimentos,
            faturamento: item.faturamento,
            valorRecebido: item.valorRecebido,
            ticketMedio:
                item.atendimentos == 0
                    ? 0
                    : item.faturamento / item.atendimentos,
          );
        }).toList();

    resultado.sort((a, b) => b.faturamento.compareTo(a.faturamento));

    return resultado;
  }

  /* ==========================================================
     RESULTADO POR SERVIÇO
     ========================================================== */

  List<AgendaDashboardResultadoServico> get resultadoPorServico {
    final mapa = <String, _AcumuladorServico>{};

    for (final item in agendamentosFiltrados) {
      if (item.status != 'concluido') {
        continue;
      }

      final chave =
          item.servicoId.isNotEmpty
              ? item.servicoId
              : 'nome:${item.servicoNome.toLowerCase()}';

      final acumulador = mapa.putIfAbsent(
        chave,
        () => _AcumuladorServico(
          id: item.servicoId,
          nome: item.servicoNome.isEmpty ? 'Serviço' : item.servicoNome,
        ),
      );

      acumulador.atendimentos++;
      acumulador.faturamento += item.valorResultado;
    }

    final resultado =
        mapa.values.map((item) {
          return AgendaDashboardResultadoServico(
            servicoId: item.id,
            servicoNome: item.nome,
            atendimentos: item.atendimentos,
            faturamento: item.faturamento,
            ticketMedio:
                item.atendimentos == 0
                    ? 0
                    : item.faturamento / item.atendimentos,
          );
        }).toList();

    resultado.sort((a, b) {
      final porQuantidade = b.atendimentos.compareTo(a.atendimentos);

      if (porQuantidade != 0) {
        return porQuantidade;
      }

      return b.faturamento.compareTo(a.faturamento);
    });

    return resultado;
  }

  /* ==========================================================
     EVOLUÇÃO DIÁRIA
     ========================================================== */

  List<AgendaDashboardDia> get evolucaoDiaria {
    final inicio = _inicioDoDia(dataInicial);
    final fim = _inicioDoDia(dataFinal);

    final mapa = <DateTime, _AcumuladorDia>{};

    var cursor = inicio;

    while (!cursor.isAfter(fim)) {
      mapa[cursor] = _AcumuladorDia(data: cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    for (final item in agendamentosFiltrados) {
      final dia = _inicioDoDia(item.inicio);
      final acumulador = mapa[dia];

      if (acumulador == null) {
        continue;
      }

      acumulador.agendamentos++;

      switch (item.status) {
        case 'concluido':
          acumulador.concluidos++;
          acumulador.faturamento += item.valorResultado;
          if (item.pagamentoRecebido) {
            acumulador.valorRecebido += item.valorPagoResultado;
          }
          break;

        case 'cancelado':
          acumulador.cancelados++;
          break;

        case 'nao_compareceu':
          acumulador.naoCompareceram++;
          break;
      }
    }

    return mapa.values
        .map(
          (item) => AgendaDashboardDia(
            data: item.data,
            agendamentos: item.agendamentos,
            concluidos: item.concluidos,
            cancelados: item.cancelados,
            naoCompareceram: item.naoCompareceram,
            faturamento: item.faturamento,
            valorRecebido: item.valorRecebido,
          ),
        )
        .toList()
      ..sort((a, b) => a.data.compareTo(b.data));
  }

  /* ==========================================================
     HELPERS
     ========================================================== */

  static DateTime _inicioDoDia(DateTime data) {
    return DateTime(data.year, data.month, data.day);
  }

  static _IntervaloDashboard _intervaloEsteMes() {
    final agora = DateTime.now();

    final inicio = DateTime(agora.year, agora.month, 1);
    final proximoMes = DateTime(agora.year, agora.month + 1, 1);
    final fim = proximoMes.subtract(const Duration(days: 1));

    return _IntervaloDashboard(inicio: inicio, fim: fim);
  }

  static String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}

/* ============================================================
   MODEL DO AGENDAMENTO PARA O DASHBOARD
   ============================================================ */

class AgendaDashboardAgendamento {
  final String id;
  final String companyId;

  final String clienteId;
  final String clienteNome;

  final String servicoId;
  final String servicoNome;
  final double valorServico;

  final String profissionalId;
  final String profissionalNome;

  final String profissionalExecutanteId;
  final String profissionalExecutanteNome;

  final DateTime inicio;
  final String status;
  final String origem;

  final double valorServicoOriginal;
  final double valorFinal;
  final double desconto;
  final double acrescimo;

  final bool pagamentoRecebido;
  final double valorPago;
  final String formaPagamento;

  const AgendaDashboardAgendamento({
    required this.id,
    required this.companyId,
    required this.clienteId,
    required this.clienteNome,
    required this.servicoId,
    required this.servicoNome,
    required this.valorServico,
    required this.profissionalId,
    required this.profissionalNome,
    required this.profissionalExecutanteId,
    required this.profissionalExecutanteNome,
    required this.inicio,
    required this.status,
    required this.origem,
    required this.valorServicoOriginal,
    required this.valorFinal,
    required this.desconto,
    required this.acrescimo,
    required this.pagamentoRecebido,
    required this.valorPago,
    required this.formaPagamento,
  });

  factory AgendaDashboardAgendamento.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final valorServico = _converterDouble(data['valorServico']);
    final valorOriginalGravado = _converterDouble(data['valorServicoOriginal']);

    return AgendaDashboardAgendamento(
      id: id,
      companyId: (data['companyId'] ?? '').toString().trim(),
      clienteId: (data['clienteId'] ?? '').toString().trim(),
      clienteNome: (data['clienteNome'] ?? 'Cliente').toString().trim(),
      servicoId: (data['servicoId'] ?? '').toString().trim(),
      servicoNome: (data['servicoNome'] ?? 'Serviço').toString().trim(),
      valorServico: valorServico,
      profissionalId: (data['profissionalId'] ?? '').toString().trim(),
      profissionalNome:
          (data['profissionalNome'] ?? 'Profissional').toString().trim(),
      profissionalExecutanteId:
          (data['profissionalExecutanteId'] ?? '').toString().trim(),
      profissionalExecutanteNome:
          (data['profissionalExecutanteNome'] ?? '').toString().trim(),
      inicio:
          _converterData(data['inicio']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: (data['status'] ?? 'agendado').toString().trim().toLowerCase(),
      origem: (data['origem'] ?? '').toString().trim().toLowerCase(),
      valorServicoOriginal:
          valorOriginalGravado > 0 ? valorOriginalGravado : valorServico,
      valorFinal: _converterDouble(data['valorFinal']),
      desconto: _converterDouble(data['desconto']),
      acrescimo: _converterDouble(data['acrescimo']),
      pagamentoRecebido: data['pagamentoRecebido'] == true,
      valorPago: _converterDouble(data['valorPago']),
      formaPagamento:
          (data['formaPagamento'] ?? '').toString().trim().toLowerCase(),
    );
  }

  /*
   * Agendamentos antigos podem não possuir valorFinal.
   * Nesse caso, para um registro concluído, usamos valorServico
   * como fallback para não zerar o histórico do dashboard.
   */
  double get valorResultado {
    if (valorFinal > 0) {
      return valorFinal;
    }

    return valorServico;
  }

  double get valorPagoResultado {
    if (!pagamentoRecebido) {
      return 0;
    }

    if (valorPago > 0) {
      return valorPago;
    }

    return valorResultado;
  }

  static DateTime? _converterData(dynamic valor) {
    if (valor is Timestamp) {
      return valor.toDate();
    }

    if (valor is DateTime) {
      return valor;
    }

    return null;
  }

  static double _converterDouble(dynamic valor) {
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
}

/* ============================================================
   MODELS DE FILTRO
   ============================================================ */

class AgendaDashboardProfissional {
  final String id;
  final String nome;

  const AgendaDashboardProfissional({required this.id, required this.nome});
}

class AgendaDashboardServico {
  final String id;
  final String nome;

  const AgendaDashboardServico({required this.id, required this.nome});
}

/* ============================================================
   RESULTADOS
   ============================================================ */

class AgendaDashboardResultadoProfissional {
  final String profissionalId;
  final String profissionalNome;
  final int atendimentos;
  final double faturamento;
  final double valorRecebido;
  final double ticketMedio;

  const AgendaDashboardResultadoProfissional({
    required this.profissionalId,
    required this.profissionalNome,
    required this.atendimentos,
    required this.faturamento,
    required this.valorRecebido,
    required this.ticketMedio,
  });
}

class AgendaDashboardResultadoServico {
  final String servicoId;
  final String servicoNome;
  final int atendimentos;
  final double faturamento;
  final double ticketMedio;

  const AgendaDashboardResultadoServico({
    required this.servicoId,
    required this.servicoNome,
    required this.atendimentos,
    required this.faturamento,
    required this.ticketMedio,
  });
}

class AgendaDashboardDia {
  final DateTime data;
  final int agendamentos;
  final int concluidos;
  final int cancelados;
  final int naoCompareceram;
  final double faturamento;
  final double valorRecebido;

  const AgendaDashboardDia({
    required this.data,
    required this.agendamentos,
    required this.concluidos,
    required this.cancelados,
    required this.naoCompareceram,
    required this.faturamento,
    required this.valorRecebido,
  });
}

/* ============================================================
   ACUMULADORES INTERNOS
   ============================================================ */

class _AcumuladorProfissional {
  final String id;
  final String nome;

  int atendimentos = 0;
  double faturamento = 0;
  double valorRecebido = 0;

  _AcumuladorProfissional({required this.id, required this.nome});
}

class _AcumuladorServico {
  final String id;
  final String nome;

  int atendimentos = 0;
  double faturamento = 0;

  _AcumuladorServico({required this.id, required this.nome});
}

class _AcumuladorDia {
  final DateTime data;

  int agendamentos = 0;
  int concluidos = 0;
  int cancelados = 0;
  int naoCompareceram = 0;

  double faturamento = 0;
  double valorRecebido = 0;

  _AcumuladorDia({required this.data});
}

class _IntervaloDashboard {
  final DateTime inicio;
  final DateTime fim;

  const _IntervaloDashboard({required this.inicio, required this.fim});
}
