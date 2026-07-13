import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/tokens.dart';

class SignChoiceScreen extends StatelessWidget {
  final String frameId;
  const SignChoiceScreen({super.key, required this.frameId});

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    final extra = state.extra is Map ? state.extra as Map : const {};
    final photoBytes = extra['photoBytes'] as Uint8List?;
    final ratio = (extra['ratio'] as num?)?.toDouble() ?? 3 / 4;
    final frameNum = extra['frameNum'] as int? ?? 0;
    final guestName = extra['guestName'] as String? ?? 'Гость';

    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;

    // Photo gets as much space as possible above the fixed bottom content
    final screenW = MediaQuery.of(context).size.width;
    final photoSectionH = (screenH * 0.38).clamp(170.0, 360.0);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Padding(
        padding: EdgeInsets.only(top: topPad, bottom: botPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _RoundIconBtn(icon: Icons.arrow_back, onTap: () => context.pop()),
                  const Spacer(),
                  Text(
                    'КАДР ${frameNum.toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, letterSpacing: 1.4, color: AppColors.ink3,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Photo (fixed height, polaroid centered) ─────────────────
            SizedBox(
              height: photoSectionH,
              width: double.infinity,
              child: Center(
                child: _Polaroid(
                  photoBytes: photoBytes,
                  ratio: ratio,
                  guestName: guestName,
                  maxHeight: photoSectionH,
                  maxWidth: screenW - 48,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Title ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Как подписать кадр?',
                style: GoogleFonts.fraunces(
                  fontWeight: FontWeight.w500,
                  fontSize: 22,
                  height: 1.15,
                  color: AppColors.ink,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Choice cards ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ChoiceCard(
                      icon: Icons.edit_outlined,
                      title: 'Текстом',
                      subtitle: 'до 120 символов',
                      onTap: () async {
                        await context.push(
                          '/guest/caption/$frameId',
                          extra: {
                            'photoBytes': photoBytes,
                            'ratio': ratio,
                            'frameNum': frameNum,
                            'guestName': guestName,
                          },
                        );
                        if (context.mounted) context.pop();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChoiceCard(
                      icon: Icons.mic_outlined,
                      title: 'Голосом',
                      subtitle: 'до 20 секунд',
                      onTap: () async {
                        await context.push(
                          '/guest/voice/$frameId',
                          extra: {
                            'photoBytes': photoBytes,
                            'ratio': ratio,
                            'frameNum': frameNum,
                            'guestName': guestName,
                          },
                        );
                        if (context.mounted) context.pop();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Skip ───────────────────────────────────────────────────
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.paper3,
                    foregroundColor: AppColors.ink2,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Пропустить',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Polaroid — максимально большое, не нарушая ни maxHeight ни maxWidth
// ─────────────────────────────────────────────────────────────────────────────
class _Polaroid extends StatelessWidget {
  final Uint8List? photoBytes;
  final double ratio;
  final String guestName;
  final double maxHeight;
  final double maxWidth;

  const _Polaroid({
    required this.photoBytes,
    required this.ratio,
    required this.guestName,
    required this.maxHeight,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    const hPad = 10.0;
    const vPad = 10.0;
    const nameH = 30.0;
    const botPad2 = 4.0;

    // Вычислить imgH из ограничения по высоте
    double imgH = (maxHeight - vPad - nameH - botPad2).clamp(1.0, double.infinity);
    double imgW = imgH * ratio;
    // Если ширина превышает maxWidth — пересчитать по ширине
    final maxImgW = maxWidth - hPad * 2;
    if (imgW > maxImgW) {
      imgW = maxImgW;
      imgH = (imgW / ratio).clamp(1.0, double.infinity);
    }

    return Container(
      width: imgW + hPad * 2,
      padding: const EdgeInsets.fromLTRB(hPad, vPad, hPad, botPad2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: imgW,
            height: imgH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: photoBytes != null
                  ? Image.memory(photoBytes!, fit: BoxFit.cover)
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFD4A574), Color(0xFF5A3E2E)],
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(
            height: nameH,
            child: Center(
              child: Text(
                guestName,
                style: GoogleFonts.caveat(fontSize: 17, color: AppColors.ink2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Round icon button
// ─────────────────────────────────────────────────────────────────────────────
class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x0F000000),
        ),
        child: Icon(icon, size: 16, color: AppColors.ink2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact choice card
// ─────────────────────────────────────────────────────────────────────────────
class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x1FC9881E),
                ),
                child: Icon(icon, size: 22, color: AppColors.amber),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  height: 1.3,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
