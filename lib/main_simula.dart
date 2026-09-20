import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options_simula.dart';
import 'Login/login_screnn.dart';
import 'home/alerts_controller.dart';
import 'services/user_context.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// Ative se for usar os emuladores
const bool _USE_EMULATORS = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔒 Inicializa Firebase apenas uma vez
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app(); // reaproveita
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // 🔌 Emuladores (se habilitado)
  if (_USE_EMULATORS) {
    await _connectToEmulators();
  }

  // 🛡️ App Check (apenas Web aqui; em Android/iOS, configure no Firebase Console)
  if (kIsWeb) {
    // ⬇️ Use a Site Key do projeto "SIMULA" no App Check (reCAPTCHA v3)
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider('SUA_SITE_KEY_DO_APP_CHECK'),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  }

  // ⚙️ Serviços que NÃO devem inicializar Firebase novamente
  UserContext.instance.initialize();
  AlertsController.instance.start();

  runApp(const MyApp());
}

Future<void> _connectToEmulators() async {
  // Ajuste host conforme o ambiente:
  // - Android Emulator: 10.0.2.2
  // - iOS Simulator: localhost
  // - Dispositivo físico: IP da sua máquina na rede local
  const host = 'localhost';
  const firestorePort = 8080;
  const authPort = 9099;
  const functionsPort = 5001;
  const storagePort = 9199;

  // Exemplos (descomente/importe os pacotes se for usar):
  //
  // import 'package:cloud_firestore/cloud_firestore.dart';
  // import 'package:firebase_auth/firebase_auth.dart';
  // import 'package:firebase_functions/firebase_functions.dart';
  // import 'package:firebase_storage/firebase_storage.dart';
  //
  // FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
  // await FirebaseAuth.instance.useAuthEmulator(host, authPort);
  // FirebaseFunctions.instance.useFunctionsEmulator(host, functionsPort);
  // FirebaseStorage.instance.useStorageEmulator(host, storagePort);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase + Flutter (Simula)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const LoginScreen(),
    );
  }
}
