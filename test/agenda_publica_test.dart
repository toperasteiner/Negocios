import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pedido_crud/Agenda/Publico/agenda_publica_controller.dart';

class _FakeFirestore extends Fake implements FirebaseFirestore {}
class _FakeFirebaseFunctions extends Fake implements FirebaseFunctions {}

void main() {
  setUpAll(() async {
    // Inicializa a formatação de datas pt_BR para testes
    await initializeDateFormatting('pt_BR', null);
  });

  group('AgendaPublicaController - Testes Unitários do Módulo Agenda Online', () {
    late AgendaPublicaController controller;

    setUp(() {
      controller = AgendaPublicaController(
        slug: 'salao-beleza-vip',
        firestore: _FakeFirestore(),
        functions: _FakeFirebaseFunctions(),
      );
    });


    tearDown(() {
      controller.dispose();
    });

    test('Estado inicial deve iniciar na etapa 0 (Serviço) com coleções vazias', () {
      expect(controller.slug, equals('salao-beleza-vip'));
      expect(controller.etapaAtual, equals(0));
      expect(controller.carregandoPagina, isTrue);
      expect(controller.servicoSelecionado, isNull);
      expect(controller.profissionalSelecionado, isNull);
      expect(controller.dataSelecionada, isNull);
      expect(controller.horarioSelecionado, isNull);
      expect(controller.possuiContato, isFalse);
      expect(controller.exibirLocalizacao, isFalse);
    });

    group('Getters de Serviço - Cálculo de Preço e Duração', () {
      test('deve tratar adequadamente serviço sem dados selecionados', () {
        expect(controller.servicoNome, isEmpty);
        expect(controller.precoServico, equals(0.0));
        expect(controller.duracaoServicoMinutos, equals(0));
        expect(controller.intervaloAposAtendimentoMinutos, equals(0));
        expect(controller.exibirPrecoServico, isFalse);
      });

      test('deve extrair nome, duração e intervalo de tipos numéricos', () {
        controller.servicoSelecionado = {
          'nome': 'Corte Degradê & Barba',
          'valorUnitario': 85.0,
          'duracaoMinutos': 45,
          'intervaloAposAtendimentoMinutos': 10,
          'exibirPrecoAgenda': true,
        };

        expect(controller.servicoNome, equals('Corte Degradê & Barba'));
        expect(controller.precoServico, equals(85.0));
        expect(controller.duracaoServicoMinutos, equals(45));
        expect(controller.intervaloAposAtendimentoMinutos, equals(10));
        expect(controller.exibirPrecoServico, isTrue);
        expect(controller.precoServicoFormatado, contains('85,00'));
      });

      test('deve fazer parsing robusto de preços formatados em String brasileira (vírgula e ponto)', () {
        controller.servicoSelecionado = {
          'nome': 'Tratamento Especial',
          'valorUnitario': '1.250,50',
          'duracaoMinutos': '60',
          'intervaloAposAtendimentoMinutos': '15',
        };

        expect(controller.precoServico, equals(1250.50));
        expect(controller.duracaoServicoMinutos, equals(60));
        expect(controller.intervaloAposAtendimentoMinutos, equals(15));
      });

      test('deve suportar campos alternativos legados como valor, preco e price', () {
        controller.servicoSelecionado = {
          'descricao': 'Manicure Simples',
          'valor': 40.0,
        };
        expect(controller.servicoNome, equals('Manicure Simples'));
        expect(controller.precoServico, equals(40.0));

        controller.servicoSelecionado = {
          'nome': 'Pedicure',
          'preco': 45.0,
        };
        expect(controller.precoServico, equals(45.0));

        controller.servicoSelecionado = {
          'nome': 'Design Sobrancelhas',
          'price': '35,00',
        };
        expect(controller.precoServico, equals(35.0));
      });
    });

    group('Getters de Data e Horário', () {
      test('deve formatar data selecionada em pt_BR corretamente', () {
        final data = DateTime(2026, 9, 25);
        controller.dataSelecionada = data;

        expect(controller.dataFormatada, equals('25/09/2026'));
        expect(controller.dataFormatadaCompleta.toLowerCase(), contains('setembro'));
        expect(controller.dataFormatadaCompleta, contains('2026'));
      });

      test('selecionarHorario deve atualizar horarioSelecionado ignorando strings vazias', () {
        controller.selecionarHorario('  ');
        expect(controller.horarioSelecionado, isNull);

        controller.selecionarHorario('14:30');
        expect(controller.horarioSelecionado, equals('14:30'));
      });
    });

    group('Validações de Dados do Cliente', () {
      test('deve exigir nome com pelo menos 2 caracteres', () {
        controller.nomeClienteCtrl.text = '';
        expect(controller.validarDadosCliente(), equals('Informe seu nome.'));

        controller.nomeClienteCtrl.text = 'A';
        expect(controller.validarDadosCliente(), equals('Informe um nome válido.'));

        controller.nomeClienteCtrl.text = 'Carlos Silva';
        // Sem telefone preenchido
        expect(controller.validarDadosCliente(), equals('Informe seu WhatsApp ou telefone.'));
      });

      test('deve validar telefone com DDD (mínimo 10 dígitos numéricos)', () {
        controller.nomeClienteCtrl.text = 'Carlos Silva';
        controller.telefoneClienteCtrl.text = '9999-999';
        expect(controller.validarDadosCliente(), equals('Informe um telefone válido com DDD.'));

        controller.telefoneClienteCtrl.text = '(11) 98765-4321';
        expect(controller.validarDadosCliente(), isNull);
      });

      test('deve validar formato do e-mail quando informado', () {
        controller.nomeClienteCtrl.text = 'Carlos Silva';
        controller.telefoneClienteCtrl.text = '(11) 98765-4321';
        
        controller.emailClienteCtrl.text = 'email_invalido';
        expect(controller.validarDadosCliente(), equals('Informe um e-mail válido.'));

        controller.emailClienteCtrl.text = 'carlos@empresa.com.br';
        expect(controller.validarDadosCliente(), isNull);
      });
    });

    group('Navegação e Transição de Etapas', () {
      test('voltarParaServico deve redefinir etapaAtual para 0 e limpar seleções posteriores', () {
        controller.etapaAtual = 1;
        controller.profissionalId = 'prof_123';
        controller.dataSelecionada = DateTime(2026, 9, 25);
        controller.horarioSelecionado = '10:00';

        controller.voltarParaServico();

        expect(controller.etapaAtual, equals(0));
        expect(controller.profissionalId, isNull);
        expect(controller.dataSelecionada, isNull);
        expect(controller.horarioSelecionado, isNull);
      });

      test('irParaDadosCliente só deve avançar da etapa 2 para a etapa 3 se data e horário existirem', () {
        controller.etapaAtual = 2;
        controller.dataSelecionada = null;
        controller.horarioSelecionado = null;

        controller.irParaDadosCliente();
        expect(controller.etapaAtual, equals(2));

        controller.dataSelecionada = DateTime(2026, 9, 25);
        controller.irParaDadosCliente();
        expect(controller.etapaAtual, equals(2));

        controller.horarioSelecionado = '09:00';
        controller.irParaDadosCliente();
        expect(controller.etapaAtual, equals(3));
      });

      test('irParaConfirmacao deve bloquear avanço se validação do cliente falhar ou dados incompletos', () {
        controller.etapaAtual = 3;
        controller.servicoId = 'serv_1';
        controller.profissionalId = 'prof_1';
        controller.dataSelecionada = DateTime(2026, 9, 25);
        controller.horarioSelecionado = '09:00';

        // Cliente inválido
        controller.nomeClienteCtrl.text = '';
        controller.irParaConfirmacao();
        expect(controller.etapaAtual, equals(3));

        // Cliente válido
        controller.nomeClienteCtrl.text = 'Mariana Oliveira';
        controller.telefoneClienteCtrl.text = '(47) 99888-7766';
        controller.irParaConfirmacao();
        expect(controller.etapaAtual, equals(4));
      });

      test('novoAgendamento deve reiniciar completamente o formulário e voltar para etapa 0', () {
        controller.etapaAtual = 4;
        controller.servicoId = 'serv_1';
        controller.nomeClienteCtrl.text = 'Mariana';
        controller.telefoneClienteCtrl.text = '47998887766';
        controller.protocoloAgendamento = 'AG-2026-999';
        controller.agendamentoConcluido = true;

        controller.novoAgendamento();

        expect(controller.etapaAtual, equals(0));
        expect(controller.servicoId, isNull);
        expect(controller.nomeClienteCtrl.text, isEmpty);
        expect(controller.telefoneClienteCtrl.text, isEmpty);
        expect(controller.protocoloAgendamento, isEmpty);
        expect(controller.agendamentoConcluido, isFalse);
      });
    });

    group('Regras de Exibição de Informações da Empresa', () {
      test('possuiContato deve retornar true se whatsapp ou instagram estiver preenchido', () {
        expect(controller.possuiContato, isFalse);

        controller.whatsapp = '11988887777';
        expect(controller.possuiContato, isTrue);

        controller.whatsapp = '';
        controller.instagram = '@salao_vip';
        expect(controller.possuiContato, isTrue);
      });

      test('exibirLocalizacao só é verdadeiro se exibirEndereco estiver habilitado e endereço não for vazio', () {
        controller.endereco = 'Av. Paulista, 1000 - Sala 42';
        controller.exibirEndereco = false;
        expect(controller.exibirLocalizacao, isFalse);

        controller.exibirEndereco = true;
        expect(controller.exibirLocalizacao, isTrue);

        controller.endereco = '   ';
        expect(controller.exibirLocalizacao, isFalse);
      });
    });
  });
}
