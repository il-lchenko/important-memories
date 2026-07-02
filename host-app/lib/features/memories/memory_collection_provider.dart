import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';

/// Fetches frames from multiple events and merges into one list
/// sorted by captured_at desc. Used by MemoryCollectionScreen.
///
/// Key: comma-joined event UUIDs (Riverpod family requires a single hashable arg).
final memoryCollectionProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, key) async {
  final dio = ref.watch(dioProvider);
  final ids = key.split(',').where((s) => s.isNotEmpty).toList();
  if (ids.isEmpty) return [];

  final results = await Future.wait(
    ids.map((id) => dio.get('events/$id/album', queryParameters: {'limit': 100})),
  );

  final all = <Map<String, dynamic>>[];
  for (final resp in results) {
    final data = resp.data as Map<String, dynamic>;
    final items = List<Map<String, dynamic>>.from(data['items'] as List);
    for (final f in items) {
      // event_id needed to open frame_detail_screen
      f['event_id'] ??= _findEventIdFromRequest(resp.requestOptions.path);
    }
    all.addAll(items);
  }

  // Sort by captured_at desc (fallback: created_at)
  all.sort((a, b) {
    final ac = (a['captured_at'] ?? a['created_at']) as String? ?? '';
    final bc = (b['captured_at'] ?? b['created_at']) as String? ?? '';
    return bc.compareTo(ac);
  });
  return all;
});

String? _findEventIdFromRequest(String path) {
  final m = RegExp(r'events/([0-9a-f-]+)/album').firstMatch(path);
  return m?.group(1);
}
