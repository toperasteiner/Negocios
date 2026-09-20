import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HorarioFuncionamentoScreen extends StatefulWidget {
  const HorarioFuncionamentoScreen({super.key});

  @override
  State<HorarioFuncionamentoScreen> createState() =>
      _HorarioFuncionamentoScreenState();
}

class _HorarioFuncionamentoScreenState
    extends State<HorarioFuncionamentoScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _saving = false;
  bool _funciona24x7 = false;
  bool _aceitaPedidoForaHorario = true;

  String? _companyId;
  String? _erro;
  bool _mostrarSucesso = false;

  final Map<String, _DiaHorario> _horarios = {
    'segunda': _DiaHorario(label: 'Segunda-feira'),
    'terca': _DiaHorario(label: 'Terça-feira'),
    'quarta': _DiaHorario(label: 'Quarta-feira'),
    'quinta': _DiaHorario(label: 'Quinta-feira'),
    'sexta': _DiaHorario(label: 'Sexta-feira'),
    'sabado': _DiaHorario(label: 'Sábado'),
    'domingo': _DiaHorario(label: 'Domingo'),
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<Map<String, dynamic>?> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final byUid = await _fs.collection('users').doc(user.uid).get();
    if (byUid.exists) return byUid.data();

    final emailKey = (user.email ?? '').trim().toLowerCase();
    if (emailKey.isNotEmpty) {
      final q =
          await _fs
              .collection('users')
              .where('emailKey', isEqualTo: emailKey)
              .limit(1)
              .get();

      if (q.docs.isNotEmpty) return q.docs.first.data();
    }

    return null;
  }

  Future<void> _carregar() async {
    try {
      final userData = await _loadUserData();
      final companyId = (userData?['companyId'] ?? '').toString().trim();

      if (companyId.isEmpty) {
        setState(() {
          _loading = false;
          _erro = 'Empresa não identificada para este usuário.';
        });
        return;
      }

      final doc = await _fs.collection('catalogo').doc(companyId).get();
      final data = doc.data();

      final horarioMap = data?['horarioFuncionamento'];

      if (horarioMap is Map) {
        for (final entry in _horarios.entries) {
          final diaData = horarioMap[entry.key];

          if (diaData is Map) {
            final aberto = diaData['aberto'] == true;
            final periodosRaw = diaData['periodos'];

            entry.value.aberto = aberto;
            entry.value.periodos.clear();

            if (periodosRaw is List) {
              for (final p in periodosRaw) {
                if (p is Map) {
                  entry.value.periodos.add(
                    _PeriodoHorario(
                      inicio: (p['inicio'] ?? '08:00').toString(),
                      fim: (p['fim'] ?? '18:00').toString(),
                      cruzaDia: p['cruzaDia'] == true,
                    ),
                  );
                }
              }
            }

            if (entry.value.periodos.isEmpty && aberto) {
              entry.value.periodos.add(_PeriodoHorario());
            }
          }
        }
      }

      setState(() {
        _companyId = companyId;
        _funciona24x7 = data?['funciona24x7'] == true;
        _aceitaPedidoForaHorario =
            (data?['aceitaPedidoForaHorario'] ?? true) == true;
        _loading = false;
        _erro = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _erro = 'Erro ao carregar horário de funcionamento: $e';
      });
    }
  }

  Future<void> _salvar() async {
    final companyId = _companyId;

    if (companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final horarioFuncionamento = <String, dynamic>{};

      for (final entry in _horarios.entries) {
        final dia = entry.value;

        horarioFuncionamento[entry.key] = {
          'aberto': _funciona24x7 ? true : dia.aberto,
          'periodos':
              _funciona24x7
                  ? []
                  : dia.periodos.map((p) {
                    return {
                      'inicio': p.inicio,
                      'fim': p.fim,
                      'cruzaDia': _cruzaDia(p.inicio, p.fim),
                    };
                  }).toList(),
        };
      }

      await _fs.collection('catalogo').doc(companyId).set({
        'companyId': companyId,
        'funciona24x7': _funciona24x7,
        'aceitaPedidoForaHorario': _aceitaPedidoForaHorario,
        'horarioFuncionamento': horarioFuncionamento,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _saving = false;
        _mostrarSucesso = true;
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() => _mostrarSucesso = false);
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar horário: $e')));
    }
  }

  bool _cruzaDia(String inicio, String fim) {
    final ini = _minutos(inicio);
    final end = _minutos(fim);
    return end <= ini;
  }

  int _minutos(String hora) {
    final parts = hora.split(':');
    if (parts.length != 2) return 0;

    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    return h * 60 + m;
  }

  Future<String?> _selecionarHora(String horaAtual) async {
    final parts = horaAtual.split(':');
    final inicial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );

    final result = await showTimePicker(
      context: context,
      initialTime: inicial,
      helpText: 'Selecionar horário',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );

    if (result == null) return null;

    final h = result.hour.toString().padLeft(2, '0');
    final m = result.minute.toString().padLeft(2, '0');

    return '$h:$m';
  }

  Widget _buildSucessoBanner() {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      offset: _mostrarSucesso ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _mostrarSucesso ? 1 : 0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Configuração atualizada',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () {
                  setState(() => _mostrarSucesso = false);
                },
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiaCard(String key, _DiaHorario dia) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                dia.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                dia.aberto ? 'Aberto neste dia' : 'Fechado neste dia',
              ),
              value: dia.aberto,
              onChanged:
                  _funciona24x7
                      ? null
                      : (value) {
                        setState(() {
                          dia.aberto = value;

                          if (value && dia.periodos.isEmpty) {
                            dia.periodos.add(_PeriodoHorario());
                          }
                        });
                      },
            ),
            if (dia.aberto && !_funciona24x7) ...[
              const SizedBox(height: 8),
              ...dia.periodos.asMap().entries.map((entry) {
                final index = entry.key;
                final periodo = entry.value;
                final cruzaDia = _cruzaDia(periodo.inicio, periodo.fim);

                return Container(
                  key: ValueKey('$key-$index-${periodo.inicio}-${periodo.fim}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _HoraButton(
                              label: 'Início',
                              value: periodo.inicio,
                              onTap: () async {
                                final hora = await _selecionarHora(
                                  periodo.inicio,
                                );
                                if (hora == null) return;

                                setState(() {
                                  periodo.inicio = hora;
                                  periodo.cruzaDia = _cruzaDia(
                                    periodo.inicio,
                                    periodo.fim,
                                  );
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HoraButton(
                              label: 'Fim',
                              value: periodo.fim,
                              onTap: () async {
                                final hora = await _selecionarHora(periodo.fim);
                                if (hora == null) return;

                                setState(() {
                                  periodo.fim = hora;
                                  periodo.cruzaDia = _cruzaDia(
                                    periodo.inicio,
                                    periodo.fim,
                                  );
                                });
                              },
                            ),
                          ),
                          if (dia.periodos.length > 1) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Remover período',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                setState(() {
                                  dia.periodos.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                      if (cruzaDia) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.nights_stay_outlined,
                              size: 18,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Este horário termina no dia seguinte.',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      dia.periodos.add(_PeriodoHorario());
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar período'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Horário de funcionamento')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erro!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horário de funcionamento'),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _saving ? null : _salvar,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_mostrarSucesso) _buildSucessoBanner(),
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    title: const Text(
                      'Funciona 24x7',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Ative se a loja aceita pedidos 24 horas por dia, todos os dias.',
                    ),
                    value: _funciona24x7,
                    onChanged: (value) {
                      setState(() {
                        _funciona24x7 = value;
                      });
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    title: const Text(
                      'Aceitar pedido fora do horário',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _aceitaPedidoForaHorario
                          ? 'Clientes poderão enviar pedidos mesmo com a loja fechada.'
                          : 'Clientes não poderão finalizar pedidos fora do horário.',
                    ),
                    value: _aceitaPedidoForaHorario,
                    onChanged: (value) {
                      setState(() {
                        _aceitaPedidoForaHorario = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_funciona24x7)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Com funcionamento 24x7 ativo, não é necessário cadastrar horários por dia.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const Text(
                'Configure os dias e horários em que a loja funciona.',
                style: TextStyle(fontSize: 16, height: 1.35),
              ),
              const SizedBox(height: 16),
              ..._horarios.entries.map((entry) {
                return _buildDiaCard(entry.key, entry.value);
              }),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _salvar,
              icon:
                  _saving
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Salvando...' : 'Salvar configuração'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DiaHorario {
  final String label;
  bool aberto;
  List<_PeriodoHorario> periodos;

  _DiaHorario({
    required this.label,
    this.aberto = false,
    List<_PeriodoHorario>? periodos,
  }) : periodos = periodos ?? [];
}

class _PeriodoHorario {
  String inicio;
  String fim;
  bool cruzaDia;

  _PeriodoHorario({
    this.inicio = '08:00',
    this.fim = '18:00',
    this.cruzaDia = false,
  });
}

class _HoraButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _HoraButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
