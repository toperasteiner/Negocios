// lib/Estoque/ConsultarAjustarEstoqueScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ConsultarAjustarEstoqueScreen extends StatefulWidget {
  const ConsultarAjustarEstoqueScreen({super.key});

  @override
  State<ConsultarAjustarEstoqueScreen> createState() =>
      _ConsultarAjustarEstoqueScreenState();
}

class _ConsultarAjustarEstoqueScreenState
    extends State<ConsultarAjustarEstoqueScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _companyId;
  String? _scopeUserId;
  bool _loadingScope = true;
  String? _scopeError;

  bool get _isCompanyScope => _companyId != null && _companyId!.isNotEmpty;
  String get _scopeField => _isCompanyScope ? 'companyId' : 'userId';

  bool _canAdjustStock = false;

  String _q = '';
  bool _apenasControlados = false;

  @override
  void initState() {
    super.initState();
    _initScope();
    _auth.authStateChanges().listen((_) {
      if (mounted) _initScope();
    });
  }

  Future<void> _initScope() async {
    final u = _auth.currentUser;

    if (u == null) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Usuário não autenticado.';
        _canAdjustStock = false;
        _companyId = null;
        _scopeUserId = null;
      });
      return;
    }

    try {
      final me = await _loadCurrentUserRecord();
      final companyId = (me?['companyId'] ?? '').toString().trim();

      final perms = (me?['permissions'] ?? {}) as Map<String, dynamic>;
      bool p(String k) => (perms[k] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeUserId = companyId.isNotEmpty ? companyId : u.uid;
        _canAdjustStock = p('canAdjustStock');
        _loadingScope = false;
        _scopeError = null;
      });
    } catch (e) {
      setState(() {
        _loadingScope = false;
        _scopeError = 'Erro ao carregar empresa/escopo: $e';
      });
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRecord() async {
    final u = _auth.currentUser;
    if (u == null) return null;

    try {
      final byUid = await _fs.collection('users').doc(u.uid).get();
      if (byUid.exists) {
        final data = byUid.data() ?? {};
        data['__docId'] = byUid.id;
        return data;
      }
    } catch (_) {}

    final email = (u.email ?? '').toLowerCase().trim();
    if (email.isNotEmpty) {
      try {
        final q =
            await _fs
                .collection('users')
                .where('emailKey', isEqualTo: email)
                .limit(1)
                .get();

        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          d['__docId'] = q.docs.first.id;
          return d;
        }
      } catch (_) {}
    }

    return null;
  }

  Query<Map<String, dynamic>> _query() {
    var q = _fs
        .collection('produtos')
        .where(_scopeField, isEqualTo: _scopeUserId ?? '__');

    if (_apenasControlados) {
      q = q.where('controlaEstoque', isEqualTo: true);
    }

    if (_q.isNotEmpty) {
      final start = _q.toLowerCase();
      final end = '$start\uf8ff';
      q = q.orderBy('nomeLower').startAt([start]).endAt([end]);
    } else {
      q = q.orderBy('nomeLower');
    }

    return q;
  }

  bool _requireAdjustStock() {
    if (_canAdjustStock) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sem permissão para ajustar estoque.')),
    );

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingScope) {
      return const Scaffold(
        backgroundColor: EstoqueStyle.bg,
        body: Center(
          child: CircularProgressIndicator(color: EstoqueStyle.primary),
        ),
      );
    }

    if (_scopeError != null) {
      return Scaffold(
        backgroundColor: EstoqueStyle.bg,
        body: Column(
          children: [
            EstoqueHeader(
              apenasControlados: _apenasControlados,
              onBack: () => Navigator.of(context).maybePop(),
              onToggleControlados: (v) {
                setState(() => _apenasControlados = v);
              },
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _scopeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: EstoqueStyle.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: EstoqueStyle.bg,
      body: Column(
        children: [
          EstoqueHeader(
            apenasControlados: _apenasControlados,
            onBack: () => Navigator.of(context).maybePop(),
            onToggleControlados: (v) {
              setState(() => _apenasControlados = v);
            },
          ),
          if (!_canAdjustStock) const _ReadOnlyBanner(),
          _SearchCard(
            value: _q,
            onChanged: (value) => setState(() => _q = value.trim()),
            onClear: () => setState(() => _q = ''),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query().snapshots(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'Erro: ${snap.error}',
                      style: const TextStyle(
                        color: EstoqueStyle.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: EstoqueStyle.primary,
                    ),
                  );
                }

                final docs = snap.data!.docs;

                if (docs.isEmpty) {
                  return const _EmptyState();
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final m = d.data();

                    return _ProdutoRow(
                      key: ValueKey(d.id),
                      docId: d.id,
                      nome: (m['nome'] ?? '').toString(),
                      unidade: (m['unidade'] ?? 'UN').toString(),
                      controlaEstoque: (m['controlaEstoque'] as bool?) ?? false,
                      estoque: _asNum(m['estoque']),
                      estoqueAlerta: _asNum(m['estoqueAlerta']),
                      canEdit: _canAdjustStock,
                      onSave: (novo) async {
                        if (!_requireAdjustStock()) return;

                        await _fs.collection('produtos').doc(d.id).update({
                          'controlaEstoque': novo.controlaEstoque,
                          'estoque': novo.estoque,
                          'estoqueAlerta': novo.estoqueAlerta,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });

                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Atualizado.')),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Text(
            'Dica: toque nos botões ± para pequenos ajustes.',
            style: TextStyle(
              color: EstoqueStyle.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  static double _asNum(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0.0;
  }
}

/* ============================ Item da lista ============================ */

class _ProdutoRow extends StatefulWidget {
  final String docId;
  final String nome;
  final String unidade;
  final bool controlaEstoque;
  final double estoque;
  final double estoqueAlerta;
  final bool canEdit;
  final Future<void> Function(_ProdutoUpdate) onSave;

  const _ProdutoRow({
    super.key,
    required this.docId,
    required this.nome,
    required this.unidade,
    required this.controlaEstoque,
    required this.estoque,
    required this.estoqueAlerta,
    required this.canEdit,
    required this.onSave,
  });

  @override
  State<_ProdutoRow> createState() => _ProdutoRowState();
}

class _ProdutoRowState extends State<_ProdutoRow> {
  late bool _controla;
  late TextEditingController _estoqueCtrl;
  late TextEditingController _alertaCtrl;
  bool _dirty = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    _controla = widget.controlaEstoque;
    _estoqueCtrl = TextEditingController(
      text: _fmt(widget.estoque, allowDecimals: true),
    );
    _alertaCtrl = TextEditingController(
      text: _fmt(widget.estoqueAlerta, allowDecimals: true),
    );

    _estoqueCtrl.addListener(() => setState(() => _dirty = true));
    _alertaCtrl.addListener(() => setState(() => _dirty = true));
  }

  @override
  void didUpdateWidget(covariant _ProdutoRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.docId != widget.docId ||
        oldWidget.controlaEstoque != widget.controlaEstoque ||
        oldWidget.estoque != widget.estoque ||
        oldWidget.estoqueAlerta != widget.estoqueAlerta ||
        oldWidget.canEdit != widget.canEdit) {
      _controla = widget.controlaEstoque;
      _estoqueCtrl.text = _fmt(widget.estoque, allowDecimals: true);
      _alertaCtrl.text = _fmt(widget.estoqueAlerta, allowDecimals: true);
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _estoqueCtrl.dispose();
    _alertaCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v, {bool allowDecimals = false}) {
    if (!allowDecimals || v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  double _parse(String s) {
    final x = s.trim().replaceAll(',', '.');
    return double.tryParse(x) ?? 0;
  }

  void _bump(TextEditingController c, double delta) {
    final v = _parse(c.text) + delta;
    c.text = v.clamp(-1e9, 1e9).toStringAsFixed((v % 1 == 0) ? 0 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.canEdit;
    final estoqueAtual = _parse(_estoqueCtrl.text);
    final alertaAtual = _parse(_alertaCtrl.text);
    final emAlerta = _controla && estoqueAtual <= alertaAtual;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: EstoqueStyle.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProdutoHeader(
            nome: widget.nome,
            controla: _controla,
            canEdit: isEnabled,
            onChanged: (v) {
              setState(() {
                _controla = v;
                _dirty = true;
              });
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _numField(
                  label: 'Estoque (${widget.unidade})',
                  helper: 'Use ± ou digite o valor.',
                  controller: _estoqueCtrl,
                  enabled: isEnabled && _controla,
                  prefixMinus: () => _bump(_estoqueCtrl, -1),
                  prefixPlus: () => _bump(_estoqueCtrl, 1),
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numField(
                  label: 'Estoque alerta',
                  helper: 'Alerta no limite informado.',
                  controller: _alertaCtrl,
                  enabled: isEnabled && _controla,
                  prefixMinus: () => _bump(_alertaCtrl, -1),
                  prefixPlus: () => _bump(_alertaCtrl, 1),
                  icon: Icons.notifications_active_outlined,
                ),
              ),
            ],
          ),
          if (emAlerta) ...[const SizedBox(height: 12), const _StockAlert()],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: EstoqueStyle.orange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed:
                      (!isEnabled || !_dirty || _salvando)
                          ? null
                          : () async {
                            setState(() => _salvando = true);

                            await widget.onSave(
                              _ProdutoUpdate(
                                controlaEstoque: _controla,
                                estoque: _parse(_estoqueCtrl.text),
                                estoqueAlerta: _parse(_alertaCtrl.text),
                              ),
                            );

                            if (mounted) {
                              setState(() {
                                _salvando = false;
                                _dirty = false;
                              });
                            }
                          },
                  icon:
                      _salvando
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.save_outlined),
                  label: const Text(
                    'Salvar',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EstoqueStyle.primary,
                    side: BorderSide(
                      color: EstoqueStyle.primary.withOpacity(0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed:
                      (!isEnabled || !_dirty || _salvando)
                          ? null
                          : () {
                            setState(() {
                              _controla = widget.controlaEstoque;
                              _estoqueCtrl.text = _fmt(
                                widget.estoque,
                                allowDecimals: true,
                              );
                              _alertaCtrl.text = _fmt(
                                widget.estoqueAlerta,
                                allowDecimals: true,
                              );
                              _dirty = false;
                            });
                          },
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text(
                    'Desfazer',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField({
    required String label,
    required String helper,
    required TextEditingController controller,
    required bool enabled,
    required VoidCallback prefixMinus,
    required VoidCallback prefixPlus,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: EstoqueStyle.primary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: EstoqueStyle.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: enabled ? EstoqueStyle.bg : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '-1',
                onPressed: enabled ? prefixMinus : null,
                icon: const Icon(Icons.remove),
                color: EstoqueStyle.primary,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\.,\-]')),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(
                    color: EstoqueStyle.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: '+1',
                onPressed: enabled ? prefixPlus : null,
                icon: const Icon(Icons.add),
                color: EstoqueStyle.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          helper,
          style: const TextStyle(
            color: EstoqueStyle.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
        ),
      ],
    );
  }
}

class _ProdutoHeader extends StatelessWidget {
  final String nome;
  final bool controla;
  final bool canEdit;
  final ValueChanged<bool> onChanged;

  const _ProdutoHeader({
    required this.nome,
    required this.controla,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _IconBadge(
          icon: Icons.inventory_2_outlined,
          color: EstoqueStyle.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            nome.isEmpty ? '—' : nome,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: EstoqueStyle.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            Switch.adaptive(
              value: controla,
              activeColor: EstoqueStyle.primary,
              onChanged: canEdit ? onChanged : null,
            ),
            const Text(
              'Controla',
              style: TextStyle(
                color: EstoqueStyle.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StockAlert extends StatelessWidget {
  const _StockAlert();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: EstoqueStyle.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EstoqueStyle.orange.withOpacity(0.25)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: EstoqueStyle.orange,
            size: 19,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Atenção: estoque em nível de alerta.',
              style: TextStyle(
                color: EstoqueStyle.orange,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProdutoUpdate {
  final bool controlaEstoque;
  final double estoque;
  final double estoqueAlerta;

  _ProdutoUpdate({
    required this.controlaEstoque,
    required this.estoque,
    required this.estoqueAlerta,
  });
}

/* ====================== Identidade visual ====================== */

class EstoqueStyle {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF3B0CA3);
  static const Color orange = Color(0xFFF97316);
  static const Color green = Color(0xFF16A34A);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFDC2626);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);

  static LinearGradient get gradient => const LinearGradient(
    colors: [primaryDark, primary, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

/* ====================== Widgets visuais ====================== */

class EstoqueHeader extends StatelessWidget {
  final bool apenasControlados;
  final VoidCallback onBack;
  final ValueChanged<bool> onToggleControlados;

  const EstoqueHeader({
    super.key,
    required this.apenasControlados,
    required this.onBack,
    required this.onToggleControlados,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: EstoqueStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        18,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Expanded(
                child: Center(
                  child: Text(
                    'Estoque',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(icon: Icons.inventory_2_outlined, onTap: () {}),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Consulte produtos e ajuste quantidades disponíveis.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 7),
                const Text(
                  'Somente controlados',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Switch.adaptive(
                  value: apenasControlados,
                  activeColor: Colors.white,
                  onChanged: onToggleControlados,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchCard({
    required this.value,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: EstoqueStyle.softShadow,
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar por nome...',
          hintStyle: const TextStyle(color: EstoqueStyle.muted),
          prefixIcon: const Icon(Icons.search, color: EstoqueStyle.primary),
          suffixIcon:
              value.isEmpty
                  ? null
                  : IconButton(
                    tooltip: 'Limpar',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
          filled: true,
          fillColor: EstoqueStyle.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EstoqueStyle.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EstoqueStyle.orange.withOpacity(0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: EstoqueStyle.orange, size: 21),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Você não tem permissão para ajustar estoque. Visualização apenas.',
              style: TextStyle(
                color: EstoqueStyle.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Nenhum produto encontrado.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: EstoqueStyle.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool forceLight;

  const _IconBadge({
    required this.icon,
    required this.color,
    this.forceLight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color:
            forceLight
                ? Colors.white.withOpacity(0.16)
                : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: forceLight ? Colors.white : color, size: 24),
    );
  }
}
