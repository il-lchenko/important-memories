import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';

final eventDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  ref.keepAlive();
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId');
  return Map<String, dynamic>.from(resp.data as Map);
});

final eventAlbumProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  ref.keepAlive();
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId/album');
  final data = resp.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['items'] as List);
});

final eventAlbumMetaProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  ref.keepAlive();
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId/album');
  final data = Map<String, dynamic>.from(resp.data as Map);
  return {
    'revealed': data['revealed'] as bool? ?? false,
    'total_frames': data['total_frames'] as int? ?? 0,
    'is_admin_preview': data['is_admin_preview'] as bool? ?? false,
  };
});

final eventProgressProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  ref.keepAlive();
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId/album', queryParameters: {'limit': 100});
  return Map<String, dynamic>.from(resp.data as Map);
});
