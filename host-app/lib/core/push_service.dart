// Заглушка PushService — реальная FCM-интеграция закомментирована,
// т.к. pub.dev с российских IP возвращает 403 для firebase_core/firebase_messaging.
// Как только пакеты станут доступны (VPN, зеркало pub-cache), раскомментировать
// секцию FCM в pubspec.yaml и заменить методы этого файла реальной реализацией
// из git history (см. коммит с меткой «FCM Flutter integration»).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

class PushService {
  static Future<void> initApp() async {
    debugPrint('[PushService] disabled (pubDev 403, see push_service.dart)');
  }

  static Future<void> registerAfterLogin(Dio dio) async {
    // no-op пока Firebase Messaging не подключен
  }

  static Future<void> attachHandlers(GoRouter router) async {
    // no-op
  }
}
