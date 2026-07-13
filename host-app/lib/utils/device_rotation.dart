import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Целевая ориентация телефона в четвертях (0..3 по часовой):
/// 0 — portrait up, 1 — landscape right (наклон вправо), 2 — portrait down,
/// 3 — landscape left (наклон влево).
class DeviceRotationNotifier extends StateNotifier<int> {
  DeviceRotationNotifier() : super(0) {
    _sub = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 50))
        .listen(_onEvent);
  }

  StreamSubscription<AccelerometerEvent>? _sub;
  DateTime _lastChange = DateTime.fromMillisecondsSinceEpoch(0);

  void _onEvent(AccelerometerEvent e) {
    // Если телефон лежит экраном вверх — gravity по Z доминирует, ориентация
    // нестабильна. Игнорируем такие сэмплы.
    if (e.z.abs() > 8.5) return;

    // Если x|y слишком слабый сигнал — то же.
    if (e.x.abs() < 1.2 && e.y.abs() < 1.2) return;

    final angleDeg = math.atan2(e.x, e.y) * 180 / math.pi;
    // angleDeg ≈ 0 для portrait up, ≈ +90 для наклона вправо, ≈ ±180 для portrait
    // down, ≈ -90 для наклона влево.
    int q;
    if (angleDeg >= -45 && angleDeg < 45) {
      q = 0;
    } else if (angleDeg >= 45 && angleDeg < 135) {
      q = 1;
    } else if (angleDeg >= -135 && angleDeg < -45) {
      q = 3;
    } else {
      q = 2;
    }

    if (q == state) return;
    final now = DateTime.now();
    if (now.difference(_lastChange).inMilliseconds < 50) return;
    _lastChange = now;
    state = q;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final deviceRotationProvider =
    StateNotifierProvider.autoDispose<DeviceRotationNotifier, int>(
  (ref) => DeviceRotationNotifier(),
);

/// Перевод четверти в радианы для Transform.rotate / AnimatedRotation.
double rotationTurnsFor(int quarter) {
  // Иконки крутятся ПРОТИВ направления физического поворота телефона,
  // чтобы оставаться вертикально по отношению к гравитации.
  // На Android sensor X-ось ведёт себя инверсно — поэтому знаки
  // подобраны эмпирически: вправо +0.25, влево -0.25.
  switch (quarter) {
    case 1:
      return 0.25; // landscape right
    case 2:
      return 0.5;
    case 3:
      return -0.25;
    default:
      return 0;
  }
}
