import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ResultadoConclusaoAgendamento {
  final bool sucesso;
  final String? pedidoId;
  final int? numeroPedido;
  final String? mensagem;

  const ResultadoConclusaoAgendamento({
    required this.sucesso,
    this.pedidoId,
    this.numeroPedido,
    this.mensagem,
  });
}

class AgendaController extends ChangeNotifier {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /* ==========================================================
     ESTADO GERAL
     ========================================================== */

  bool carregando = false;
  String? erro;

  String companyId = '';

  DateTime dataSelecionada = DateTime.now();

  String profissionalFiltroId = '';
  String statusFiltro = 'todos';

  List<AgendaProfissional> profissionais = [];
  List<AgendaAgendamento> agendamentos = [];

  /* ==========================================================
     INICIALIZAÇÃO
     ========================================================== */

  Future<void> inicializar() async {
    carregando = true;
    erro = null;

    notifyListeners();

    try {
      await _carregarCompanyId();

      await carregarProfissionais();

      await carregarAgendamentos();
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao inicializar agenda: $e');
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível carregar a agenda.';
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  /* ==========================================================
     COMPANY ID
     ========================================================== */

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

    final data = userSnap.data() ?? {};

    companyId = (data['companyId'] ?? uid).toString().trim();

    if (companyId.isEmpty) {
      companyId = uid;
    }

    if (kDebugMode) {
      debugPrint('🏢 Agenda companyId: $companyId');
    }
  }

  /* ==========================================================
     PROFISSIONAIS
     ========================================================== */

  Future<void> carregarProfissionais() async {
    profissionais = [];

    if (companyId.isEmpty) {
      return;
    }

    try {
      /*
       * Para manter a consulta interna simples, buscamos
       * os profissionais pela coleção pública já existente.
       *
       * Ela contém somente:
       * - profissionalId
       * - nome
       * - companyId
       * - ativo
       *
       * Isso é suficiente para o filtro da agenda.
       */
      final snapshot =
          await _fs
              .collection('agenda_profissionais_publicos')
              .doc(companyId)
              .collection('profissionais')
              .get();

      final lista =
          snapshot.docs
              .map((doc) {
                final data = doc.data();

                return AgendaProfissional(
                  id: doc.id,
                  nome:
                      (data['nome'] ?? data['displayName'] ?? 'Profissional')
                          .toString()
                          .trim(),
                  ativo: data['ativo'] == true,
                );
              })
              .where((profissional) {
                return profissional.ativo;
              })
              .toList();

      lista.sort((a, b) {
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

      profissionais = lista;

      if (kDebugMode) {
        debugPrint('✅ ${profissionais.length} profissional(is) carregado(s).');
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar profissionais da agenda: $e');

        debugPrintStack(stackTrace: stack);
      }

      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /* ==========================================================
     AGENDAMENTOS
     ========================================================== */

  Future<bool> descancelarAgendamento({
    required AgendaAgendamento agendamento,
  }) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        erro = 'Usuário não autenticado.';
        notifyListeners();
        return false;
      }

      await _fs.collection('agenda_agendamentos').doc(agendamento.id).update({
        'status': 'agendado',

        'motivoCancelamento': null,
        'canceladoEm': null,
        'canceladoPor': null,

        'descanceladoEm': FieldValue.serverTimestamp(),
        'descanceladoPor': user.uid,

        'updatedAt': FieldValue.serverTimestamp(),
      });

      await carregarAgendamentos();

      return true;
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Erro Firebase ao descancelar agendamento: '
          '${e.code} - ${e.message}',
        );
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível descancelar o agendamento.';
      notifyListeners();

      return false;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao descancelar agendamento: $e');
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível descancelar o agendamento.';
      notifyListeners();

      return false;
    }
  }

  /* ==========================================================
     NÃO COMPARECEU
     ========================================================== */

  Future<bool> marcarNaoCompareceu({
    required AgendaAgendamento agendamento,
  }) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        erro = 'Usuário não autenticado.';
        notifyListeners();
        return false;
      }

      final ref = _fs.collection('agenda_agendamentos').doc(agendamento.id);
      final snap = await ref.get();

      if (!snap.exists) {
        erro = 'Agendamento não encontrado.';
        notifyListeners();
        return false;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final empresaAtual = (data['companyId'] ?? '').toString().trim();
      final statusAtual =
          (data['status'] ?? 'agendado').toString().trim().toLowerCase();

      if (empresaAtual.isNotEmpty && empresaAtual != companyId) {
        erro = 'Este agendamento não pertence à empresa atual.';
        notifyListeners();
        return false;
      }

      if (statusAtual == 'concluido') {
        erro =
            'Um agendamento concluído não pode ser marcado como não compareceu.';
        notifyListeners();
        return false;
      }

      if (statusAtual == 'cancelado') {
        erro =
            'Um agendamento cancelado não pode ser marcado como não compareceu.';
        notifyListeners();
        return false;
      }

      if (statusAtual == 'nao_compareceu') {
        return true;
      }

      await ref.update({
        'status': 'nao_compareceu',
        'naoCompareceuEm': FieldValue.serverTimestamp(),
        'naoCompareceuPor': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });

      await carregarAgendamentos();
      return true;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao marcar não comparecimento: $e');
        debugPrintStack(stackTrace: stack);
      }
      erro = 'Não foi possível marcar o cliente como não compareceu.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> desfazerNaoComparecimento({
    required AgendaAgendamento agendamento,
  }) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        erro = 'Usuário não autenticado.';
        notifyListeners();
        return false;
      }

      final ref = _fs.collection('agenda_agendamentos').doc(agendamento.id);
      final snap = await ref.get();

      if (!snap.exists) {
        erro = 'Agendamento não encontrado.';
        notifyListeners();
        return false;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final empresaAtual = (data['companyId'] ?? '').toString().trim();
      final statusAtual =
          (data['status'] ?? 'agendado').toString().trim().toLowerCase();

      if (empresaAtual.isNotEmpty && empresaAtual != companyId) {
        erro = 'Este agendamento não pertence à empresa atual.';
        notifyListeners();
        return false;
      }

      if (statusAtual != 'nao_compareceu') {
        erro = 'Este agendamento não está marcado como não compareceu.';
        notifyListeners();
        return false;
      }

      await ref.update({
        'status': 'agendado',
        'naoCompareceuEm': FieldValue.delete(),
        'naoCompareceuPor': FieldValue.delete(),
        'naoComparecimentoDesfeitoEm': FieldValue.serverTimestamp(),
        'naoComparecimentoDesfeitoPor': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });

      await carregarAgendamentos();
      return true;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao desfazer não comparecimento: $e');
        debugPrintStack(stackTrace: stack);
      }
      erro = 'Não foi possível reativar o agendamento.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelarAgendamento({
    required AgendaAgendamento agendamento,
    String? motivo,
  }) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        erro = 'Usuário não autenticado.';
        notifyListeners();
        return false;
      }

      await _fs.collection('agenda_agendamentos').doc(agendamento.id).update({
        'status': 'cancelado',
        'motivoCancelamento':
            motivo?.trim().isEmpty == true ? null : motivo?.trim(),
        'canceladoEm': FieldValue.serverTimestamp(),
        'canceladoPor': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await carregarAgendamentos();

      return true;
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Erro Firebase ao cancelar agendamento: '
          '${e.code} - ${e.message}',
        );
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível cancelar o agendamento.';
      notifyListeners();

      return false;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao cancelar agendamento: $e');
        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível cancelar o agendamento.';
      notifyListeners();

      return false;
    }
  }

  /* ==========================================================
     CONCLUIR AGENDAMENTO / CRIAR PEDIDO
     ========================================================== */

  Future<ResultadoConclusaoAgendamento> concluirAgendamento({
    required AgendaAgendamento agendamento,
    required double valorOriginal,
    required double valorFinal,
    required double desconto,
    required double acrescimo,
    required bool pagamentoRecebido,
    String? formaPagamento,
    required String profissionalExecutanteId,
    required String profissionalExecutanteNome,
  }) async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Usuário não autenticado.',
        );
      }

      if (companyId.isEmpty) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Empresa não identificada.',
        );
      }

      if (agendamento.companyId.isNotEmpty &&
          agendamento.companyId != companyId) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Este agendamento não pertence à empresa atual.',
        );
      }

      if (valorOriginal < 0 ||
          valorFinal <= 0 ||
          desconto < 0 ||
          acrescimo < 0) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Informe valores válidos para o atendimento.',
        );
      }

      final formaPagamentoNormalizada =
          (formaPagamento ?? '').trim().toLowerCase();

      if (pagamentoRecebido && formaPagamentoNormalizada.isEmpty) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Informe a forma de pagamento.',
        );
      }

      final profissionalId = profissionalExecutanteId.trim();
      final profissionalNome = profissionalExecutanteNome.trim();

      if (profissionalId.isEmpty || profissionalNome.isEmpty) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Informe o profissional que realizou o atendimento.',
        );
      }

      final agendamentoRef = _fs
          .collection('agenda_agendamentos')
          .doc(agendamento.id);

      /*
       * Recarrega o documento antes da conclusão para evitar
       * usar somente o estado que estava na tela.
       */
      final agendamentoSnap = await agendamentoRef.get();

      if (!agendamentoSnap.exists) {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Agendamento não encontrado.',
        );
      }

      final dadosAtuais = agendamentoSnap.data() ?? <String, dynamic>{};

      final statusAtual =
          (dadosAtuais['status'] ?? 'agendado').toString().trim().toLowerCase();

      if (statusAtual == 'cancelado') {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem:
              'Um agendamento cancelado não pode ser marcado como concluído.',
        );
      }

      if (statusAtual == 'nao_compareceu') {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem:
              'Um agendamento marcado como não compareceu não pode ser concluído.',
        );
      }

      final pedidoExistenteId =
          (dadosAtuais['pedidoId'] ?? '').toString().trim();

      if (pedidoExistenteId.isNotEmpty) {
        return ResultadoConclusaoAgendamento(
          sucesso: false,
          pedidoId: pedidoExistenteId,
          numeroPedido: _converterNumeroPedido(dadosAtuais['numeroPedido']),
          mensagem: 'Este agendamento já possui um pedido vinculado.',
        );
      }

      if (statusAtual == 'concluido') {
        return const ResultadoConclusaoAgendamento(
          sucesso: false,
          mensagem: 'Este agendamento já está concluído.',
        );
      }

      /* ======================================================
         PRÓXIMO NÚMERO DO PEDIDO

         Mantém o mesmo padrão utilizado pelo catálogo público:
         pedidos_index / scope / ano / numero.
         ====================================================== */

      final agora = DateTime.now();
      final ano = agora.year;

      final indexSnap =
          await _fs
              .collection('pedidos_index')
              .where('scope', isEqualTo: companyId)
              .where('ano', isEqualTo: ano)
              .orderBy('numero', descending: true)
              .limit(1)
              .get();

      final proximoNumero =
          indexSnap.docs.isEmpty
              ? 1
              : _converterNumeroPedido(indexSnap.docs.first.data()['numero']) +
                  1;

      /* ======================================================
         REFERÊNCIAS
         ====================================================== */

      final pedidoRef = _fs.collection('pedidos').doc();

      final pedidoIndexRef = _fs.collection('pedidos_index').doc();

      final pedidoPagamentoRef = _fs.collection('pedido_pagamento').doc();

      final contasReceberRef = _fs.collection('contas_receber').doc();

      DocumentReference<Map<String, dynamic>>? fluxoCaixaRef;

      if (pagamentoRecebido) {
        fluxoCaixaRef = _fs.collection('fluxo_caixa').doc();
      }

      /* ======================================================
         ITEM DO SERVIÇO

         O profissional executante fica também no item para
         permitir relatórios e comissão no futuro.
         ====================================================== */

      final itensServicos = <Map<String, dynamic>>[
        {
          'refId': agendamento.servicoId,
          'nome': agendamento.servicoNome,
          'quantidade': 1.0,
          'valorUnitario': valorFinal,
          'valorOriginal': valorOriginal,
          'desconto': desconto,
          'acrescimo': acrescimo,
          'total': valorFinal,
          'subtotalVenda': valorFinal,
          'custoUnitario': 0.0,
          'subtotalCusto': 0.0,
          'lucroItem': valorFinal,
          'profissionalId': profissionalId,
          'profissionalNome': profissionalNome,
        },
      ];

      final batch = _fs.batch();

      /* ======================================================
         PEDIDO
         ====================================================== */

      batch.set(pedidoRef, {
        'companyId': companyId,

        'clienteId': agendamento.clienteId,
        'cliente': agendamento.clienteNome,
        'clienteNome': agendamento.clienteNome,
        'clienteTelefone':
            agendamento.telefoneExibicao.isEmpty
                ? null
                : agendamento.telefoneExibicao,
        'clienteEmail':
            agendamento.clienteEmail.isEmpty ? null : agendamento.clienteEmail,

        'itensProdutos': <Map<String, dynamic>>[],
        'itensServicos': itensServicos,

        'subtotalProdutos': 0.0,
        'subtotalServicos': valorFinal,
        'subtotal': valorFinal,
        'taxaEntrega': 0.0,
        'total': valorFinal,

        // Valores praticados no atendimento
        'valorOriginal': valorOriginal,
        'valorFinal': valorFinal,
        'desconto': desconto,
        'acrescimo': acrescimo,

        // Situação do recebimento
        'pagamentoRecebido': pagamentoRecebido,
        'formaPagamento': pagamentoRecebido ? formaPagamentoNormalizada : null,

        /*
           * Liga pedido e agenda.
           */
        'origem': 'agenda',
        'agendamentoId': agendamento.id,
        'contasReceberId': contasReceberRef.id,

        /*
           * Quem efetivamente prestou o serviço.
           */
        'profissionalId': profissionalId,
        'profissionalNome': profissionalNome,

        'observacao':
            agendamento.observacao.isEmpty ? null : agendamento.observacao,

        /*
           * O atendimento já foi realizado.
           */
        'status': 'concluido',
        'situacao': 'Fechado',

        'data': Timestamp.now(),

        'ano': ano,
        'numero': proximoNumero,

        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });

      /* ======================================================
         PEDIDO PAGAMENTO

         Mantém a mesma estrutura-base usada pelo catálogo
         e registra a situação informada no encerramento.
         ====================================================== */

      batch.set(pedidoPagamentoRef, {
        'companyId': companyId,
        'userId': user.uid,
        'createdByUid': user.uid,

        'pedidoId': pedidoRef.id,

        'tipo': 'avista',
        'numeroParcelas': 1,

        'totalPedido': valorFinal,

        'dataPrimeiroPagamento': Timestamp.now(),

        'pagamentoRecebido': pagamentoRecebido,

        'formaPagamento': pagamentoRecebido ? formaPagamentoNormalizada : null,

        'valorPago': pagamentoRecebido ? valorFinal : 0.0,

        'status': pagamentoRecebido ? 'pago' : 'aberto',

        'dataPagamento':
            pagamentoRecebido
                ? Timestamp.fromDate(
                  DateTime(agora.year, agora.month, agora.day),
                )
                : null,

        'createdAt': FieldValue.serverTimestamp(),

        'updatedAt': FieldValue.serverTimestamp(),
      });

      /* ======================================================
         ÍNDICE DO PEDIDO
         ====================================================== */

      batch.set(pedidoIndexRef, {
        'scope': companyId,
        'ano': ano,
        'numero': proximoNumero,
        'pedidoId': pedidoRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ========================================================
      // CONTAS A RECEBER
      // ========================================================

      final hoje = DateTime.now();

      final vencimento = DateTime(hoje.year, hoje.month, hoje.day);

      final dataPagamento = DateTime(agora.year, agora.month, agora.day);

      batch.set(contasReceberRef, {
        // Escopo
        'userId': user.uid,
        'companyId': companyId,
        'createdByUid': user.uid,

        // Origem / vínculos
        'origem': 'agenda',
        'agendamentoId': agendamento.id,

        'pedidoId': pedidoRef.id,
        'pedidoNumero': proximoNumero,
        'pedidoAno': ano,

        // Cliente
        'clienteId':
            agendamento.clienteId.isEmpty ? null : agendamento.clienteId,

        'clienteNome':
            agendamento.clienteNome.isEmpty ? null : agendamento.clienteNome,

        // Descrição
        'descricao':
            agendamento.servicoNome.isEmpty
                ? 'Atendimento da agenda'
                : agendamento.servicoNome,

        // Valores comerciais
        'valorOriginal': valorOriginal,
        'valor': valorFinal,
        'desconto': desconto,
        'acrescimo': acrescimo,

        // Financeiro
        'vencimento': Timestamp.fromDate(vencimento),

        'status': pagamentoRecebido ? 'pago' : 'aberto',

        /*
         * O app ainda não trabalha com pagamento parcial.
         * Portanto:
         * - recebido = título integralmente pago;
         * - não recebido = título integralmente em aberto.
         */
        'valorPago': pagamentoRecebido ? valorFinal : null,

        'dataPagamento':
            pagamentoRecebido ? Timestamp.fromDate(dataPagamento) : null,

        'formaPagamento': pagamentoRecebido ? formaPagamentoNormalizada : null,

        'pagamentoRecebido': pagamentoRecebido,

        if (fluxoCaixaRef != null) 'fluxoCaixaId': fluxoCaixaRef.id,

        // Categoria financeira (mantida sem preenchimento automático)
        'categoriaKey': null,
        'categoriaNome': null,

        // Profissional executante
        'profissionalId': profissionalId,
        'profissionalNome': profissionalNome,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      /* ======================================================
         FLUXO DE CAIXA

         Segue o mesmo padrão utilizado por
         ContasReceberHomeScreen._marcarPago().

         Só é criado quando o pagamento já foi recebido.
         ====================================================== */

      if (pagamentoRecebido && fluxoCaixaRef != null) {
        final numeroFormatado = proximoNumero.toString().padLeft(3, '0');

        final observacaoFluxo =
            'Pedido: $numeroFormatado-$ano '
            'Cliente: ${agendamento.clienteNome} '
            'Valor: ${_formatarMoeda(valorFinal)}';

        batch.set(fluxoCaixaRef, {
          'userId': user.uid,
          'companyId': companyId,
          'createdByUid': user.uid,

          'data': Timestamp.fromDate(dataPagamento),

          'tipo': 'entrada',

          'valorAbs': valorFinal,
          'valor': valorFinal,

          'observacao': observacaoFluxo,

          'clienteNome':
              agendamento.clienteNome.isEmpty ? null : agendamento.clienteNome,

          'fornecedorNome': null,

          'pedidoId': pedidoRef.id,
          'contasReceberId': contasReceberRef.id,

          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      /* ======================================================
         ATUALIZA O AGENDAMENTO
         ====================================================== */

      batch.update(agendamentoRef, {
        'status': 'concluido',

        'pedidoId': pedidoRef.id,
        'numeroPedido': proximoNumero,
        'contasReceberId': contasReceberRef.id,

        if (fluxoCaixaRef != null) 'fluxoCaixaId': fluxoCaixaRef.id,

        // Valores do atendimento
        'valorServicoOriginal': valorOriginal,
        'valorFinal': valorFinal,
        'desconto': desconto,
        'acrescimo': acrescimo,

        // Situação do recebimento
        'pagamentoRecebido': pagamentoRecebido,
        'formaPagamento': pagamentoRecebido ? formaPagamentoNormalizada : null,
        'valorPago': pagamentoRecebido ? valorFinal : null,
        'dataPagamento':
            pagamentoRecebido ? Timestamp.fromDate(dataPagamento) : null,

        /*
           * Mantemos profissionalId/profissionalNome originais
           * do agendamento. Estes campos registram quem
           * efetivamente realizou o atendimento.
           */
        'profissionalExecutanteId': profissionalId,
        'profissionalExecutanteNome': profissionalNome,

        'concluidoEm': FieldValue.serverTimestamp(),
        'concluidoPor': user.uid,

        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });

      await batch.commit();

      await carregarAgendamentos();

      return ResultadoConclusaoAgendamento(
        sucesso: true,
        pedidoId: pedidoRef.id,
        numeroPedido: proximoNumero,
        mensagem:
            pagamentoRecebido
                ? 'Agendamento concluído, pedido criado e pagamento registrado.'
                : 'Agendamento concluído, pedido criado e título gerado em aberto.',
      );
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Firebase ao concluir agendamento: '
          '${e.code} - ${e.message}',
        );
        debugPrintStack(stackTrace: stack);
      }

      return ResultadoConclusaoAgendamento(
        sucesso: false,
        mensagem: e.message ?? 'Não foi possível concluir o agendamento.',
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao concluir agendamento: $e');
        debugPrintStack(stackTrace: stack);
      }

      return const ResultadoConclusaoAgendamento(
        sucesso: false,
        mensagem: 'Não foi possível concluir o agendamento.',
      );
    }
  }

  Future<void> carregarAgendamentos() async {
    if (companyId.isEmpty) {
      return;
    }

    carregando = true;
    erro = null;

    notifyListeners();

    try {
      final inicioDia = DateTime(
        dataSelecionada.year,
        dataSelecionada.month,
        dataSelecionada.day,
      );

      final fimDia = inicioDia.add(const Duration(days: 1));

      Query<Map<String, dynamic>> query = _fs
          .collection('agenda_agendamentos')
          .where('companyId', isEqualTo: companyId)
          .where(
            'inicio',
            isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia),
          )
          .where('inicio', isLessThan: Timestamp.fromDate(fimDia));

      /*
       * Não aplicamos profissional/status direto no Firestore
       * nesta primeira versão.
       *
       * Fazemos esses filtros localmente para reduzir
       * a necessidade de índices compostos adicionais.
       */
      final snapshot = await query.get();

      final lista =
          snapshot.docs.map((doc) {
            return AgendaAgendamento.fromFirestore(doc.id, doc.data());
          }).toList();

      lista.sort((a, b) {
        return a.inicio.compareTo(b.inicio);
      });

      agendamentos = lista;

      if (kDebugMode) {
        debugPrint(
          '📅 Agenda ${_formatarDataLog(dataSelecionada)}: '
          '${agendamentos.length} registro(s).',
        );

        for (final agendamento in agendamentos) {
          debugPrint(
            '🕐 ${agendamento.horarioInicio} '
            '- ${agendamento.clienteNome} '
            '- ${agendamento.servicoNome}',
          );
        }
      }
    } on FirebaseException catch (e, stack) {
      if (kDebugMode) {
        debugPrint(
          '❌ Firebase Agenda: '
          '${e.code} - ${e.message}',
        );

        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível carregar os agendamentos.';
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('❌ Erro ao carregar agendamentos: $e');

        debugPrintStack(stackTrace: stack);
      }

      erro = 'Não foi possível carregar os agendamentos.';
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  /* ==========================================================
     FILTROS
     ========================================================== */

  List<AgendaAgendamento> get agendamentosFiltrados {
    var lista = List<AgendaAgendamento>.from(agendamentos);

    if (profissionalFiltroId.isNotEmpty) {
      lista =
          lista.where((agendamento) {
            return agendamento.profissionalId == profissionalFiltroId;
          }).toList();
    }

    if (statusFiltro != 'todos') {
      lista =
          lista.where((agendamento) {
            return agendamento.status == statusFiltro;
          }).toList();
    }

    lista.sort((a, b) {
      return a.inicio.compareTo(b.inicio);
    });

    return lista;
  }

  void selecionarProfissional(String profissionalId) {
    profissionalFiltroId = profissionalId.trim();

    notifyListeners();
  }

  void selecionarStatus(String status) {
    final valor = status.trim().toLowerCase();

    statusFiltro = valor.isEmpty ? 'todos' : valor;

    notifyListeners();
  }

  /* ==========================================================
     NAVEGAÇÃO ENTRE DATAS
     ========================================================== */

  Future<void> selecionarData(DateTime data) async {
    dataSelecionada = DateTime(data.year, data.month, data.day);

    await carregarAgendamentos();
  }

  Future<void> diaAnterior() async {
    dataSelecionada = dataSelecionada.subtract(const Duration(days: 1));

    await carregarAgendamentos();
  }

  Future<void> proximoDia() async {
    dataSelecionada = dataSelecionada.add(const Duration(days: 1));

    await carregarAgendamentos();
  }

  Future<void> irParaHoje() async {
    final agora = DateTime.now();

    dataSelecionada = DateTime(agora.year, agora.month, agora.day);

    await carregarAgendamentos();
  }

  bool get ehHoje {
    final agora = DateTime.now();

    return dataSelecionada.year == agora.year &&
        dataSelecionada.month == agora.month &&
        dataSelecionada.day == agora.day;
  }

  /* ==========================================================
     HELPERS
     ========================================================== */

  int _converterNumeroPedido(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _formatarMoeda(double valor) {
    final texto = valor.toStringAsFixed(2);
    final partes = texto.split('.');

    final inteiro = partes[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );

    return 'R\$ $inteiro,${partes[1]}';
  }

  String _formatarDataLog(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }
}

/* ============================================================
   MODEL PROFISSIONAL
   ============================================================ */

class AgendaProfissional {
  final String id;
  final String nome;
  final bool ativo;

  const AgendaProfissional({
    required this.id,
    required this.nome,
    required this.ativo,
  });
}

/* ============================================================
   MODEL AGENDAMENTO
   ============================================================ */

class AgendaAgendamento {
  final String id;

  final String companyId;

  final String clienteId;
  final String clienteNome;
  final String clienteTelefone;
  final String clienteWhatsapp;
  final String clienteEmail;

  final String servicoId;
  final String servicoNome;

  final double valorServico;
  final int duracaoMinutos;
  final int intervaloAposAtendimentoMinutos;

  final String profissionalId;
  final String profissionalNome;

  final DateTime inicio;
  final DateTime fim;
  final DateTime fimOcupacao;

  final String status;
  final String origem;

  final String observacao;

  const AgendaAgendamento({
    required this.id,
    required this.companyId,
    required this.clienteId,
    required this.clienteNome,
    required this.clienteTelefone,
    required this.clienteWhatsapp,
    required this.clienteEmail,
    required this.servicoId,
    required this.servicoNome,
    required this.valorServico,
    required this.duracaoMinutos,
    required this.intervaloAposAtendimentoMinutos,
    required this.profissionalId,
    required this.profissionalNome,
    required this.inicio,
    required this.fim,
    required this.fimOcupacao,
    required this.status,
    required this.origem,
    required this.observacao,
  });

  factory AgendaAgendamento.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final inicio =
        _converterTimestamp(data['inicio']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final fim = _converterTimestamp(data['fim']) ?? inicio;

    final fimOcupacao = _converterTimestamp(data['fimOcupacao']) ?? fim;

    return AgendaAgendamento(
      id: id,

      companyId: (data['companyId'] ?? '').toString(),

      clienteId: (data['clienteId'] ?? '').toString(),

      clienteNome: (data['clienteNome'] ?? 'Cliente').toString().trim(),

      clienteTelefone: (data['clienteTelefone'] ?? '').toString().trim(),

      clienteWhatsapp: (data['clienteWhatsapp'] ?? '').toString().trim(),

      clienteEmail: (data['clienteEmail'] ?? '').toString().trim(),

      servicoId: (data['servicoId'] ?? '').toString(),

      servicoNome: (data['servicoNome'] ?? 'Serviço').toString().trim(),

      valorServico: _converterDouble(data['valorServico']),

      duracaoMinutos: _converterInt(data['duracaoMinutos']),

      intervaloAposAtendimentoMinutos: _converterInt(
        data['intervaloAposAtendimentoMinutos'],
      ),

      profissionalId: (data['profissionalId'] ?? '').toString(),

      profissionalNome:
          (data['profissionalNome'] ?? 'Profissional').toString().trim(),

      inicio: inicio,
      fim: fim,
      fimOcupacao: fimOcupacao,

      status: (data['status'] ?? 'agendado').toString().trim().toLowerCase(),

      origem: (data['origem'] ?? '').toString().trim(),

      observacao: (data['observacao'] ?? '').toString().trim(),
    );
  }

  /* ==========================================================
     GETTERS
     ========================================================== */

  String get horarioInicio {
    return _formatarHora(inicio);
  }

  String get horarioFim {
    return _formatarHora(fim);
  }

  String get horarioPeriodo {
    return '$horarioInicio - $horarioFim';
  }

  String get telefoneExibicao {
    if (clienteWhatsapp.isNotEmpty) {
      return clienteWhatsapp;
    }

    return clienteTelefone;
  }

  String get statusDescricao {
    switch (status) {
      case 'agendado':
        return 'Agendado';

      case 'confirmado':
        return 'Confirmado';

      case 'em_atendimento':
        return 'Em atendimento';

      case 'concluido':
        return 'Concluído';

      case 'cancelado':
        return 'Cancelado';

      case 'nao_compareceu':
        return 'Não compareceu';

      default:
        return status.isEmpty ? 'Agendado' : status;
    }
  }

  /* ==========================================================
     CONVERSORES
     ========================================================== */

  static DateTime? _converterTimestamp(dynamic valor) {
    if (valor is Timestamp) {
      return valor.toDate();
    }

    if (valor is DateTime) {
      return valor;
    }

    return null;
  }

  static int _converterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
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

  static String _formatarHora(DateTime data) {
    final hora = data.hour.toString().padLeft(2, '0');

    final minuto = data.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }
}
