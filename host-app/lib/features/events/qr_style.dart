import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/tokens.dart';

/// 4 пресета оформления QR. Хранятся локально в SharedPreferences
/// по ключу `qr_preset_{eventId}`. При null (не выбран) — classic.
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

Future<QrPreset> loadQrPreset(String eventId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_storageKey(eventId));
  if (raw == null) return QrPreset.classic;
  for (final p in QrPreset.values) {
    if (p.name == raw) return p;
  }
  return QrPreset.classic;
}

Future<void> saveQrPreset(String eventId, QrPreset preset) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey(eventId), preset.name);
}
