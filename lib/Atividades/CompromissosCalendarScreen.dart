import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../Cadastros/NovoCompromissoSheet.dart';

/// ========= helpers reaproveitados da tela de lista =========

enum _ApptFlag { none, overdue, soon }

_ApptFlag _flagFor(DateTime now, DateTime when) {
  if (when.isBefore(now)) return _ApptFlag.overdue;
  if (!when.isAfter(now.add(const Duration(minutes: 30)))) {
    return _ApptFlag.soon;
  }
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
        backgroundColor: Colors.redAccent,
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

String _fmtData(DateTime dt) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${dt.year} • $hh:$mi';
}

class CompromissosCalendarScreen extends StatefulWidget {
  const CompromissosCalendarScreen({super.key});

  @override
  State<CompromissosCalendarScreen> createState() =>
      _CompromissosCalendarScreenState();
}

class _CompromissosCalendarScreenState
    extends State<CompromissosCalendarScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String? _scopeUserId;
  bool _loadingScope = true;
  String? _scopeError;

  @override
  void initState() {
    super.initState();
    _initScope();
  }

  void _logError(Object error, [StackTrace? st, String where = '']) {
    final tag = where.isEmpty ? 'AgendaCalendar' : 'AgendaCalendar::$where';
    debugPrint('[$tag] ERROR: $error');
    if (st != null) debugPrintStack(stackTrace: st);
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;
    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
      });
      return;
    }
    setState(() {
      _scopeUserId = u.uid;
      _loadingScope = false;
      _scopeError = null;
    });
  }

  /// Stream com todos os compromissos do mês atual do usuário logado
  Stream<QuerySnapshot<Map<String, dynamic>>> _monthStream() {
    final userId = _scopeUserId;
    if (userId == null) return const Stream.empty();

    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final firstDayNextMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      1,
    );

    return _fs
        .collection('agenda')
        .where('userId', isEqualTo: userId)
        .where(
          'compromisso',
          isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth),
        )
        .where('compromisso', isLessThan: Timestamp.fromDate(firstDayNextMonth))
        .orderBy('compromisso')
        .snapshots();
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

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

  /// === NOVO: duplicar compromisso (abre como inclusão, com dados preenchidos) ===
  Map<String, dynamic> _buildDuplicateInitial(Map<String, dynamic> src) {
    final copy = Map<String, dynamic>.from(src);

    // Campos que não devem ser herdados
    const toStrip = {
      'status',
      'createdAt',
      'updatedAt',
      'userId',
      'companyId',
      'id',
      'docId',
    };
    copy.removeWhere((k, v) => toStrip.contains(k));

    // Se quiser garantir status "pendente" no formulário:
    // copy['status'] = 'pendente';

    return copy;
  }

  Future<void> _duplicarCompromisso(Map<String, dynamic> data) async {
    try {
      final ts = data['compromisso'];
      final DateTime? dt = ts is Timestamp ? ts.toDate() : null;

      final initial = _buildDuplicateInitial(data);

      final created = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        // Sem docId => tela em modo "novo", porém com `initial` preenchido
        builder: (_) => NovoCompromissoSheet(initial: initial, initialDate: dt),
      );

      if (!mounted) return;
      if (created == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compromisso duplicado com sucesso.')),
        );
      }
    } catch (e, st) {
      _logError(e, st, '_duplicarCompromisso');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao duplicar compromisso: $e')),
      );
    }
  }

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

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return Scaffold(
        appBar: AppBar(title: const Text('Agenda')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_scopeError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Agenda')),
        body: Center(child: Text(_scopeError!)),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda (Calendário)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            // pega o dia selecionado no calendário, ou o dia focado, ou hoje
            final baseDay = _selectedDay ?? _focusedDay ?? DateTime.now();

            // monta a data inicial: mesma data do calendário, horário atual
            final now = DateTime.now();
            final initialDate = DateTime(
              baseDay.year,
              baseDay.month,
              baseDay.day,
              now.hour,
              now.minute,
            );

            final created = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => NovoCompromissoSheet(initialDate: initialDate),
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

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _monthStream(),
        builder: (context, snapshot) {
          // Mapa dia -> lista de docs de agenda
          final eventsByDay =
              <DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

          if (snapshot.hasData) {
            for (final doc in snapshot.data!.docs) {
              final data = doc.data();
              final ts = data['compromisso'] as Timestamp?;
              if (ts == null) continue;
              final dt = ts.toDate();
              final key = _dayKey(dt);
              eventsByDay.putIfAbsent(key, () => []).add(doc);
            }
          }

          final selectedDay = _selectedDay ?? _focusedDay;
          final selectedKey = _dayKey(selectedDay);
          final selectedEvents = eventsByDay[selectedKey] ?? [];

          return Column(
            children: [
              // ===== Calendário =====
              TableCalendar(
                locale: 'pt_BR',
                firstDay: DateTime(2000),
                lastDay: DateTime(2100),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                startingDayOfWeek: StartingDayOfWeek.monday,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: (day) {
                  final key = _dayKey(day);
                  return eventsByDay[key] ?? [];
                },
                calendarStyle: CalendarStyle(
                  markerDecoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) {
                  setState(() {
                    _focusedDay = focused;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
              ),

              const Divider(height: 1),

              // ===== Lista de compromissos do dia selecionado =====
              Expanded(
                child:
                    snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator())
                        : selectedEvents.isEmpty
                        ? const Center(
                          child: Text('Nenhum compromisso neste dia.'),
                        )
                        : ListView.builder(
                          itemCount: selectedEvents.length,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          itemBuilder: (context, index) {
                            final doc = selectedEvents[index];
                            final m = doc.data();
                            final id = doc.id;

                            final ts = m['compromisso'] as Timestamp?;
                            final dt = ts?.toDate();

                            final status =
                                (m['status'] ?? '').toString().toLowerCase();
                            final isClosed =
                                status == 'finalizado' || status == 'cancelado';

                            final cliente = (m['clienteNome'] ?? '').toString();
                            final numero = (m['numero'] as num?)?.toInt();
                            final ano = (m['ano'] as num?)?.toInt();
                            final obs =
                                (m['compromissoTexto'] ?? '').toString();

                            String _pedidoLabel() {
                              if (numero != null && ano != null) {
                                return '${numero.toString().padLeft(3, '0')}-$ano';
                              }
                              return '-';
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
                                    if (dt != null && !isClosed)
                                      _flagChip(flag, dt),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    _kvLine(
                                      context,
                                      'Convidado',
                                      cliente.isEmpty ? '-' : cliente,
                                    ),
                                    _kvLine(context, 'Pedido', _pedidoLabel()),
                                    if (obs.isNotEmpty)
                                      _kvLine(context, 'Assunto', obs),
                                  ],
                                ),
                                onTap: () => _editarCompromisso(id, m),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      _editarCompromisso(id, m);
                                    } else if (value == 'dup') {
                                      _duplicarCompromisso(m);
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
                                          value: 'dup',
                                          child: ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              Icons.control_point_duplicate,
                                            ),
                                            title: Text('Duplicar'),
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
                                            title: Text(
                                              'Marcar como finalizado',
                                            ),
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
                                            title: Text(
                                              'Marcar como cancelado',
                                            ),
                                          ),
                                        ),
                                      ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// linha helper: "rótulo: valor"
Widget _kvLine(BuildContext context, String k, String v) {
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
