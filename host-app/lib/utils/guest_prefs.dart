import 'package:shared_preferences/shared_preferences.dart';

/// Хранилище гость-сессий в SharedPreferences с разделением по event_id.
///
/// До рефакторинга ключи были общие (`guest_token`, `guest_event_id`, ...),
/// поэтому при переключении между двумя событиями (например, хост открывает
/// свой альбом B, будучи гостем события A) данные одного затирали данные
/// другого. Теперь токен/счётчик/lut пишутся под суффиксом event_id, а общий
/// указатель `current_guest_event_id` помнит, какое событие активно сейчас
/// (для splash-роутинга и pre-fill в sign/caption/voice экранах).
class GuestPrefs {
  GuestPrefs._();

  static const _kCurrentEventId = 'current_guest_event_id';

  // Backward-compat — старые ключи. Читаем, чтобы поднять прежнюю гость-сессию
  // после обновления APK. Не пишем.
  static const _kLegacyToken = 'guest_token';
  static const _kLegacyEventId = 'guest_event_id';
  static const _kLegacyFrames = 'guest_frames_remaining';
  static const _kLegacyLut = 'guest_lut_preset';

  static String _tokenKey(String eventId) => 'gs_token_$eventId';
  static String _framesKey(String eventId) => 'gs_frames_$eventId';
  static String _lutKey(String eventId) => 'gs_lut_$eventId';

  /// Текущая активная гость-сессия (для splash и для sign-флоу).
  static Future<String?> currentEventId() async {
    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getString(_kCurrentEventId);
    if (cur != null && cur.isNotEmpty) return cur;
    // Fallback: старый общий ключ (для прежних установок APK).
    final legacy = prefs.getString(_kLegacyEventId);
    return (legacy != null && legacy.isNotEmpty) ? legacy : null;
  }

  /// Сохранить только что созданную/полученную гость-сессию для конкретного
  /// события и сделать её активной.
  static Future<void> saveSession({
    required String eventId,
    required String token,
    required int framesRemaining,
    String? lutPreset,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey(eventId), token);
    await prefs.setInt(_framesKey(eventId), framesRemaining);
    if (lutPreset != null) {
      await prefs.setString(_lutKey(eventId), lutPreset);
    }
    await prefs.setString(_kCurrentEventId, eventId);
  }

  /// Прочитать X-Guest-Token для конкретного события. Если по новому ключу
  /// нет — fallback на легаси-ключ, но только если он принадлежит этому
  /// событию.
  static Future<String> tokenFor(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey(eventId));
    if (t != null && t.isNotEmpty) return t;
    final legacyEvent = prefs.getString(_kLegacyEventId) ?? '';
    if (legacyEvent == eventId) {
      return prefs.getString(_kLegacyToken) ?? '';
    }
    return '';
  }

  /// Остаток кадров для события (или 0, если сессии нет).
  static Future<int> framesRemainingFor(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_framesKey(eventId));
    if (v != null) return v;
    final legacyEvent = prefs.getString(_kLegacyEventId) ?? '';
    if (legacyEvent == eventId) {
      return prefs.getInt(_kLegacyFrames) ?? 0;
    }
    return 0;
  }

  /// Установить остаток кадров после съёмки.
  static Future<void> setFramesRemainingFor(String eventId, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_framesKey(eventId), value);
  }

  /// LUT-пресет, выбранный хостом для события.
  static Future<String> lutPresetFor(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_lutKey(eventId));
    if (v != null && v.isNotEmpty) return v;
    final legacyEvent = prefs.getString(_kLegacyEventId) ?? '';
    if (legacyEvent == eventId) {
      return prefs.getString(_kLegacyLut) ?? 'original';
    }
    return 'original';
  }

  /// Полный выход из гость-режима — стирает все per-event записи и текущий
  /// указатель. Не трогает device_fingerprint и selected_role.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList(growable: false);
    for (final k in keys) {
      if (k.startsWith('gs_token_') ||
          k.startsWith('gs_frames_') ||
          k.startsWith('gs_lut_')) {
        await prefs.remove(k);
      }
    }
    await prefs.remove(_kCurrentEventId);
    // Старые ключи тоже на всякий
    await prefs.remove(_kLegacyToken);
    await prefs.remove(_kLegacyEventId);
    await prefs.remove(_kLegacyFrames);
    await prefs.remove(_kLegacyLut);
  }
}
