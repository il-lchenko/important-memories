import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/api_client.dart';

part 'events_provider.g.dart';

/// Список событий, на которые пользователь был приглашён как гость.
final invitedEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/invited');
  return List<Map<String, dynamic>>.from(resp.data as List);
});

@riverpod
Future<List<Map<String, dynamic>>> events(Ref ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/');
  return List<Map<String, dynamic>>.from(resp.data as List);
}

@riverpod
Future<Map<String, dynamic>> createEvent(Ref ref, Map<String, dynamic> data) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.post('events/', data: {
    'name': data['name'],
    'event_type': data['event_type'],
    'frames_per_guest': data['frames_per_guest'],
    'reveal_mode': data['reveal_mode'],
    if (data['reveal_at'] != null) 'reveal_at': data['reveal_at'],
    if (data['start_at'] != null) 'start_at': data['start_at'],
    'film': data['film'],
    'plan': data['plan'],
    if (data['storage_extension'] != null) 'storage_extension': data['storage_extension'],
  });
  return Map<String, dynamic>.from(resp.data as Map);
}
