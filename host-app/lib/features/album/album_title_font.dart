import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/tokens.dart';

/// 4 пресета шрифта для title альбома. Применяется в hero-заголовке
/// `album_screen` (hero-title). Хранится локально по `title_font_{eventId}`.
enum TitleFont { playfair, fraunces, caveat, manrope }

class TitleFontStyle {
  final String label;
  final String preview;
  final TextStyle Function(double fontSize) build;

  const TitleFontStyle({
    required this.label,
    required this.preview,
    required this.build,
  });
}

final Map<TitleFont, TitleFontStyle> kTitleFonts = {
  TitleFont.playfair: TitleFontStyle(
    label: 'Playfair',
    preview: 'Aa',
    build: (size) => GoogleFonts.playfairDisplay(
      fontFeatures: const [FontFeature.liningFigures()],
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.1,
      color: AppColors.ink,
    ),
  ),
  TitleFont.fraunces: TitleFontStyle(
    label: 'Fraunces',
    preview: 'Aa',
    build: (size) => GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.6,
      height: 1.05,
      color: AppColors.ink,
    ),
  ),
  TitleFont.caveat: TitleFontStyle(
    label: 'Caveat',
    preview: 'Aa',
    build: (size) => GoogleFonts.caveat(
      fontSize: size + 10, // Caveat визуально мельче — компенсируем
      fontWeight: FontWeight.w600,
      height: 1.0,
      color: AppColors.ink,
    ),
  ),
  TitleFont.manrope: TitleFontStyle(
    label: 'Manrope',
    preview: 'Aa',
    build: (size) => GoogleFonts.manrope(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.1,
      color: AppColors.ink,
    ),
  ),
};

String _storageKey(String eventId) => 'title_font_$eventId';

Future<TitleFont> loadTitleFont(String eventId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_storageKey(eventId));
  if (raw == null) return TitleFont.playfair;
  for (final f in TitleFont.values) {
    if (f.name == raw) return f;
  }
  return TitleFont.playfair;
}

Future<void> saveTitleFont(String eventId, TitleFont font) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey(eventId), font.name);
}

/// Bottom sheet picker. Возвращает выбранный TitleFont или null (отмена).
Future<TitleFont?> showTitleFontPicker(
  BuildContext context, {
  required TitleFont current,
  required String sampleText,
}) {
  return showModalBottomSheet<TitleFont>(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20, 18, 20,
        24 + MediaQuery.of(ctx).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Шрифт заголовка',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: const Icon(Icons.close, size: 22, color: AppColors.ink3),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...TitleFont.values.map((font) {
            final style = kTitleFonts[font]!;
            final isSelected = font == current;
            return GestureDetector(
              onTap: () => Navigator.of(ctx).pop(font),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0x14C9881E)
                      : AppColors.paper2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.amber : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            sampleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.build(24),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            style.label.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Inter', fontSize: 10,
                              letterSpacing: 1.4,
                              color: isSelected ? AppColors.amber : AppColors.ink3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, color: AppColors.amber, size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}
