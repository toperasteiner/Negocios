import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../Home/home_screen.dart';
import 'login_screnn.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<bool> _isUserActive(User user) async {
    final fs = FirebaseFirestore.instance;

    // tenta por UID
    try {
      final byUid = await fs.collection('users').doc(user.uid).get();
      if (byUid.exists) {
        final data = byUid.data() ?? {};
        return (data['active'] ?? true) == true;
      }
    } catch (_) {}

    // tenta por emailKey
    final emailKey =
        (user.email ?? '')
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

        if (q.docs.isNotEmpty) {
          final data = q.docs.first.data();
          return (data['active'] ?? true) == true;
        }
      } catch (_) {}
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;

        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder<bool>(
          future: _isUserActive(user),
          builder: (context, activeSnap) {
            if (activeSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final isActive = activeSnap.data ?? true;

            if (!isActive) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await FirebaseAuth.instance.signOut();
              });

              return const Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Usuário inativo. Contate o administrador.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            return const HomeScreen();
          },
        );
      },
    );
  }
}
