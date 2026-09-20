import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Seletores/SelecionarClienteSheet.dart';
import '../Cadastros/NovoCompromissoSheet.dart';

enum CompromissoFiltro { hoje, semana, dias15, mes, data }

enum StatusFiltro { todos, pendentes, finalizado, cancelado }

/* ---------- helper simples para intervalo ---------- */
class _Range {
  final DateTime start;
  final DateTime endExclusive;
  const _Range(this.start, this.endExclusive);
}

/* ---------- helpers de alerta visual ---------- */
enum _ApptFlag { none, overdue, soon }

_ApptFlag _flagFor(DateTime now, DateTime when) {
  if (when.isBefore(now)) return _ApptFlag.overdue;
  if (!when.isAfter(now.add(const Duration(minutes: 30))))
    return _ApptFlag.soon;
  return _ApptFlag.none;
}

Widget _flagChip(_ApptFlag f, DateTime when) {
  switch (f) {
    case _ApptFlag.overdue:
      return Chip(
        label: const Text(
          'ATRASADO',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.redAccent.shade100,
        side: BorderSide.none,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      );
    case _ApptFlag.soon:
      final mins =
          (() {
            final m = when.difference(DateTime.now()).inMinutes;
            return m <= 0 ? 1 : m;
          })();
      return Chip(
        label: Text(
          'Começa em $mins min',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.amber.shade200,
        side: BorderSide.none,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      );
    case _ApptFlag.none:
      return const SizedBox.shrink();
  }
}

class CompromissosListaScreen extends StatefulWidget {
  const CompromissosListaScreen({super.key});

  @override
  State<CompromissosListaScreen> createState() =>
      _CompromissosListaScreenState();
}

class _CompromissosListaScreenState extends State<CompromissosListaScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  CompromissoFiltro _filtro = CompromissoFiltro.hoje;
  StatusFiltro _statusFiltro = StatusFiltro.todos;
  DateTime? _dataEscolhida;

  /* ================== LOG ================== */
  void _logError(Object error, [StackTrace? stack, String where = '']) {
    final tag =
        where.isEmpty ? 'CompromissosLista' : 'CompromissosLista::$where';
    debugPrint('[$tag] ERROR: $error');
    if (stack != null) {
      debugPrintStack(stackTrace: stack);
    }
  }

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _dayEndExclusive(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  _Range _range() {
    final now = DateTime.now();
    switch (_filtro) {
      case CompromissoFiltro.hoje:
        return _Range(_dayStart(now), _dayEndExclusive(now));
      case CompromissoFiltro.semana:
        final weekday = now.weekday; // 1=Mon ... 7=Sun
        final s = _dayStart(
          now,
        ).subtract(Duration(days: weekday - 1)); // segunda
        final e = _dayEndExclusive(
          s.add(const Duration(days: 6)),
        ); // domingo (excl.)
        return _Range(s, e);
      case CompromissoFiltro.dias15:
        final s = _dayStart(now);
        final e = _dayEndExclusive(s.add(const Duration(days: 14)));
        return _Range(s, e);
      case CompromissoFiltro.mes:
        final s = DateTime(now.year, now.month, 1);
        final e = DateTime(now.year, now.month + 1, 1);
        return _Range(s, e);
      case CompromissoFiltro.data:
        final base = _dataEscolhida ?? now;
        return _Range(_dayStart(base), _dayEndExclusive(base));
    }
  }

  // helper rótulo de período
  String _labelFiltro(CompromissoFiltro f) {
    switch (f) {
      case CompromissoFiltro.hoje:
        return 'Hoje';
      case CompromissoFiltro.semana:
        return 'Essa semana';
      case CompromissoFiltro.dias15:
        return '15 dias';
      case CompromissoFiltro.mes:
        return 'Esse mês';
      case CompromissoFiltro.data:
        return 'Data';
    }
  }

  String _fmtData(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} • $hh:$mi';
  }

  Future<void> _setStatus(String docId, String status) async {
    try {
      await _fs.collection('agenda').doc(docId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      final label = status == 'finalizado' ? 'finalizado' : 'cancelado';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compromisso marcado como $label.')),
      );
    } catch (e, st) {
      _logError(e, st, '_setStatus');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao atualizar status: $e')));
    }
  }

  Widget _statusChip(String status) {
    final s = status.toLowerCase();
    if (s == 'finalizado') {
      return Chip(
        label: const Text(
          'Finalizado',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.green.shade100,
        side: BorderSide.none,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      );
    }
    if (s == 'cancelado') {
      return Chip(
        label: const Text(
          'Cancelado',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.grey.shade300,
        side: BorderSide.none,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      );
    }
    return const SizedBox.shrink();
  }

  // abre sheet de compromisso em modo edição
  Future<void> _editarCompromisso(
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      final ts = data['compromisso'];
      final DateTime? initialDate = ts is Timestamp ? ts.toDate() : null;

      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder:
            (_) => NovoCompromissoSheet(
              docId: docId,
              initial: data,
              initialDate: initialDate,
            ),
      );

      if (!mounted) return;
      if (ok == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compromisso atualizado.')),
        );
      }
    } catch (e, st) {
      _logError(e, st, '_editarCompromisso');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao abrir/atualizar: $e')));
    }
  }

  // excluir (com confirmação)
  Future<void> _excluirCompromisso(String docId) async {
    final sure = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Excluir compromisso?'),
            content: const Text('Esta ação não pode ser desfeita.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
    );
    if (sure != true) return;

    try {
      await _fs.collection('agenda').doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Compromisso excluído.')));
    } catch (e, st) {
      _logError(e, st, '_excluirCompromisso');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao excluir: $e')));
    }
  }

  Future<void> _pickDate() async {
    try {
      final hoje = DateTime.now();
      final d = await showDatePicker(
        context: context,
        firstDate: hoje.subtract(const Duration(days: 365 * 2)),
        lastDate: hoje.add(const Duration(days: 365 * 2)),
        initialDate: _dataEscolhida ?? hoje,
        helpText: 'Escolha a data do compromisso',
      );
      if (d != null) {
        setState(() {
          _dataEscolhida = d;
          _filtro = CompromissoFiltro.data;
        });
      }
    } catch (e, st) {
      _logError(e, st, '_pickDate');
    }
  }

  Future<void> _verificarPorData() async {
    try {
      final hoje = DateTime.now();
      final d = await showDatePicker(
        context: context,
        firstDate: hoje.subtract(const Duration(days: 365 * 2)),
        lastDate: hoje.add(const Duration(days: 365 * 2)),
        initialDate: _dataEscolhida ?? hoje,
        helpText: 'Selecione a data para verificar',
      );
      if (d == null) return;

      final u = _auth.currentUser;
      if (u == null) return;

      final start = _dayStart(d);
      final end = _dayEndExclusive(d);

      // *** SEMPRE por userId do logado ***
      final snap =
          await _fs
              .collection('agenda')
              .where('userId', isEqualTo: u.uid)
              .where(
                'compromisso',
                isGreaterThanOrEqualTo: Timestamp.fromDate(start),
              )
              .where('compromisso', isLessThan: Timestamp.fromDate(end))
              .get();

      final qtd = snap.docs.length;

      if (!mounted) return;
      setState(() {
        _dataEscolhida = d;
        _filtro = CompromissoFiltro.data;
      });

      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final msg =
          qtd == 0
              ? 'Nenhum compromisso em $dd/$mm/${d.year}.'
              : '$qtd compromisso(s) em $dd/$mm/${d.year}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e, st) {
      _logError(e, st, '_verificarPorData');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao verificar por data: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _auth.currentUser;
    if (u == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compromissos')),
        body: const Center(child: Text('Faça login para ver os compromissos.')),
      );
    }

    final r = _range();
    final start = r.start;
    final end = r.endExclusive;

    // *** SEMPRE por userId do logado ***
    Query<Map<String, dynamic>> q = _fs
        .collection('agenda')
        .where('userId', isEqualTo: u.uid)
        .where('compromisso', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('compromisso', isLessThan: Timestamp.fromDate(end))
        .orderBy('compromisso');

    // Filtro por status no servidor quando possível
    if (_statusFiltro == StatusFiltro.finalizado) {
      q = q.where('status', isEqualTo: 'finalizado');
    } else if (_statusFiltro == StatusFiltro.cancelado) {
      q = q.where('status', isEqualTo: 'cancelado');
    }
    // "pendentes" e "todos" filtrados no cliente

    final filtros = CompromissoFiltro.values;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compromissos'),
        actions: [
          IconButton(
            tooltip: 'Verificar dia',
            onPressed: _verificarPorData,
            icon: const Icon(Icons.event_outlined),
          ),
          if (_filtro == CompromissoFiltro.data && _dataEscolhida != null)
            IconButton(
              tooltip: 'Limpar data',
              onPressed: () => setState(() => _dataEscolhida = null),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            final created = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => const NovoCompromissoSheet(),
            );
            if (!mounted) return;
            if (created == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Compromisso criado com sucesso.'),
                ),
              );
            }
          } catch (e, st) {
            _logError(e, st, 'FAB::NovoCompromisso');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Falha ao criar compromisso: $e')),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo compromisso'),
      ),
      body: Column(
        children: [
          // Chips de período
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in filtros) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_labelFiltro(f)),
                      selected: _filtro == f,
                      onSelected: (_) {
                        if (f == CompromissoFiltro.data) {
                          _pickDate();
                        } else {
                          setState(() => _filtro = f);
                        }
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                    ),
                  ),
                ],
                if (_filtro == CompromissoFiltro.data)
                  FilledButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text(
                      _dataEscolhida == null
                          ? 'Escolher data'
                          : 'Data: ${_dataEscolhida!.day.toString().padLeft(2, '0')}/${_dataEscolhida!.month.toString().padLeft(2, '0')}',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Chips de status
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Todos'),
                    selected: _statusFiltro == StatusFiltro.todos,
                    onSelected:
                        (_) =>
                            setState(() => _statusFiltro = StatusFiltro.todos),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Pendentes'),
                    selected: _statusFiltro == StatusFiltro.pendentes,
                    onSelected:
                        (_) => setState(
                          () => _statusFiltro = StatusFiltro.pendentes,
                        ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Finalizados'),
                    selected: _statusFiltro == StatusFiltro.finalizado,
                    onSelected:
                        (_) => setState(
                          () => _statusFiltro = StatusFiltro.finalizado,
                        ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Cancelados'),
                    selected: _statusFiltro == StatusFiltro.cancelado,
                    onSelected:
                        (_) => setState(
                          () => _statusFiltro = StatusFiltro.cancelado,
                        ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  _logError(snap.error!, null, 'StreamBuilder');
                  return Center(child: Text('Erro: ${snap.error}'));
                }

                final docs = (snap.data?.docs ?? []);

                // Filtra no CLIENTE quando status = pendentes
                List<QueryDocumentSnapshot<Map<String, dynamic>>> rows = docs;
                if (_statusFiltro == StatusFiltro.pendentes) {
                  rows =
                      rows.where((d) {
                        final s =
                            (d.data()['status'] ?? '').toString().toLowerCase();
                        return s != 'finalizado' && s != 'cancelado';
                      }).toList();
                }

                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum compromisso no período.'),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final doc = rows[i];
                    final id = doc.id;
                    final m = doc.data();

                    final ts = m['compromisso'];
                    final dt = ts is Timestamp ? ts.toDate() : null;

                    final status = (m['status'] ?? '').toString().toLowerCase();
                    final isClosed =
                        status == 'finalizado' || status == 'cancelado';

                    final cliente = (m['clienteNome'] ?? '').toString();
                    final numero = (m['numero'] as num?)?.toInt();
                    final ano = (m['ano'] as num?)?.toInt();
                    final obs = (m['compromissoTexto'] ?? '').toString();

                    String _pedidoLabel() {
                      if (numero != null && ano != null) {
                        return '${numero.toString().padLeft(3, '0')}-$ano';
                      }
                      return '-';
                    }

                    Future<void> _editar() async {
                      try {
                        final updated = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          builder:
                              (_) => NovoCompromissoSheet(
                                docId: id,
                                initial: m,
                                initialDate: dt,
                              ),
                        );
                        if (updated == true && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Compromisso atualizado.'),
                            ),
                          );
                        }
                      } catch (e, st) {
                        _logError(e, st, 'item::_editar');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Falha ao editar: $e')),
                          );
                        }
                      }
                    }

                    final now = DateTime.now();
                    final flag =
                        (!isClosed && dt != null)
                            ? _flagFor(now, dt)
                            : _ApptFlag.none;

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side:
                            flag == _ApptFlag.none
                                ? BorderSide.none
                                : BorderSide(
                                  color:
                                      flag == _ApptFlag.overdue
                                          ? Colors.red
                                          : Colors.amber,
                                  width: 1.2,
                                ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.event_available_outlined,
                          color:
                              isClosed
                                  ? (status == 'cancelado'
                                      ? Colors.grey
                                      : Colors.green)
                                  : (flag == _ApptFlag.overdue
                                      ? Colors.red
                                      : (flag == _ApptFlag.soon
                                          ? Colors.amber.shade800
                                          : null)),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                dt != null ? _fmtData(dt) : 'Sem data',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (status.isNotEmpty) _statusChip(status),
                            if (dt != null && !isClosed) _flagChip(flag, dt),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            _kvLine(
                              'Convidado',
                              cliente.isEmpty ? '-' : cliente,
                            ),
                            _kvLine('Pedido', _pedidoLabel()),
                            if (obs.isNotEmpty) _kvLine('Assunto', obs),
                          ],
                        ),
                        onTap: _editar,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              _editarCompromisso(id, m);
                            } else if (value == 'del') {
                              _excluirCompromisso(id);
                            } else if (value == 'done') {
                              await _setStatus(id, 'finalizado');
                            } else if (value == 'cancel') {
                              await _setStatus(id, 'cancelado');
                            }
                          },
                          itemBuilder:
                              (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Editar'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'del',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    title: Text('Excluir'),
                                  ),
                                ),
                                PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'done',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.green,
                                    ),
                                    title: Text('Marcar como finalizado'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.cancel_outlined,
                                      color: Colors.grey,
                                    ),
                                    title: Text('Marcar como cancelado'),
                                  ),
                                ),
                              ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // linha "helpers" – rótulo + valor em uma linha
  Widget _kvLine(String k, String v) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(
            text: '$k: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: v),
        ],
      ),
    );
  }
}
