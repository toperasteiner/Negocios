import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HorariosFuncionamentoScreen extends StatefulWidget {
  const HorariosFuncionamentoScreen({super.key});

  @override
  State<HorariosFuncionamentoScreen> createState() =>
      _HorariosFuncionamentoScreenState();
}

class _HorariosFuncionamentoScreenState
    extends State<HorariosFuncionamentoScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _carregando = true;
  bool _salvando = false;

  String? _companyId;

  final Map<String, DiaHorario> _dias = {
    'segunda': DiaHorario(
      label: 'Segunda-feira',
      ativo: true,
      periodos: [
        PeriodoHorario(inicio: '08:00', fim: '12:00'),
        PeriodoHorario(inicio: '13:00', fim: '18:00'),
      ],
    ),
    'terca': DiaHorario(
      label: 'Terça-feira',
      ativo: true,
      periodos: [
        PeriodoHorario(inicio: '08:00', fim: '12:00'),
        PeriodoHorario(inicio: '13:00', fim: '18:00'),
      ],
    ),
    'quarta': DiaHorario(
      label: 'Quarta-feira',
      ativo: true,
      periodos: [
        PeriodoHorario(inicio: '08:00', fim: '12:00'),
        PeriodoHorario(inicio: '13:00', fim: '18:00'),
      ],
    ),
    'quinta': DiaHorario(
      label: 'Quinta-feira',
      ativo: true,
      periodos: [
        PeriodoHorario(inicio: '08:00', fim: '12:00'),
        PeriodoHorario(inicio: '13:00', fim: '18:00'),
      ],
    ),
    'sexta': DiaHorario(
      label: 'Sexta-feira',
      ativo: true,
      periodos: [
        PeriodoHorario(inicio: '08:00', fim: '12:00'),
        PeriodoHorario(inicio: '13:00', fim: '18:00'),
      ],
    ),
    'sabado': DiaHorario(
      label: 'Sábado',
      ativo: true,
      periodos: [PeriodoHorario(inicio: '08:00', fim: '12:00')],
    ),
    'domingo': DiaHorario(label: 'Domingo', ativo: false, periodos: []),
  };

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

      if (companyId == null || companyId.isEmpty) {
        setState(() {
          _carregando = false;
        });

        _mensagem('Não foi possível identificar a empresa.');
        return;
      }

      _companyId = companyId;

      await _carregarConfiguracao();

      if (!mounted) return;

      setState(() {
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem('Erro ao carregar horários: $e');
    }
  }

  /* ==========================================================
     IDENTIFICAR EMPRESA
     ========================================================== */

  Future<String?> _descobrirCompanyId() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

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

    final data = query.docs.first.data();

    final companyId = (data['companyId'] ?? '').toString().trim();

    return companyId.isEmpty ? null : companyId;
  }

  /* ==========================================================
     CARREGAR CONFIGURAÇÃO
     ========================================================== */

  Future<void> _carregarConfiguracao() async {
    if (_companyId == null) {
      return;
    }

    final doc =
        await _fs.collection('agenda_configuracoes').doc(_companyId).get();

    if (!doc.exists) {
      return;
    }

    final data = doc.data();

    if (data == null) {
      return;
    }

    final horarios = data['horariosFuncionamento'];

    if (horarios is! Map) {
      return;
    }

    for (final entry in _dias.entries) {
      final chave = entry.key;

      final configDia = horarios[chave];

      if (configDia is! Map) {
        continue;
      }

      final ativo = (configDia['ativo'] ?? false) == true;

      final periodosRaw = configDia['periodos'];

      final List<PeriodoHorario> periodos = [];

      if (periodosRaw is List) {
        for (final item in periodosRaw) {
          if (item is Map) {
            final inicio = (item['inicio'] ?? '').toString();

            final fim = (item['fim'] ?? '').toString();

            if (inicio.isNotEmpty && fim.isNotEmpty) {
              periodos.add(PeriodoHorario(inicio: inicio, fim: fim));
            }
          }
        }
      }

      _dias[chave] = DiaHorario(
        label: entry.value.label,
        ativo: ativo,
        periodos: periodos,
      );
    }
  }

  /* ==========================================================
     SELECIONAR HORÁRIO
     ========================================================== */

  Future<void> _selecionarHorario({
    required String diaKey,
    required int index,
    required bool inicio,
  }) async {
    final dia = _dias[diaKey];

    if (dia == null) {
      return;
    }

    final periodo = dia.periodos[index];

    final valorAtual = inicio ? periodo.inicio : periodo.fim;

    final initialTime = _stringParaTimeOfDay(valorAtual);

    final horario = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: inicio ? 'Horário inicial' : 'Horário final',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );

    if (horario == null) {
      return;
    }

    final valor = _formatarHorario(horario);

    setState(() {
      if (inicio) {
        periodo.inicio = valor;
      } else {
        periodo.fim = valor;
      }
    });
  }

  /* ==========================================================
     ADICIONAR PERÍODO
     ========================================================== */

  void _adicionarPeriodo(String diaKey) {
    final dia = _dias[diaKey];

    if (dia == null) {
      return;
    }

    String inicio = '08:00';
    String fim = '12:00';

    if (dia.periodos.isNotEmpty) {
      final ultimo = dia.periodos.last;

      final ultimoFimMin = _horarioParaMinutos(ultimo.fim);

      final novoInicio = ultimoFimMin + 60;
      final novoFim = novoInicio + 60;

      if (novoInicio < 24 * 60) {
        inicio = _minutosParaHorario(novoInicio.clamp(0, 1439));
      }

      if (novoFim < 24 * 60) {
        fim = _minutosParaHorario(novoFim.clamp(0, 1439));
      }
    }

    setState(() {
      dia.periodos.add(PeriodoHorario(inicio: inicio, fim: fim));
    });
  }

  /* ==========================================================
     REMOVER PERÍODO
     ========================================================== */

  void _removerPeriodo(String diaKey, int index) {
    final dia = _dias[diaKey];

    if (dia == null) {
      return;
    }

    setState(() {
      dia.periodos.removeAt(index);
    });
  }

  /* ==========================================================
     COPIAR HORÁRIOS
     ========================================================== */

  Future<void> _copiarHorarios(String origemKey) async {
    final origem = _dias[origemKey];

    if (origem == null) {
      return;
    }

    final selecionados = <String, bool>{};

    for (final key in _dias.keys) {
      if (key != origemKey) {
        selecionados[key] = false;
      }
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Row(
                children: [
                  _AgendaIconBadge(
                    icon: Icons.content_copy_outlined,
                    color: AgendaHorarioStyle.primary,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Copiar horários',
                      style: TextStyle(
                        color: AgendaHorarioStyle.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecione os dias que receberão os mesmos horários de ${origem.label}.',
                      style: const TextStyle(
                        color: AgendaHorarioStyle.muted,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ...selecionados.entries.map((entry) {
                      final dia = _dias[entry.key]!;

                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: AgendaHorarioStyle.primary,
                        title: Text(
                          dia.label,
                          style: const TextStyle(
                            color: AgendaHorarioStyle.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        value: entry.value,
                        onChanged: (value) {
                          setDialogState(() {
                            selecionados[entry.key] = value ?? false;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AgendaHorarioStyle.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Copiar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmou != true) {
      return;
    }

    setState(() {
      for (final entry in selecionados.entries) {
        if (!entry.value) {
          continue;
        }

        final destino = _dias[entry.key]!;

        destino.ativo = origem.ativo;

        destino.periodos =
            origem.periodos
                .map((p) => PeriodoHorario(inicio: p.inicio, fim: p.fim))
                .toList();
      }
    });

    _mensagem('Horários copiados.');
  }

  /* ==========================================================
     VALIDAÇÃO
     ========================================================== */

  String? _validar() {
    for (final entry in _dias.entries) {
      final dia = entry.value;

      if (!dia.ativo) {
        continue;
      }

      if (dia.periodos.isEmpty) {
        return '${dia.label}: adicione pelo menos um horário.';
      }

      final periodosOrdenados = [...dia.periodos];

      periodosOrdenados.sort(
        (a, b) => _horarioParaMinutos(
          a.inicio,
        ).compareTo(_horarioParaMinutos(b.inicio)),
      );

      for (int i = 0; i < periodosOrdenados.length; i++) {
        final atual = periodosOrdenados[i];

        final inicioAtual = _horarioParaMinutos(atual.inicio);

        final fimAtual = _horarioParaMinutos(atual.fim);

        if (fimAtual <= inicioAtual) {
          return '${dia.label}: o horário final precisa ser posterior ao horário inicial.';
        }

        if (i > 0) {
          final anterior = periodosOrdenados[i - 1];

          final fimAnterior = _horarioParaMinutos(anterior.fim);

          if (inicioAtual < fimAnterior) {
            return '${dia.label}: existem horários sobrepostos.';
          }
        }
      }
    }

    return null;
  }

  /* ==========================================================
     SALVAR
     ========================================================== */

  Future<void> _salvar() async {
    final erro = _validar();

    if (erro != null) {
      _mensagem(erro);
      return;
    }

    if (_companyId == null || _companyId!.isEmpty) {
      _mensagem('Não foi possível identificar a empresa.');
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final horarios = <String, dynamic>{};

      for (final entry in _dias.entries) {
        final dia = entry.value;

        horarios[entry.key] = {
          'ativo': dia.ativo,
          'periodos':
              dia.periodos
                  .map((p) => {'inicio': p.inicio, 'fim': p.fim})
                  .toList(),
        };
      }

      final ref = _fs.collection('agenda_configuracoes').doc(_companyId);

      final doc = await ref.get();

      final dados = <String, dynamic>{
        'companyId': _companyId,
        'horariosFuncionamento': horarios,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      };

      if (!doc.exists) {
        dados['createdAt'] = FieldValue.serverTimestamp();
      }

      await ref.set(dados, SetOptions(merge: true));

      if (!mounted) return;

      _mensagem('Horários salvos com sucesso.');
    } catch (e) {
      if (!mounted) return;

      _mensagem('Erro ao salvar horários: $e');
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  /* ==========================================================
     AUXILIARES
     ========================================================== */

  TimeOfDay _stringParaTimeOfDay(String value) {
    final partes = value.split(':');

    if (partes.length != 2) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    final hora = int.tryParse(partes[0]) ?? 8;

    final minuto = int.tryParse(partes[1]) ?? 0;

    return TimeOfDay(hour: hora, minute: minuto);
  }

  String _formatarHorario(TimeOfDay time) {
    final hora = time.hour.toString().padLeft(2, '0');

    final minuto = time.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  int _horarioParaMinutos(String horario) {
    final partes = horario.split(':');

    if (partes.length != 2) {
      return 0;
    }

    final hora = int.tryParse(partes[0]) ?? 0;

    final minuto = int.tryParse(partes[1]) ?? 0;

    return hora * 60 + minuto;
  }

  String _minutosParaHorario(int minutos) {
    final hora = minutos ~/ 60;

    final minuto = minutos % 60;

    return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
  }

  void _mensagem(String texto) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: AgendaHorarioStyle.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AgendaHorarioStyle.bg,
      body: Column(
        children: [
          _AgendaPageHeader(
            title: 'Horários de atendimento',
            subtitle:
                'Defina os dias e horários em que sua empresa poderá receber agendamentos.',
            icon: Icons.schedule_outlined,
            onBack: () => Navigator.of(context).maybePop(),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                _cabecalho(),

                const SizedBox(height: 14),

                ..._dias.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _cardDia(entry.key, entry.value),
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AgendaHorarioStyle.primary,
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
                      _salvando ? 'Salvando...' : 'Salvar horários',
                      style: const TextStyle(fontWeight: FontWeight.w800),
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

  /* ==========================================================
     CABEÇALHO INTERNO
     ========================================================== */

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AgendaHorarioStyle.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AgendaIconBadge(
            icon: Icons.calendar_month_outlined,
            color: AgendaHorarioStyle.blue,
          ),

          SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Horário padrão da empresa',
                  style: TextStyle(
                    color: AgendaHorarioStyle.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                SizedBox(height: 5),

                Text(
                  'Esses horários serão usados como padrão para os profissionais da sua agenda.',
                  style: TextStyle(
                    color: AgendaHorarioStyle.muted,
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
     CARD DIA
     ========================================================== */

  Widget _cardDia(String diaKey, DiaHorario dia) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color:
              dia.ativo
                  ? AgendaHorarioStyle.border
                  : AgendaHorarioStyle.muted.withOpacity(0.20),
        ),
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
                  color:
                      dia.ativo
                          ? AgendaHorarioStyle.primary.withOpacity(0.09)
                          : AgendaHorarioStyle.muted.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  dia.ativo
                      ? Icons.calendar_today_outlined
                      : Icons.event_busy_outlined,
                  color:
                      dia.ativo
                          ? AgendaHorarioStyle.primary
                          : AgendaHorarioStyle.muted,
                  size: 21,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dia.label,
                      style: const TextStyle(
                        color: AgendaHorarioStyle.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      dia.ativo ? _resumoDia(dia) : 'Fechado',
                      style: TextStyle(
                        color:
                            dia.ativo
                                ? AgendaHorarioStyle.muted
                                : AgendaHorarioStyle.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              Switch.adaptive(
                value: dia.ativo,
                activeColor: AgendaHorarioStyle.primary,
                onChanged: (value) {
                  setState(() {
                    dia.ativo = value;

                    if (value && dia.periodos.isEmpty) {
                      dia.periodos.add(
                        PeriodoHorario(inicio: '08:00', fim: '12:00'),
                      );
                    }
                  });
                },
              ),
            ],
          ),

          if (!dia.ativo) ...[
            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AgendaHorarioStyle.orange.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.block_outlined,
                    size: 18,
                    color: AgendaHorarioStyle.orange,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Não recebe agendamentos neste dia.',
                    style: TextStyle(
                      color: AgendaHorarioStyle.orange,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (dia.ativo) ...[
            const SizedBox(height: 14),

            ...List.generate(dia.periodos.length, (index) {
              final periodo = dia.periodos[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _linhaPeriodo(
                  diaKey: diaKey,
                  index: index,
                  periodo: periodo,
                  podeRemover: dia.periodos.length > 1,
                ),
              );
            }),

            const SizedBox(height: 2),

            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AgendaHorarioStyle.primary,
                  ),
                  onPressed: () {
                    _adicionarPeriodo(diaKey);
                  },
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text(
                    'Adicionar horário',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),

                const Spacer(),

                PopupMenuButton<String>(
                  tooltip: 'Mais opções',
                  color: Colors.white,
                  onSelected: (value) {
                    if (value == 'copiar') {
                      _copiarHorarios(diaKey);
                    }
                  },
                  itemBuilder: (context) {
                    return const [
                      PopupMenuItem(
                        value: 'copiar',
                        child: Row(
                          children: [
                            Icon(
                              Icons.content_copy_outlined,
                              color: AgendaHorarioStyle.primary,
                              size: 19,
                            ),
                            SizedBox(width: 10),
                            Text('Copiar para outros dias'),
                          ],
                        ),
                      ),
                    ];
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AgendaHorarioStyle.primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: AgendaHorarioStyle.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _resumoDia(DiaHorario dia) {
    if (dia.periodos.isEmpty) {
      return 'Sem horários';
    }

    if (dia.periodos.length == 1) {
      return '${dia.periodos.first.inicio} às ${dia.periodos.first.fim}';
    }

    return '${dia.periodos.length} períodos configurados';
  }

  /* ==========================================================
     LINHA PERÍODO
     ========================================================== */

  Widget _linhaPeriodo({
    required String diaKey,
    required int index,
    required PeriodoHorario periodo,
    required bool podeRemover,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AgendaHorarioStyle.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgendaHorarioStyle.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _botaoHorario(
              valor: periodo.inicio,
              onTap: () {
                _selecionarHorario(diaKey: diaKey, index: index, inicio: true);
              },
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'até',
              style: TextStyle(
                color: AgendaHorarioStyle.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          Expanded(
            child: _botaoHorario(
              valor: periodo.fim,
              onTap: () {
                _selecionarHorario(diaKey: diaKey, index: index, inicio: false);
              },
            ),
          ),

          const SizedBox(width: 4),

          IconButton(
            tooltip: 'Remover horário',
            onPressed:
                podeRemover
                    ? () {
                      _removerPeriodo(diaKey, index);
                    }
                    : null,
            icon: Icon(
              Icons.delete_outline,
              color:
                  podeRemover
                      ? AgendaHorarioStyle.orange
                      : AgendaHorarioStyle.muted.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  /* ==========================================================
     BOTÃO HORÁRIO
     ========================================================== */

  Widget _botaoHorario({required String valor, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgendaHorarioStyle.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.access_time,
              size: 18,
              color: AgendaHorarioStyle.blue,
            ),

            const SizedBox(width: 7),

            Flexible(
              child: Text(
                valor,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AgendaHorarioStyle.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   MODELOS
   ============================================================ */

class DiaHorario {
  final String label;
  bool ativo;
  List<PeriodoHorario> periodos;

  DiaHorario({
    required this.label,
    required this.ativo,
    required this.periodos,
  });
}

class PeriodoHorario {
  String inicio;
  String fim;

  PeriodoHorario({required this.inicio, required this.fim});
}

/* ============================================================
   HEADER PADRÃO AGENDA
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
        gradient: AgendaHorarioStyle.gradient,
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
                      fontSize: 22,
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

/* ============================================================
   CORES
   ============================================================ */

class AgendaHorarioStyle {
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
