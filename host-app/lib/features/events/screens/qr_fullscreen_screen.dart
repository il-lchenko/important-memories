import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';

class QrFullscreenScreen extends ConsumerWidget {
  final String eventId;
  const QrFullscreenScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));
    final title = eventAsync.maybeWhen(
      data: (e) => (e['title'] ?? e['name'] ?? 'Событие') as String,
      orElse: () => '',
    );
    final shortCode = eventAsync.maybeWhen(
      data: (e) => e['short_code'] as String? ?? eventId,
      orElse: () => eventId,
    );
    const guestBase = String.fromEnvironment(
      'GUEST_PWA_URL',
      defaultValue: 'https://impomento.pro',
    );
    final joinUrlFull = '$guestBase/g/$shortCode';
    final joinUrl = joinUrlFull.replaceFirst(RegExp(r'https?://'), '');

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(
          children: [
            // Top nav
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.close, color: AppColors.drText, size: 24),
                  ),
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      letterSpacing: 0.16,
                      color: AppColors.drAmber,
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),

            // Core content
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                      fontWeight: FontWeight.w500,
                      fontSize: 28,
                      letterSpacing: -0.01 * 28,
                      height: 1.1,
                      color: AppColors.drText,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR code
                  Container(
                    width: 280,
                    height: 280,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40FFB347),
                          blurRadius: 60,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: joinUrlFull,
                      version: QrVersions.auto,
                      backgroundColor: AppColors.paper,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.ink,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // URL pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x14FFB347),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x33FFB347)),
                    ),
                    child: Text(
                      joinUrl,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 14,
                        letterSpacing: 0.04,
                        color: AppColors.drAmber,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Hint
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Отправьте QR-код или ссылку гостям.\nОткрыв страницу, они смогут сразу начать съёмку',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Color(0x8CF0E6D2),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              child: Row(
                children: [
                  Expanded(
                    child: _DarkButton(
                      icon: Icons.copy_outlined,
                      label: 'Скопировать',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: 'https://$joinUrl'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ссылка скопирована')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DarkButton(
                      icon: Icons.share_outlined,
                      label: 'Поделиться',
                      onTap: () => Share.share(
                        'Присоединяйся к «$title»!\n$joinUrlFull',
                        subject: title,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DarkButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0x14FFB347),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x33FFB347)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.drAmber, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.drAmber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

