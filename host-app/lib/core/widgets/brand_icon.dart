import 'package:flutter/material.dart';

import '../tokens.dart';
import 'brand_icon_data.dart';

/// Фирменные значки ImpoMento (event, solo, mini, plus): ink-штрихи и янтарная искра.
/// Пути совпадают с веб-версией (guest-pwa/src/app/iconData.ts).
class BrandIcon extends StatelessWidget {
  final String name;
  final double size;
  final double stroke;
  final Color ink;
  final Color accent;

  /// Одноцветный режим (для строк списков): всё рисуется цветом [color].
  const BrandIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.stroke = 1.8,
    this.ink = AppColors.ink,
    this.accent = AppColors.amber,
  });

  const BrandIcon.mono(
    this.name, {
    super.key,
    this.size = 24,
    this.stroke = 1.8,
    Color color = AppColors.amber,
  })  : ink = color,
        accent = color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BrandIconPainter(name, stroke, ink, accent)),
    );
  }
}

/// Material-иконка, выровненная по оптическому размеру (таблица kIconNorm из шрифта):
/// иначе «скачать» выглядит мельче «настроек» при одинаковом size.
class UiIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const UiIcon(this.icon, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final n = kIconNorm[icon.codePoint];
    final child = Icon(icon, size: size, color: color);
    if (n == null) return SizedBox(width: size, height: size, child: child);
    return SizedBox(
      width: size,
      height: size,
      child: Transform.translate(
        offset: Offset(n[1] * size, n[2] * size),
        child: Transform.scale(scale: n[0], child: child),
      ),
    );
  }
}

final _paths = <String, Path>{};

Path _parse(String d) {
  return _paths.putIfAbsent(d, () {
    final path = Path();
    final tokens = RegExp(r'[MLHVCQZ]|-?\d*\.?\d+').allMatches(d).map((m) => m.group(0)!).toList();
    var i = 0;
    double n() => double.parse(tokens[i++]);
    var cx = 0.0, cy = 0.0;
    String cmd = 'M';
    while (i < tokens.length) {
      final t = tokens[i];
      if (RegExp(r'[A-Z]').hasMatch(t)) {
        cmd = t;
        i++;
        if (cmd == 'Z') {
          path.close();
          continue;
        }
      }
      switch (cmd) {
        case 'M':
          cx = n(); cy = n();
          path.moveTo(cx, cy);
          cmd = 'L';
        case 'L':
          cx = n(); cy = n();
          path.lineTo(cx, cy);
        case 'H':
          cx = n();
          path.lineTo(cx, cy);
        case 'V':
          cy = n();
          path.lineTo(cx, cy);
        case 'Q':
          final x1 = n(), y1 = n(), x = n(), y = n();
          path.quadraticBezierTo(x1, y1, x, y);
          cx = x; cy = y;
        case 'C':
          final x1 = n(), y1 = n(), x2 = n(), y2 = n(), x = n(), y = n();
          path.cubicTo(x1, y1, x2, y2, x, y);
          cx = x; cy = y;
        default:
          i++;
      }
    }
    return path;
  });
}

class _BrandIconPainter extends CustomPainter {
  final String name;
  final double stroke;
  final Color ink;
  final Color accent;
  const _BrandIconPainter(this.name, this.stroke, this.ink, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final layers = brandIconData[name];
    if (layers == null) return;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    for (final (kind, d) in layers) {
      final path = _parse(d);
      switch (kind) {
        case 'accent':
          canvas.drawPath(path, Paint()..color = accent..style = PaintingStyle.fill..isAntiAlias = true);
        case 'badge':
          canvas.drawPath(path, Paint()..color = accent..style = PaintingStyle.fill..isAntiAlias = true);
        case 'white':
          canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill..isAntiAlias = true);
        case 'whiteStroke':
          canvas.drawPath(
            path,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeCap = StrokeCap.round
              ..isAntiAlias = true,
          );
        case 'ink':
          canvas.drawPath(path, Paint()..color = ink..style = PaintingStyle.fill..isAntiAlias = true);
        default:
          canvas.drawPath(
            path,
            Paint()
              ..color = kind == 'soft' ? ink.withValues(alpha: 0.3) : ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..isAntiAlias = true,
          );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandIconPainter old) =>
      old.name != name || old.ink != ink || old.accent != accent || old.stroke != stroke;
}

/// Маркер списков: маленькая янтарная искра.
class SparkMark extends StatelessWidget {
  final double size;
  const SparkMark({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _SparkPainter()));
  }
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(12 * s, 2 * s)
      ..quadraticBezierTo(14 * s, 10 * s, 22 * s, 12 * s)
      ..quadraticBezierTo(14 * s, 14 * s, 12 * s, 22 * s)
      ..quadraticBezierTo(10 * s, 14 * s, 2 * s, 12 * s)
      ..quadraticBezierTo(10 * s, 10 * s, 12 * s, 2 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = AppColors.amber..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
