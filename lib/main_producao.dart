import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'Login/login_screnn.dart';
import 'home/alerts_controller.dart';
import 'services/user_context.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'Login/auth_gate.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'Catalogo/CatalogoPublicoScreen.dart';
import 'Agenda/PaginaAgendamentoPublica.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

final FacebookAppEvents facebookAppEvents = FacebookAppEvents();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Firebase apenas uma vez (evita [core/duplicate-app])
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app(); // reaproveita a instância existente
    }
  } on FirebaseException catch (e) {
    // Se ocorrer corrida e vier duplicate-app, apenas ignora;
    // outros erros, propaga.
    if (e.code != 'duplicate-app') rethrow;
  }

  // 🌎 Intl / locale pt_BR
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR', null);

  if (kDebugMode) {
    final opts = DefaultFirebaseOptions.currentPlatform;

    debugPrint('🔥 Firebase connected: projectId=${opts.projectId}');

    debugPrint('🔥 appId=${opts.appId}');
  }

  UserContext.instance.initialize();
  AlertsController.instance.start();

  await FirebaseAnalytics.instance;

  /* ==========================================================
     ROTAS PÚBLICAS WEB
     ========================================================== */

  if (kIsWeb) {
    final uri = Uri.base;

    final pathSegments =
        uri.pathSegments.where((segment) => segment.trim().isNotEmpty).toList();

    if (kDebugMode) {
      debugPrint('🌐 URL: ${uri.toString()}');
      debugPrint('🌐 Path: ${uri.path}');
      debugPrint('🌐 Segmentos: $pathSegments');
    }

    /* ========================================================
       AGENDA PÚBLICA

       Exemplo:
       /agendar/barbearia-do-joao
       ======================================================== */

    if (pathSegments.length >= 2 &&
        pathSegments.first.toLowerCase() == 'agendar') {
      final slugAgenda = pathSegments[1].trim().toLowerCase();

      if (slugAgenda.isNotEmpty) {
        runApp(AppPublico(child: PaginaAgendamentoPublica(slug: slugAgenda)));

        return;
      }
    }

    /* ========================================================
       CATÁLOGO PÚBLICO

       Mantém exatamente a estrutura atual.

       Exemplo:
       /minha-loja
       ======================================================== */

    if (pathSegments.isNotEmpty) {
      final slugCatalogo = pathSegments.first.trim();

      if (slugCatalogo.isNotEmpty) {
        runApp(
          AppPublico(child: CatalogoPublicoScreen(slugCatalogo: slugCatalogo)),
        );

        return;
      }
    }
  }

  /* ==========================================================
     APLICATIVO NORMAL
     ========================================================== */

  runApp(const MyApp());
}

/* ============================================================
   MATERIAL APP DAS PÁGINAS PÚBLICAS

   Usado tanto pelo catálogo quanto pela Agenda Online.
   ============================================================ */

class AppPublico extends StatelessWidget {
  final Widget child;

  const AppPublico({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),

      locale: const Locale('pt', 'BR'),

      supportedLocales: const [Locale('pt', 'BR')],

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: child,
    );
  }
}

/* ============================================================
   APLICATIVO NORMAL
   ============================================================ */

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase + Flutter',

      debugShowCheckedModeBanner: false,

      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),

      // 🌎 Configuração de localização para pt-BR
      locale: const Locale('pt', 'BR'),

      supportedLocales: const [Locale('pt', 'BR')],

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const AuthGate(),
    );
  }
}
