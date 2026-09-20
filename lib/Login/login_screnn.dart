// lib/auth/login_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'register_screen.dart';
import 'reset_password_screen.dart';
import '../Home/home_screen.dart';
import '../Planos/PlanService.dart';

class LoginColors {
  static const Color purple = Color(0xFF4A18B8);
  static const Color deepPurple = Color(0xFF2F148C);
  static const Color orange = Color(0xFFFF6A21);
  static const Color background = Color(0xFFF7F7FA);
  static const Color textDark = Color(0xFF1D1B20);
  static const Color textMuted = Color(0xFF6C6775);
  static const Color inputFill = Color(0xFFF8F5FF);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  static const String kFixedEmail = '';
  static const String kFixedPassword = '';

  static const Map<String, bool> _adminDefaultPermissions = {
    'canAccountsPayable': true,
    'canAccountsPayableCancel': true,
    'canAccountsReceivable': true,
    'canAdjustStock': true,
    'canManageProducts': true,
    'canManageServices': true,
    'canRegisterClientsSuppliers': true,
    'canRegisterOrders': true,
    'canAccountsPayableEditOpen': true,
    'canAccountsPayableMarkPaid': true,
    'canAccountsReceivableCancel': true,
    'canAccountsReceivableEditOpen': true,
    'canAccountsReceivableMarkPaid': true,
    'canDashboardFinance': true,
    'canDashboardOrdersByPeriod': true,
    'canDashboardPayables': true,
    'canDashboardReceivables': true,
    'canDashboardSales': true,
    'canDashboardTopProducts': true,
    'canDashboardTopServices': true,
    'canDashboardCashFlow': true,
    'canManagePaymentCategories': true,
    'canManageGoals': true,
    'canManagePurchases': true,
    'canManageCategories': true,
  };

  @override
  void initState() {
    super.initState();
    _email.text = kFixedEmail;
    _password.text = kFixedPassword;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _ensureSubscriptionDefaults(
    Map<String, dynamic> source,
    Map<String, dynamic> updates,
  ) {
    final planId = (source['planId'] ?? '').toString().trim();
    final planStatus = (source['planStatus'] ?? '').toString().trim();
    final billingCycle = (source['billingCycle'] ?? '').toString().trim();
    final subscriptionProvider =
        (source['subscriptionProvider'] ?? '').toString().trim();

    if (planId.isEmpty) updates['planId'] = 'free';
    if (planStatus.isEmpty) updates['planStatus'] = 'active';
    if (billingCycle.isEmpty) updates['billingCycle'] = 'monthly';

    if (!source.containsKey('planStartAt')) updates['planStartAt'] = null;
    if (!source.containsKey('planEndAt')) updates['planEndAt'] = null;
    if (!source.containsKey('trialStartAt')) updates['trialStartAt'] = null;
    if (!source.containsKey('trialEndAt')) updates['trialEndAt'] = null;

    if (subscriptionProvider.isEmpty) {
      updates['subscriptionProvider'] = 'manual';
    }

    if (!source.containsKey('subscriptionProductId')) {
      updates['subscriptionProductId'] = null;
    }

    if (!source.containsKey('purchaseToken')) {
      updates['purchaseToken'] = null;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _loadCurrentUserDoc() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return null;

    final fs = FirebaseFirestore.instance;

    try {
      final byUid = await fs.collection('users').doc(authUser.uid).get();
      if (byUid.exists) return byUid;
    } catch (_) {}

    final emailKey =
        (authUser.email ?? '')
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
            .trim()
            .toLowerCase();

    if (emailKey.isNotEmpty) {
      try {
        final q =
            await fs
                .collection('users')
                .where('emailKey', isEqualTo: emailKey)
                .limit(1)
                .get();

        if (q.docs.isNotEmpty) return q.docs.first;
      } catch (_) {}
    }

    return null;
  }

  Future<void> _enforceActiveOrSignOut() async {
    final snap = await _loadCurrentUserDoc();
    final data = snap?.data() ?? {};
    final isActive = (data['active'] ?? true) == true;

    if (!isActive) {
      await FirebaseAuth.instance.signOut();
      throw FirebaseAuthException(
        code: 'user-disabled',
        message: 'Usuário inativo.',
      );
    }
  }

  Future<void> _ensureUserDocIfMissing() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    final fs = FirebaseFirestore.instance;
    final uid = authUser.uid;
    final selfRef = fs.collection('users').doc(uid);
    final selfSnap = await selfRef.get();
    final now = FieldValue.serverTimestamp();

    if (selfSnap.exists) {
      final data = selfSnap.data() ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase();

      final Map<String, dynamic> updates = {};

      final existingAuthUid = (data['authUid'] ?? '').toString().trim();

      if (existingAuthUid.isEmpty || existingAuthUid != uid) {
        updates['authUid'] = uid;
      }

      _ensureSubscriptionDefaults(data, updates);

      if (role == 'admin') {
        final currentPerms = Map<String, dynamic>.from(
          data['permissions'] ?? {},
        );

        final updatedPerms = Map<String, dynamic>.from(currentPerms);
        bool changedPerms = false;

        _adminDefaultPermissions.forEach((k, v) {
          if (updatedPerms[k] != true) {
            updatedPerms[k] = true;
            changedPerms = true;
          }
        });

        if (changedPerms) updates['permissions'] = updatedPerms;
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = now;
        await selfRef.update(updates);
      }

      return;
    }

    final emailRaw = authUser.email ?? '';
    final emailKey =
        emailRaw
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
            .trim()
            .toLowerCase();

    if (emailKey.isNotEmpty) {
      QuerySnapshot<Map<String, dynamic>> q =
          await fs
              .collection('users')
              .where('emailKey', isEqualTo: emailKey)
              .limit(1)
              .get();

      if (q.docs.isEmpty) {
        q =
            await fs
                .collection('users')
                .where('email', isEqualTo: emailKey)
                .limit(1)
                .get();
      }

      if (q.docs.isNotEmpty) {
        final existingRef = q.docs.first.reference;
        final existingData = q.docs.first.data();
        final role = (existingData['role'] ?? '').toString().toLowerCase();

        final Map<String, dynamic> updates = {'authUid': uid, 'updatedAt': now};

        _ensureSubscriptionDefaults(existingData, updates);

        if (role == 'admin') {
          final currentPerms = Map<String, dynamic>.from(
            existingData['permissions'] ?? {},
          );

          final updatedPerms = Map<String, dynamic>.from(currentPerms);
          bool changedPerms = false;

          _adminDefaultPermissions.forEach((k, v) {
            if (updatedPerms[k] != true) {
              updatedPerms[k] = true;
              changedPerms = true;
            }
          });

          if (changedPerms) updates['permissions'] = updatedPerms;
        }

        await existingRef.set(updates, SetOptions(merge: true));
        return;
      }
    }

    await selfRef.set({
      'displayName': authUser.displayName ?? '',
      'email': emailKey.isEmpty ? (authUser.email ?? '') : emailKey,
      if (emailKey.isNotEmpty) 'emailKey': emailKey,
      'companyId': uid,
      'role': 'admin',
      'active': true,
      'permissions': _adminDefaultPermissions,
      'authUid': uid,
      'planId': 'free',
      'planStatus': 'active',
      'billingCycle': 'monthly',
      'planStartAt': null,
      'planEndAt': null,
      'trialStartAt': null,
      'trialEndAt': null,
      'subscriptionProvider': 'manual',
      'subscriptionProductId': null,
      'purchaseToken': null,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> _ensureSubscriptionIfMissing() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    final fs = FirebaseFirestore.instance;
    final uid = authUser.uid;

    final userDoc = await fs.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};

    String companyId = (userData['companyId'] ?? '').toString().trim();
    if (companyId.isEmpty) companyId = uid;

    final subRef = fs.collection('subscriptions').doc(companyId);
    final subDoc = await subRef.get();

    if (!subDoc.exists) {
      await subRef.set({
        'companyId': companyId,
        'planId': 'free',
        'status': 'active',
        'productId': null,
        'purchaseToken': null,
        'billingCycle': null,
        'trial': false,
        'startedAt': FieldValue.serverTimestamp(),
        'expiresAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _afterLogin() async {
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      await _ensureUserDocIfMissing();
      await _ensureSubscriptionIfMissing();
      await _enforceActiveOrSignOut();

      await PlanService.instance.load();

      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      _showSnack(_mapAuthError(e));
    } catch (_) {
      _showSnack('Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);

    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final gUser = await GoogleSignIn().signIn();

        if (gUser == null) {
          setState(() => _loading = false);
          return;
        }

        final gAuth = await gUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: gAuth.accessToken,
          idToken: gAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      await _ensureUserDocIfMissing();
      await _ensureSubscriptionIfMissing();
      await _enforceActiveOrSignOut();

      await PlanService.instance.load();

      await _afterLogin();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'popup-closed-by-user') _showSnack(_mapAuthError(e));
    } catch (e) {
      _showSnack('Falha no login Google. ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-mail inválido.';
      case 'user-disabled':
        return 'Usuário inativo. Contate o administrador.';
      case 'user-not-found':
      case 'wrong-password':
        return 'E-mail ou senha incorretos.';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente mais tarde.';
      case 'network-request-failed':
        return 'Sem conexão. Verifique sua internet.';
      default:
        return 'Falha ao entrar (${e.code}).';
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validateEmail(String? v) {
    final s = (v ?? '').trim();

    if (s.isEmpty) return 'Informe seu e-mail';

    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!re.hasMatch(s)) return 'E-mail inválido';

    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').isEmpty) return 'Informe sua senha';
    if ((v ?? '').length < 6) return 'Senha deve ter ao menos 6 caracteres';

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 720;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const _LoginGradientBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LoginHeader(compact: compact),
                        const SizedBox(height: 10),
                        _LoginCard(
                          formKey: _formKey,
                          emailController: _email,
                          passwordController: _password,
                          obscure: _obscure,
                          loading: _loading,
                          onTogglePassword: () {
                            setState(() => _obscure = !_obscure);
                          },
                          onSubmit: _signIn,
                          onGoogle: _signInWithGoogle,
                          onForgot: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ResetPasswordScreen(),
                              ),
                            );
                          },
                          onCreateAccount: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterScreen(),
                              ),
                            );
                          },
                          validateEmail: _validateEmail,
                          validatePassword: _validatePassword,
                        ),
                        SizedBox(height: compact ? 14 : 22),
                        const _TermsFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_loading)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    color: Colors.black.withOpacity(0.35),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoginGradientBackground extends StatelessWidget {
  const _LoginGradientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                LoginColors.deepPurple,
                LoginColors.purple,
                Color(0xFF7C24D6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -110,
          left: -90,
          child: _DecorativeCircle(size: 250, opacity: 0.14),
        ),
        Positioned(
          top: 210,
          right: -115,
          child: _DecorativeCircle(size: 230, opacity: 0.10, borderOnly: true),
        ),

        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: MediaQuery.sizeOf(context).height * 0.50,
            decoration: const BoxDecoration(
              color: LoginColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(42)),
            ),
          ),
        ),
      ],
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final double opacity;
  final bool borderOnly;

  const _DecorativeCircle({
    required this.size,
    required this.opacity,
    this.borderOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            borderOnly ? Colors.transparent : Colors.white.withOpacity(opacity),
        shape: BoxShape.circle,
        border:
            borderOnly
                ? Border.all(color: Colors.white.withOpacity(opacity), width: 2)
                : null,
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  final bool compact;

  const _LoginHeader({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 64 : 76,
          height: compact ? 64 : 76,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.shopping_bag_outlined,
            color: LoginColors.purple,
            size: 34,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'CRUD Negócios',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 21 : 24,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Bem-vindo 👋',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 21 : 24,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Acesse sua conta para continuar',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.88),
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscure;
  final bool loading;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onForgot;
  final VoidCallback onCreateAccount;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validatePassword;

  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscure,
    required this.loading,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onGoogle,
    required this.onForgot,
    required this.onCreateAccount,
    required this.validateEmail,
    required this.validatePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: LoginColors.purple.withOpacity(0.14),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            _LoginTextField(
              controller: emailController,
              hint: 'Seu e-mail',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
            ),
            const SizedBox(height: 12),
            _LoginTextField(
              controller: passwordController,
              hint: 'Sua senha',
              icon: Icons.lock_outline_rounded,
              obscureText: obscure,
              validator: validatePassword,
              suffixIcon: IconButton(
                onPressed: loading ? null : onTogglePassword,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: LoginColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _GradientButton(
              text: 'Entrar',
              loading: loading,
              onPressed: loading ? null : onSubmit,
            ),
            const SizedBox(height: 14),
            const _OrDivider(),
            const SizedBox(height: 12),
            _GoogleButton(
              loading: loading,
              onPressed: loading ? null : onGoogle,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: loading ? null : onForgot,
                child: const Text(
                  'Esqueci minha senha',
                  style: TextStyle(
                    color: LoginColors.purple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const Divider(height: 22),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: loading ? null : onCreateAccount,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text(
                  'Criar conta',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: LoginColors.purple,
                  side: const BorderSide(color: LoginColors.purple, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _LoginTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(
        color: LoginColors.textDark,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: LoginColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: LoginColors.purple),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: LoginColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: LoginColors.purple.withOpacity(0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: LoginColors.purple, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String text;
  final bool loading;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.text,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Ink(
          height: 50,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [
                LoginColors.purple,
                Color(0xFFD93E7E),
                LoginColors.orange,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: LoginColors.orange.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child:
                loading
                    ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onPressed;

  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: Image.network(
          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
          width: 22,
          height: 22,
          errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata),
        ),
        label: const Text(
          'Continuar com Google',
          style: TextStyle(
            color: LoginColors.textDark,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: LoginColors.purple.withOpacity(0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'ou',
            style: TextStyle(
              color: LoginColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}

class _TermsFooter extends StatelessWidget {
  const _TermsFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Icon(Icons.verified_user_outlined, color: LoginColors.purple, size: 26),
        SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: 'Ao continuar, você concorda com nossos ',
              children: [
                TextSpan(
                  text: 'Termos de Uso',
                  style: TextStyle(
                    color: LoginColors.purple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: ' e '),
                TextSpan(
                  text: 'Política de Privacidade.',
                  style: TextStyle(
                    color: LoginColors.purple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            style: TextStyle(
              color: LoginColors.textMuted,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
