import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HorarioProfissionalScreen extends StatefulWidget {
  final String profissionalId;
  final String profissionalNome;
  final String companyId;

  const HorarioProfissionalScreen({
    super.key,
    required this.profissionalId,
    required this.profissionalNome,
    required this.companyId,
  });

  @override
  State<HorarioProfissionalScreen> createState() =>
      _HorarioProfissionalScreenState();
}

class _HorarioProfissionalScreenState extends State<HorarioProfissionalScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _carregando = true;
  bool _salvando = false;

  bool _usaHorarioPadraoEmpresa = true;

  Map<String, DiaHorario> _horariosEmpresa = {};
  Map<String, DiaHorario> _horariosProfissional = {};

  final Map<String, String> _labelsDias = {
    'segunda': 'Segunda-feira',
    'terca': 'Terça-feira',
    'quarta': 'Quarta-feira',
    'quinta': 'Quinta-feira',
    'sexta': 'Sexta-feira',
    'sabado': 'Sábado',
    'domingo': 'Domingo',
  };

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      await _carregarHorarioEmpresa();
      await _carregarHorarioProfissional();

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

  Future<void> _carregarHorarioEmpresa() async {
    final doc =
        await _fs
            .collection('agenda_configuracoes')
            .doc(widget.companyId)
            .get();

    final Map<String, DiaHorario> horarios = {};

    for (final entry in _labelsDias.entries) {
      horarios[entry.key] = DiaHorario(
        label: entry.value,
        ativo: false,
        periodos: [],
      );
    }

    if (!doc.exists) {
      _horariosEmpresa = horarios;
      _horariosProfissional = _copiarHorarios(horarios);
      return;
    }

    final data = doc.data();

    if (data == null) {
      _horariosEmpresa = horarios;
      _horariosProfissional = _copiarHorarios(horarios);
      return;
    }

    final raw = data['horariosFuncionamento'];

    if (raw is Map) {
      for (final entry in _labelsDias.entries) {
        final diaRaw = raw[entry.key];

        if (diaRaw is! Map) {
          continue;
        }

        final ativo = (diaRaw['ativo'] ?? false) == true;

        final periodos = <PeriodoHorario>[];

        final periodosRaw = diaRaw['periodos'];

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

        horarios[entry.key] = DiaHorario(
          label: entry.value,
          ativo: ativo,
          periodos: periodos,
        );
      }
    }

    _horariosEmpresa = horarios;
    _horariosProfissional = _copiarHorarios(horarios);
  }

  Future<void> _carregarHorarioProfissional() async {
    final doc =
        await _fs
            .collection('agenda_profissionais_horarios')
            .doc(widget.profissionalId)
            .get();

    if (!doc.exists) {
      _usaHorarioPadraoEmpresa = true;
      _horariosProfissional = _copiarHorarios(_horariosEmpresa);
      return;
    }

    final data = doc.data();

    if (data == null) {
      return;
    }

    _usaHorarioPadraoEmpresa =
        (data['usaHorarioPadraoEmpresa'] ?? true) == true;

    if (_usaHorarioPadraoEmpresa) {
      _horariosProfissional = _copiarHorarios(_horariosEmpresa);
      return;
    }

    final raw = data['horarios'];

    if (raw is! Map) {
      _horariosProfissional = _copiarHorarios(_horariosEmpresa);
      return;
    }

    final horarios = <String, DiaHorario>{};

    for (final entry in _labelsDias.entries) {
      final diaRaw = raw[entry.key];

      if (diaRaw is! Map) {
        horarios[entry.key] = DiaHorario(
          label: entry.value,
          ativo: false,
          periodos: [],
        );
        continue;
      }

      final ativo = (diaRaw['ativo'] ?? false) == true;

      final periodos = <PeriodoHorario>[];

      final periodosRaw = diaRaw['periodos'];

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

      horarios[entry.key] = DiaHorario(
        label: entry.value,
        ativo: ativo,
        periodos: periodos,
      );
    }

    _horariosProfissional = horarios;
  }

  Map<String, DiaHorario> _copiarHorarios(Map<String, DiaHorario> origem) {
    final copia = <String, DiaHorario>{};

    for (final entry in origem.entries) {
      copia[entry.key] = DiaHorario(
        label: entry.value.label,
        ativo: entry.value.ativo,
        periodos:
            entry.value.periodos
                .map((p) => PeriodoHorario(inicio: p.inicio, fim: p.fim))
                .toList(),
      );
    }

    return copia;
  }

  Future<void> _selecionarHorario({
    required String diaKey,
    required int index,
    required bool inicio,
  }) async {
    final dia = _horariosProfissional[diaKey];

    if (dia == null) return;

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

    if (horario == null) return;

    final valor = _formatarHorario(horario);

    setState(() {
      if (inicio) {
        periodo.inicio = valor;
      } else {
        periodo.fim = valor;
      }
    });
  }

  void _adicionarPeriodo(String diaKey) {
    final dia = _horariosProfissional[diaKey];

    if (dia == null) return;

    setState(() {
      dia.periodos.add(PeriodoHorario(inicio: '08:00', fim: '12:00'));
    });
  }

  void _removerPeriodo(String diaKey, int index) {
    final dia = _horariosProfissional[diaKey];

    if (dia == null) return;

    setState(() {
      dia.periodos.removeAt(index);
    });
  }

  String? _validar() {
    if (_usaHorarioPadraoEmpresa) {
      return null;
    }

    for (final entry in _horariosProfissional.entries) {
      final dia = entry.value;

      if (!dia.ativo) continue;

      if (dia.periodos.isEmpty) {
        return '${dia.label}: adicione pelo menos um horário.';
      }

      final ordenados = [...dia.periodos];

      ordenados.sort(
        (a, b) => _horarioParaMinutos(
          a.inicio,
        ).compareTo(_horarioParaMinutos(b.inicio)),
      );

      for (int i = 0; i < ordenados.length; i++) {
        final atual = ordenados[i];

        final inicioAtual = _horarioParaMinutos(atual.inicio);

        final fimAtual = _horarioParaMinutos(atual.fim);

        if (fimAtual <= inicioAtual) {
          return '${dia.label}: o horário final precisa ser posterior ao inicial.';
        }

        if (i > 0) {
          final anterior = ordenados[i - 1];

          final fimAnterior = _horarioParaMinutos(anterior.fim);

          if (inicioAtual < fimAnterior) {
            return '${dia.label}: existem horários sobrepostos.';
          }
        }
      }
    }

    return null;
  }

  Future<void> _salvar() async {
    final erro = _validar();

    if (erro != null) {
      _mensagem(erro);
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final dados = <String, dynamic>{
        'companyId': widget.companyId,
        'profissionalId': widget.profissionalId,
        'usaHorarioPadraoEmpresa': _usaHorarioPadraoEmpresa,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser?.uid,
      };

      if (!_usaHorarioPadraoEmpresa) {
        final horarios = <String, dynamic>{};

        for (final entry in _horariosProfissional.entries) {
          horarios[entry.key] = {
            'ativo': entry.value.ativo,
            'periodos':
                entry.value.periodos
                    .map((p) => {'inicio': p.inicio, 'fim': p.fim})
                    .toList(),
          };
        }

        dados['horarios'] = horarios;
      } else {
        dados['horarios'] = FieldValue.delete();
      }

      final ref = _fs
          .collection('agenda_profissionais_horarios')
          .doc(widget.profissionalId);

      final atual = await ref.get();

      if (!atual.exists) {
        dados['createdAt'] = FieldValue.serverTimestamp();
      }

      await ref.set(dados, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Horário do profissional salvo com sucesso.'),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      _mensagem('Erro ao salvar horário: $e');
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  TimeOfDay _stringParaTimeOfDay(String value) {
    final partes = value.split(':');

    if (partes.length != 2) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    return TimeOfDay(
      hour: int.tryParse(partes[0]) ?? 8,
      minute: int.tryParse(partes[1]) ?? 0,
    );
  }

  String _formatarHorario(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  int _horarioParaMinutos(String horario) {
    final partes = horario.split(':');

    if (partes.length != 2) return 0;

    final hora = int.tryParse(partes[0]) ?? 0;

    final minuto = int.tryParse(partes[1]) ?? 0;

    return hora * 60 + minuto;
  }

  void _mensagem(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F7FC),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Horário do profissional',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon:
                _salvando
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _cabecalho(),

          const SizedBox(height: 14),

          _cardHorarioPadrao(),

          const SizedBox(height: 14),

          if (!_usaHorarioPadraoEmpresa)
            ..._horariosProfissional.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _cardDia(entry.key, entry.value),
              ),
            ),

          if (_usaHorarioPadraoEmpresa) _visualizarHorarioPadrao(),

          const SizedBox(height: 12),

          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar horário'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E1EA)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 23,
            backgroundColor: Color(0xFFECE8F8),
            child: Icon(Icons.person_outline, color: Color(0xFF545F9E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.profissionalNome,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Defina os horários em que este profissional poderá receber agendamentos.',
                  style: TextStyle(color: Color(0xFF686571), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardHorarioPadrao() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E1EA)),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Usar horário padrão da empresa',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Quando ativado, qualquer alteração feita no horário geral da empresa será automaticamente aplicada a este profissional.',
        ),
        value: _usaHorarioPadraoEmpresa,
        onChanged: (value) {
          setState(() {
            _usaHorarioPadraoEmpresa = value;

            if (!value) {
              _horariosProfissional = _copiarHorarios(_horariosEmpresa);
            }
          });
        },
      ),
    );
  }

  Widget _visualizarHorarioPadrao() {
    return Column(
      children:
          _horariosEmpresa.entries.map((entry) {
            final dia = entry.value;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4E1EA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dia.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (!dia.ativo)
                    const Text(
                      'Não atende',
                      style: TextStyle(color: Color(0xFF777380)),
                    )
                  else
                    ...dia.periodos.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${p.inicio} até ${p.fim}'),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _cardDia(String diaKey, DiaHorario dia) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E1EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dia.label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch.adaptive(
                value: dia.ativo,
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

          if (!dia.ativo)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Não atende neste dia',
                style: TextStyle(color: Color(0xFF777380)),
              ),
            ),

          if (dia.ativo) ...[
            const SizedBox(height: 8),

            ...List.generate(dia.periodos.length, (index) {
              final periodo = dia.periodos[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _botaoHorario(
                        periodo.inicio,
                        () => _selecionarHorario(
                          diaKey: diaKey,
                          index: index,
                          inicio: true,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('até'),
                    ),
                    Expanded(
                      child: _botaoHorario(
                        periodo.fim,
                        () => _selecionarHorario(
                          diaKey: diaKey,
                          index: index,
                          inicio: false,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          dia.periodos.length > 1
                              ? () => _removerPeriodo(diaKey, index)
                              : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),

            TextButton.icon(
              onPressed: () => _adicionarPeriodo(diaKey),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar horário'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botaoHorario(String valor, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F8FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDAD6E0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 19, color: Color(0xFF545F9E)),
            const SizedBox(width: 8),
            Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

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
