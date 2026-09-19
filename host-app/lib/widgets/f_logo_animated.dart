/// Порт логотипа-анимации F из analysis/brand/anim/logo-anim-F.html.
/// Все тайминги/пути/градиенты соответствуют оригиналу 1-в-1.
/// Полный цикл 5200мс, потом повтор.
///
/// Фазы:
///   1) draw stroke gold ring — 0..1300мс
///   2) draw stroke inner brown — 280..1580мс
///   3) glow radial fade-in — 1450..3350мс, потом breathe 4.8с бесконечно
///   4) flash burst — 1450..3150мс (scale .04→1.28→2.4)
///   5) spark grow — 1450..3350мс (keyframes из HTML)
///   6) sparkle twinkle — 3400мс+ бесконечно
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class FLogoAnimated extends StatefulWidget {
  final double size;
  final bool isDark;
  final bool loop;
  final double speed;
  const FLogoAnimated({
    super.key,
    required this.size,
    this.isDark = false,
    this.loop = false,
    this.speed = 1.0,
  });

  @override
  State<FLogoAnimated> createState() => _FLogoAnimatedState();
}

class _FLogoAnimatedState extends State<FLogoAnimated>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  static const _baseCycle = Duration(milliseconds: 5200);

  @override
  void initState() {
    super.initState();
    final duration = Duration(
      milliseconds: (_baseCycle.inMilliseconds / widget.speed).round(),
    );
    _c = AnimationController(vsync: this, duration: duration);
    if (widget.loop) {
      _c.repeat();
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _FLogoPainter(t: _c.value, isDark: widget.isDark),
        ),
      ),
    );
  }
}

class _FLogoPainter extends CustomPainter {
  final double t; // 0..1 через 5200мс
  final bool isDark;
  _FLogoPainter({required this.t, required this.isDark});

  static const _viewBox = 512.0;

  // Кэш path'ов (постоянные, не зависят от t).
  static final Path _ringPath = Path()
    ..addRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(66, 66, 380, 380),
      const Radius.circular(88),
    ));
  static final Path _innerBrkPath = Path()
    ..addRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(88, 88, 336, 336),
      const Radius.circular(72),
    ));
  static final Path _sparkPath = Path()
    ..moveTo(256, 118)
    ..cubicTo(264.5, 214, 298, 247.5, 394, 256)
    ..cubicTo(298, 264.5, 264.5, 298, 256, 394)
    ..cubicTo(247.5, 298, 214, 264.5, 118, 256)
    ..cubicTo(214, 247.5, 247.5, 214, 256, 118)
    ..close();

  // Кэш метрик пути кольца — computeMetrics дорогое.
  static ui.PathMetric? _ringMetricCache;
  static ui.PathMetric _ringMetric() {
    _ringMetricCache ??= _ringPath.computeMetrics().first;
    return _ringMetricCache!;
  }

  static ui.PathMetric? _innerMetricCache;
  static ui.PathMetric _innerMetric() {
    _innerMetricCache ??= _innerBrkPath.computeMetrics().first;
    return _innerMetricCache!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    canvas.scale(scale);

    final tMs = t * 5200;

    _paintRing(canvas, tMs);
    _paintInnerBrk(canvas, tMs);
    _paintGlow(canvas, tMs);
    _paintFlash(canvas, tMs);
    _paintSpark(canvas, tMs);
  }

  // ── 1) Gold ring stroke draw 0..1300мс ─────────────────────────────────
  void _paintRing(Canvas canvas, double tMs) {
    final progress = _easeOutQuint(((tMs - 0) / 1300).clamp(0.0, 1.0));
    final metric = _ringMetric();
    final subPath = metric.extractPath(0, metric.length * progress);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-0.64, -0.77),
        end: Alignment(0.68, 0.80),
        colors: [
          Color(0xFFFBDC95),
          Color(0xFFF0BC5C),
          Color(0xFFD89A31),
          Color(0xFFA96E18),
          Color(0xFF6E4A10),
        ],
        stops: [0.0, 0.28, 0.52, 0.78, 1.0],
      ).createShader(const Rect.fromLTWH(92, 60, 338, 402))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(subPath, paint);
  }

  // ── 2) Inner brown brk stroke draw 280..1580мс, fade in 1100..3200 ─────
  void _paintInnerBrk(Canvas canvas, double tMs) {
    final drawT = ((tMs - 280) / 1300).clamp(0.0, 1.0);
    final opacityT = ((tMs - 1100) / 2100).clamp(0.0, 1.0);
    final opacity = _easeInOutSine(opacityT);
    if (opacity == 0 || drawT == 0) return;
    final metric = _innerMetric();
    final subPath = metric.extractPath(0, metric.length * drawT);
    final baseColor =
        isDark ? const Color(0xFF4A3A1E) : const Color(0xFFD8C79A);
    final paint = Paint()
      ..color = baseColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(subPath, paint);
  }

  // ── 3) Glow radial fade-in + breathe ──────────────────────────────────
  void _paintGlow(Canvas canvas, double tMs) {
    if (tMs < 1450) return;

    // fade-in 1450..3350 (1.9s, cubic-bezier ~ easeOut)
    final inT = ((tMs - 1450) / 1900).clamp(0.0, 1.0);
    // Пик в 32%, затем плавно к глobal glow value.
    double factor;
    if (inT < 0.32) {
      final s = inT / 0.32;
      factor = _easeInOutCubic(s);
    } else {
      final s = (inT - 0.32) / 0.68;
      final peak = 1.0;
      final settle = isDark ? 0.72 : 0.82;
      factor = peak + (settle - peak) * _easeOutCubic(s);
    }

    // breathe после 3550мс
    if (tMs > 3550) {
      final b = ((tMs - 3550) / 4800) % 1;
      final base = isDark ? 0.72 : 0.82;
      final low = isDark ? 0.48 : 0.60;
      final wave = 0.5 - 0.5 * math.cos(b * 2 * math.pi);
      factor = base + (low - base) * wave;
    }

    // Shader — не поддерживает opacity напрямую, применим через layer.
    final shader = ui.Gradient.radial(
      const Offset(256, 256),
      138,
      isDark
          ? [
              const Color(0xFFFFD07A).withValues(alpha: 0.92 * factor),
              const Color(0xFFFF9E33).withValues(alpha: 0.40 * factor),
              const Color(0xFFF2851C).withValues(alpha: 0.13 * factor),
              const Color(0xFFF2851C).withValues(alpha: 0),
            ]
          : [
              const Color(0xFFF6A83A).withValues(alpha: 0.60 * factor),
              const Color(0xFFE5860F).withValues(alpha: 0.30 * factor),
              const Color(0xFFE5860F).withValues(alpha: 0.10 * factor),
              const Color(0xFFE5860F).withValues(alpha: 0),
            ],
      const [0, 0.4, 0.72, 1.0],
    );
    canvas.drawCircle(
      const Offset(256, 256),
      138,
      Paint()..shader = shader,
    );
  }

  // ── 4) Flash burst 1450..3150мс scale .04→1.28→2.4 ────────────────────
  void _paintFlash(Canvas canvas, double tMs) {
    if (tMs < 1450 || tMs > 3150) return;
    final flashT = (tMs - 1450) / 1700;
    double scale, opacity;
    if (flashT < 0.22) {
      final s = flashT / 0.22;
      final e = _easeOutCubic(s);
      opacity = e;
      scale = 0.04 + (1.28 - 0.04) * e;
    } else {
      final s = (flashT - 0.22) / 0.78;
      final e = _easeInCubic(s);
      opacity = 1 - e;
      scale = 1.28 + (2.4 - 1.28) * s;
    }
    canvas.save();
    canvas.translate(256, 256);
    canvas.scale(scale);
    canvas.translate(-256, -256);
    final shader = ui.Gradient.radial(
      const Offset(256, 256),
      150,
      [
        const Color(0xFFFFFDF6).withValues(alpha: opacity),
        const Color(0xFFFFF0CE).withValues(alpha: 0.62 * opacity),
        const Color(0xFFFFE1A6).withValues(alpha: 0.18 * opacity),
        const Color(0xFFFFE1A6).withValues(alpha: 0),
      ],
      const [0, 0.32, 0.64, 1.0],
    );
    canvas.drawCircle(
      const Offset(256, 256),
      150,
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  // ── 5) Spark grow 1450..3350мс + twinkle infinite ─────────────────────
  void _paintSpark(Canvas canvas, double tMs) {
    if (tMs < 1450) return;

    // opacity 1450..1730 (.28s ease-out)
    final opacityT = ((tMs - 1450) / 280).clamp(0.0, 1.0);
    final opacity = _easeOutCubic(opacityT);
    if (opacity == 0) return;

    // sparkPop scale — точные keyframes из HTML.
    final popT = ((tMs - 1450) / 1900).clamp(0.0, 1.0);
    double scale = _sparkPopScale(popT);

    // twinkle после 3400мс, 4s ease-in-out alternate 1.0↔1.05
    if (tMs > 3400) {
      final tw = ((tMs - 3400) / 4000) % 2;
      final phase = tw > 1 ? 2 - tw : tw; // triangle wave 0..1..0
      final e = _easeInOutSine(phase);
      scale *= 1.0 + 0.05 * e;
    }

    canvas.save();
    canvas.translate(256, 256);
    canvas.scale(scale);
    canvas.translate(-256, -256);

    final shader = const LinearGradient(
      begin: Alignment(0, -0.79),
      end: Alignment(0, 0.79),
      colors: [
        Color(0xFFF0BE72),
        Color(0xFFD2941F),
        Color(0xFF9A6712),
      ],
      stops: [0, 0.5, 1.0],
    ).createShader(const Rect.fromLTWH(118, 130, 276, 250));

    final darkShader = const LinearGradient(
      begin: Alignment(0, -0.85),
      end: Alignment(0, 0.85),
      colors: [
        Color(0xFFFFE7B4),
        Color(0xFFFFB84A),
        Color(0xFFD98A22),
      ],
      stops: [0, 0.42, 1.0],
    ).createShader(const Rect.fromLTWH(118, 118, 276, 276));

    final paint = Paint()..shader = isDark ? darkShader : shader;

    if (opacity < 1) {
      canvas.saveLayer(
        const Rect.fromLTWH(0, 0, _viewBox, _viewBox),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      canvas.drawPath(_sparkPath, paint);
      canvas.restore();
    } else {
      canvas.drawPath(_sparkPath, paint);
    }

    canvas.restore();
  }

  // ── keyframes из HTML @keyframes sparkPop ─────────────────────────────
  double _sparkPopScale(double t) {
    const keys = [
      [0.0, 0.03], [0.06, 0.12], [0.12, 0.3], [0.18, 0.56],
      [0.24, 0.82], [0.29, 1.0], [0.32, 1.12], [0.37, 1.095],
      [0.43, 1.068], [0.52, 1.04], [0.64, 1.02], [0.80, 1.007],
      [1.0, 1.0],
    ];
    for (int i = 0; i < keys.length - 1; i++) {
      final k0 = keys[i], k1 = keys[i + 1];
      if (t <= k1[0]) {
        final segT = (t - k0[0]) / (k1[0] - k0[0]);
        // Линейно между кадрами — как CSS animation-timing-function: linear.
        return k0[1] + (k1[1] - k0[1]) * segT;
      }
    }
    return 1.0;
  }

  // Easings
  double _easeOutQuint(double t) => 1 - math.pow(1 - t, 5).toDouble();
  double _easeInCubic(double t) => t * t * t;
  double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
  double _easeInOutCubic(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  double _easeInOutSine(double t) => -(math.cos(math.pi * t) - 1) / 2;

  @override
  bool shouldRepaint(covariant _FLogoPainter old) =>
      old.t != t || old.isDark != isDark;
}
