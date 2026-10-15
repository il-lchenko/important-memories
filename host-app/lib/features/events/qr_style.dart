import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/tokens.dart';

/// 4 пресета оформления QR. Хранятся на сервере в `settings.qr_style`.
/// При null (не выбран) — classic.
enum QrPreset { classic, dark, warm, mono }

class QrPresetStyle {
  final String label;
  final Color canvas;     // Внутренний фон QR (bg модулей)
  final Color modules;    // Цвет модулей и глаз
  final Color container;  // Фон обёртки-контейнера (визуальная рамка)
  final Color glow;       // Цвет soft-glow тени за контейнером
  final Color subtitle;   // Цвет "классика"/"тёмная"/... в picker
  final bool darkBg;      // Для контрастного шрифта в preview

  const QrPresetStyle({
    required this.label,
    required this.canvas,
    required this.modules,
    required this.container,
    required this.glow,
    required this.subtitle,
    required this.darkBg,
  });
}

const Map<QrPreset, QrPresetStyle> kQrPresets = {
  QrPreset.classic: QrPresetStyle(
    label: 'Классика',
    canvas: AppColors.paper,
    modules: AppColors.ink,
    container: AppColors.paper,
    glow: Color(0x40FFB347),
    subtitle: AppColors.ink3,
    darkBg: false,
  ),
  QrPreset.dark: QrPresetStyle(
    label: 'Тёмная',
    canvas: AppColors.dark2,
    modules: AppColors.drAmber,
    container: AppColors.dark2,
    glow: Color(0x33FFB347),
    subtitle: AppColors.drAmber,
    darkBg: true,
  ),
  QrPreset.warm: QrPresetStyle(
    label: 'Тёплая',
    canvas: Color(0xFFF3E3C8),
    modules: AppColors.ink,
    container: Color(0xFFF3E3C8),
    glow: Color(0x55C9881E),
    subtitle: AppColors.amber2,
    darkBg: false,
  ),
  QrPreset.mono: QrPresetStyle(
    label: 'Моно',
    canvas: Colors.white,
    modules: Colors.black,
    container: Colors.white,
    glow: Color(0x1A000000),
    subtitle: AppColors.ink3,
    darkBg: false,
  ),
};

String _storageKey(String eventId) => 'qr_preset_$eventId';

QrPreset parseQrPreset(String? raw) {
  for (final p in QrPreset.values) {
    if (p.name == raw) return p;
  }
  return QrPreset.classic;
}

/// [serverValue] — `settings.qr_style` события. Если на сервере пусто, а в
/// SharedPreferences осталось значение от старой версии — выгружаем его один раз.
Future<QrPreset> loadQrPreset(Dio dio, String eventId, {String? serverValue}) async {
  if (serverValue != null) return parseQrPreset(serverValue);
  final prefs = await SharedPreferences.getInstance();
  final local = prefs.getString(_storageKey(eventId));
  if (local == null) return QrPreset.classic;
  try {
    await dio.patch('events/$eventId/settings', data: {'qr_style': local});
    await prefs.remove(_storageKey(eventId));
  } catch (_) {}
  return parseQrPreset(local);
}

Future<void> saveQrPreset(Dio dio, String eventId, QrPreset preset) async {
  await dio.patch('events/$eventId/settings', data: {'qr_style': preset.name});
}
