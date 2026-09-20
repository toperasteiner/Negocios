import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// REMOVA o import antigo da sheet de clientes 👇
// import '../Seletores/SelecionarClienteSheet.dart';

// Garanta que o caminho bate com onde você colocou a sheet unificada.
// Pelo seu arquivo enviado, ela está em lib/Pessoas/SelecionarPessoaSheet.dart
import '../seletores/SelecionarPessoaSheet.dart';

class NovoCompromissoSheet extends StatefulWidget {
  final String? docId; // null = novo | não-nulo = editar
  final Map<String, dynamic>? initial; // dados atuais
  final DateTime? initialDate; // sugestão de data/hora

  const NovoCompromissoSheet({
    super.key,
    this.docId,
    this.initial,
    this.initialDate,
  });

  @override
  State<NovoCompromissoSheet> createState() => _NovoCompromissoSheetState();
}

class _NovoCompromissoSheetState extends State<NovoCompromissoSheet> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  DateTime? _compromisso; // data/hora do compromisso
  final _textoCtrl = TextEditingController(); // assunto/observação

  // AGORA usa PessoaSelecionada (sheet unificada)
  PessoaSelecionada? _pessoa;

  bool _salvando = false;

  bool get _isEdicao => widget.docId != null;

  @override
  void initState() {
    super.initState();

    // --- Pré-preenche com initial / initialDate ---
    final ts = widget.initial?['compromisso'];
    final fromInitial = ts is Timestamp ? ts.toDate() : null;
    _compromisso = widget.initialDate ?? fromInitial;

    _textoCtrl.text = (widget.initial?['compromissoTexto'] ?? '').toString();

    final cliId = widget.initial?['clienteId'] as String?;
    final cliNome = (widget.initial?['clienteNome'] ?? '').toString();
    if (cliId != null && cliNome.isNotEmpty) {
      _pessoa = PessoaSelecionada(id: cliId, nome: cliNome);
    }
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDataHora() async {
    final base = _compromisso ?? DateTime.now();

    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDate: DateTime(base.year, base.month, base.day),
      helpText: 'Escolha a data',
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (t == null) return;

    setState(() {
      _compromisso = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _selecionarPessoa() async {
    // >>> IMPORTANTE: o genérico aqui é PessoaSelecionada
    final res = await showModalBottomSheet<PessoaSelecionada>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => const SelecionarPessoaSheet(
            // como você pediu, sem filtro default só de clientes; começa como "Todos"
            filtroInicial: PessoaFiltro.ambos,
          ),
    );
    if (res != null) setState(() => _pessoa = res);
  }

  Future<void> _salvar() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login.')));
      return;
    }
    if (_compromisso == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Defina a data/hora.')));
      return;
    }

    setState(() => _salvando = true);
    try {
      final payload = <String, dynamic>{
        // Você pediu explicitamente: agenda.userId = id do usuário logado (UID)
        'userId': uid,
        'compromisso': Timestamp.fromDate(_compromisso!),
        'compromissoTexto':
            _textoCtrl.text.trim().isEmpty ? null : _textoCtrl.text.trim(),

        // Mantém os campos já usados no restante do app
        'clienteId': _pessoa?.id,
        'clienteNome': _pessoa?.nome,

        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdicao) {
        // EDITAR
        await _fs.collection('agenda').doc(widget.docId!).update(payload);
      } else {
        // NOVO
        payload['createdAt'] = FieldValue.serverTimestamp();
        await _fs.collection('agenda').add(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // sinaliza sucesso para a lista
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String _fmt(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} • $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final pad =
        MediaQuery.of(context).viewInsets +
        const EdgeInsets.fromLTRB(18, 8, 18, 24);

    return SafeArea(
      child: Padding(
        padding: pad,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pegador superior do bottom-sheet
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 4, bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Cabeçalho da Sheet
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B21B6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: Color(0xFF5B21B6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEdicao ? 'Editar compromisso' : 'Novo compromisso',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isEdicao
                              ? 'Altere a data, pessoa ou observações'
                              : 'Agende um compromisso ou atividade',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: const Color(0xFF64748B),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Card: Data e hora
              InkWell(
                onTap: _pickDataHora,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _compromisso != null
                        ? const Color(0xFFF8FAFC)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _compromisso != null
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Color(0xFFF97316),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Data e Horário *',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _compromisso == null
                                  ? 'Definir data e hora'
                                  : _fmt(_compromisso!),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: _compromisso != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _compromisso != null
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.edit_calendar_outlined,
                              size: 14,
                              color: Color(0xFF475569),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Escolher',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Card: Pessoa (cliente/fornecedor)
              InkWell(
                onTap: _selecionarPessoa,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _pessoa != null
                        ? const Color(0xFFF8FAFC)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _pessoa != null
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Color(0xFF3B82F6),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pessoa Vinculada (opcional)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _pessoa == null
                                  ? 'Nenhuma pessoa selecionada'
                                  : _pessoa!.nome,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: _pessoa != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _pessoa != null
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_pessoa != null)
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF94A3B8),
                          ),
                          tooltip: 'Remover pessoa',
                          onPressed: () => setState(() => _pessoa = null),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.person_search_outlined,
                                size: 14,
                                color: Color(0xFF475569),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Selecionar',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Assunto / Observação
              TextField(
                controller: _textoCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                decoration: InputDecoration(
                  labelText: 'Assunto / observação (opcional)',
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                  hintText: 'Ex.: Reunião com cliente, visita técnica...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Color(0xFF5B21B6),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Ações
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _salvando ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5B21B6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        minimumSize: const Size.fromHeight(50),
                        elevation: 2,
                        shadowColor: const Color(0xFF5B21B6).withValues(alpha: 0.4),
                      ),
                      icon:
                          _salvando
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _isEdicao ? 'Salvar alterações' : 'Salvar',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
