import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/tokens.dart';

/// Выбор, что создать: событие с гостями, соло-альбом или подборку (мини-альбом).
Future<void> showNewAlbumSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.paper3, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Новый альбом',
              style: GoogleFonts.playfairDisplay(
                fontFeatures: [const FontFeature.liningFigures()],
                fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            _Choice(
              icon: Icons.groups_outlined,
              title: 'Событие с гостями',
              text: 'Свадьба, день рождения, корпоратив. Гости снимают по QR-коду.',
              onTap: () { Navigator.of(ctx).pop(); context.push('/events/create'); },
            ),
            _Choice(
              icon: Icons.photo_camera_outlined,
              title: 'Соло-альбом',
              text: 'Личный альбом без гостей: путешествие, отпуск, дневник.',
              onTap: () { Navigator.of(ctx).pop(); context.push('/solo/create'); },
            ),
            _Choice(
              icon: Icons.auto_awesome_mosaic_outlined,
              title: 'Мини-альбом',
              text: 'Подборка лучших кадров из ваших альбомов, без копий файлов.',
              onTap: () { Navigator.of(ctx).pop(); context.push('/collections/create'); },
            ),
          ],
        ),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  const _Choice({required this.icon, required this.title, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.amber, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.playfairDisplay(
                          fontFeatures: [const FontFeature.liningFigures()],
                          fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink,
                        )),
                    const SizedBox(height: 3),
                    Text(text,
                        style: GoogleFonts.manrope(fontSize: 13, height: 1.4, color: AppColors.ink3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
