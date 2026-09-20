import 'package:flutter/material.dart';

enum TipoEntregaPedido { semEntrega, dataUnica, programada }

String tipoEntregaKey(TipoEntregaPedido tipo) {
  switch (tipo) {
    case TipoEntregaPedido.semEntrega:
      return 'sem_entrega';
    case TipoEntregaPedido.dataUnica:
      return 'data_unica';
    case TipoEntregaPedido.programada:
      return 'programada';
  }
}

String tipoEntregaLabel(TipoEntregaPedido tipo) {
  switch (tipo) {
    case TipoEntregaPedido.semEntrega:
      return 'Sem entrega configurada';
    case TipoEntregaPedido.dataUnica:
      return 'Data única';
    case TipoEntregaPedido.programada:
      return 'Entregas programadas';
  }
}

class EntregaPedidoItem {
  final String? refId;
  final String tipo; // produto ou servico
  final String nome;
  final String unidade;
  final double quantidadePedido;
  final double quantidadeEntrega;

  EntregaPedidoItem({
    required this.refId,
    required this.tipo,
    required this.nome,
    required this.unidade,
    required this.quantidadePedido,
    required this.quantidadeEntrega,
  });

  Map<String, dynamic> toMap() {
    return {
      'refId': refId,
      'tipo': tipo,
      'nome': nome,
      'unidade': unidade,
      'quantidadePedido': quantidadePedido,
      'quantidadeEntrega': quantidadeEntrega,
    };
  }
}

class EntregaProgramada {
  final DateTime dataEntrega;
  final String? observacao;
  final List<EntregaPedidoItem> itens;

  EntregaProgramada({
    required this.dataEntrega,
    this.observacao,
    required this.itens,
  });

  Map<String, dynamic> toMap() {
    return {
      'dataEntrega': dataEntrega,
      'observacao': observacao,
      'itens': itens.map((e) => e.toMap()).toList(),
    };
  }
}

class EntregaPedidoConfig {
  final TipoEntregaPedido tipoEntrega;
  final DateTime? dataUnica;
  final String? observacao;
  final List<EntregaProgramada> entregas;

  EntregaPedidoConfig({
    required this.tipoEntrega,
    this.dataUnica,
    this.observacao,
    this.entregas = const [],
  });

  String resumo() {
    if (tipoEntrega == TipoEntregaPedido.semEntrega) {
      return 'Sem entrega configurada';
    }

    if (tipoEntrega == TipoEntregaPedido.dataUnica) {
      if (dataUnica == null) return 'Data única não informada';
      return 'Data única: ${_fmtData(dataUnica!)}';
    }

    if (entregas.isEmpty) return 'Nenhuma entrega programada';
    return 'Entregas programadas • ${entregas.length} data(s)';
  }

  static String _fmtData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  Map<String, dynamic> toMap() {
    return {
      'tipoEntrega': tipoEntregaKey(tipoEntrega),
      'tipoEntregaLabel': tipoEntregaLabel(tipoEntrega),
      'dataUnica': dataUnica,
      'observacao': observacao,
      'entregas': entregas.map((e) => e.toMap()).toList(),
    };
  }
}

class ItemPedidoEntregaBase {
  final String? refId;
  final String tipo; // produto ou servico
  final String nome;
  final String unidade;
  final double quantidade;

  ItemPedidoEntregaBase({
    required this.refId,
    required this.tipo,
    required this.nome,
    required this.unidade,
    required this.quantidade,
  });
}

class ConfigurarEntregaPedidoScreen extends StatefulWidget {
  final EntregaPedidoConfig? initial;
  final List<ItemPedidoEntregaBase> itensPedido;

  const ConfigurarEntregaPedidoScreen({
    super.key,
    this.initial,
    required this.itensPedido,
  });

  @override
  State<ConfigurarEntregaPedidoScreen> createState() =>
      _ConfigurarEntregaPedidoScreenState();
}

class _ConfigurarEntregaPedidoScreenState
    extends State<ConfigurarEntregaPedidoScreen> {
  TipoEntregaPedido _tipoEntrega = TipoEntregaPedido.semEntrega;

  DateTime? _dataUnica;
  final _observacaoCtrl = TextEditingController();

  final List<EntregaProgramada> _entregas = [];

  @override
  void initState() {
    super.initState();

    final initial = widget.initial;
    if (initial != null) {
      _tipoEntrega = initial.tipoEntrega;
      _dataUnica = initial.dataUnica;
      _observacaoCtrl.text = initial.observacao ?? '';
      _entregas.addAll(initial.entregas);
    }
  }

  @override
  void dispose() {
    _observacaoCtrl.dispose();
    super.dispose();
  }

  String _fmtData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  double _qtdJaProgramada(ItemPedidoEntregaBase item) {
    double total = 0;

    for (final entrega in _entregas) {
      for (final it in entrega.itens) {
        final mesmoId =
            item.refId != null &&
            item.refId!.isNotEmpty &&
            it.refId == item.refId;
        final mesmoNome =
            item.refId == null && it.nome == item.nome && it.tipo == item.tipo;

        if (mesmoId || mesmoNome) {
          total += it.quantidadeEntrega;
        }
      }
    }

    return total;
  }

  double _qtdDisponivel(ItemPedidoEntregaBase item) {
    final disponivel = item.quantidade - _qtdJaProgramada(item);
    return disponivel < 0 ? 0 : disponivel;
  }

  Future<void> _selecionarDataUnica() async {
    final now = DateTime.now();

    final data = await showDatePicker(
      context: context,
      initialDate: _dataUnica ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (data != null) {
      setState(() => _dataUnica = data);
    }
  }

  Future<void> _adicionarEntregaProgramada({int? index}) async {
    final existente = index == null ? null : _entregas[index];

    final result = await Navigator.push<EntregaProgramada>(
      context,
      MaterialPageRoute(
        builder:
            (_) => _EditarEntregaProgramadaScreen(
              itensPedido: widget.itensPedido,
              entregaExistente: existente,
              quantidadeJaProgramada: (item) {
                double ja = _qtdJaProgramada(item);

                if (existente != null) {
                  for (final it in existente.itens) {
                    final mesmoId =
                        item.refId != null &&
                        item.refId!.isNotEmpty &&
                        it.refId == item.refId;

                    final mesmoNome =
                        item.refId == null &&
                        it.nome == item.nome &&
                        it.tipo == item.tipo;

                    if (mesmoId || mesmoNome) {
                      ja -= it.quantidadeEntrega;
                    }
                  }
                }

                return ja < 0 ? 0 : ja;
              },
            ),
        fullscreenDialog: true,
      ),
    );

    if (result != null) {
      setState(() {
        if (index == null) {
          _entregas.add(result);
        } else {
          _entregas[index] = result;
        }

        _entregas.sort((a, b) => a.dataEntrega.compareTo(b.dataEntrega));
      });
    }
  }

  void _removerEntrega(int index) {
    setState(() => _entregas.removeAt(index));
  }

  void _salvar() {
    if (_tipoEntrega == TipoEntregaPedido.dataUnica && _dataUnica == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a data da entrega.')),
      );
      return;
    }

    if (_tipoEntrega == TipoEntregaPedido.programada && _entregas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos uma entrega programada.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      EntregaPedidoConfig(
        tipoEntrega: _tipoEntrega,
        dataUnica: _dataUnica,
        observacao:
            _observacaoCtrl.text.trim().isEmpty
                ? null
                : _observacaoCtrl.text.trim(),
        entregas: _entregas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar entrega'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _salvar,
            icon: const Icon(Icons.check),
            label: const Text('Salvar configuração'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(
            'Defina como a entrega deste pedido será realizada.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 16),

          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tipo de entrega',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                SegmentedButton<TipoEntregaPedido>(
                  segments: const [
                    ButtonSegment(
                      value: TipoEntregaPedido.semEntrega,
                      label: Text('Sem entrega'),
                      icon: Icon(Icons.block_outlined),
                    ),
                    ButtonSegment(
                      value: TipoEntregaPedido.dataUnica,
                      label: Text('Data única'),
                      icon: Icon(Icons.event_outlined),
                    ),
                    ButtonSegment(
                      value: TipoEntregaPedido.programada,
                      label: Text('Programada'),
                      icon: Icon(Icons.view_timeline_outlined),
                    ),
                  ],
                  selected: {_tipoEntrega},
                  onSelectionChanged: (v) {
                    setState(() => _tipoEntrega = v.first);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_tipoEntrega == TipoEntregaPedido.semEntrega) _semEntregaCard(cs),

          if (_tipoEntrega == TipoEntregaPedido.dataUnica) _dataUnicaCard(cs),

          if (_tipoEntrega == TipoEntregaPedido.programada) _programadaCard(cs),
        ],
      ),
    );
  }

  Widget _semEntregaCard(ColorScheme cs) {
    return _card(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.info_outline, color: cs.primary),
        title: const Text(
          'Nenhuma entrega configurada',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Use esta opção quando o pedido não precisa de controle de entrega, '
          'será retirado pelo cliente ou a entrega ainda será combinada.',
        ),
      ),
    );
  }

  Widget _dataUnicaCard(ColorScheme cs) {
    return _card(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_available_outlined, color: cs.primary),
            title: const Text(
              'Data prevista de entrega',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _dataUnica == null
                  ? 'toque para selecionar'
                  : _fmtData(_dataUnica!),
            ),
            trailing: Icon(Icons.chevron_right, color: cs.primary),
            onTap: _selecionarDataUnica,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _observacaoCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Observação da entrega',
              hintText: 'Ex.: entregar no período da manhã...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _programadaCard(ColorScheme cs) {
    final totalItens = widget.itensPedido.length;
    final itensPendentes =
        widget.itensPedido.where((e) => _qtdDisponivel(e) > 0).length;

    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Entregas programadas',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Configure uma ou mais datas de entrega. Em cada data, informe '
                'quais itens serão entregues e suas quantidades.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniResumo(
                      'Programações',
                      '${_entregas.length}',
                      Icons.event_note_outlined,
                      cs,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniResumo(
                      'Itens pendentes',
                      '$itensPendentes/$totalItens',
                      Icons.inventory_2_outlined,
                      cs,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (_entregas.isEmpty)
          _card(
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.local_shipping_outlined),
              title: Text(
                'Nenhuma entrega adicionada',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Toque no botão abaixo para criar a primeira entrega programada.',
              ),
            ),
          ),

        for (int i = 0; i < _entregas.length; i++) ...[
          _entregaCard(i, _entregas[i], cs),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _adicionarEntregaProgramada(),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar entrega programada'),
          ),
        ),
      ],
    );
  }

  Widget _entregaCard(int index, EntregaProgramada entrega, ColorScheme cs) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.local_shipping_outlined, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Entrega ${index + 1} • ${_fmtData(entrega.dataEntrega)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _adicionarEntregaProgramada(index: index),
              ),
              IconButton(
                tooltip: 'Remover',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removerEntrega(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in entrega.itens)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${item.nome} — ${_fmtQtd(item.quantidadeEntrega)} ${item.unidade}',
              ),
            ),
          if ((entrega.observacao ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entrega.observacao!,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniResumo(
    String label,
    String value,
    IconData icon,
    ColorScheme cs,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  String _fmtQtd(double v) {
    final casas = v % 1 == 0 ? 0 : 2;
    return v.toStringAsFixed(casas).replaceAll('.', ',');
  }
}

class _EditarEntregaProgramadaScreen extends StatefulWidget {
  final List<ItemPedidoEntregaBase> itensPedido;
  final EntregaProgramada? entregaExistente;
  final double Function(ItemPedidoEntregaBase item) quantidadeJaProgramada;

  const _EditarEntregaProgramadaScreen({
    required this.itensPedido,
    required this.quantidadeJaProgramada,
    this.entregaExistente,
  });

  @override
  State<_EditarEntregaProgramadaScreen> createState() =>
      _EditarEntregaProgramadaScreenState();
}

class _EditarEntregaProgramadaScreenState
    extends State<_EditarEntregaProgramadaScreen> {
  DateTime? _dataEntrega;
  final _observacaoCtrl = TextEditingController();

  final Map<String, TextEditingController> _qtdCtrls = {};
  final Set<String> _selecionados = {};

  @override
  void initState() {
    super.initState();

    final existente = widget.entregaExistente;
    if (existente != null) {
      _dataEntrega = existente.dataEntrega;
      _observacaoCtrl.text = existente.observacao ?? '';

      for (final item in existente.itens) {
        final key = _keyItem(item.refId, item.tipo, item.nome);
        _selecionados.add(key);
        _qtdCtrls[key] = TextEditingController(
          text: _fmtQtd(item.quantidadeEntrega),
        );
      }
    }
  }

  @override
  void dispose() {
    _observacaoCtrl.dispose();
    for (final c in _qtdCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _keyItem(String? refId, String tipo, String nome) {
    if (refId != null && refId.isNotEmpty) return '$tipo::$refId';
    return '$tipo::$nome';
  }

  String _fmtData(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _fmtQtd(double v) {
    final casas = v % 1 == 0 ? 0 : 2;
    return v.toStringAsFixed(casas).replaceAll('.', ',');
  }

  double _parseQtd(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  Future<void> _selecionarData() async {
    final now = DateTime.now();

    final data = await showDatePicker(
      context: context,
      initialDate: _dataEntrega ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (data != null) {
      setState(() => _dataEntrega = data);
    }
  }

  void _salvar() {
    if (_dataEntrega == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a data da entrega.')),
      );
      return;
    }

    final itensEntrega = <EntregaPedidoItem>[];

    for (final item in widget.itensPedido) {
      final key = _keyItem(item.refId, item.tipo, item.nome);

      if (!_selecionados.contains(key)) continue;

      final qtd = _parseQtd(_qtdCtrls[key]?.text ?? '');
      final jaProgramado = widget.quantidadeJaProgramada(item);
      final disponivel = item.quantidade - jaProgramado;

      if (qtd <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Informe a quantidade de ${item.nome}.')),
        );
        return;
      }

      if (qtd > disponivel) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Quantidade de ${item.nome} maior que o disponível para programar.',
            ),
          ),
        );
        return;
      }

      itensEntrega.add(
        EntregaPedidoItem(
          refId: item.refId,
          tipo: item.tipo,
          nome: item.nome,
          unidade: item.unidade,
          quantidadePedido: item.quantidade,
          quantidadeEntrega: qtd,
        ),
      );
    }

    if (itensEntrega.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione pelo menos um item.')),
      );
      return;
    }

    Navigator.pop(
      context,
      EntregaProgramada(
        dataEntrega: _dataEntrega!,
        observacao:
            _observacaoCtrl.text.trim().isEmpty
                ? null
                : _observacaoCtrl.text.trim(),
        itens: itensEntrega,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entregaExistente == null ? 'Nova entrega' : 'Editar entrega',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _salvar,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar entrega'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              leading: Icon(Icons.event_available_outlined, color: cs.primary),
              title: const Text(
                'Data da entrega',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _dataEntrega == null
                    ? 'toque para selecionar'
                    : _fmtData(_dataEntrega!),
              ),
              trailing: Icon(Icons.chevron_right, color: cs.primary),
              onTap: _selecionarData,
            ),
          ),
          const SizedBox(height: 12),

          const Text(
            'Itens desta entrega',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),

          for (final item in widget.itensPedido) _itemCard(item, cs),

          const SizedBox(height: 12),
          TextField(
            controller: _observacaoCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Observação',
              hintText: 'Ex.: entregar somente os materiais da primeira etapa',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(ItemPedidoEntregaBase item, ColorScheme cs) {
    final key = _keyItem(item.refId, item.tipo, item.nome);
    final selecionado = _selecionados.contains(key);

    final jaProgramado = widget.quantidadeJaProgramada(item);
    final disponivel = item.quantidade - jaProgramado;

    _qtdCtrls.putIfAbsent(key, () => TextEditingController());

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            CheckboxListTile(
              value: selecionado,
              contentPadding: EdgeInsets.zero,
              title: Text(
                item.nome,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Qtd. pedido: ${_fmtQtd(item.quantidade)} ${item.unidade} '
                '• Já programado: ${_fmtQtd(jaProgramado)} '
                '• Disponível: ${_fmtQtd(disponivel)}',
              ),
              onChanged:
                  disponivel <= 0
                      ? null
                      : (v) {
                        setState(() {
                          if (v == true) {
                            _selecionados.add(key);
                            if ((_qtdCtrls[key]?.text ?? '').isEmpty) {
                              _qtdCtrls[key]?.text = _fmtQtd(disponivel);
                            }
                          } else {
                            _selecionados.remove(key);
                          }
                        });
                      },
            ),
            if (selecionado)
              TextField(
                controller: _qtdCtrls[key],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantidade a entregar',
                  suffixText: item.unidade,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
