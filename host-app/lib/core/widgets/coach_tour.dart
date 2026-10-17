import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tokens.dart';

/// Ключи элементов, которые подсвечивает экскурсия по приложению.
class TourKeys {
  static final fab = GlobalKey(debugLabel: 'tour_fab');
  static final header = GlobalKey(debugLabel: 'tour_header');
  static final framesTab = GlobalKey(debugLabel: 'tour_frames_tab');
  static final profileTab = GlobalKey(debugLabel: 'tour_profile_tab');
  static final eventCover = GlobalKey(debugLabel: 'tour_event_cover');
  static final eventQr = GlobalKey(debugLabel: 'tour_event_qr');
  static final eventAlbum = GlobalKey(debugLabel: 'tour_event_album');
  static final eventReveal = GlobalKey(debugLabel: 'tour_event_reveal');
  static final eventSettings = GlobalKey(debugLabel: 'tour_event_settings');
}

enum CoachKind { normal, welcome, finish }

class CoachStep {
  final GlobalKey? target;
  final String title;
  final String? text;
  final CoachKind kind;
  final List<String>? points; // нумерованный список (шаг «Как это работает»)
  final String? ctaLabel;
  final VoidCallback? onCta;
  const CoachStep({
    this.target,
    required this.title,
    this.text,
    this.kind = CoachKind.normal,
    this.points,
    this.ctaLabel,
    this.onCta,
  });
}

Future<bool> tourSeen(String name) async {
  try {
    return (await SharedPreferences.getInstance()).getBool('tour_${name}_v1') ?? false;
  } catch (_) {
    return true;
  }
}

Future<void> markTourSeen(String name) async {
  try {
    await (await SharedPreferences.getInstance()).setBool('tour_${name}_v1', true);
  } catch (_) {}
}

Future<void> resetTours() async {
  try {
    final p = await SharedPreferences.getInstance();
    for (final n in ['albums', 'event']) {
      await p.remove('tour_${n}_v1');
    }
  } catch (_) {}
}

/// Показывает экскурсию поверх экрана. Возвращает true, если пройдена до конца.
Future<bool> showCoachTour(BuildContext context, List<CoachStep> steps) {
  final visible = steps.where((s) => s.target == null || s.target!.currentContext != null).toList();
  if (visible.isEmpty) return Future.value(false);
  final completer = Completer<bool>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachOverlay(
      steps: visible,
      onClose: (ok) {
        if (completer.isCompleted) return;
        entry.remove();
        completer.complete(ok);
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return completer.future;
}

class _CoachOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final void Function(bool completed) onClose;
  const _CoachOverlay({required this.steps, required this.onClose});

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> with TickerProviderStateMixin {
  static const _pad = 7.0;
  static const _dim = Color(0xD1100B08);

  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..repeat();
  late final AnimationController _spark = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat(reverse: true);
  final _cardKey = GlobalKey();

  int _i = 0;
  Rect? _from;
  Rect? _to;
  double _radius = 14;
  double _cardH = 220;

  CoachStep get _step => widget.steps[_i];
  bool get _last => _i == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0, animate: false));
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    _spark.dispose();
    super.dispose();
  }

  Rect? _measure(CoachStep s) {
    final ctx = s.target?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return (topLeft & box.size).inflate(_pad);
  }

  Future<void> _goTo(int index, {bool animate = true}) async {
    final s = widget.steps[index];
    final ctx = s.target?.currentContext;
    if (ctx != null) {
      try {
        await Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      } catch (_) {}
    }
    if (!mounted) return;
    final next = _measure(s);
    final current = _animatedRect();
    setState(() {
      _i = index;
      _from = current ?? next;
      _to = next;
      _radius = next == null ? 0 : math.min(22.0, next.shortestSide / 2);
    });
    if (animate) {
      _move.forward(from: 0);
    } else {
      _move.value = 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _cardKey.currentContext?.size?.height;
      if (h != null && (h - _cardH).abs() > 1 && mounted) setState(() => _cardH = h);
    });
  }

  Rect? _animatedRect() {
    if (_to == null && _from == null) return null;
    final t = Curves.easeOutCubic.transform(_move.value);
    if (_from == null) return _to;
    if (_to == null) return Rect.lerp(_from, Rect.fromCenter(center: _from!.center, width: 0, height: 0), t);
    return Rect.lerp(_from, _to, t);
  }

  void _next() {
    if (_last) {
      widget.onClose(true);
      _step.onCta?.call();
    } else {
      _goTo(_i + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => widget.onClose(false),
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: AnimatedBuilder(
            animation: Listenable.merge([_move, _pulse]),
            builder: (context, _) {
              final hole = _animatedRect();
              final center = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 0, height: 0);
              return Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScrimPainter(
                      hole: hole ?? center,
                      radius: _radius,
                      pulse: _pulse.value,
                      ring: _to != null,
                      dim: _dim,
                    ),
                  ),
                ),
                _buildCard(size, pad),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Size size, EdgeInsets pad) {
    final s = _step;
    final special = s.kind != CoachKind.normal;
    final cardW = math.min(340.0, size.width - 32);
    final target = _to;
    double top;
    double left;
    ({bool below, double x})? arrow;
    if (target != null) {
      final below = size.height - target.bottom;
      final placeBelow = below >= _cardH + 28 || below >= target.top;
      top = placeBelow ? target.bottom + 14 : target.top - 14 - _cardH;
      top = top.clamp(pad.top + 16, math.max(pad.top + 16, size.height - _cardH - 16));
      final cx = target.center.dx;
      left = (cx - cardW / 2).clamp(16.0, size.width - cardW - 16);
      arrow = (below: placeBelow, x: (cx - left).clamp(26.0, cardW - 26));
    } else {
      top = math.max(pad.top + 16, (size.height - _cardH) / 2);
      left = (size.width - cardW) / 2;
    }
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      top: top,
      left: left,
      width: cardW,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(_i),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: Transform.scale(scale: 0.96 + 0.04 * v, child: child)),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            key: _cardKey,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 20), spreadRadius: -10)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (special)
                Center(child: _SparkBadge(controller: _spark))
              else
                Padding(
                  padding: const EdgeInsets.only(right: 80),
                  child: Row(children: [
                    const _SparkDot(),
                    const SizedBox(width: 6),
                    Text('ШАГ ${_i + 1} ИЗ ${widget.steps.length}',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: AppColors.ink3)),
                  ]),
                ),
              SizedBox(height: special ? 2 : 6),
              Text(s.title,
                  textAlign: special ? TextAlign.center : TextAlign.start,
                  style: GoogleFonts.playfairDisplay(
                    fontFeatures: [const FontFeature.liningFigures()],
                    fontSize: special ? 26 : 22, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.3, color: AppColors.ink,
                  )),
              const SizedBox(height: 8),
              if (s.text != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(s.text!,
                      textAlign: special ? TextAlign.center : TextAlign.start,
                      style: GoogleFonts.manrope(fontSize: 14.5, height: 1.5, color: AppColors.ink2)),
                ),
              if (s.points != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(children: [
                    for (var k = 0; k < s.points!.length; k++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 24, height: 24,
                            decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text('${k + 1}', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s.points![k], style: GoogleFonts.manrope(fontSize: 14.5, height: 1.45, color: AppColors.ink2))),
                        ]),
                      ),
                  ]),
                ),
              Row(children: [
                _Dots(count: widget.steps.length, index: _i),
                const Spacer(),
                if (_i > 0 && !special)
                  IconButton(
                    onPressed: () => _goTo(_i - 1),
                    icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.ink3),
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(96, 44), padding: const EdgeInsets.symmetric(horizontal: 20)),
                    child: Text(_last ? (s.ctaLabel ?? 'Готово') : (s.kind == CoachKind.welcome ? 'Показать' : 'Далее'),
                        style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
          ),
          if (!_last)
            Positioned(
              top: 6, right: 8,
              child: TextButton(
                onPressed: () => widget.onClose(false),
                style: TextButton.styleFrom(foregroundColor: AppColors.ink3, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text('Пропустить', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          if (arrow != null)
            Positioned(
              left: arrow.x - 8,
              top: arrow.below ? -7 : null,
              bottom: arrow.below ? null : -7,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(width: 16, height: 16, decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(3))),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final double radius;
  final double pulse;
  final bool ring;
  final Color dim;
  const _ScrimPainter({required this.hole, required this.radius, required this.pulse, required this.ring, required this.dim});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final cut = Path()..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, cut), Paint()..color = dim);
    if (!ring) return;
    final base = RRect.fromRectAndRadius(hole.inflate(3), Radius.circular(radius + 3));
    canvas.drawRRect(base, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFB347)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 5));
    final grow = Curves.easeOut.transform(pulse);
    final wave = RRect.fromRectAndRadius(hole.inflate(3 + 12 * grow), Radius.circular(radius + 3 + 12 * grow));
    canvas.drawRRect(wave, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFB347).withValues(alpha: (1 - grow) * 0.9));
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) =>
      old.hole != hole || old.pulse != pulse || old.radius != radius || old.ring != ring;
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var k = 0; k < count; k++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(right: 5),
          width: k == index ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: k == index ? AppColors.amber : k < index ? AppColors.amber.withValues(alpha: 0.55) : AppColors.ink4.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ]);
  }
}

class _SparkDot extends StatelessWidget {
  const _SparkDot();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 12, height: 12, child: CustomPaint(painter: _SparkPaint(1)));
}

class _SparkPaint extends CustomPainter {
  final double scale;
  const _SparkPaint(this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24 * scale;
    final c = size.center(Offset.zero);
    Offset p(double x, double y) => Offset(c.dx + (x - 12) * s, c.dy + (y - 12) * s);
    final path = Path()
      ..moveTo(p(12, 1).dx, p(12, 1).dy)
      ..quadraticBezierTo(p(14.4, 9.6).dx, p(14.4, 9.6).dy, p(23, 12).dx, p(23, 12).dy)
      ..quadraticBezierTo(p(14.4, 14.4).dx, p(14.4, 14.4).dy, p(12, 23).dx, p(12, 23).dy)
      ..quadraticBezierTo(p(9.6, 14.4).dx, p(9.6, 14.4).dy, p(1, 12).dx, p(1, 12).dy)
      ..quadraticBezierTo(p(9.6, 9.6).dx, p(9.6, 9.6).dy, p(12, 1).dx, p(12, 1).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.amber..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant _SparkPaint old) => old.scale != scale;
}

/// Мерцающая искра с расходящимися кольцами для приветствия и финала.
class _SparkBadge extends StatelessWidget {
  final AnimationController controller;
  const _SparkBadge({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84, height: 84,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          return CustomPaint(painter: _BadgePainter(t));
        },
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  final double t;
  const _BadgePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final shift in [0.0, 0.5]) {
      final k = (t + shift) % 1;
      canvas.drawCircle(c, 14 + 28 * k, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.amber.withValues(alpha: (1 - k) * 0.6));
    }
    final scale = 0.9 + 0.22 * Curves.easeInOut.transform(t);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.14 * t);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(c, 20, Paint()..color = const Color(0xFFFFB347).withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    _SparkPaint(scale * 0.64).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BadgePainter old) => old.t != t;
}
