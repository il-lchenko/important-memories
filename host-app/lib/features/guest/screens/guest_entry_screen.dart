import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';

class GuestEntryScreen extends StatelessWidget {
  const GuestEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  _IconBtn(
                    icon: Icons.arrow_back,
                    onTap: () => context.go('/role'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Подключитесь\nк альбому',
                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                      letterSpacing: -0.64,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'У организатора есть QR-код или короткий код события',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _EntryCard(
                    icon: _QrIcon(),
                    title: 'Сканировать QR',
                    subtitle: 'Откроется камера',
                    onTap: () => context.push('/guest/qr'),
                  ),
                  const SizedBox(height: 10),
                  _EntryCard(
                    icon: const Icon(Icons.keyboard_outlined,
                        size: 22, color: AppColors.ink2),
                    title: 'Ввести код вручную',
                    subtitle: '8 символов',
                    onTap: () => context.push('/guest/code'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(height: bottom + 24),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSizes.iconBtnSize,
        height: AppSizes.iconBtnSize,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: AppRadius.smBR,
        ),
        child: Icon(icon, size: 18, color: AppColors.ink2),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: AppRadius.mdBR,
          border: Border.all(color: const Color(0x0F1A1714), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: AppRadius.smBR,
              ),
              child: Center(child: icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
          ],
        ),
      ),
    );
  }
}

class _QrIcon extends StatelessWidget {
  const _QrIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _QrIconPainter(),
    );
  }
}

class _QrIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.ink2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square;
    const r = 2.0;
    final s = size.width / 3;
    // 4 mini squares
    for (final (ox, oy) in [(0.0, 0.0), (2 * s, 0.0), (2 * s, 2 * s), (0.0, 2 * s)]) {
      canvas.drawRRect(
        RRect.fromLTRBR(ox, oy, ox + s, oy + s, const Radius.circular(r)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
