import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
import '../../utils/guest_prefs.dart';

final guestEventPreviewProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, code) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('guest/events/$code');
  return Map<String, dynamic>.from(resp.data as Map);
});

/// GET /guest/sessions/me — текущая сессия анонимного гостя.
final guestSessionProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final eventId = await GuestPrefs.currentEventId();
  if (eventId == null) throw Exception('No active guest event');
  final token = await GuestPrefs.tokenFor(eventId);
  if (token.isEmpty) throw Exception('No guest token');
  final dio = ref.watch(dioProvider);
  final resp = await dio.get(
    'guest/sessions/me',
    options: Options(headers: {'X-Guest-Token': token}),
  );
  return Map<String, dynamic>.from(resp.data as Map);
});

Future<String> getDeviceFingerprint() async {
  final prefs = await SharedPreferences.getInstance();
  var fp = prefs.getString('device_fingerprint');
  if (fp == null) {
    final rand = Random.secure();
    final bytes = List.generate(16, (_) => rand.nextInt(256));
    fp = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString('device_fingerprint', fp);
  }
  return fp;
}
