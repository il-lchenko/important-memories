import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';

class SignChoiceScreen extends StatefulWidget {
  final String frameId;
  const SignChoiceScreen({super.key, required this.frameId});

  @override
  State<SignChoiceScreen> createState() => _SignChoiceScreenState();
}

class _SignChoiceScreenState extends State<SignChoiceScreen> {
  String _eventId = '';

  @override
  void initState() {
    super.initState();
    GuestPrefs.currentEventId().then((id) {
      if (mounted) setState(() => _eventId = id ?? '');
    });
  }

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

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Padding(
        padding: EdgeInsets.only(top: topPad, bottom: botPad),
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  _RoundIconBtn(
                    icon: Icons.arrow_back,
                    onTap: () => context.pop(),
                  ),
                  const Spacer(),
                  Text(
                    'ПОДПИСЬ К КАДРУ ${frameNum.toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      letterSpacing: 1.4,
                      color: AppColors.ink3,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34),
                ],
              ),
            ),

            // Polaroid with real photo
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: _SmallPolaroid(
                  photoBytes: photoBytes,
                  ratio: ratio,
                  guestName: guestName,
                ),
              ),
            ),

            // Title + subtitle
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Как подписать кадр?',
                    style: GoogleFonts.fraunces(
                      fontWeight: FontWeight.w500,
                      fontSize: 22,
                      height: 1.15,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Выберите способ — текст или голосовое сообщение.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.ink3,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Choice cards
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _ChoiceCard(
                      icon: Icons.edit_outlined,
                      title: 'Текстом',
                      subtitle: 'Короткая фраза\nдо 120 символов',
                      onTap: () => context.push(
                        '/guest/caption/${widget.frameId}',
                        extra: {
                          'photoBytes': photoBytes,
                          'ratio': ratio,
                          'frameNum': frameNum,
                          'guestName': guestName,
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChoiceCard(
                      icon: Icons.mic_outlined,
                      title: 'Голосом',
                      subtitle: 'Запись\nдо 20 секунд',
                      onTap: () => context.push(
                        '/guest/voice/${widget.frameId}',
                        extra: {
                          'photoBytes': photoBytes,
                          'ratio': ratio,
                          'frameNum': frameNum,
                          'guestName': guestName,
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Skip — ghost
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: OutlinedButton(
                  onPressed: () => context.go('/guest/camera/$_eventId'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink3,
                    side: const BorderSide(color: AppColors.paper3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Пропустить',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared polaroid (used by sign/caption/voice screens)
// ─────────────────────────────────────────────────────────────────────────────
class _SmallPolaroid extends StatelessWidget {
  final Uint8List? photoBytes;
  final double ratio;
  final String guestName;

  const _SmallPolaroid({
    required this.photoBytes,
    required this.ratio,
    required this.guestName,
  });

  static const double width = 130;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.026, // ≈ -1.5°
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: ratio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: photoBytes != null
                    ? Image.memory(
                        photoBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
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
              height: width * 0.18,
              child: Center(
                child: Text(
                  guestName,
                  style: GoogleFonts.caveat(
                    fontSize: width * 0.13,
                    color: AppColors.ink2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Round light icon button
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
// Choice card (text / voice)
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
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x1FC9881E),
                ),
                child: Icon(icon, size: 20, color: AppColors.amber),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
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

