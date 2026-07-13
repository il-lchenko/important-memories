// Placeholder — заменить через FlutterFire CLI:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=impomento-XXXX
// Пока значения-заглушки, Firebase.initializeApp() бросит исключение — это ок,
// pushService ловит его в try-catch и просто не активирует FCM-фичу.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey: 'REPLACE_ME',
        appId: 'REPLACE_ME',
        messagingSenderId: 'REPLACE_ME',
        projectId: 'REPLACE_ME',
      );
}
