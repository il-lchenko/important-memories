// Dart port of backend/app/workers/thumbnail.py film pipeline.
// Used both in GuestCameraScreen (via compute isolate) and directly.
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class _FilmPreset {
  final List<List<double>> r, g, b;
  final double saturation;
  final double fade;
  final double temperature;
  final List<double> shadowTint;
  final List<double> highlightTint;
  final bool bw;

  const _FilmPreset({
    required this.r,
    required this.g,
    required this.b,
    required this.saturation,
    required this.fade,
    required this.temperature,
    required this.shadowTint,
    required this.highlightTint,
    this.bw = false,
  });
}

const _presets = <String, _FilmPreset>{
  'portra400': _FilmPreset(
    r: [[0.0, 0.06], [0.20, 0.22], [0.5, 0.55], [0.82, 0.85], [1.0, 0.96]],
    g: [[0.0, 0.05], [0.20, 0.20], [0.5, 0.51], [0.82, 0.80], [1.0, 0.91]],
    b: [[0.0, 0.07], [0.20, 0.18], [0.5, 0.46], [0.82, 0.74], [1.0, 0.86]],
    saturation: 0.98, fade: 0.09, temperature: 4.0,
    shadowTint: [3.0, 1.0, -1.0],
    highlightTint: [16.0, 4.0, -2.0],
  ),
  'fuji400h': _FilmPreset(
    r: [[0.0, 0.10], [0.25, 0.26], [0.5, 0.50], [0.78, 0.78], [1.0, 0.90]],
    g: [[0.0, 0.06], [0.25, 0.22], [0.5, 0.50], [0.78, 0.82], [1.0, 0.96]],
    b: [[0.0, 0.15], [0.25, 0.34], [0.5, 0.57], [0.78, 0.83], [1.0, 0.95]],
    saturation: 0.82, fade: 0.18, temperature: -5.0,
    shadowTint: [6.0, -3.0, 9.0],
    highlightTint: [-3.0, 2.0, 6.0],
  ),
  'cinestill': _FilmPreset(
    r: [[0.0, 0.04], [0.2, 0.20], [0.5, 0.50], [0.8, 0.84], [1.0, 0.97]],
    g: [[0.0, 0.05], [0.2, 0.20], [0.5, 0.50], [0.8, 0.78], [1.0, 0.92]],
    b: [[0.0, 0.18], [0.2, 0.36], [0.5, 0.58], [0.8, 0.74], [1.0, 0.84]],
    saturation: 1.04, fade: 0.16, temperature: -14.0,
    shadowTint: [-14.0, -8.0, 22.0],
    highlightTint: [12.0, 5.0, -10.0],
  ),
  'ilford': _FilmPreset(
    r: [[0.0, 0.06], [0.22, 0.18], [0.5, 0.52], [0.78, 0.86], [1.0, 0.96]],
    g: [[0.0, 0.06], [0.22, 0.18], [0.5, 0.52], [0.78, 0.86], [1.0, 0.96]],
    b: [[0.0, 0.06], [0.22, 0.18], [0.5, 0.52], [0.78, 0.86], [1.0, 0.96]],
    saturation: 0.0, fade: 0.10, temperature: 0.0,
    shadowTint: [0.0, 0.0, 0.0],
    highlightTint: [0.0, 0.0, 0.0],
    bw: true,
  ),
};

Uint8List _buildLut(List<List<double>> points) {
  final sorted = [...points]..sort((a, b) => a[0].compareTo(b[0]));
  final lut = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    final x = i / 255.0;
    int j = 0;
    while (j < sorted.length - 1 && sorted[j + 1][0] < x) {
      j++;
    }
    if (j >= sorted.length - 1) {
      lut[i] = (sorted.last[1] * 255).clamp(0, 255).round();
      continue;
    }
    final x0 = sorted[j][0], y0 = sorted[j][1];
    final x1 = sorted[j + 1][0], y1 = sorted[j + 1][1];
    final t = (x - x0) / (x1 - x0);
    final ts = t * t * (3.0 - 2.0 * t); // smoothstep
    lut[i] = ((y0 + (y1 - y0) * ts) * 255).clamp(0, 255).round();
  }
  return lut;
}

img.Image applyFilmFilter(img.Image image, String preset) {
  if (preset == 'original') return image;
  final f = _presets[preset];
  if (f == null) return image;

  final rLut = _buildLut(f.r);
  final gLut = _buildLut(f.g);
  final bLut = _buildLut(f.b);

  for (final pixel in image) {
    final ri = pixel.r.toInt().clamp(0, 255);
    final gi = pixel.g.toInt().clamp(0, 255);
    final bi = pixel.b.toInt().clamp(0, 255);

    if (f.bw) {
      final lum = (ri * 0.299 + gi * 0.587 + bi * 0.114).clamp(0, 255).round();
      final mapped = rLut[lum].toDouble();
      pixel.r = mapped;
      pixel.g = mapped;
      pixel.b = mapped;
    } else {
      double rf = rLut[ri].toDouble();
      double gf = gLut[gi].toDouble();
      double bf = bLut[bi].toDouble();

      // Fade (lift blacks)
      if (f.fade > 0) {
        rf += (255 - rf) * (f.fade * 0.18);
        gf += (255 - gf) * (f.fade * 0.18);
        bf += (255 - bf) * (f.fade * 0.18);
      }

      // Tone-split tint
      final lum = (rf * 0.299 + gf * 0.587 + bf * 0.114) / 255.0;
      final shadowW = (1.0 - lum) * (1.0 - lum);
      final highW = lum * lum;
      rf += shadowW * f.shadowTint[0] + highW * f.highlightTint[0];
      gf += shadowW * f.shadowTint[1] + highW * f.highlightTint[1];
      bf += shadowW * f.shadowTint[2] + highW * f.highlightTint[2];

      // Temperature
      if (f.temperature != 0) {
        rf += f.temperature * 0.15;
        bf -= f.temperature * 0.15;
      }

      // Saturation (luminance-preserving)
      if (f.saturation != 1.0) {
        final lum2 = rf * 0.299 + gf * 0.587 + bf * 0.114;
        rf = lum2 + (rf - lum2) * f.saturation;
        gf = lum2 + (gf - lum2) * f.saturation;
        bf = lum2 + (bf - lum2) * f.saturation;
      }

      pixel.r = rf.clamp(0.0, 255.0);
      pixel.g = gf.clamp(0.0, 255.0);
      pixel.b = bf.clamp(0.0, 255.0);
    }
  }

  return image;
}

// Top-level function — runs in compute() isolate.
// Returns Map with 'bytes' (Uint8List), 'width' (int), 'height' (int).
Map<String, Object> processImageInIsolate(Map<String, Object> params) {
  final bytes = params['bytes'] as Uint8List;
  final preset = params['preset'] as String;
  final maxSize = (params['maxSize'] as int?) ?? 4000;
  final quarter = (params['quarter'] as int?) ?? 0;
  final targetRatio = (params['targetRatio'] as double?);

  var image = img.decodeImage(bytes)!;
  image = img.bakeOrientation(image).convert(numChannels: 3);

  final isLandscape = image.width > image.height;
  final quarterIsLandscape = quarter == 1 || quarter == 3;

  if (isLandscape && quarterIsLandscape) {
    // Landscape shot: camera plugin returns upside-down landscape — flip 180°.
    image = img.copyRotate(image, angle: 180);
  } else if (isLandscape && !quarterIsLandscape) {
    // Portrait shot but image is still landscape — bakeOrientation had no EXIF to act on.
    // Sensor top = right side of phone → scene UP is at RIGHT of landscape → rotate 90° CCW.
    image = img.copyRotate(image, angle: -90);
  }

  // Центральный кроп до targetRatio (w/h) — если задан.
  // Камера всегда снимает 4:3 (или 3:4 после поворота). Для 3:4 — no-op.
  // Для полноэкранного режима — кропим до aspect экрана.
  if (targetRatio != null) {
    final w = image.width;
    final h = image.height;
    final srcRatio = w / h;
    if ((srcRatio - targetRatio).abs() > 0.01) {
      int cropW, cropH;
      if (srcRatio > targetRatio) {
        // Слишком широкое — режем боковины
        cropH = h;
        cropW = (h * targetRatio).round();
      } else {
        // Слишком высокое — режем верх/низ
        cropW = w;
        cropH = (w / targetRatio).round();
      }
      final x = ((w - cropW) / 2).round();
      final y = ((h - cropH) / 2).round();
      image = img.copyCrop(image, x: x, y: y, width: cropW, height: cropH);
    }
  }

  // Resize to max side = maxSize
  final longerSide = image.width > image.height ? image.width : image.height;
  if (longerSide > maxSize) {
    final scale = maxSize / longerSide;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  if (preset != 'original') {
    image = applyFilmFilter(image, preset);
  }

  final jpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 92));
  return {
    'bytes': jpegBytes,
    'width': image.width,
    'height': image.height,
  };
}

String filmLabel(String preset) {
  const labels = {
    'portra400': 'PORTRA 400',
    'fuji400h': 'FUJI 400H',
    'cinestill': 'CINESTILL 800T',
    'ilford': 'ILFORD HP5+',
    'original': 'БЕЗ ФИЛЬТРА',
  };
  return labels[preset] ?? preset.toUpperCase();
}
