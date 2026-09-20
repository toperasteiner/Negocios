// lib/UsuarioFormScreen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // para Clipboard

class UsuarioFormScreen extends StatefulWidget {
  final String? userDocId;
  final Map<String, dynamic>? initialData;

  const UsuarioFormScreen({super.key, this.userDocId, this.initialData});

  @override
  State<UsuarioFormScreen> createState() => _UsuarioFormScreenState();
}

class _UsuarioFormScreenState extends State<UsuarioFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _nomeFocus = FocusNode();
  final _emailFocus = FocusNode();

  bool _salvando = false;
  bool _carregandoEdicao = false;
  bool _dirty = false; // <- houve alteração no formulário?

  bool get _isEditing => widget.userDocId != null;

  String? _companyIdDoRegistro;

  // ===== Permissões =====
  // Cadastros
  bool _pCadClientesFornecedores = false;
  bool _pCadProdutos = false;
  bool _pCadServicos = false;
  bool _pCadCategoriasPagamento = false; // acesso a categorias de pagamento
  bool _pCadMetas = false; // 👈 NOVO: Metas (acesso/cadastro)
  bool _pCadCompras = false;
  bool _pCadCategoria = false;

  // Atividades
  bool _pCadPedidos = false;
  bool _pAlterarEstoque = false;

  // Financeiro
  bool _pContasPagar = false;
  bool _pContasReceber = false;

  // 🔐 Subpermissões de Contas a Pagar
  bool _pCP_EditarAberto = false; // canAccountsPayableEditOpen
  bool _pCP_MarcarPago = false; // canAccountsPayableMarkPaid
  bool _pCP_CancelarTitulo = false; // canAccountsPayableCancel

  // 🔐 Subpermissões de Contas a Receber
  bool _pCR_EditarAberto = false; // canAccountsReceivableEditOpen
  bool _pCR_MarcarPago = false; // canAccountsReceivableMarkPaid
  bool _pCR_CancelarTitulo = false; // canAccountsReceivableCancel

  // Dashboards
  bool _pDash_CP = false; // canDashboardPayables
  bool _pDash_CR = false; // canDashboardReceivables
  bool _pDash_Financeiro = false; // canDashboardFinance
  bool _pDash_PedidosPeriodo = false; // canDashboardOrdersByPeriod
  bool _pDash_TopProdutos = false; // canDashboardTopProducts
  bool _pDash_TopServicos = false; // canDashboardTopServices
  bool _pDash_Vendas = false; // canDashboardSales
  bool _pDash_Fluxo = false; // canDashboardCashFlow

  // Status do usuário
  bool _ativo = true;

  @override
  void initState() {
    super.initState();
    _nomeCtrl.addListener(() => setState(() => _dirty = true));
    _emailCtrl.addListener(() => setState(() => _dirty = true));
    _initFromEditIfNeeded();
  }

  void _setAllPerms(bool on) {
    setState(() {
      // Cadastros
      _pCadClientesFornecedores = on;
      _pCadProdutos = on;
      _pCadServicos = on;
      _pCadCategoriasPagamento = on;
      _pCadMetas = on; // 👈 NOVO
      _pCadCompras = on;
      _pCadCategoria = on;

      // Atividades
      _pCadPedidos = on;
      _pAlterarEstoque = on;

      // Financeiro — Pagar
      _pContasPagar = on;
      _pCP_EditarAberto = on && _pContasPagar;
      _pCP_MarcarPago = on && _pContasPagar;
      _pCP_CancelarTitulo = on && _pContasPagar;

      // Financeiro — Receber
      _pContasReceber = on;
      _pCR_EditarAberto = on && _pContasReceber;
      _pCR_MarcarPago = on && _pContasReceber;
      _pCR_CancelarTitulo = on && _pContasReceber;

      // Dashboards
      _pDash_Fluxo = on;
      _pDash_Vendas = on;
      _pDash_CP = on;
      _pDash_CR = on;
      _pDash_Financeiro = on;
      _pDash_PedidosPeriodo = on;
      _pDash_TopProdutos = on;
      _pDash_TopServicos = on;

      _dirty = true;
    });
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _nomeFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _initFromEditIfNeeded() async {
    if (!_isEditing) return;

    final d = widget.initialData;
    if (d != null) {
      _hydrate(d);
      return;
    }

    setState(() => _carregandoEdicao = true);
    try {
      final fs = FirebaseFirestore.instance;
      final snap = await fs.collection('users').doc(widget.userDocId).get();
      final data = snap.data();
      if (data != null) {
        _hydrate(data);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usuário não encontrado.')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e, st) {
      debugPrint('[UsuarioForm] erro ao carregar edição: $e');
      debugPrint('[UsuarioForm] stack: $st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar usuário: $e')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _carregandoEdicao = false);
    }
  }

  void _hydrate(Map<String, dynamic> d) {
    debugPrint('[UsuarioForm] editando doc=${widget.userDocId}');

    _nomeCtrl.text = (d['displayName'] ?? '').toString();
    _emailCtrl.text = (d['email'] ?? '').toString();
    _ativo = (d['active'] ?? true) == true;

    _companyIdDoRegistro = (d['companyId'] ?? '').toString();

    final perms = (d['permissions'] ?? {}) as Map<String, dynamic>;
    bool p(String k) => (perms[k] ?? false) == true;

    // Cadastros / Atividades / Financeiro
    _pCadClientesFornecedores = p('canRegisterClientsSuppliers');
    _pCadProdutos = p('canManageProducts');
    _pCadServicos = p('canManageServices');
    _pCadCategoriasPagamento = p('canManagePaymentCategories');
    _pCadMetas = p('canManageGoals'); // 👈 NOVO
    _pCadCompras = p('canManagePurchases');
    _pCadCategoria = p('canManageCategories'); // 👈 NOVO
    _pCadPedidos = p('canRegisterOrders');
    _pAlterarEstoque = p('canAdjustStock');
    _pContasPagar = p('canAccountsPayable');
    _pContasReceber = p('canAccountsReceivable');

    // CP
    _pCP_EditarAberto = p('canAccountsPayableEditOpen');
    _pCP_MarcarPago = p('canAccountsPayableMarkPaid');
    _pCP_CancelarTitulo = p('canAccountsPayableCancel');

    // CR
    _pCR_EditarAberto = p('canAccountsReceivableEditOpen');
    _pCR_MarcarPago = p('canAccountsReceivableMarkPaid');
    _pCR_CancelarTitulo = p('canAccountsReceivableCancel');

    // Dashboards
    _pDash_CP = p('canDashboardPayables');
    _pDash_CR = p('canDashboardReceivables');
    _pDash_Financeiro = p('canDashboardFinance');
    _pDash_PedidosPeriodo = p('canDashboardOrdersByPeriod');
    _pDash_TopProdutos = p('canDashboardTopProducts');
    _pDash_TopServicos = p('canDashboardTopServices');
    _pDash_Vendas = p('canDashboardSales');
    _pDash_Fluxo = p('canDashboardCashFlow');

    setState(() {});
  }

  String? _validaNome(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o nome';
    if (s.length < 2) return 'Nome muito curto';
    return null;
  }

  String? _validaEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Informe o e-mail';
    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!re.hasMatch(s)) return 'E-mail inválido';
    return null;
  }

  Future<String?> _descobrirMeuCompanyId(User user) async {
    final fs = FirebaseFirestore.instance;
    try {
      final byUid = await fs.collection('users').doc(user.uid).get();
      if (byUid.exists) {
        final data = byUid.data();
        final cid = data?['companyId'] as String?;
        if (cid != null && cid.isNotEmpty) return cid;
      }
    } catch (_) {}

    final emailKey = (user.email ?? '').trim().toLowerCase();
    if (emailKey.isNotEmpty) {
      final q =
          await fs
              .collection('users')
              .where('emailKey', isEqualTo: emailKey)
              .limit(1)
              .get();
      if (q.docs.isNotEmpty) {
        final cid = q.docs.first.data()['companyId'] as String?;
        if (cid != null && cid.isNotEmpty) return cid;
      }
    }
    return null;
  }

  Map<String, dynamic> _buildPermissions() {
    return {
      // Cadastros / Atividades / Financeiro
      'canRegisterClientsSuppliers': _pCadClientesFornecedores,
      'canManageProducts': _pCadProdutos,
      'canManageServices': _pCadServicos,
      'canManagePaymentCategories': _pCadCategoriasPagamento,
      'canManageGoals': _pCadMetas,
      'canManagePurchases': _pCadCompras, // 👈 NOVO
      'canManageCategories': _pCadCategoria, // 👈 NOVO
      'canRegisterOrders': _pCadPedidos,
      'canAdjustStock': _pAlterarEstoque,
      'canAccountsPayable': _pContasPagar,
      'canAccountsReceivable': _pContasReceber,

      // CP subperms
      'canAccountsPayableEditOpen': _pContasPagar && _pCP_EditarAberto,
      'canAccountsPayableMarkPaid': _pContasPagar && _pCP_MarcarPago,
      'canAccountsPayableCancel': _pContasPagar && _pCP_CancelarTitulo,

      // CR subperms
      'canAccountsReceivableEditOpen': _pContasReceber && _pCR_EditarAberto,
      'canAccountsReceivableMarkPaid': _pContasReceber && _pCR_MarcarPago,
      'canAccountsReceivableCancel': _pContasReceber && _pCR_CancelarTitulo,

      // Dashboards
      'canDashboardPayables': _pDash_CP,
      'canDashboardReceivables': _pDash_CR,
      'canDashboardFinance': _pDash_Financeiro,
      'canDashboardOrdersByPeriod': _pDash_PedidosPeriodo,
      'canDashboardTopProducts': _pDash_TopProdutos,
      'canDashboardTopServices': _pDash_TopServicos,
      'canDashboardSales': _pDash_Vendas,
      'canDashboardCashFlow': _pDash_Fluxo,
    };
  }

  Future<void> _mostrarOrientacoesPosCadastro({
    required String email,
    String? nome,
  }) async {
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.mark_email_read_rounded, color: Color(0xFF5B21B6)),
                SizedBox(width: 8),
                Text('Orientações para o usuário'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((nome ?? '').isNotEmpty)
                  Text(
                    'Usuário: $nome',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'E-mail: $email',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B21B6),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '1) O usuário deve baixar o app em seu dispositivo.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 6),
                const Text(
                  '2) Ao abrir o app, ele deve se cadastrar usando exatamente o e-mail informado acima.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 6),
                const Text(
                  '3) Após o cadastro, o acesso será vinculado à sua empresa e as permissões concedidas aqui serão aplicadas.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dica: copie o e-mail para compartilhar com o funcionário.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: email));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('E-mail copiado.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar e-mail'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5B21B6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
    );
  }

  Future<bool> _emailJaExiste(String emailLower) async {
    try {
      final fs = FirebaseFirestore.instance;
      final q =
          await fs
              .collection('users')
              .where('emailKey', isEqualTo: emailLower)
              .limit(1)
              .get();
      return q.docs.isNotEmpty;
    } catch (e) {
      debugPrint('[UsuarioForm] erro ao checar duplicidade: $e');
      return true; // conservador
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {}); // força mensagem de erro nos campos
      return;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Faça login para salvar.')));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _salvando = true);

    try {
      final fs = FirebaseFirestore.instance;
      final companyId =
          _isEditing
              ? (_companyIdDoRegistro ?? await _descobrirMeuCompanyId(authUser))
              : await _descobrirMeuCompanyId(authUser);

      if (companyId == null || companyId.isEmpty) {
        throw 'Não foi possível determinar o companyId do usuário logado.';
      }

      final email = _emailCtrl.text.trim();
      final emailKey = email.toLowerCase();
      final displayName = _nomeCtrl.text.trim();

      if (!_isEditing) {
        final existe = await _emailJaExiste(emailKey);
        if (existe) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('E-mail já cadastrado. Escolha outro.'),
            ),
          );
          setState(() => _salvando = false);
          return;
        }
      }

      final data = <String, dynamic>{
        'active': _ativo,
        'companyId': companyId,
        'displayName': displayName,
        'email': email,
        'emailKey': emailKey,
        'permissions': _buildPermissions(),
        'role': (widget.initialData?['role'] ?? 'funcionario').toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      bool created;

      if (_isEditing) {
        final ref = fs.collection('users').doc(widget.userDocId);
        await ref.update(data);
        created = false;
      } else {
        final toCreate = {...data, 'createdAt': FieldValue.serverTimestamp()};
        await fs.collection('users').add(toCreate);
        created = true;
      }

      if (!mounted) return;
      _dirty = false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(created ? 'Usuário criado.' : 'Usuário atualizado.'),
        ),
      );

      if (created) {
        await _mostrarOrientacoesPosCadastro(email: email, nome: displayName);
      }

      Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('[UsuarioForm][_salvar] ERRO: $e');
      debugPrint('[UsuarioForm][_salvar] STACK: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar usuário: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<bool> _confirmarSaidaSeAlterado() async {
    if (!_dirty || _salvando) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
                SizedBox(width: 8),
                Text('Descartar alterações?'),
              ],
            ),
            content: const Text(
              'Você fez alterações que ainda não foram salvas. Deseja realmente descartá-las?',
              style: TextStyle(color: Color(0xFF475569)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continuar editando'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar'),
              ),
            ],
          ),
    );
    return ok == true;
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF3B0CA3), // primaryDark
            Color(0xFF5B21B6), // primary
            Color(0xFFF97316), // orange
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: () async {
                        final ok = await _confirmarSaidaSeAlterado();
                        if (ok && mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      tooltip: 'Voltar',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Editar Usuário' : 'Adicionar Usuário',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Gerencie dados de acesso e permissões',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      tooltip: 'Salvar',
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
              if (_dirty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Você tem alterações não salvas',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _salvando
                      ? null
                      : () async {
                          final ok = await _confirmarSaidaSeAlterado();
                          if (ok && mounted) Navigator.pop(context);
                        },
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
                    'Descartar',
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
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _isEditing ? 'Atualizar' : 'Salvar',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final headerChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _ativo
            ? const Color(0xFF10B981).withValues(alpha: 0.12)
            : const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _ativo
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _ativo ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: _ativo ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            _ativo ? 'Ativo' : 'Inativo',
            style: TextStyle(
              color: _ativo ? const Color(0xFF047857) : const Color(0xFFB91C1C),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !_dirty || _salvando,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _confirmarSaidaSeAlterado();
        if (ok && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: _carregandoEdicao
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF5B21B6)),
              )
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ===== Dados Básicos =====
                          _SectionCard(
                            title: 'Dados do Usuário',
                            icon: Icons.person_rounded,
                            iconColor: const Color(0xFF5B21B6),
                            trailing: headerChip,
                            child: Form(
                              key: _formKey,
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              child: Column(
                                children: [
                                  _input(
                                    controller: _nomeCtrl,
                                    label: 'Nome completo *',
                                    validator: _validaNome,
                                    prefix: const Icon(Icons.person_outline),
                                    focusNode: _nomeFocus,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                                  ),
                                  const SizedBox(height: 12),
                                  _input(
                                    controller: _emailCtrl,
                                    label: 'E-mail de acesso *',
                                    keyboardType: TextInputType.emailAddress,
                                    validator: _validaEmail,
                                    prefix: const Icon(Icons.alternate_email),
                                    readOnly: _isEditing,
                                    helperText: _isEditing
                                        ? 'O e-mail é chave de login e não pode ser alterado.'
                                        : 'Use o e-mail que o usuário utilizará para login.',
                                    focusNode: _emailFocus,
                                    textInputAction: TextInputAction.done,
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: SwitchListTile.adaptive(
                                      value: _ativo,
                                      activeTrackColor: const Color(0xFF5B21B6),
                                      onChanged: (v) {
                                        setState(() {
                                          _ativo = v;
                                          _dirty = true;
                                        });
                                      },
                                      title: const Text(
                                        'Usuário Ativo',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      subtitle: const Text(
                                        'Quando inativo, o usuário é bloqueado no sistema.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ===== Ações Globais de Permissões =====
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.done_all_rounded, size: 18),
                                    label: const Text(
                                      'Ativar tudo',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF5B21B6),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      minimumSize: const Size.fromHeight(46),
                                    ),
                                    onPressed: () => _setAllPerms(true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                                    label: const Text(
                                      'Desativar tudo',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF475569),
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      minimumSize: const Size.fromHeight(46),
                                    ),
                                    onPressed: () => _setAllPerms(false),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ===== Permissões =====
                          _PermGroupCard(
                            icon: Icons.app_registration_rounded,
                            iconColor: const Color(0xFF3B82F6),
                            title: 'Cadastros',
                            items: [
                              _PermItem(
                                label: 'Cadastrar clientes/fornecedores',
                                value: _pCadClientesFornecedores,
                                onChanged: (v) => setState(() {
                                  _pCadClientesFornecedores = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Cadastrar produtos',
                                value: _pCadProdutos,
                                onChanged: (v) => setState(() {
                                  _pCadProdutos = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Cadastrar serviços',
                                value: _pCadServicos,
                                onChanged: (v) => setState(() {
                                  _pCadServicos = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Categorias de pagamento (acesso)',
                                value: _pCadCategoriasPagamento,
                                onChanged: (v) => setState(() {
                                  _pCadCategoriasPagamento = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Metas (acesso/cadastro)',
                                value: _pCadMetas,
                                onChanged: (v) => setState(() {
                                  _pCadMetas = v;
                                  _dirty = true;
                                }),
                                info: 'Permite acessar e gerenciar as metas (MetasHome/Cadastro).',
                              ),
                              _PermItem(
                                label: 'Compras (acesso/cadastro)',
                                value: _pCadCompras,
                                onChanged: (v) => setState(() {
                                  _pCadCompras = v;
                                  _dirty = true;
                                }),
                                info: 'Permite acessar e gerenciar compras.',
                              ),
                              _PermItem(
                                label: 'Categoria de Produtos (acesso/cadastro)',
                                value: _pCadCategoria,
                                onChanged: (v) => setState(() {
                                  _pCadCategoria = v;
                                  _dirty = true;
                                }),
                                info: 'Permite acessar e gerenciar categorias de produtos.',
                              ),
                            ],
                            onSelectAll: () => setState(() {
                              _pCadClientesFornecedores = true;
                              _pCadProdutos = true;
                              _pCadServicos = true;
                              _pCadCategoriasPagamento = true;
                              _pCadMetas = true;
                              _pCadCompras = true;
                              _pCadCategoria = true;
                              _dirty = true;
                            }),
                            onClearAll: () => setState(() {
                              _pCadClientesFornecedores = false;
                              _pCadProdutos = false;
                              _pCadServicos = false;
                              _pCadCategoriasPagamento = false;
                              _pCadMetas = false;
                              _pCadCompras = false;
                              _pCadCategoria = false;
                              _dirty = true;
                            }),
                          ),

                          const SizedBox(height: 12),

                          _PermGroupCard(
                            icon: Icons.task_alt_rounded,
                            iconColor: const Color(0xFF10B981),
                            title: 'Atividades',
                            items: [
                              _PermItem(
                                label: 'Cadastrar pedidos',
                                value: _pCadPedidos,
                                onChanged: (v) => setState(() {
                                  _pCadPedidos = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Alterar estoque',
                                value: _pAlterarEstoque,
                                onChanged: (v) => setState(() {
                                  _pAlterarEstoque = v;
                                  _dirty = true;
                                }),
                              ),
                            ],
                            onSelectAll: () => setState(() {
                              _pCadPedidos = true;
                              _pAlterarEstoque = true;
                              _dirty = true;
                            }),
                            onClearAll: () => setState(() {
                              _pCadPedidos = false;
                              _pAlterarEstoque = false;
                              _dirty = true;
                            }),
                          ),

                          const SizedBox(height: 12),

                          // ===== Financeiro — Contas a Pagar =====
                          _PermGroupCard(
                            icon: Icons.arrow_upward_rounded,
                            iconColor: const Color(0xFFEF4444),
                            title: 'Financeiro — Contas a Pagar',
                            items: [
                              _PermItem(
                                label: 'Contas a pagar (acesso)',
                                value: _pContasPagar,
                                info: 'Controla acesso à tela de Contas a Pagar',
                                onChanged: (v) => setState(() {
                                  _pContasPagar = v;
                                  if (!v) {
                                    _pCP_EditarAberto = false;
                                    _pCP_MarcarPago = false;
                                    _pCP_CancelarTitulo = false;
                                  }
                                  _dirty = true;
                                }),
                              ),
                            ],
                            childrenWhenOn: _pContasPagar
                                ? [
                                    _PermItem(
                                      label: 'Editar valor/vencimento',
                                      info: 'Permite ajustar valor e vencimento de títulos em aberto',
                                      value: _pCP_EditarAberto,
                                      isChild: true,
                                      onChanged: (v) => setState(() {
                                        _pCP_EditarAberto = v;
                                        _dirty = true;
                                      }),
                                    ),
                                    _PermItem(
                                      label: 'Marcar como Pago',
                                      info: 'Permite registrar pagamento do título',
                                      value: _pCP_MarcarPago,
                                      isChild: true,
                                      onChanged: (v) => setState(() {
                                        _pCP_MarcarPago = v;
                                        _dirty = true;
                                      }),
                                    ),
                                    _PermItem(
                                      label: 'Cancelar Título',
                                      info: 'Permite marcar um título como cancelado',
                                      value: _pCP_CancelarTitulo,
                                      isChild: true,
                                      onChanged: (v) => setState(() {
                                        _pCP_CancelarTitulo = v;
                                        _dirty = true;
                                      }),
                                    ),
                                  ]
                                : null,
                            onSelectAll: () => setState(() {
                              _pContasPagar = true;
                              _pCP_EditarAberto = true;
                              _pCP_MarcarPago = true;
                              _pCP_CancelarTitulo = true;
                              _dirty = true;
                            }),
                            onClearAll: () => setState(() {
                              _pCP_EditarAberto = false;
                              _pCP_MarcarPago = false;
                              _pCP_CancelarTitulo = false;
                              _pContasPagar = false;
                              _dirty = true;
                            }),
                          ),

                          const SizedBox(height: 12),

                          // ===== Financeiro — Contas a Receber =====
                          _PermGroupCard(
                            icon: Icons.arrow_downward_rounded,
                            iconColor: const Color(0xFF059669),
                            title: 'Financeiro — Contas a Receber',
                            items: [
                              _PermItem(
                                label: 'Contas a receber (acesso)',
                                value: _pContasReceber,
                                info: 'Controla acesso à tela de Contas a Receber',
                                onChanged: (v) => setState(() {
                                  _pContasReceber = v;
                                  if (!v) {
                                    _pCR_EditarAberto = false;
                                    _pCR_MarcarPago = false;
                                    _pCR_CancelarTitulo = false;
                                  }
                                  _dirty = true;
                                }),
                              ),
                            ],
                            childrenWhenOn: _pContasReceber
                                ? [
                                    _PermItem(
                                      label: 'Editar valor/vencimento',
                                      info: 'Permite ajustar valor e vencimento de títulos em aberto',
                                      value: _pCR_EditarAberto,
                                      isChild: true,
                                      onChanged: (v) => setState(() {
                                        _pCR_EditarAberto = v;
                                        _dirty = true;
                                      }),
                                    ),
                                    _PermItem(
                                      label: 'Marcar como Pago',
                                      info: 'Permite registrar pagamento do título',
                                      value: _pCR_MarcarPago,
                                      isChild: true,
                                      onChanged: (v) => setState(() {
                                        _pCR_MarcarPago = v;
                                        _dirty = true;
                                      }),
                                    ),
                                    _PermItem(
                                      label: 'Cancelar Título',
                                      info: 'Permite marcar um título como cancelado',
                                      value: _pCR_CancelarTitulo,
                                      isChild: true,
                                      onChanged: (v) => setState(() {
                                        _pCR_CancelarTitulo = v;
                                        _dirty = true;
                                      }),
                                    ),
                                  ]
                                : null,
                            onSelectAll: () => setState(() {
                              _pContasReceber = true;
                              _pCR_EditarAberto = true;
                              _pCR_MarcarPago = true;
                              _pCR_CancelarTitulo = true;
                              _dirty = true;
                            }),
                            onClearAll: () => setState(() {
                              _pCR_EditarAberto = false;
                              _pCR_MarcarPago = false;
                              _pCR_CancelarTitulo = false;
                              _pContasReceber = false;
                              _dirty = true;
                            }),
                          ),

                          const SizedBox(height: 12),

                          // ===== Dashboards =====
                          _PermGroupCard(
                            icon: Icons.insights_rounded,
                            iconColor: const Color(0xFF8B5CF6),
                            title: 'Dashboards',
                            items: [
                              _PermItem(
                                label: 'Fluxo (Pagar/Receber)',
                                value: _pDash_Fluxo,
                                onChanged: (v) => setState(() {
                                  _pDash_Fluxo = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Vendas',
                                value: _pDash_Vendas,
                                onChanged: (v) => setState(() {
                                  _pDash_Vendas = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Contas a pagar',
                                value: _pDash_CP,
                                onChanged: (v) => setState(() {
                                  _pDash_CP = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Contas a receber',
                                value: _pDash_CR,
                                onChanged: (v) => setState(() {
                                  _pDash_CR = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Financeiro',
                                value: _pDash_Financeiro,
                                onChanged: (v) => setState(() {
                                  _pDash_Financeiro = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Pedidos por período',
                                value: _pDash_PedidosPeriodo,
                                onChanged: (v) => setState(() {
                                  _pDash_PedidosPeriodo = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Top produtos',
                                value: _pDash_TopProdutos,
                                onChanged: (v) => setState(() {
                                  _pDash_TopProdutos = v;
                                  _dirty = true;
                                }),
                              ),
                              _PermItem(
                                label: 'Top serviços',
                                value: _pDash_TopServicos,
                                onChanged: (v) => setState(() {
                                  _pDash_TopServicos = v;
                                  _dirty = true;
                                }),
                              ),
                            ],
                            onSelectAll: () => setState(() {
                              _pDash_Fluxo = true;
                              _pDash_Vendas = true;
                              _pDash_CP = true;
                              _pDash_CR = true;
                              _pDash_Financeiro = true;
                              _pDash_PedidosPeriodo = true;
                              _pDash_TopProdutos = true;
                              _pDash_TopServicos = true;
                              _dirty = true;
                            }),
                            onClearAll: () => setState(() {
                              _pDash_Fluxo = false;
                              _pDash_Vendas = false;
                              _pDash_CP = false;
                              _pDash_CR = false;
                              _pDash_Financeiro = false;
                              _pDash_PedidosPeriodo = false;
                              _pDash_TopProdutos = false;
                              _pDash_TopServicos = false;
                              _dirty = true;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  // ---- widgets auxiliares ----

  Widget _input({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? prefix,
    bool readOnly = false,
    String? helperText,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      keyboardType: keyboardType,
      readOnly: readOnly,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(
        fontSize: 14,
        color: readOnly ? const Color(0xFF64748B) : const Color(0xFF1E293B),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        helperText: helperText,
        helperMaxLines: 2,
        helperStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
          borderSide: const BorderSide(color: Color(0xFF5B21B6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        isDense: true,
        filled: true,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        prefixIcon: prefix != null
            ? IconTheme(
                data: const IconThemeData(color: Color(0xFF64748B), size: 20),
                child: prefix,
              )
            : null,
        suffixIcon: controller.text.isEmpty || readOnly
            ? null
            : IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                onPressed: () {
                  controller.clear();
                  setState(() => _dirty = true);
                },
              ),
      ),
      onChanged: (_) => setState(() => _dirty = true),
    );
  }
}

/// Card de seção genérica com título e trailing opcional
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;
  final Color? iconColor;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (iconColor ?? const Color(0xFF5B21B6)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor ?? const Color(0xFF5B21B6), size: 18),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Item de perm com switch e tooltip opcional
class _PermItem extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? info;
  final bool isChild;

  const _PermItem({
    required this.label,
    required this.value,
    required this.onChanged,
    this.info,
    this.isChild = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: isChild ? 16 : 0, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isChild ? const Color(0xFFF8FAFC) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isChild ? Border.all(color: const Color(0xFFE2E8F0)) : null,
      ),
      child: Row(
        children: [
          if (isChild) ...[
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isChild ? FontWeight.w500 : FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          if (info != null)
            Tooltip(
              message: info!,
              triggerMode: TooltipTriggerMode.tap,
              child: const Padding(
                padding: EdgeInsets.only(left: 6, right: 4),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          Switch.adaptive(
            value: value,
            activeTrackColor: const Color(0xFF5B21B6),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Card de grupo de permissões com ExpansionTile, contador e ações "ativar tudo"/"limpar"
class _PermGroupCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<_PermItem> items;
  final List<_PermItem>? childrenWhenOn;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClearAll;

  const _PermGroupCard({
    required this.icon,
    this.iconColor = const Color(0xFF5B21B6),
    required this.title,
    required this.items,
    this.childrenWhenOn,
    this.onSelectAll,
    this.onClearAll,
  });

  @override
  State<_PermGroupCard> createState() => _PermGroupCardState();
}

class _PermGroupCardState extends State<_PermGroupCard> {
  int _countOn() {
    int c = 0;
    for (final it in widget.items) {
      if (it.value) c++;
    }
    if (widget.childrenWhenOn != null) {
      for (final it in widget.childrenWhenOn!) {
        if (it.value) c++;
      }
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final total =
        (widget.childrenWhenOn == null)
            ? widget.items.length
            : widget.items.length + widget.childrenWhenOn!.length;
    final ativos = _countOn();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, color: widget.iconColor, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ativos > 0
                      ? const Color(0xFF5B21B6).withValues(alpha: 0.1)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$ativos / $total',
                  style: TextStyle(
                    color: ativos > 0
                        ? const Color(0xFF5B21B6)
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          children: [
            // Ações rápidas
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  if (widget.onSelectAll != null)
                    TextButton.icon(
                      onPressed: widget.onSelectAll,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF5B21B6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text(
                        'Ativar tudo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (widget.onClearAll != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: widget.onClearAll,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      icon: const Icon(Icons.clear_all_rounded, size: 16),
                      label: const Text(
                        'Desativar tudo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 6),
            ...widget.items,
            if (widget.childrenWhenOn != null)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(children: widget.childrenWhenOn!),
                crossFadeState:
                    _hasParentOn(widget.items)
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasParentOn(List<_PermItem> items) {
    return items.isNotEmpty && items.first.value == true;
  }
}
