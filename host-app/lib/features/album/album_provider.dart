import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';

final eventDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId');
  return Map<String, dynamic>.from(resp.data as Map);
});

final eventAlbumProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, eventId) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId/album');
  final data = resp.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['items'] as List);
});

/// Метаданные альбома: total_frames, revealed, is_admin_preview.
/// Используется для баннера «Альбом видите только вы» когда хост открывает альбом до reveal_at.
final eventAlbumMetaProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId/album');
  final data = Map<String, dynamic>.from(resp.data as Map);
  return {
    'revealed': data['revealed'] as bool? ?? false,
    'total_frames': data['total_frames'] as int? ?? 0,
    'is_admin_preview': data['is_admin_preview'] as bool? ?? false,
  };
});

// Returns full album response (items + total_frames) with limit=100 for progress screen
final eventProgressProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('events/$eventId/album', queryParameters: {'limit': 100});
  return Map<String, dynamic>.from(resp.data as Map);
});
