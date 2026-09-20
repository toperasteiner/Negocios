// lib/Pedidos/GarantiaScreen.dart
import 'package:flutter/material.dart';

enum GarantiaUnidade { dias, meses, anos }

class GarantiaConfig {
  final GarantiaUnidade unidade;
  final int periodo; // ex.: 30, 12, 3...
  final String condicoesTexto; // texto livre

  const GarantiaConfig({
    required this.unidade,
    required this.periodo,
    required this.condicoesTexto,
  });

  String resumo() {
    final u = switch (unidade) {
      GarantiaUnidade.dias => periodo == 1 ? 'dia' : 'dias',
      GarantiaUnidade.meses => periodo == 1 ? 'mês' : 'meses',
      GarantiaUnidade.anos => periodo == 1 ? 'ano' : 'anos',
    };
    return '$periodo $u';
  }

  Map<String, dynamic> toMap() => {
    'unidade': switch (unidade) {
      GarantiaUnidade.dias => 'dias',
      GarantiaUnidade.meses => 'meses',
      GarantiaUnidade.anos => 'anos',
    },
    'periodo': periodo,
    'condicoesTexto':
        condicoesTexto.trim().isEmpty ? null : condicoesTexto.trim(),
  };
}

class GarantiaScreen extends StatefulWidget {
  final GarantiaConfig? initial;
  const GarantiaScreen({super.key, this.initial});

  @override
  State<GarantiaScreen> createState() => _GarantiaScreenState();
}

class _GarantiaScreenState extends State<GarantiaScreen> {
  GarantiaUnidade _u = GarantiaUnidade.anos;
  int? _periodo; // null = ainda não escolhido
  final _textoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _u = i.unidade;
      _periodo = i.periodo;
      _textoCtrl.text = i.condicoesTexto;
    }
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  void _setPreset(int v) => setState(() => _periodo = v);

  Future<void> _setOutros() async {
    final c = TextEditingController(
      text: _periodo == null ? '' : _periodo.toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Outro período'),
            content: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor numérico'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('OK'),
              ),
            ],
          ),
    );
    if (ok == true) {
      final v = int.tryParse(c.text);
      if (v != null && v > 0) setState(() => _periodo = v);
    }
  }

  void _gerarCondicoes() {
    final label = switch (_u) {
      GarantiaUnidade.dias => 'dias',
      GarantiaUnidade.meses => 'meses',
      GarantiaUnidade.anos => 'anos',
    };
    final p =
        _periodo ??
        (switch (_u) {
          GarantiaUnidade.dias => 90,
          GarantiaUnidade.meses => 12,
          GarantiaUnidade.anos => 1,
        });

    _textoCtrl.text =
        'Garantia contratual de $p $label contra defeitos de fabricação, '
        'contados a partir da data da entrega/execução. A garantia não cobre '
        'desgaste natural, mau uso, acidente, agentes químicos, umidade ou '
        'intervenções de terceiros não autorizados. Para acionamento, o cliente '
        'deve apresentar o comprovante do serviço/produto.';
    setState(() {});
  }

  List<Widget> _buildPresets() {
    switch (_u) {
      case GarantiaUnidade.dias:
        return [
          _ChipBtn('30 dias', () => _setPreset(30), selected: _periodo == 30),
          _ChipBtn('90 dias', () => _setPreset(90), selected: _periodo == 90),
          _ChipBtn('Outros (dias)', _setOutros),
        ];
      case GarantiaUnidade.meses:
        return [
          _ChipBtn('3 meses', () => _setPreset(3), selected: _periodo == 3),
          _ChipBtn('12 meses', () => _setPreset(12), selected: _periodo == 12),
          _ChipBtn('Outros (meses)', _setOutros),
        ];
      case GarantiaUnidade.anos:
        return [
          _ChipBtn('1 ano', () => _setPreset(1), selected: _periodo == 1),
          _ChipBtn('3 anos', () => _setPreset(3), selected: _periodo == 3),
          _ChipBtn('Outros (anos)', _setOutros),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Garantia')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () {
              if (_periodo == null || _periodo! <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione o período da garantia.'),
                  ),
                );
                return;
              }
              final cfg = GarantiaConfig(
                unidade: _u,
                periodo: _periodo!,
                condicoesTexto: _textoCtrl.text,
              );
              Navigator.pop(context, cfg);
            },
            child: const Text('salvar garantia'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Text(
            'Garantia contratual',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Dias, meses ou anos?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),

          // “segmented” de dias/meses/anos
          Row(
            children: [
              Expanded(
                child: _SegBtn('dias', _u == GarantiaUnidade.dias, () {
                  setState(() {
                    _u = GarantiaUnidade.dias;
                    _periodo = null;
                  });
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegBtn('meses', _u == GarantiaUnidade.meses, () {
                  setState(() {
                    _u = GarantiaUnidade.meses;
                    _periodo = null;
                  });
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegBtn('anos', _u == GarantiaUnidade.anos, () {
                  setState(() {
                    _u = GarantiaUnidade.anos;
                    _periodo = null;
                  });
                }),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Text(
            'Qual é o período de garantia?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),

          Wrap(spacing: 10, runSpacing: 10, children: _buildPresets()),

          const SizedBox(height: 20),
          Text(
            'Condições da garantia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),

          // botão “gerar as condições...”
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _gerarCondicoes,
              icon: const Icon(Icons.auto_awesome),
              label: const Text(
                'gerar as condições da garantia automaticamente',
              ),
            ),
          ),
          const SizedBox(height: 12),

          // textarea
          TextField(
            controller: _textoCtrl,
            maxLines: 8,
            decoration: InputDecoration(
              hintText:
                  'Use este campo para escrever detalhes relacionados à garantia.\n\n'
                  'Dica: você pode salvar um texto padrão nas suas configurações e reutilizar aqui.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegBtn(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          color: selected ? cs.primary.withOpacity(0.08) : cs.surface,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? cs.primary : null,
          ),
        ),
      ),
    );
  }
}

class _ChipBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool selected;
  const _ChipBtn(this.text, this.onTap, {this.selected = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(text),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? cs.onPrimary : null,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: cs.primary,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );
  }
}
