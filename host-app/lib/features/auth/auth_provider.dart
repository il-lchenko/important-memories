import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
import '../../core/push_service.dart';
import '../guest/guest_provider.dart' show getDeviceFingerprint;

part 'auth_provider.g.dart';

const _storage = FlutterSecureStorage();

final currentUserProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('users/me');
  return Map<String, dynamic>.from(resp.data as Map);
});

@riverpod
class Auth extends _$Auth {
  @override
  Future<bool> build() async {
    try {
      final token = await _storage.read(key: 'access_token');
      return token != null;
    } catch (_) {
      // Keystore недоступен (например, после апгрейда APK с другой подписью)
      try { await _storage.deleteAll(); } catch (_) {}
      return false;
    }
  }

  Future<void> requestCode(String email) async {
    final dio = ref.read(dioProvider);
    await dio.post('auth/email/request', data: {'email': email});
  }

  Future<void> verifyCode(String email, String code) async {
    final dio = ref.read(dioProvider);
    final fingerprint = await getDeviceFingerprint();
    final resp = await dio.post('auth/email/verify', data: {
      'email': email,
      'code': code,
      'fingerprint': fingerprint,
    });
    // Валидируем ответ — при частичном/пустом теле не даём приложению крашнуться.
    final data = resp.data;
    final access = (data is Map ? data['access_token'] : null) as String?;
    final refresh = (data is Map ? data['refresh_token'] : null) as String?;
    if (access == null || refresh == null || access.isEmpty || refresh.isEmpty) {
      throw StateError('Некорректный ответ сервера. Попробуйте ещё раз.');
    }
    await _storage.write(key: 'access_token',  value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_role', 'host');
    state = const AsyncData(true);
    // Регистрируем FCM-токен на бэкенде (fire-and-forget).
    unawaited(PushService.registerAfterLogin(ref.read(dioProvider)));
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AsyncData(false);
  }
}
