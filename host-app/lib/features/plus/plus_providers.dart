import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Лимиты и права пользователя с сервера: соло, подборки, подписка «Плюс».
final entitlementsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resp = await ref.watch(dioProvider).get('me/entitlements');
  return Map<String, dynamic>.from(resp.data as Map);
});

/// Состояние подписки «Плюс» (GET /me/subscription).
final subscriptionProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resp = await ref.watch(dioProvider).get('me/subscription');
  return Map<String, dynamic>.from(resp.data as Map);
});

/// Каталог цен и состава подписки (GET /pricing → plus).
final plusPricingProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resp = await ref.watch(dioProvider).get('pricing');
  final data = Map<String, dynamic>.from(resp.data as Map);
  return Map<String, dynamic>.from((data['plus'] as Map?) ?? const {});
});

/// Мои мини-альбомы (подборки).
final collectionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resp = await ref.watch(dioProvider).get('collections/');
  return Map<String, dynamic>.from(resp.data as Map);
});

/// Одна подборка с кадрами.
final collectionProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final resp = await ref.watch(dioProvider).get('collections/$id');
  return Map<String, dynamic>.from(resp.data as Map);
});

/// Кадры одного альбома для выбора в подборку (первая страница, до 100).
final albumFramesProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) async {
  final resp = await ref.watch(dioProvider).get(
    'events/$eventId/album',
    queryParameters: {'limit': 100},
  );
  return Map<String, dynamic>.from(resp.data as Map);
});

/// Платные стили (доп. QR и шрифты) закрыты, пока подписка запущена и её нет.
bool stylesLocked(Map<String, dynamic>? entitlements) {
  if (entitlements == null) return false;
  final enabled = entitlements['subscription_enabled'] == true;
  final plus = entitlements['plus'] == true;
  return enabled && !plus;
}
