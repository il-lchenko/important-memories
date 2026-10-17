import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../tokens.dart';

/// «Проявочная»: тёмная карточка (Darkroom из дизайн-системы) с перфорацией плёнки слева и искрой.
/// Для состояний, требующих действия: запуск события, статус подписки.
class DarkroomCard extends StatelessWidget {
  final String kicker;
  final String title;
  final List<({String label, String state})>? stages; // state: done | now | next
  final List<Widget> children;
  const DarkroomCard({super.key, required this.kicker, required this.title, this.stages, this.children = const []});

  static const _bg = Color(0xFF16100C);
  static const _text = Color(0xFFF0E6D2);
  static const _glow = Color(0xFFFFB347);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _bg),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.15,
                  colors: [_glow.withValues(alpha: 0.26), _glow.withValues(alpha: 0)],
                  stops: const [0, 0.55],
                ),
              ),
            ),
          ),
          Positioned(
            right: -22,
            top: -22,
            child: SizedBox(width: 132, height: 132, child: CustomPaint(painter: _SparkPainter())),
          ),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(width: 30, child: CustomPaint(painter: _EdgePainter())),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 20, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(kicker.toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.8, color: _glow)),
                    const SizedBox(height: 8),
                    Text(title,
                        style: GoogleFonts.playfairDisplay(
                          fontFeatures: [const FontFeature.liningFigures()],
                          fontSize: 24, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.3, color: _text,
                        )),
                    const SizedBox(height: 14),
                    if (stages != null) ...[
                      Row(children: [
                        for (var i = 0; i < stages!.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(child: _Stage(label: stages![i].label, state: stages![i].state)),
                        ],
                      ]),
                      const SizedBox(height: 16),
                    ],
                    ...children,
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Текст внутри «проявочной».
class DarkroomText extends StatelessWidget {
  final String text;
  const DarkroomText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: GoogleFonts.manrope(fontSize: 14, height: 1.5, color: DarkroomCard._text.withValues(alpha: 0.72))),
      );
}

class _Stage extends StatelessWidget {
  final String label;
  final String state;
  const _Stage({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final done = state == 'done';
    final now = state == 'now';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? DarkroomCard._glow.withValues(alpha: 0.88) : null,
        borderRadius: BorderRadius.circular(6),
        border: done ? null : Border.all(color: now ? DarkroomCard._glow : DarkroomCard._glow.withValues(alpha: 0.3)),
        boxShadow: now ? [BoxShadow(color: DarkroomCard._glow.withValues(alpha: 0.35), blurRadius: 12)] : null,
      ),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6,
            color: done ? DarkroomCard._bg : now ? DarkroomCard._glow : DarkroomCard._text.withValues(alpha: 0.5),
          )),
    );
  }
}

class _EdgePainter extends CustomPainter {
  const _EdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0C0806));
    canvas.drawLine(
      Offset(size.width - 0.5, 0), Offset(size.width - 0.5, size.height),
      Paint()..color = DarkroomCard._glow.withValues(alpha: 0.28)..strokeWidth = 1,
    );
    final hole = Paint()..color = AppColors.paper.withValues(alpha: 0.92);
    for (double y = 6; y + 14 <= size.height; y += 26) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(9, y, 12, 14), const Radius.circular(3.5)), hole);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(12 * s, 1 * s)
      ..quadraticBezierTo(14.4 * s, 9.6 * s, 23 * s, 12 * s)
      ..quadraticBezierTo(14.4 * s, 14.4 * s, 12 * s, 23 * s)
      ..quadraticBezierTo(9.6 * s, 14.4 * s, 1 * s, 12 * s)
      ..quadraticBezierTo(9.6 * s, 9.6 * s, 12 * s, 1 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = DarkroomCard._glow.withValues(alpha: 0.13)..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
