// lib/Servicos/ServicosCrudScreen.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../Planos/PlanService.dart';
import '../Planos/PlanosScreen.dart';
import '../Seletores/SelecionarCategoriaSheet.dart';

class ServicosCrudScreen extends StatefulWidget {
  const ServicosCrudScreen({super.key});

  @override
  State<ServicosCrudScreen> createState() => _ServicosCrudScreenState();
}

class _ServicosCrudScreenState extends State<ServicosCrudScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  String? _companyId;
  String? _scopeCompanyId;
  bool _loadingCompany = true;
  String? _loadError;

  bool _canManageServices = false;

  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _q = '';

  bool _loadingPlan = true;
  String? _planError;
  int _servicesUsed = 0;
  int _servicesLimit = -1;
  bool _canCreateByPlan = true;

  static const Map<String, String> _unidadesDesc = {
    'UN': 'Unidade',
    'H': 'Hora',
    'DI': 'Diária',
    'M': 'Metro',
    'M²': 'Metro quadrado',
    'M³': 'Metro cúbico',
    'KG': 'Quilograma',
    'PÇ': 'Peça',
    'CX': 'Caixa',
    'DZ': 'Dúzia',
    'KIT': 'Kit / Conjunto',
    'PAR': 'Par',
  };

  void _onPlanChanged() {
    if (!mounted) return;
    final service = PlanService.instance;
    if (!service.isLoaded) return;
    setState(() {
      _servicesLimit = service.getLimit('maxServices');
      if (!_loadingPlan && _planError == null) {
        _canCreateByPlan =
            (service.companyId ?? '').isNotEmpty &&
            (_servicesLimit == -1 || _servicesUsed < _servicesLimit);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    PlanService.instance.addListener(_onPlanChanged);
    _buscaCtrl.addListener(_onSearchChange);
    _loadCompanyScope();
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    _debounce?.cancel();
    _buscaCtrl.removeListener(_onSearchChange);
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPlanRules() async {
    try {
      setState(() {
        _loadingPlan = true;
        _planError = null;
      });

      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final usados = await PlanService.instance.getCurrentServicesCount();
      final limite = PlanService.instance.getLimit('maxServices');
      final canCreate = await PlanService.instance.canCreateService();

      if (!mounted) return;

      setState(() {
        _servicesUsed = usados;
        _servicesLimit = limite;
        _canCreateByPlan = canCreate;
        _loadingPlan = false;
        _planError = null;
      });
      // A plan notification may have arrived while the count was loading.
      _onPlanChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _planError = 'Erro ao validar plano: $e';
      });
    }
  }

  void _showPlanLimitDialog({
    required String titulo,
    required String mensagem,
  }) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(titulo),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ServicoStyle.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanosScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Ver planos'),
              ),
            ],
          ),
    );
  }

  Future<bool> _requirePlanSlot() async {
    try {
      if (!PlanService.instance.isLoaded) {
        await PlanService.instance.load();
      }

      final canCreate = await PlanService.instance.canCreateService();
      final usados = await PlanService.instance.getCurrentServicesCount();
      final limite = PlanService.instance.getLimit('maxServices');

      if (!mounted) return false;

      setState(() {
        _servicesUsed = usados;
        _servicesLimit = limite;
        _canCreateByPlan = canCreate;
      });

      if (canCreate) return true;

      _showPlanLimitDialog(
        titulo: 'Limite de serviços atingido',
        mensagem:
            limite == -1
                ? 'Seu plano não permite esta ação.'
                : 'Você já atingiu o limite de serviços do seu plano atual.\n\n'
                    'Serviços usados: $usados\n'
                    'Limite do plano: $limite\n\n'
                    'Faça upgrade para continuar cadastrando serviços.',
      );

      return false;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao validar plano: $e')));

      return false;
    }
  }

  Future<void> _loadCompanyScope() async {
    final u = _auth.currentUser;

    if (u == null) {
      setState(() {
        _loadingCompany = false;
        _loadError = 'Usuário não autenticado.';
      });
      return;
    }

    try {
      Map<String, dynamic>? me;

      final byUid = await _fs.collection('users').doc(u.uid).get();

      if (byUid.exists) {
        me = byUid.data() ?? {};
      } else {
        final email = (u.email ?? '').toLowerCase().trim();

        if (email.isNotEmpty) {
          final q =
              await _fs
                  .collection('users')
                  .where('emailKey', isEqualTo: email)
                  .limit(1)
                  .get();

          if (q.docs.isNotEmpty) me = q.docs.first.data();
        }
      }

      if (me == null) {
        setState(() {
          _loadingCompany = false;
          _loadError = 'Registro do usuário não encontrado em "users".';
        });
        return;
      }

      final companyId = (me['companyId'] ?? '').toString().trim();
      final perms = (me['permissions'] ?? {}) as Map<String, dynamic>;
      final cms = (perms['canManageServices'] ?? false) == true;

      setState(() {
        _companyId = companyId.isEmpty ? null : companyId;
        _scopeCompanyId = _companyId;
        _canManageServices = cms;
        _loadingCompany = false;
        _loadError = null;
      });

      await _refreshPlanRules();
    } catch (e) {
      setState(() {
        _loadingCompany = false;
        _loadError = 'Erro ao carregar empresa/permissões: $e';
      });
    }
  }

  void _onSearchChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final v = _buscaCtrl.text.trim();
      if (v != _q) setState(() => _q = v);
    });
  }

  Query<Map<String, dynamic>> _baseQuery(String scopeCompanyId) {
    return _fs
        .collection('servicos')
        .where('companyId', isEqualTo: scopeCompanyId);
  }

  Query<Map<String, dynamic>> _query(String scopeCompanyId) {
    final text = _q.trim();

    if (text.isNotEmpty) {
      final lower = text.toLowerCase();
      return _baseQuery(
        scopeCompanyId,
      ).orderBy('nomeLower').startAt([lower]).endAt(['$lower\uf8ff']);
    }

    return _baseQuery(scopeCompanyId).orderBy('nomeLower');
  }

  Future<void> _deleteStorageImage(String? raw) async {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return;

    try {
      final Reference ref =
          value.startsWith('http://') ||
                  value.startsWith('https://') ||
                  value.startsWith('gs://')
              ? FirebaseStorage.instance.refFromURL(value)
              : FirebaseStorage.instance.ref(value);

      await ref.delete();
    } catch (e) {
      debugPrint('⚠️ Não foi possível remover a imagem do serviço: $e');
    }
  }

  bool _requirePerm() {
    if (_canManageServices) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissão. É necessário "Cadastrar/Alterar serviços".',
        ),
      ),
    );

    return false;
  }

  Future<void> _confirmarExclusao(
    String id,
    String nome, {
    String? imagemUrl,
  }) async {
    if (!_requirePerm()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Text('Excluir serviço'),
            content: Text('Tem certeza que deseja excluir "$nome"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir'),
                style: FilledButton.styleFrom(
                  backgroundColor: ServicoStyle.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      final companyId = _scopeCompanyId;

      if (companyId == null || companyId.isEmpty) {
        throw Exception('Empresa não identificada para exclusão do serviço.');
      }

      final servicoRef = _fs.collection('servicos').doc(id);

      final publicoRef = _fs
          .collection('agenda_servicos_publicos')
          .doc(companyId)
          .collection('servicos')
          .doc(id);

      final batch = _fs.batch();
      batch.delete(servicoRef);
      batch.delete(publicoRef);
      await batch.commit();

      // Limpeza do arquivo no Storage é feita depois da exclusão do documento.
      // Se falhar, não interrompe a regra atual de exclusão do serviço.
      await _deleteStorageImage(imagemUrl);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Serviço excluído.')));
      }

      await _refreshPlanRules();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
      }
    }
  }

  Future<void> _abrirFormulario(
    BuildContext context, {
    String? servicoId,
    Map<String, dynamic>? dados,
  }) async {
    if (!_requirePerm()) return;

    if (servicoId == null) {
      final ok = await _requirePlanSlot();
      if (!ok) return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ServicoStyle.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (_) => _FormServicoSheet(
            servicoId: servicoId,
            initial: dados,
            unidadesDesc: _unidadesDesc,
            canManageServices: _canManageServices,
          ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            servicoId == null
                ? 'Serviço cadastrado com sucesso.'
                : 'Serviço atualizado com sucesso.',
          ),
        ),
      );

      await _refreshPlanRules();
    }
  }

  Widget _buildPlanWarningCard(BuildContext context) {
    final planoAtual = PlanService.instance.planId.toUpperCase();
    final ilimitado = _servicesLimit == -1;
    final restantes = ilimitado ? 999999 : (_servicesLimit - _servicesUsed);
    final atingiuLimite = !ilimitado && _servicesUsed >= _servicesLimit;
    final mostrarAviso = !ilimitado && restantes <= 5;

    if (!mostrarAviso && _planError == null) {
      return const SizedBox.shrink();
    }

    final color = atingiuLimite ? ServicoStyle.red : ServicoStyle.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(
            icon:
                atingiuLimite
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plano: $planoAtual',
                  style: const TextStyle(
                    color: ServicoStyle.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  atingiuLimite
                      ? 'Você atingiu o limite do seu plano para serviços.'
                      : 'Faltam apenas $restantes serviço(s) para atingir o limite do seu plano.',
                  style: const TextStyle(
                    color: ServicoStyle.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_planError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _planError!,
                    style: const TextStyle(
                      color: ServicoStyle.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ServicoStyle.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlanosScreen()),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Fazer upgrade'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCompany) {
      return const Scaffold(
        backgroundColor: ServicoStyle.bg,
        body: Center(
          child: CircularProgressIndicator(color: ServicoStyle.primary),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: ServicoStyle.bg,
        body: Column(
          children: [
            ServicosHeader(
              onBack: () => Navigator.of(context).maybePop(),
              onNew: () => _abrirFormulario(context),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ServicoStyle.text,
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

    if (_uid == null) {
      return const Scaffold(
        backgroundColor: ServicoStyle.bg,
        body: Center(child: Text('Faça login para ver seus serviços.')),
      );
    }

    if (_scopeCompanyId == null) {
      return Scaffold(
        backgroundColor: ServicoStyle.bg,
        body: Column(
          children: [
            ServicosHeader(
              onBack: () => Navigator.of(context).maybePop(),
              onNew: _requirePerm,
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Empresa não definida para o usuário. Configure o companyId no cadastro do usuário para listar os serviços.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ServicoStyle.text,
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

    final fabEnabled =
        _canManageServices &&
        !_loadingPlan &&
        (_canCreateByPlan || _servicesLimit == -1);

    return Scaffold(
      backgroundColor: ServicoStyle.bg,
      body: Column(
        children: [
          ServicosHeader(
            onBack: () => Navigator.of(context).maybePop(),
            onNew:
                _loadingPlan
                    ? null
                    : (_canManageServices
                        ? () => _abrirFormulario(context)
                        : _requirePerm),
          ),
          if (_loadingPlan)
            const LinearProgressIndicator(
              minHeight: 3,
              color: ServicoStyle.primary,
            ),
          if (!_loadingPlan) _buildPlanWarningCard(context),
          _SearchCard(
            controller: _buscaCtrl,
            q: _q,
            onClear: () {
              _buscaCtrl.clear();
              FocusScope.of(context).unfocus();
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query(_scopeCompanyId!).snapshots().handleError((e, st) {
                debugPrint('❌ Firestore stream error (serviços): $e');
                debugPrint('$st');
              }),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: ServicoStyle.primary,
                    ),
                  );
                }

                if (snap.hasError) {
                  return Center(child: Text('Erro ao carregar: ${snap.error}'));
                }

                var docs = snap.data?.docs ?? [];

                if (_q.isNotEmpty) {
                  final qLower = _q.toLowerCase();
                  docs =
                      docs.where((d) {
                        final m = d.data();
                        final nomeLower =
                            (m['nomeLower'] ?? m['nome'] ?? '')
                                .toString()
                                .toLowerCase();

                        return nomeLower.contains(qLower);
                      }).toList();
                }

                if (docs.isEmpty) {
                  return RefreshIndicator(
                    color: ServicoStyle.primary,
                    onRefresh: _refreshPlanRules,
                    child: _EmptyState(
                      q: _q,
                      onClear: () => _buscaCtrl.clear(),
                      onNew:
                          _loadingPlan
                              ? null
                              : (fabEnabled
                                  ? () => _abrirFormulario(context)
                                  : () async {
                                    if (!_requirePerm()) return;
                                    await _requirePlanSlot();
                                  }),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: ServicoStyle.primary,
                  onRefresh: _refreshPlanRules,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final map = docs[i].data();
                      final id = docs[i].id;

                      final nome = (map['nome'] ?? '').toString();
                      final desc = (map['descricao'] ?? '').toString();
                      final unidade = (map['unidade'] ?? 'UN').toString();
                      final imagemUrl = (map['imagemUrl'] ?? '').toString();

                      final valor =
                          (map['valorUnitario'] is num)
                              ? (map['valorUnitario'] as num).toDouble()
                              : double.tryParse('${map['valorUnitario']}') ??
                                  0.0;

                      final custoExecucao =
                          (map['custoExecucao'] is num)
                              ? (map['custoExecucao'] as num).toDouble()
                              : double.tryParse('${map['custoExecucao']}') ??
                                  0.0;

                      return _ServicoCard(
                        nome: nome,
                        descricao: desc,
                        unidade: unidade,
                        valor: valor,
                        custoExecucao: custoExecucao,
                        imagemUrl: imagemUrl,
                        fmtMoeda: _fmtMoeda,
                        onTap: () {
                          if (_canManageServices) {
                            _abrirFormulario(
                              context,
                              servicoId: id,
                              dados: {
                                'nome': nome,
                                'descricao': desc,
                                'valorUnitario': valor,
                                'custoExecucao': custoExecucao,
                                'unidade': unidade,
                                'categoriaId': map['categoriaId'],
                                'categoriaNome': map['categoriaNome'],
                                'imagemUrl': imagemUrl,

                                'disponivelAgendamento':
                                    (map['disponivelAgendamento'] ?? false) ==
                                    true,

                                'duracaoMinutos': map['duracaoMinutos'] ?? 60,

                                'intervaloAposAtendimentoMinutos':
                                    map['intervaloAposAtendimentoMinutos'] ?? 0,

                                'exibirPrecoAgenda':
                                    (map['exibirPrecoAgenda'] ?? true) == true,
                              },
                            );
                          } else {
                            _requirePerm();
                          }
                        },
                        onEdit:
                            _canManageServices
                                ? () {
                                  _abrirFormulario(
                                    context,
                                    servicoId: id,
                                    dados: {
                                      'nome': nome,
                                      'descricao': desc,
                                      'valorUnitario': valor,
                                      'custoExecucao': custoExecucao,
                                      'unidade': unidade,
                                      'categoriaId': map['categoriaId'],
                                      'categoriaNome': map['categoriaNome'],
                                      'imagemUrl': imagemUrl,

                                      'disponivelAgendamento':
                                          (map['disponivelAgendamento'] ??
                                              false) ==
                                          true,

                                      'duracaoMinutos':
                                          map['duracaoMinutos'] ?? 60,

                                      'intervaloAposAtendimentoMinutos':
                                          map['intervaloAposAtendimentoMinutos'] ??
                                          0,

                                      'exibirPrecoAgenda':
                                          (map['exibirPrecoAgenda'] ?? true) ==
                                          true,
                                    },
                                  );
                                }
                                : null,
                        onDelete:
                            _canManageServices
                                ? () => _confirmarExclusao(
                                  id,
                                  nome,
                                  imagemUrl: imagemUrl,
                                )
                                : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:
            fabEnabled ? ServicoStyle.orange : Colors.grey.shade300,
        foregroundColor: fabEnabled ? Colors.white : Colors.grey.shade700,
        onPressed:
            _loadingPlan
                ? null
                : (fabEnabled
                    ? () => _abrirFormulario(context)
                    : () async {
                      if (!_requirePerm()) return;
                      await _requirePlanSlot();
                    }),
        icon: const Icon(Icons.add),
        label: Text(_loadingPlan ? 'Validando...' : 'Novo serviço'),
      ),
    );
  }

  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final inteiro = parts[0];
    final dec = parts[1];

    final withThousand = inteiro.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );

    return 'R\$ $withThousand,$dec';
  }
}

/* ====================== FORMULÁRIO ====================== */

class _FormServicoSheet extends StatefulWidget {
  final String? servicoId;
  final Map<String, dynamic>? initial;
  final Map<String, String> unidadesDesc;
  final bool canManageServices;

  const _FormServicoSheet({
    required this.servicoId,
    required this.initial,
    required this.unidadesDesc,
    required this.canManageServices,
  });

  @override
  State<_FormServicoSheet> createState() => _FormServicoSheetState();
}

class _FormServicoSheetState extends State<_FormServicoSheet> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;
  final _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();
  final _custoCtrl = TextEditingController();

  String _unidade = 'UN';
  bool _salvando = false;
  String? _categoriaId;
  String? _categoriaNome;

  bool _disponivelAgendamento = false;
  bool _exibirPrecoAgenda = true;

  final _duracaoMinutosCtrl = TextEditingController(text: '60');
  final _intervaloAtendimentoCtrl = TextEditingController(text: '0');

  // Imagem do serviço: no máximo 1 imagem.
  String? _imagemAtual;
  String? _imagemOriginal;
  XFile? _novaImagem;
  bool _removerImagemExistente = false;

  @override
  void initState() {
    super.initState();

    final d = widget.initial;
    _categoriaId = widget.initial?['categoriaId'];
    _categoriaNome = widget.initial?['categoriaNome'];

    final imagemInicial =
        (widget.initial?['imagemUrl'] ?? '').toString().trim();
    _imagemAtual = imagemInicial.isEmpty ? null : imagemInicial;
    _imagemOriginal = _imagemAtual;

    if (d != null) {
      _nomeCtrl.text = (d['nome'] ?? '').toString();
      _descCtrl.text = (d['descricao'] ?? '').toString();

      final v =
          (d['valorUnitario'] is num)
              ? (d['valorUnitario'] as num).toDouble()
              : double.tryParse('${d['valorUnitario']}') ?? 0.0;
      _valorCtrl.text = _fmtCampo(v);

      final c =
          (d['custoExecucao'] is num)
              ? (d['custoExecucao'] as num).toDouble()
              : double.tryParse('${d['custoExecucao']}') ?? 0.0;
      _custoCtrl.text = _fmtCampo(c);

      _unidade = (d['unidade'] ?? 'UN').toString();

      _disponivelAgendamento = (d['disponivelAgendamento'] ?? false) == true;

      _exibirPrecoAgenda = (d['exibirPrecoAgenda'] ?? true) == true;

      final duracao =
          (d['duracaoMinutos'] is num)
              ? (d['duracaoMinutos'] as num).toInt()
              : int.tryParse('${d['duracaoMinutos']}') ?? 60;

      final intervalo =
          (d['intervaloAposAtendimentoMinutos'] is num)
              ? (d['intervaloAposAtendimentoMinutos'] as num).toInt()
              : int.tryParse('${d['intervaloAposAtendimentoMinutos']}') ?? 0;

      _duracaoMinutosCtrl.text = duracao.toString();
      _intervaloAtendimentoCtrl.text = intervalo.toString();
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    _valorCtrl.dispose();
    _custoCtrl.dispose();

    _duracaoMinutosCtrl.dispose();
    _intervaloAtendimentoCtrl.dispose();
    super.dispose();
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

  Future<(String?, String?)> _resolveOwnerAndCompany() async {
    final me = await _loadCurrentUserRecord();

    if (me == null) return (null, null);

    final role = (me['role'] ?? '').toString().toLowerCase().trim();
    final companyId = (me['companyId'] ?? '').toString().trim();
    final uid = _auth.currentUser?.uid;

    if (role == 'admin') {
      return (
        companyId.isNotEmpty ? companyId : uid,
        companyId.isNotEmpty ? companyId : null,
      );
    }

    if (role == 'funcionario') {
      if (companyId.isEmpty) return (null, null);
      return (companyId, companyId);
    }

    return (null, null);
  }

  String _fmtCampo(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String _fmtMoeda(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final inteiro = parts[0];
    final dec = parts[1];

    final withThousand = inteiro.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );

    return 'R\$ $withThousand,$dec';
  }

  double _parseMoeda(String s) {
    final x = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(x) ?? 0.0;
  }

  String? _validaNome(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o nome do serviço';
    if (s.length < 2) return 'Nome muito curto';
    return null;
  }

  String? _validaValor(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o valor unitário';
    if (_parseMoeda(s) < 0) return 'Valor inválido';
    return null;
  }

  String? _validaCusto(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o custo para execução';
    if (_parseMoeda(s) < 0) return 'Custo inválido';
    return null;
  }

  Future<void> _selecionarImagem() async {
    if (!widget.canManageServices || _salvando) return;

    try {
      final imagem = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );

      if (imagem == null) return;

      setState(() {
        _novaImagem = imagem;
        // A imagem antiga somente será removida do Storage após o novo
        // cadastro/alteração ter sido salvo com sucesso.
        _removerImagemExistente = _imagemOriginal != null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao selecionar imagem: $e')));
    }
  }

  void _removerImagem() {
    if (_salvando) return;

    setState(() {
      if (_novaImagem != null) {
        _novaImagem = null;
        // Se havia uma imagem original e o usuário apenas cancelou a nova,
        // a original volta a ser mantida.
        _removerImagemExistente =
            _imagemAtual == null && _imagemOriginal != null;
        return;
      }

      if (_imagemAtual != null) {
        _imagemAtual = null;
        _removerImagemExistente = _imagemOriginal != null;
      }
    });
  }

  Future<String> _uploadImagemServico({
    required String servicoId,
    required String companyId,
    required XFile imagem,
  }) async {
    final bytes = await imagem.readAsBytes();

    final mime = (imagem.mimeType ?? '').toLowerCase();
    String extensao = 'jpg';

    if (mime.contains('png')) {
      extensao = 'png';
    } else if (mime.contains('webp')) {
      extensao = 'webp';
    } else if (mime.contains('gif')) {
      extensao = 'gif';
    } else {
      final nome = imagem.name.toLowerCase();
      if (nome.endsWith('.png')) {
        extensao = 'png';
      } else if (nome.endsWith('.webp')) {
        extensao = 'webp';
      } else if (nome.endsWith('.gif')) {
        extensao = 'gif';
      }
    }

    final contentType =
        mime.isNotEmpty
            ? mime
            : (extensao == 'png'
                ? 'image/png'
                : extensao == 'webp'
                ? 'image/webp'
                : extensao == 'gif'
                ? 'image/gif'
                : 'image/jpeg');

    final ts = DateTime.now().microsecondsSinceEpoch;
    final path = 'servicos/$companyId/$servicoId/imagem_$ts.$extensao';

    final ref = _storage.ref().child(path);

    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: contentType),
    );

    // Gravamos o fullPath em vez da URL assinada. A tela resolve o
    // downloadURL ao exibir, seguindo o mesmo padrão já usado no app.
    return ref.fullPath;
  }

  Future<void> _deleteStorageImage(String? raw) async {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return;

    try {
      final Reference ref =
          value.startsWith('http://') ||
                  value.startsWith('https://') ||
                  value.startsWith('gs://')
              ? _storage.refFromURL(value)
              : _storage.ref(value);
      await ref.delete();
    } catch (e) {
      debugPrint('⚠️ Erro ao remover imagem antiga do serviço: $e');
    }
  }

  Map<String, dynamic> _dadosPublicosServico({
    required String companyId,
    required String servicoId,
  }) {
    return {
      'companyId': companyId,
      'servicoId': servicoId,

      'nome': _nomeCtrl.text.trim(),

      'descricao': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),

      'valorUnitario': _parseMoeda(_valorCtrl.text),

      'duracaoMinutos': int.tryParse(_duracaoMinutosCtrl.text.trim()) ?? 60,

      'intervaloAposAtendimentoMinutos':
          int.tryParse(_intervaloAtendimentoCtrl.text.trim()) ?? 0,

      'exibirPrecoAgenda': _exibirPrecoAgenda,

      'ativo': true,

      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _salvar() async {
    if (!widget.canManageServices) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para salvar serviços.')),
      );
      return;
    }

    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login para salvar.')));
      return;
    }

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verifique os campos obrigatórios do serviço.'),
        ),
      );
      return;
    }

    if (_disponivelAgendamento) {
      final duracao = int.tryParse(_duracaoMinutosCtrl.text.trim());

      final intervalo = int.tryParse(_intervaloAtendimentoCtrl.text.trim());

      if (duracao == null || duracao <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe uma duração válida para o serviço.'),
          ),
        );
        return;
      }

      if (intervalo == null || intervalo < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe um intervalo válido após o atendimento.'),
          ),
        );
        return;
      }
    }

    setState(() => _salvando = true);

    String docId = widget.servicoId ?? '';
    String? imagemNovaPath;

    try {
      final (ownerId, companyId) = await _resolveOwnerAndCompany();

      if (ownerId == null || companyId == null || companyId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sem empresa vinculada: configure o companyId no cadastro do usuário.',
              ),
            ),
          );
        }
        return;
      }

      final dados = <String, dynamic>{
        'nome': _nomeCtrl.text.trim(),
        'nomeLower': _nomeCtrl.text.trim().toLowerCase(),
        'descricao':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),

        'valorUnitario': _parseMoeda(_valorCtrl.text),
        'custoExecucao': _parseMoeda(_custoCtrl.text),

        'unidade': _unidade,

        'categoriaId': _categoriaId,
        'categoriaNome': _categoriaNome,

        // Agenda online
        'disponivelAgendamento': _disponivelAgendamento,
        'duracaoMinutos': int.tryParse(_duracaoMinutosCtrl.text.trim()) ?? 60,
        'intervaloAposAtendimentoMinutos':
            int.tryParse(_intervaloAtendimentoCtrl.text.trim()) ?? 0,
        'exibirPrecoAgenda': _exibirPrecoAgenda,

        'updatedAt': FieldValue.serverTimestamp(),
      };

      // ============================================================
      // 1. SALVA O SERVIÇO E SINCRONIZA A PROJEÇÃO PÚBLICA DA AGENDA
      // EM UMA ÚNICA OPERAÇÃO ATÔMICA.
      // ============================================================
      final servicoRef =
          widget.servicoId == null
              ? _fs.collection('servicos').doc()
              : _fs.collection('servicos').doc(widget.servicoId!);

      docId = servicoRef.id;

      final publicoRef = _fs
          .collection('agenda_servicos_publicos')
          .doc(companyId)
          .collection('servicos')
          .doc(docId);

      final batch = _fs.batch();

      if (widget.servicoId == null) {
        batch.set(servicoRef, {
          ...dados,
          'ownerId': ownerId,
          'companyId': companyId,
          'userId': uid,
          'createdByUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        batch.update(servicoRef, dados);
      }

      // Somente serviços disponíveis para agendamento existem
      // na projeção pública.
      if (_disponivelAgendamento) {
        batch.set(publicoRef, {
          ..._dadosPublicosServico(companyId: companyId, servicoId: docId),
          if (widget.servicoId == null)
            'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        batch.delete(publicoRef);
      }

      await batch.commit();

      // ============================================================
      // 2. PROCESSA A IMAGEM SOMENTE DEPOIS DE O SERVIÇO EXISTIR.
      // Mesmo padrão usado no cadastro de produtos.
      // ============================================================
      if (_novaImagem != null) {
        final ts = DateTime.now().microsecondsSinceEpoch;

        // O produto já usa o UID na pasta do Storage.
        // Mantemos o mesmo padrão para serviços.
        final path = 'servicos/$uid/${docId}_$ts.jpg';
        final ref = _storage.ref().child(path);

        final bytes = await _novaImagem!.readAsBytes();

        await ref.putData(
          bytes,
          SettableMetadata(contentType: _novaImagem!.mimeType ?? 'image/jpeg'),
        );

        imagemNovaPath = ref.fullPath;

        await _fs.collection('servicos').doc(docId).update({
          'imagemUrl': imagemNovaPath,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // A nova imagem já está referenciada no Firestore.
        // Agora é seguro apagar a anterior.
        if (_imagemOriginal != null &&
            _imagemOriginal!.isNotEmpty &&
            _imagemOriginal != imagemNovaPath) {
          await _deleteStorageImage(_imagemOriginal);
        }
      } else if (_removerImagemExistente) {
        await _fs.collection('servicos').doc(docId).update({
          'imagemUrl': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (_imagemOriginal != null && _imagemOriginal!.isNotEmpty) {
          await _deleteStorageImage(_imagemOriginal);
        }
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } on FirebaseException catch (e, st) {
      debugPrint('❌ Erro Firebase ao salvar serviço: ${e.code}');
      debugPrint('${e.message}');
      debugPrint('$st');

      // Se o upload ocorreu mas o update do Firestore falhou,
      // evita deixar o arquivo novo órfão.
      if (imagemNovaPath != null) {
        await _deleteStorageImage(imagemNovaPath);
      }

      if (!mounted) return;

      String mensagem = e.message ?? e.code;

      if (e.code == 'permission-denied' || e.code == 'unauthorized') {
        mensagem =
            'Sem permissão para gravar a imagem no Firebase Storage. '
            'Verifique as regras do Storage para a pasta "servicos/".';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar serviço: $mensagem'),
          duration: const Duration(seconds: 7),
        ),
      );
    } catch (e, st) {
      debugPrint('❌ Erro ao salvar serviço: $e');
      debugPrint('$st');

      if (imagemNovaPath != null) {
        await _deleteStorageImage(imagemNovaPath);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar serviço: $e'),
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  Widget _agendaOnlineSection() {
    final cs = Theme.of(context).colorScheme;

    final valorAtual = _parseMoeda(_valorCtrl.text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBadge(
                icon: Icons.calendar_month_outlined,
                color: ServicoStyle.primary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agenda online',
                      style: TextStyle(
                        color: ServicoStyle.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Configure este serviço para agendamentos.',
                      style: TextStyle(
                        color: ServicoStyle.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _disponivelAgendamento,
            onChanged:
                _salvando
                    ? null
                    : (value) {
                      setState(() {
                        _disponivelAgendamento = value;
                      });
                    },
            title: const Text(
              'Disponível para agendamento',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Permite que clientes agendem este serviço pela agenda online.',
            ),
            secondary: Icon(
              Icons.event_available_outlined,
              color:
                  _disponivelAgendamento
                      ? ServicoStyle.green
                      : ServicoStyle.muted,
            ),
          ),

          if (_disponivelAgendamento) ...[
            const Divider(height: 24),

            TextFormField(
              controller: _duracaoMinutosCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDecoration(
                label: 'Duração do serviço *',
                helper: 'Tempo necessário para realizar o atendimento.',
                icon: Icons.schedule_outlined,
                suffix: const Padding(
                  padding: EdgeInsets.only(right: 14, top: 15),
                  child: Text(
                    'min',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ServicoStyle.muted,
                    ),
                  ),
                ),
              ),
              validator: (value) {
                if (!_disponivelAgendamento) return null;

                final duracao = int.tryParse((value ?? '').trim());

                if (duracao == null || duracao <= 0) {
                  return 'Informe a duração do serviço';
                }

                return null;
              },
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _intervaloAtendimentoCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDecoration(
                label: 'Intervalo após atendimento',
                helper: 'Tempo de preparação antes do próximo cliente.',
                icon: Icons.hourglass_bottom_outlined,
                suffix: const Padding(
                  padding: EdgeInsets.only(right: 14, top: 15),
                  child: Text(
                    'min',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ServicoStyle.muted,
                    ),
                  ),
                ),
              ),
              validator: (value) {
                if (!_disponivelAgendamento) return null;

                final intervalo = int.tryParse((value ?? '').trim());

                if (intervalo == null || intervalo < 0) {
                  return 'Informe um intervalo válido';
                }

                return null;
              },
            ),

            const SizedBox(height: 8),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _exibirPrecoAgenda,
              onChanged:
                  _salvando
                      ? null
                      : (value) {
                        setState(() {
                          _exibirPrecoAgenda = value;
                        });
                      },
              title: const Text(
                'Exibir preço na agenda',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _exibirPrecoAgenda
                    ? 'O cliente verá o valor unitário deste serviço.'
                    : 'O preço não será exibido para o cliente.',
              ),
              secondary: Icon(
                Icons.sell_outlined,
                color:
                    _exibirPrecoAgenda
                        ? ServicoStyle.green
                        : ServicoStyle.muted,
              ),
            ),

            if (_exibirPrecoAgenda) ...[
              const SizedBox(height: 4),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ServicoStyle.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: ServicoStyle.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Preço exibido na agenda: '
                        '${_fmtMoeda(valorAtual)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ServicoStyle.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding =
        MediaQuery.of(context).viewInsets +
        const EdgeInsets.fromLTRB(16, 8, 16, 16);

    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Row(
              children: [
                const _IconBadge(
                  icon: Icons.handyman_outlined,
                  color: ServicoStyle.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.servicoId == null
                        ? 'Novo serviço'
                        : 'Editar serviço',
                    style: const TextStyle(
                      color: ServicoStyle.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.canManageServices) ...[
              const SizedBox(height: 10),
              const _PermissionBox(),
            ],
            const SizedBox(height: 14),
            _imagemServicoCard(),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _field(
                    controller: _nomeCtrl,
                    label: 'Nome do serviço *',
                    prefixIcon: Icons.handyman_outlined,
                    validator: _validaNome,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _descCtrl,
                    label: 'Descrição',
                    prefixIcon: Icons.description_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _categoriaField(),
                  const SizedBox(height: 12),
                  _field(
                    controller: _custoCtrl,
                    label: 'Custo para execução *',
                    helperText: 'Quanto você gasta para realizar esse serviço.',
                    prefixIcon: Icons.payments_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\., ]')),
                    ],
                    validator: _validaCusto,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (ctx, c) {
                      final narrow = c.maxWidth < 420;

                      final valorField = _field(
                        controller: _valorCtrl,
                        label: 'Valor unitário *',
                        helperText: 'Valor cobrado do cliente.',
                        prefixIcon: Icons.request_page_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\., ]'),
                          ),
                        ],
                        validator: _validaValor,
                      );

                      final unidadeField = DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _unidade,
                        decoration: _inputDecoration(
                          label: 'Unid. *',
                          icon: Icons.straighten_outlined,
                        ),
                        items:
                            widget.unidadesDesc.entries.map((e) {
                              return DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  '${e.key} — ${e.value}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                        selectedItemBuilder: (ctx) {
                          final keys = widget.unidadesDesc.keys.toList();

                          return keys
                              .map(
                                (k) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    k,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              )
                              .toList();
                        },
                        onChanged: (v) => setState(() => _unidade = v ?? 'UN'),
                      );

                      if (narrow) {
                        return Column(
                          children: [
                            valorField,
                            const SizedBox(height: 12),
                            unidadeField,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(flex: 2, child: valorField),
                          const SizedBox(width: 12),
                          Expanded(child: unidadeField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _agendaOnlineSection(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ServicoStyle.primary,
                            side: BorderSide(
                              color: ServicoStyle.primary.withOpacity(0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              _salvando
                                  ? null
                                  : () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                          label: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: ServicoStyle.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              (_salvando || !widget.canManageServices)
                                  ? null
                                  : _salvar,
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
                                  : const Icon(Icons.check_rounded),
                          label: Text(
                            widget.servicoId == null ? 'Salvar' : 'Atualizar',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _imagemServicoCard() {
    final temImagemNova = _novaImagem != null;
    final temImagemAtual = _imagemAtual != null && _imagemAtual!.isNotEmpty;
    final temImagem = temImagemNova || temImagemAtual;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBadge(
                icon: Icons.image_outlined,
                color: ServicoStyle.primary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Imagem do serviço',
                      style: TextStyle(
                        color: ServicoStyle.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Opcional • 1 imagem',
                      style: TextStyle(
                        color: ServicoStyle.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (temImagem)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child:
                        temImagemNova
                            ? _XFileImagePreview(file: _novaImagem!)
                            : _StorageImagePreview(raw: _imagemAtual!),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withOpacity(0.65),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Remover imagem',
                      onPressed:
                          (_salvando || !widget.canManageServices)
                              ? null
                              : _removerImagem,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap:
                  (_salvando || !widget.canManageServices)
                      ? null
                      : _selecionarImagem,
              child: Container(
                width: double.infinity,
                height: 145,
                decoration: BoxDecoration(
                  color: ServicoStyle.bg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: ServicoStyle.primary.withOpacity(0.22),
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: ServicoStyle.primary,
                      size: 34,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Adicionar imagem',
                      style: TextStyle(
                        color: ServicoStyle.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Selecione uma imagem da galeria',
                      style: TextStyle(color: ServicoStyle.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          if (temImagem) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    (_salvando || !widget.canManageServices)
                        ? null
                        : _selecionarImagem,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ServicoStyle.primary,
                  side: BorderSide(
                    color: ServicoStyle.primary.withOpacity(0.25),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text(
                  'Trocar imagem',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoriaField() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final dadosEmpresa = await _resolveOwnerAndCompany();
        final scopeCompanyId = dadosEmpresa.$2 ?? dadosEmpresa.$1;

        if (scopeCompanyId == null || scopeCompanyId.isEmpty) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Empresa não identificada.')),
          );
          return;
        }

        if (!mounted) return;

        final result = await showModalBottomSheet<CategoriaSelecionada>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const SelecionarCategoriaSheet(tipo: 'servico'),
        );

        if (result != null) {
          setState(() {
            _categoriaId = result.id;
            _categoriaNome = result.nome;
          });
        }
      },
      child: InputDecorator(
        decoration: _inputDecoration(
          label: 'Categoria',
          helper: 'Opcional',
          icon: Icons.category_outlined,
          suffix:
              _categoriaId == null
                  ? const Icon(Icons.search)
                  : IconButton(
                    tooltip: 'Remover categoria',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _categoriaId = null;
                        _categoriaNome = null;
                      });
                    },
                  ),
        ),
        child: Text(
          _categoriaNome == null || _categoriaNome!.isEmpty
              ? 'Selecionar categoria'
              : _categoriaNome!,
          style: TextStyle(
            color:
                _categoriaNome == null || _categoriaNome!.isEmpty
                    ? ServicoStyle.muted
                    : ServicoStyle.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    String? label,
    String? helperText,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: _inputDecoration(
        label: label,
        helper: helperText,
        icon: prefixIcon,
        suffix:
            controller.text.isEmpty
                ? null
                : IconButton(
                  tooltip: 'Limpar',
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  InputDecoration _inputDecoration({
    String? label,
    String? helper,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon == null ? null : Icon(icon, color: ServicoStyle.primary),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: ServicoStyle.primary, width: 1.4),
      ),
      isDense: true,
    );
  }
}

/* ====================== WIDGETS VISUAIS ====================== */

class ServicosHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onNew;

  const ServicosHeader({super.key, required this.onBack, required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: ServicoStyle.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 6,
        16,
        16,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              const Expanded(
                child: Center(
                  child: Text(
                    'Serviços',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(icon: Icons.add, onTap: onNew ?? () {}),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Cadastre e gerencie os serviços oferecidos pela sua empresa.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final TextEditingController controller;
  final String q;
  final VoidCallback onClear;

  const _SearchCard({
    required this.controller,
    required this.q,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Buscar por nome do serviço...',
          hintStyle: const TextStyle(color: ServicoStyle.muted),
          prefixIcon: const Icon(Icons.search, color: ServicoStyle.primary),
          suffixIcon:
              q.isEmpty
                  ? null
                  : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.clear),
                    onPressed: onClear,
                  ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        textInputAction: TextInputAction.search,
      ),
    );
  }
}

class _ServicoCard extends StatelessWidget {
  final String nome;
  final String descricao;
  final String unidade;
  final double valor;
  final double custoExecucao;
  final String imagemUrl;
  final String Function(double value) fmtMoeda;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ServicoCard({
    required this.nome,
    required this.descricao,
    required this.unidade,
    required this.valor,
    required this.custoExecucao,
    required this.imagemUrl,
    required this.fmtMoeda,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServicoThumbnail(imagemUrl: imagemUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isNotEmpty ? nome : 'Sem nome',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ServicoStyle.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (descricao.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ServicoStyle.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          label: 'Unidade: $unidade',
                          icon: Icons.straighten_outlined,
                        ),
                        _InfoChip(
                          label: 'Valor: ${fmtMoeda(valor)}',
                          icon: Icons.request_quote_outlined,
                        ),
                        _InfoChip(
                          label: 'Custo: ${fmtMoeda(custoExecucao)}',
                          icon: Icons.payments_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (v) {
                  if (v == 'edit') onEdit?.call();
                  if (v == 'del') onDelete?.call();
                },
                itemBuilder:
                    (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        enabled: onEdit != null,
                        child: const Text('Editar'),
                      ),
                      PopupMenuItem(
                        value: 'del',
                        enabled: onDelete != null,
                        child: const Text('Excluir'),
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

class _ServicoThumbnail extends StatelessWidget {
  final String imagemUrl;

  const _ServicoThumbnail({required this.imagemUrl});

  @override
  Widget build(BuildContext context) {
    if (imagemUrl.trim().isEmpty) {
      return const _IconBadge(
        icon: Icons.handyman_outlined,
        color: ServicoStyle.primary,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 58,
        height: 58,
        child: _StorageImagePreview(
          raw: imagemUrl,
          fallback: const _IconBadge(
            icon: Icons.handyman_outlined,
            color: ServicoStyle.primary,
          ),
        ),
      ),
    );
  }
}

class _StorageImagePreview extends StatelessWidget {
  final String raw;
  final Widget? fallback;

  const _StorageImagePreview({required this.raw, this.fallback});

  Future<String> _resolve() async {
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final Reference ref =
        value.startsWith('gs://')
            ? FirebaseStorage.instance.refFromURL(value)
            : FirebaseStorage.instance.ref(value);

    return ref.getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolve(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            color: ServicoStyle.bg,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ServicoStyle.primary,
              ),
            ),
          );
        }

        final url = snap.data;
        if (url == null || url.isEmpty) {
          return fallback ??
              Container(
                color: ServicoStyle.bg,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: ServicoStyle.muted,
                ),
              );
        }

        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) =>
                  fallback ??
                  Container(
                    color: ServicoStyle.bg,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: ServicoStyle.muted,
                    ),
                  ),
        );
      },
    );
  }
}

class _XFileImagePreview extends StatelessWidget {
  final XFile file;

  const _XFileImagePreview({required this.file});

  Future<Uint8List> _bytes() => file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            color: ServicoStyle.bg,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: ServicoStyle.primary),
          );
        }

        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: ServicoStyle.bg,
            child: const Icon(
              Icons.broken_image_outlined,
              color: ServicoStyle.muted,
            ),
          );
        }

        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ServicoStyle.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: ServicoStyle.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ServicoStyle.text,
                fontSize: 12,
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
  final String q;
  final VoidCallback onClear;
  final VoidCallback? onNew;

  const _EmptyState({
    required this.q,
    required this.onClear,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 44),
        Column(
          children: [
            const _IconBadge(
              icon: Icons.handyman_outlined,
              color: ServicoStyle.orange,
            ),
            const SizedBox(height: 14),
            Text(
              q.isEmpty
                  ? 'Nenhum serviço cadastrado para esta empresa.'
                  : 'Nenhum serviço encontrado para “$q”.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ServicoStyle.text,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              q.isEmpty
                  ? 'Toque em “Novo serviço” para começar.'
                  : 'Tente outro termo ou limpe a busca.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ServicoStyle.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (q.isNotEmpty)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpar busca'),
              )
            else
              OutlinedButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add),
                label: const Text('Cadastrar primeiro serviço'),
              ),
          ],
        ),
      ],
    );
  }
}

class _PermissionBox extends StatelessWidget {
  const _PermissionBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ServicoStyle.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ServicoStyle.orange.withOpacity(0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: ServicoStyle.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Você não tem permissão para criar/alterar serviços.',
              style: TextStyle(
                color: ServicoStyle.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

/* ====================== STYLE ====================== */

class ServicoStyle {
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
}
