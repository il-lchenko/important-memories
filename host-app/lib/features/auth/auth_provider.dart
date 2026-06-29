import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
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
    final token = await _storage.read(key: 'access_token');
    return token != null;
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
    await _storage.write(key: 'access_token',  value: resp.data['access_token']  as String);
    await _storage.write(key: 'refresh_token', value: resp.data['refresh_token'] as String);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_role', 'host');
    state = const AsyncData(true);
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AsyncData(false);
  }
}
