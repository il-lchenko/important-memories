import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';

/// Ленту раздела «Кадры» — блоки с типами: tilted, collage_a..e, grid_6.
final memoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('memories/');
  final data = resp.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['blocks'] as List);
});
