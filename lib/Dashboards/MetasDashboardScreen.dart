import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardMetasProdutosScreen extends StatefulWidget {
  const DashboardMetasProdutosScreen({super.key});

  @override
  State<DashboardMetasProdutosScreen> createState() =>
      _DashboardMetasProdutosScreenState();
}

class _DashboardMetasProdutosScreenState
    extends State<DashboardMetasProdutosScreen> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _uid;
  String? _companyId;

  bool _loadingInit = true;
  String? _initError;

  // Permissões
  bool _canManageGoals = false; // 👈 NOVO

  // Metas (goals)
  List<_Goal> _goals = [];
  _Goal? _selectedGoal;

  // Usuários da empresa para o filtro
  List<_UserInfo> _companyUsers = [];
  String? _selectedAuthUid; // null = "Todos" (quando pode ver todos)
  bool _loadingUsers = false;

  // Resultado KPI (sempre "alvo x atingido", mas o que significa depende do KPI)
  bool _loadingData = false;
  String? _dataError;

  double _alvoTotal = 0;
  double _atingidoTotal = 0;
  double _progressoTotal = 0; // 0..1
  double _restanteTotal = 0;

  // Faturamento específico de novos clientes (somente para kpi = novos_clientes_faturamento_qtd)
  double _faturamentoNovosClientes = 0;

  // Linhas para exibição
  List<_ProdRow> _prodRows = []; // para KPI produtos/serviços
  List<_PedidoRow> _pedidoRows = []; // para KPI pedidos e novos_clientes...

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      setState(() {
        _loadingInit = true;
        _initError = null;
      });

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não logado.');
      }
      _uid = user.uid;

      // ========= Descobrir companyId do usuário logado =========
      Map<String, dynamic> udata = {};
      DocumentSnapshot<Map<String, dynamic>>? userDoc;

      // 1) Tenta doc com id = auth.uid
      final docById = await _fs
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions());
      if (docById.exists) {
        userDoc = docById;
        udata = docById.data() ?? {};
      }

      // 2) Se não achou ou veio sem companyId, tenta por authUid = uid
      String? tmpCompanyId =
          (udata['companyId'] ?? udata['company_id']) as String?;
      if (userDoc == null || tmpCompanyId == null || tmpCompanyId.isEmpty) {
        final qsAuth =
            await _fs
                .collection('users')
                .where('authUid', isEqualTo: user.uid)
                .limit(1)
                .get();

        if (qsAuth.docs.isNotEmpty) {
          userDoc = qsAuth.docs.first;
          udata = userDoc.data() as Map<String, dynamic>? ?? {};
          tmpCompanyId = (udata['companyId'] ?? udata['company_id']) as String?;
        }
      }

      // 3) Fallback extra: tenta uid/userId dentro do doc
      if (tmpCompanyId == null || tmpCompanyId.isEmpty) {
        final maybeCompany =
            (udata['companyId'] ?? udata['company_id']) as String?;
        if (maybeCompany != null && maybeCompany.isNotEmpty) {
          tmpCompanyId = maybeCompany;
        }
      }

      // ====== Permissão canManageGoals ======
      dynamic rawPerm = udata['canManageGoals'];

      // Se não estiver na raiz, tenta buscar em um mapa de permissões
      if (rawPerm == null) {
        final perms =
            (udata['permissions'] as Map<String, dynamic>?) ??
            (udata['permissoes'] as Map<String, dynamic>?);

        if (perms != null) {
          rawPerm =
              perms['canManageGoals'] ??
              perms['goalsManage'] ??
              perms['goals_manage'];
        }
      }

      bool canManage = false;
      if (rawPerm is bool) {
        canManage = rawPerm;
      } else if (rawPerm is num) {
        canManage = rawPerm != 0;
      } else if (rawPerm is String) {
        final v = rawPerm.toLowerCase().trim();
        canManage =
            (v == 'true' || v == '1' || v == 'yes' || v == 'y' || v == 'sim');
      }

      _canManageGoals = canManage; // 👈 guarda permissão em memória

      // 4) Se ainda não tiver companyId, considera empresa solo (uid)
      _companyId =
          (tmpCompanyId == null || tmpCompanyId.isEmpty) ? _uid : tmpCompanyId;

      // 1) Carrega usuários da empresa (para o filtro)
      await _loadUsersForCompany();

      // 2) Carrega metas
      await _loadGoals();
    } catch (e) {
      _initError = 'Erro ao inicializar: $e';
    } finally {
      if (mounted) {
        setState(() {
          _loadingInit = false;
        });
      }
    }
  }

  Future<void> _loadUsersForCompany() async {
    if (_companyId == null) return;

    try {
      setState(() {
        _loadingUsers = true;
        _companyUsers = [];
        _selectedAuthUid = null; // valor inicial; ajustamos abaixo
      });

      final users = <_UserInfo>[];
      final seenDocIds = <String>{};

      // --- 1) Usuários com companyId ---
      final qsCompanyId =
          await _fs
              .collection('users')
              .where('companyId', isEqualTo: _companyId)
              .get();

      for (final d in qsCompanyId.docs) {
        if (seenDocIds.contains(d.id)) continue;
        seenDocIds.add(d.id);

        final data = d.data() as Map<String, dynamic>? ?? {};

        final nome =
            (data['nome'] ?? data['name'] ?? data['displayName'] ?? d.id)
                .toString();

        final rawAuthUid = (data['authUid'] ?? '').toString().trim();
        final effectiveAuthUid = rawAuthUid.isNotEmpty ? rawAuthUid : d.id;

        final legacyRaw = data['userId'] ?? data['uid'] ?? data['id'];
        final legacyUserId =
            legacyRaw == null ? null : legacyRaw.toString().trim();

        users.add(
          _UserInfo(
            authUid: effectiveAuthUid,
            nome: nome,
            docId: d.id,
            legacyUserId: legacyUserId,
          ),
        );
      }

      // --- 2) Usuários com company_id (legado) ---
      final qsCompanyIdLegacy =
          await _fs
              .collection('users')
              .where('company_id', isEqualTo: _companyId)
              .get();

      for (final d in qsCompanyIdLegacy.docs) {
        if (seenDocIds.contains(d.id)) continue;
        seenDocIds.add(d.id);

        final data = d.data() as Map<String, dynamic>? ?? {};

        final nome =
            (data['nome'] ?? data['name'] ?? data['displayName'] ?? d.id)
                .toString();

        final rawAuthUid = (data['authUid'] ?? '').toString().trim();
        final effectiveAuthUid = rawAuthUid.isNotEmpty ? rawAuthUid : d.id;

        final legacyRaw = data['userId'] ?? data['uid'] ?? data['id'];
        final legacyUserId =
            legacyRaw == null ? null : legacyRaw.toString().trim();

        users.add(
          _UserInfo(
            authUid: effectiveAuthUid,
            nome: nome,
            docId: d.id,
            legacyUserId: legacyUserId,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _companyUsers = users;

        // 👇 Regra do filtro conforme permissão
        if (_canManageGoals) {
          // Tem permissão -> pode ver "Todos" e escolher usuários
          _selectedAuthUid = null; // "Todos os usuários"
        } else {
          // NÃO tem permissão -> só pode ver ele mesmo
          _selectedAuthUid = _uid; // força filtro no usuário logado
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
      }
    }
  }

  Future<void> _loadGoals() async {
    if (_companyId == null) return;

    setState(() {
      _goals = [];
      _selectedGoal = null;
    });

    final qs =
        await _fs
            .collection('goals')
            .where('companyId', isEqualTo: _companyId)
            // Carrega metas de produtos/serviços, pedidos e novos clientes
            .where(
              'kpi',
              whereIn: [
                'produtos_servicos',
                'pedidos',
                'novos_clientes_faturamento_qtd',
              ],
            )
            .orderBy('periodEnd', descending: true)
            .limit(50)
            .get();

    final goals = <_Goal>[];
    for (final doc in qs.docs) {
      try {
        goals.add(_Goal.fromDoc(doc));
      } catch (_) {
        // ignora documentos mal formatados
      }
    }

    if (!mounted) return;

    setState(() {
      _goals = goals;
      _selectedGoal = goals.isNotEmpty ? goals.first : null;
    });

    if (_selectedGoal != null) {
      await _loadGoalData();
    }
  }

  /// Converte os userIds da meta (que podem ser docId, userId, authUid etc.)
  /// para um conjunto de authUids reais (usados em pedidos.createdByUid).
  Set<String> _resolveMetaAuthUids(_Goal goal) {
    final rawIds =
        goal.userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    // Se não temos usuários carregados, assumimos que o que está na meta já é authUid
    if (_companyUsers.isEmpty) return rawIds;

    final Set<String> metaAuthUids = {};

    for (final u in _companyUsers) {
      if (rawIds.contains(u.authUid) ||
          rawIds.contains(u.docId) ||
          (u.legacyUserId != null && rawIds.contains(u.legacyUserId!))) {
        metaAuthUids.add(u.authUid);
      }
    }

    // Se por algum motivo não encontramos correspondência, volta para rawIds
    return metaAuthUids.isEmpty ? rawIds : metaAuthUids;
  }

  Future<void> _loadGoalData() async {
    final goal = _selectedGoal;
    if (goal == null || _companyId == null) return;

    final bool isUserScope = [
      'users',
      'user',
      'usuario',
      'usuarios',
    ].contains(goal.scopeType.toLowerCase());

    try {
      setState(() {
        _loadingData = true;
        _dataError = null;
      });

      if (goal.periodStart == null || goal.periodEnd == null) {
        throw Exception('Meta sem período definido (periodStart/periodEnd).');
      }

      final ini = _at00(goal.periodStart!);
      final fim = _at00(goal.periodEnd!.add(const Duration(days: 1)));

      final iniTs = Timestamp.fromDate(ini);
      final fimTs = Timestamp.fromDate(fim);

      // Query base de pedidos (sempre por empresa + período)
      Query baseQuery = _fs
          .collection('pedidos')
          .where('companyId', isEqualTo: _companyId)
          .where('data', isGreaterThanOrEqualTo: iniTs)
          .where('data', isLessThan: fimTs);

      // Vamos acumular os docs de pedidos aqui (com ou sem whereIn)
      final List<QueryDocumentSnapshot> pedidoDocs = [];

      // ===== RESPEITAR ESCOPO DA META =====
      if (isUserScope) {
        // META POR USUÁRIOS
        final metaAuthUids = _resolveMetaAuthUids(goal);

        if (metaAuthUids.isEmpty) {
          throw Exception(
            'Meta por usuários sem usuários vinculados (scope.userIds vazio).',
          );
        }

        if (_selectedAuthUid != null) {
          // Usuário filtrado na tela -> precisa estar na meta (considerando todos os formatos)
          if (!metaAuthUids.contains(_selectedAuthUid!)) {
            throw Exception('Usuário selecionado não faz parte desta meta.');
          }

          final snap =
              await baseQuery
                  .where('createdByUid', isEqualTo: _selectedAuthUid)
                  .get();
          pedidoDocs.addAll(snap.docs);
        } else {
          // "Todos", mas apenas UIDs que fazem parte da meta (sempre authUid)
          final ids = metaAuthUids.toList();
          if (ids.length <= 10) {
            final snap =
                await baseQuery.where('createdByUid', whereIn: ids).get();
            pedidoDocs.addAll(snap.docs);
          } else {
            for (var i = 0; i < ids.length; i += 10) {
              final chunk = ids.sublist(i, min(i + 10, ids.length));
              final snap =
                  await baseQuery.where('createdByUid', whereIn: chunk).get();
              pedidoDocs.addAll(snap.docs);
            }
          }
        }
      } else {
        // META POR EMPRESA
        Query q = baseQuery;
        if (_selectedAuthUid != null) {
          q = q.where('createdByUid', isEqualTo: _selectedAuthUid);
        }
        final snap = await q.get();
        pedidoDocs.addAll(snap.docs);
      }

      // === FILTRAR PEDIDOS CANCELADOS (status == "cancelado") ===
      pedidoDocs.removeWhere((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final status =
            (data['status'] ??
                    data['statusPedido'] ??
                    data['status_pedido'] ??
                    '')
                .toString()
                .toLowerCase();
        return status == 'cancelado';
      });

      // Agora, dependendo do KPI, fazemos o cálculo

      double alvoTotal = 0;
      double atingidoTotal = 0;
      double progressoTotal = 0;
      double restanteTotal = 0;

      double faturamentoNovosClientes = 0;

      List<_ProdRow> prodRows = [];
      List<_PedidoRow> pedidoRows = [];

      // =================== KPI: PRODUTOS/SERVIÇOS ===================
      if (goal.kpi == 'produtos_servicos') {
        // Monta mapa de alvos por itemId a partir dos itens da meta
        final Map<String, _GoalItem> targetByItemId = {
          for (final it in goal.items)
            if (it.itemId != null) it.itemId!: it,
        };

        if (targetByItemId.isEmpty) {
          throw Exception('Meta sem itens de produtos/serviços.');
        }

        // Soma quantidade vendida por itemId
        final Map<String, double> vendidosPorItem = {
          for (final id in targetByItemId.keys) id: 0.0,
        };

        for (final doc in pedidoDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};

          // Produtos
          final itensProd =
              (data['itensProdutos'] ?? data['itens_produtos'])
                  as List<dynamic>? ??
              [];
          for (final raw in itensProd) {
            final map = raw as Map<String, dynamic>? ?? {};
            final refId =
                (map['refId'] ?? map['produtoId'] ?? map['id']) as String?;
            if (refId == null) continue;
            if (!targetByItemId.containsKey(refId)) continue;

            final qtdRaw = map['quantidade'] ?? map['qtd'] ?? 0;
            final qtd = (qtdRaw is num) ? qtdRaw.toDouble() : 0.0;

            vendidosPorItem[refId] = (vendidosPorItem[refId] ?? 0.0) + qtd;
          }

          // Serviços
          final itensServ =
              (data['itensServicos'] ?? data['itens_servicos'])
                  as List<dynamic>? ??
              [];
          for (final raw in itensServ) {
            final map = raw as Map<String, dynamic>? ?? {};
            final refId =
                (map['refId'] ?? map['servicoId'] ?? map['id']) as String?;
            if (refId == null) continue;
            if (!targetByItemId.containsKey(refId)) continue;

            final qtdRaw = map['quantidade'] ?? map['qtd'] ?? 0;
            final qtd = (qtdRaw is num) ? qtdRaw.toDouble() : 0.0;

            vendidosPorItem[refId] = (vendidosPorItem[refId] ?? 0.0) + qtd;
          }
        }

        // Monta linhas por produto/serviço
        final rows = <_ProdRow>[];
        double alvo = 0;
        double atingido = 0;

        targetByItemId.forEach((itemId, goalItem) {
          final metaQtd = goalItem.quantidade;
          final vendidaQtd = vendidosPorItem[itemId] ?? 0.0;

          alvo += metaQtd;
          atingido += vendidaQtd;

          rows.add(
            _ProdRow(
              itemId: itemId,
              nome: goalItem.nome,
              metaQtd: metaQtd,
              vendidoQtd: vendidaQtd,
            ),
          );
        });

        rows.sort((a, b) => a.nome.compareTo(b.nome));

        final progresso =
            alvo > 0
                ? ((atingido / alvo).clamp(0.0, 999.0) as num).toDouble()
                : 0.0;
        final restante = max(alvo - atingido, 0.0);

        alvoTotal = alvo;
        atingidoTotal = atingido;
        progressoTotal = progresso;
        restanteTotal = restante;
        prodRows = rows;
        pedidoRows = [];
        faturamentoNovosClientes = 0;
      }
      // =================== KPI: PEDIDOS (VALOR) ===================
      else if (goal.kpi == 'pedidos') {
        // Meta em valor (ex: 50.000 BRL)
        double alvo = goal.target ?? 0.0;
        double atingido = 0.0;
        final rows = <_PedidoRow>[];

        for (final doc in pedidoDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};

          final clienteNome =
              (data['clienteNome'] ??
                      data['cliente_nome'] ??
                      data['cliente'] ??
                      data['nomeCliente'] ??
                      '—')
                  .toString();

          final numero =
              (data['numero'] ??
                      data['numeroPedido'] ??
                      data['numero_pedido'] ??
                      doc.id)
                  .toString();

          final ts = data['data'] as Timestamp?;
          final dataPedido = ts?.toDate();

          final status =
              (data['status'] ??
                      data['statusPedido'] ??
                      data['status_pedido'] ??
                      'Pendente')
                  .toString();

          // sempre pegar do campo pedidos.total
          final rawTotal = data['total'];
          double valor = 0.0;
          if (rawTotal is num) {
            valor = rawTotal.toDouble();
          } else if (rawTotal is String) {
            final cleaned =
                rawTotal.replaceAll('.', '').replaceAll(',', '.').trim();
            valor = double.tryParse(cleaned) ?? 0.0;
          }

          atingido += valor;

          rows.add(
            _PedidoRow(
              id: doc.id,
              clienteNome: clienteNome,
              numero: numero,
              total: valor,
              data: dataPedido,
              status: status,
            ),
          );
        }

        // Ordena por data desc, depois número
        rows.sort((a, b) {
          final da = a.data ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.data ?? DateTime.fromMillisecondsSinceEpoch(0);
          final cmp = db.compareTo(da);
          if (cmp != 0) return cmp;
          return a.numero.compareTo(b.numero);
        });

        final progresso =
            alvo > 0
                ? ((atingido / alvo).clamp(0.0, 999.0) as num).toDouble()
                : 0.0;
        final restante = max(alvo - atingido, 0.0);

        alvoTotal = alvo;
        atingidoTotal = atingido;
        progressoTotal = progresso;
        restanteTotal = restante;
        pedidoRows = rows;
        prodRows = [];
        faturamentoNovosClientes = 0;
      }
      // =================== KPI: NOVOS CLIENTES (QTD + FATURAMENTO) ===================
      else if (goal.kpi == 'novos_clientes_faturamento_qtd') {
        // 1) Descobrir todos os clienteId que têm pedidos no período
        final Set<String> clienteIdsComPedido = {};
        for (final doc in pedidoDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final cid = (data['clienteId'] ?? data['cliente_id']) as String?;
          if (cid != null && cid.isNotEmpty) {
            clienteIdsComPedido.add(cid);
          }
        }

        if (clienteIdsComPedido.isEmpty) {
          // Sem pedidos no período => sem novos clientes com faturamento
          alvoTotal = goal.target ?? 0.0;
          atingidoTotal = 0;
          progressoTotal = 0;
          restanteTotal = alvoTotal;
          faturamentoNovosClientes = 0;
          prodRows = [];
          pedidoRows = [];
        } else {
          // 2) Buscar clientes criados dentro da janela da meta
          final clientesSnap =
              await _fs
                  .collection('clientes')
                  .where('companyId', isEqualTo: _companyId)
                  .where('createdAt', isGreaterThanOrEqualTo: iniTs)
                  .where('createdAt', isLessThan: fimTs)
                  .get();

          final Set<String> novosClientesIds = {};
          for (final c in clientesSnap.docs) {
            if (clienteIdsComPedido.contains(c.id)) {
              novosClientesIds.add(c.id);
            }
          }

          final double alvo = goal.target ?? 0.0;
          final double qtdNovosClientes = novosClientesIds.length.toDouble();

          // 3) Faturamento apenas dos pedidos desses novos clientes
          double faturamento = 0.0;
          final rows = <_PedidoRow>[];

          for (final doc in pedidoDocs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final cid = (data['clienteId'] ?? data['cliente_id']) as String?;
            if (cid == null || !novosClientesIds.contains(cid)) continue;

            final clienteNome =
                (data['clienteNome'] ??
                        data['cliente_nome'] ??
                        data['cliente'] ??
                        data['nomeCliente'] ??
                        '—')
                    .toString();

            final numero =
                (data['numero'] ??
                        data['numeroPedido'] ??
                        data['numero_pedido'] ??
                        doc.id)
                    .toString();

            final ts = data['data'] as Timestamp?;
            final dataPedido = ts?.toDate();

            final status =
                (data['status'] ??
                        data['statusPedido'] ??
                        data['status_pedido'] ??
                        'Pendente')
                    .toString();

            final rawTotal = data['total'];
            double valor = 0.0;
            if (rawTotal is num) {
              valor = rawTotal.toDouble();
            } else if (rawTotal is String) {
              final cleaned =
                  rawTotal.replaceAll('.', '').replaceAll(',', '.').trim();
              valor = double.tryParse(cleaned) ?? 0.0;
            }

            faturamento += valor;

            rows.add(
              _PedidoRow(
                id: doc.id,
                clienteNome: clienteNome,
                numero: numero,
                total: valor,
                data: dataPedido,
                status: status,
              ),
            );
          }

          // Ordena por data desc, depois número
          rows.sort((a, b) {
            final da = a.data ?? DateTime.fromMillisecondsSinceEpoch(0);
            final db = b.data ?? DateTime.fromMillisecondsSinceEpoch(0);
            final cmp = db.compareTo(da);
            if (cmp != 0) return cmp;
            return a.numero.compareTo(b.numero);
          });

          final progresso =
              alvo > 0
                  ? ((qtdNovosClientes / alvo).clamp(0.0, 999.0) as num)
                      .toDouble()
                  : 0.0;
          final restante = max(alvo - qtdNovosClientes, 0.0);

          alvoTotal = alvo; // alvo em QUANTIDADE de clientes
          atingidoTotal = qtdNovosClientes; // nº de clientes novos
          progressoTotal = progresso;
          restanteTotal = restante;
          faturamentoNovosClientes = faturamento;
          pedidoRows = rows; // lista de pedidos dos novos clientes
          prodRows = [];
        }
      } else {
        throw Exception('KPI ainda não implementado para: ${goal.kpi}');
      }

      if (!mounted) return;
      setState(() {
        _prodRows = prodRows;
        _pedidoRows = pedidoRows;
        _alvoTotal = alvoTotal;
        _atingidoTotal = atingidoTotal;
        _progressoTotal = progressoTotal;
        _restanteTotal = restanteTotal;
        _faturamentoNovosClientes = faturamentoNovosClientes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataError = 'Erro ao calcular meta: $e';
        _prodRows = [];
        _pedidoRows = [];
        _alvoTotal = 0;
        _atingidoTotal = 0;
        _progressoTotal = 0;
        _restanteTotal = 0;
        _faturamentoNovosClientes = 0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard de Metas')),
      body:
          _loadingInit
              ? const Center(child: CircularProgressIndicator())
              : _initError != null
              ? Center(child: Text(_initError!))
              : Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMetaSelector(theme),
                    const SizedBox(height: 8),
                    _buildUserSelector(theme),
                    const SizedBox(height: 8),
                    Expanded(child: _buildContent(theme)),
                  ],
                ),
              ),
    );
  }

  Widget _buildMetaSelector(ThemeData theme) {
    return Row(
      children: [
        const Text('Meta:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<_Goal>(
            isExpanded: true,
            value: _selectedGoal,
            hint: const Text('Selecione uma meta'),
            items:
                _goals
                    .map(
                      (g) => DropdownMenuItem<_Goal>(
                        value: g,
                        child: Text(g.name),
                      ),
                    )
                    .toList(),
            onChanged: (g) async {
              if (g == null) return;
              setState(() => _selectedGoal = g);
              await _loadGoalData();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserSelector(ThemeData theme) {
    if (_loadingUsers) {
      return const Row(
        children: [
          Text('Usuário:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    }

    // Se não pode gerenciar metas -> só mostra o usuário logado
    if (!_canManageGoals) {
      _UserInfo? self;
      for (final u in _companyUsers) {
        if (u.authUid == _uid ||
            u.docId == _uid ||
            (u.legacyUserId != null && u.legacyUserId == _uid)) {
          self = u;
          break;
        }
      }

      self ??= _UserInfo(
        authUid: _uid ?? '',
        nome: 'Você',
        docId: _uid ?? '',
        legacyUserId: null,
      );

      final value = _selectedAuthUid ?? self.authUid;

      return Row(
        children: [
          const Text('Usuário:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: value,
              // apenas um item: o próprio usuário
              items: [
                DropdownMenuItem<String?>(
                  value: self.authUid,
                  child: Text(self.nome, overflow: TextOverflow.ellipsis),
                ),
              ],
              // Pode até deixar clicável, mas só tem ele mesmo
              onChanged: (v) async {
                // Garante que o filtro continua sendo o próprio usuário
                setState(() => _selectedAuthUid = self!.authUid);
                await _loadGoalData();
              },
            ),
          ),
        ],
      );
    }

    // Pode gerenciar metas -> vê todos e "Todos os usuários"
    return Row(
      children: [
        const Text('Usuário:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String?>(
            isExpanded: true,
            value: _selectedAuthUid,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Todos os usuários'),
              ),
              ..._companyUsers.map(
                (u) => DropdownMenuItem<String?>(
                  value: u.authUid,
                  child: Text(u.nome, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) async {
              setState(() => _selectedAuthUid = value);
              await _loadGoalData();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    final goal = _selectedGoal;
    if (goal == null) {
      return const Center(
        child: Text('Selecione uma meta para visualizar o dashboard.'),
      );
    }

    if (_loadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dataError != null) {
      return Center(child: Text(_dataError!));
    }

    final isPedidos = goal.kpi == 'pedidos';
    final isNovos = goal.kpi == 'novos_clientes_faturamento_qtd';

    if ((isPedidos || isNovos) && _pedidoRows.isEmpty) {
      return const Center(
        child: Text('Nenhum pedido encontrado para esta meta.'),
      );
    }

    if (!isPedidos && !isNovos && _prodRows.isEmpty) {
      return const Center(
        child: Text('Nenhum dado encontrado para esta meta.'),
      );
    }

    return Column(
      children: [
        _buildKpiCards(theme, goal),
        const SizedBox(height: 12),
        Expanded(
          child:
              (isPedidos || isNovos)
                  ? _buildPedidosListCard(theme)
                  : _buildProdutosListCard(theme),
        ),
      ],
    );
  }

  /// KPIs em cards 2 por linha
  Widget _buildKpiCards(ThemeData theme, _Goal goal) {
    String fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

    final isPedidos = goal.kpi == 'pedidos';
    final isNovos = goal.kpi == 'novos_clientes_faturamento_qtd';

    final List<_KpiInfo> items;

    if (isNovos) {
      // KPI de novos clientes: alvo e atingido em QUANTIDADE de clientes,
      // e um card separado de faturamento em R$.
      items = [
        _KpiInfo(
          label: 'Alvo (clientes)',
          value: fmt(_alvoTotal),
          icon: Icons.flag_outlined,
          color: Colors.blueGrey,
        ),
        _KpiInfo(
          label: 'Novos clientes',
          value: fmt(_atingidoTotal),
          icon: Icons.person_add_alt,
          color: Colors.green,
        ),
        _KpiInfo(
          label: 'Progresso',
          value: '${(_progressoTotal * 100).clamp(0, 999).toStringAsFixed(1)}%',
          icon: Icons.trending_up,
          color: Colors.orange,
        ),
        _KpiInfo(
          label: 'Faturamento (R\$)',
          value: _brl(_faturamentoNovosClientes),
          icon: Icons.attach_money,
          color: Colors.teal,
        ),
      ];
    } else {
      final labelAlvo = isPedidos ? 'Alvo (R\$)' : 'Alvo (Qtd)';
      final labelAtingido = isPedidos ? 'Atingido (R\$)' : 'Atingido (Qtd)';
      final labelRestante = isPedidos ? 'Restante (R\$)' : 'Restante (Qtd)';

      items = [
        _KpiInfo(
          label: labelAlvo,
          value: isPedidos ? _brl(_alvoTotal) : fmt(_alvoTotal),
          icon: Icons.flag_outlined,
          color: Colors.blueGrey,
        ),
        _KpiInfo(
          label: labelAtingido,
          value: isPedidos ? _brl(_atingidoTotal) : fmt(_atingidoTotal),
          icon: Icons.check_circle_outline,
          color: Colors.green,
        ),
        _KpiInfo(
          label: 'Progresso',
          value: '${(_progressoTotal * 100).clamp(0, 999).toStringAsFixed(1)}%',
          icon: Icons.trending_up,
          color: Colors.orange,
        ),
        _KpiInfo(
          label: labelRestante,
          value: isPedidos ? _brl(_restanteTotal) : fmt(_restanteTotal),
          icon: Icons.hourglass_bottom,
          color: Colors.redAccent,
        ),
      ];
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.5, // mais largo que alto
          children: items.map(_buildKpiCard).toList(),
        ),
      ),
    );
  }

  Widget _buildKpiCard(_KpiInfo info) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Icon(info.icon, size: 22, color: info.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  info.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ======= LISTA PARA KPI PRODUTOS/SERVIÇOS =======
  Widget _buildProdutosListCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView.separated(
          itemCount: _prodRows.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, index) {
            final r = _prodRows[index];
            final perc = r.progresso * 100;
            return ListTile(
              dense: true,
              title: Text(
                r.nome,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meta: ${r.metaQtd.toStringAsFixed(r.metaQtd % 1 == 0 ? 0 : 2)}  '
                    '• Vendido: ${r.vendidoQtd.toStringAsFixed(r.vendidoQtd % 1 == 0 ? 0 : 2)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: r.progresso.clamp(0.0, 1.0)),
                  const SizedBox(height: 2),
                  Text(
                    'Progresso: ${perc.clamp(0, 999).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ======= LISTA PARA KPI PEDIDOS / NOVOS CLIENTES =======
  Widget _buildPedidosListCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView.separated(
          itemCount: _pedidoRows.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, index) {
            final p = _pedidoRows[index];
            final dataStr = _fmtDate(p.data);
            final status = p.status.isEmpty ? '—' : p.status;

            return ListTile(
              dense: true,
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text(
                '${p.clienteNome} • ${_brl(p.total)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Nº ${p.numero} • $dataStr • $status',
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ====================== MODELOS AUXILIARES ======================

class _Goal {
  final String id;
  final String companyId;
  final String name;
  final String
  kpi; // 'produtos_servicos', 'pedidos', 'novos_clientes_faturamento_qtd'

  /// 'company' / 'users' (ou 'empresa' / 'usuario' para compatibilidade)
  final String scopeType;

  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// Itens para metas de produtos/serviços
  final List<_GoalItem> items;

  /// UIDs de usuários (Firebase Auth) vinculados à meta (para metas por usuário)
  final List<String> userIds;

  /// Meta em valor (para KPI = pedidos) ou em QTD (para novos clientes)
  final double? target;
  final String unit;

  _Goal({
    required this.id,
    required this.companyId,
    required this.name,
    required this.kpi,
    required this.scopeType,
    required this.periodStart,
    required this.periodEnd,
    required this.items,
    required this.userIds,
    required this.target,
    required this.unit,
  });

  factory _Goal.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Itens da meta (para produtos/serviços)
    final itemsRaw = data['itemsTargets'] ?? data['items'] ?? [];
    final itemsList =
        (itemsRaw as List<dynamic>? ?? [])
            .map((e) => _GoalItem.fromMap(e as Map<String, dynamic>? ?? {}))
            .where((i) => i.itemId != null)
            .toList();

    // Escopo (company / users) vindo de scope.level
    final scope = data['scope'] as Map<String, dynamic>? ?? {};
    final scopeLevelRaw =
        scope['level'] ?? scope['leval']; // trata typo "leval"
    final scopeType =
        (scopeLevelRaw ?? data['scopeType'] ?? data['escopo'] ?? 'company')
            .toString();

    // Lista de usuários da meta (scope.userIds, fallback userIds de topo)
    final scopeUserIdsRaw = scope['userIds'] ?? data['userIds'] ?? [];
    final userIds =
        (scopeUserIdsRaw as List<dynamic>? ?? []).map((e) => '$e').toList();

    // Meta em valor (para KPI pedidos) ou em quantidade (para novos clientes)
    final rawTarget = data['target'];
    double? target;
    if (rawTarget is num) {
      target = rawTarget.toDouble();
    } else if (rawTarget is String) {
      final cleaned = rawTarget.replaceAll('.', '').replaceAll(',', '.').trim();
      target = double.tryParse(cleaned);
    }

    final unit = (data['unit'] ?? '').toString();

    return _Goal(
      id: doc.id,
      companyId: (data['companyId'] ?? '') as String,
      name: (data['name'] ?? data['nome'] ?? doc.id) as String,
      kpi: (data['kpi'] ?? 'produtos_servicos') as String,
      scopeType: scopeType,
      periodStart: (data['periodStart'] as Timestamp?)?.toDate(),
      periodEnd: (data['periodEnd'] as Timestamp?)?.toDate(),
      items: itemsList,
      userIds: userIds,
      target: target,
      unit: unit,
    );
  }
}

class _GoalItem {
  final String? itemId;
  final String nome;
  final double quantidade;
  final String tipo; // produto/servico
  final String kpi;

  _GoalItem({
    required this.itemId,
    required this.nome,
    required this.quantidade,
    required this.tipo,
    required this.kpi,
  });

  factory _GoalItem.fromMap(Map<String, dynamic> map) {
    final qtdRaw = map['quantidade'] ?? map['qtd'] ?? 0;
    final qtd = (qtdRaw is num) ? qtdRaw.toDouble() : 0.0;

    return _GoalItem(
      itemId: (map['itemId'] ?? map['refId'] ?? map['id']) as String?,
      nome: (map['nome'] ?? map['name'] ?? '') as String,
      quantidade: qtd,
      tipo: (map['tipo'] ?? 'produto') as String,
      kpi: (map['kpi'] ?? 'produtos_servicos') as String,
    );
  }
}

class _UserInfo {
  final String authUid; // UID do Firebase Auth (createdByUid)
  final String nome;
  final String docId;
  final String? legacyUserId;

  _UserInfo({
    required this.authUid,
    required this.nome,
    required this.docId,
    this.legacyUserId,
  });
}

// Para KPI produtos/serviços
class _ProdRow {
  final String itemId;
  final String nome;
  final double metaQtd;
  final double vendidoQtd;

  _ProdRow({
    required this.itemId,
    required this.nome,
    required this.metaQtd,
    required this.vendidoQtd,
  });

  double get progresso =>
      metaQtd > 0
          ? ((vendidoQtd / metaQtd).clamp(0.0, 999.0) as num).toDouble()
          : 0.0;
}

// Para KPI pedidos / novos clientes
class _PedidoRow {
  final String id;
  final String clienteNome;
  final String numero;
  final double total;
  final DateTime? data;
  final String status;

  _PedidoRow({
    required this.id,
    required this.clienteNome,
    required this.numero,
    required this.total,
    required this.data,
    required this.status,
  });
}

class _KpiInfo {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  _KpiInfo({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

// ====================== HELPERS ======================

DateTime _at00(DateTime d) =>
    DateTime(d.year, d.month, d.day); // meia-noite "local"

String _fmtDate(DateTime? d) {
  if (d == null) return '--/--/----';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// Formata double em BRL básico, ex: 1500 -> "R$ 1.500,00"
String _brl(double v) {
  int cents = (v * 100).round();
  int absCents = cents.abs();
  int reais = absCents ~/ 100;
  int centavos = absCents % 100;

  String reaisStr = reais.toString();
  final sb = StringBuffer();
  for (int i = 0; i < reaisStr.length; i++) {
    final ch = reaisStr[i];
    int posFromEnd = reaisStr.length - i;
    sb.write(ch);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) {
      sb.write('.');
    }
  }
  final intFormatted = sb.toString();
  final centsStr = centavos.toString().padLeft(2, '0');
  final prefix = cents < 0 ? '-R\$ ' : 'R\$ ';
  return '$prefix$intFormatted,$centsStr';
}
