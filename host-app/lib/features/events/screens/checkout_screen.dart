import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../events_provider.dart';

/// Смета создаваемого события: слайдер гостей → тариф → выбор кадров → итог.
/// Открывается после шага 5 «Плёнка» из [CreateEventScreen].
class CheckoutScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> draft;
  const CheckoutScreen({super.key, required this.draft});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  static const _tiers = <int>[5, 10, 25, 50, 75, 100, 150, 175, 200, 250];

  static const _storageOptions = <String, ({int days, int rub, String label})>{
    'base': (days: 0,   rub: 0,    label: 'Базовый'),
    '3m':   (days: 90,  rub: 490,  label: '+3 мес'),
    '6m':   (days: 180, rub: 790,  label: '+6 мес'),
    '1y':   (days: 365, rub: 1290, label: '+1 год'),
  };

  int _tierIndex = 3; // 50 гостей по умолчанию
  String _storageKey = 'base';
  bool _loading = false;

  int get _framesPerGuest =>
      (widget.draft['frames_per_guest'] as int?) ?? 30;

  bool get _isExtendedFrames => _framesPerGuest > 30;

  int get _guests => _tiers[_tierIndex];

  String get _planId => switch (_guests) {
    5   => 'free',
    10  => 'p10',
    25  => 'p25',
    50  => 'p50',
    75  => 'p75',
    100 => 'p100',
    150 => 'p150',
    175 => 'p175',
    200 => 'p200',
    250 => 'p250',
    _   => 'custom',
  };

  int get _planPriceRub => switch (_planId) {
    'free' => 0,
    'p10'  => 249,
    'p25'  => 449,
    'p50'  => 1290,
    'p75'  => 1990,
    'p100' => 2990,
    'p150' => 4490,
    'p175' => 5490,
    'p200' => 6290,
    'p250' => 7690,
    _      => 0,
  };

  int get _retentionDays => switch (_planId) {
    'free' => 14,
    'p10'  => 30,
    'p25'  => 60,
    'p50'  => 90,
    'p75'  => 90,
    'p100' => 120,
    'p150' => 150,
    'p175' => 180,
    'p200' => 180,
    'p250' => 240,
    _      => 60,
  };

  int get _framesExtraRub => _isExtendedFrames ? _guests * 5 : 0;
  int get _storageExtraRub => _storageOptions[_storageKey]!.rub;
  int get _storageExtraDays => _storageOptions[_storageKey]!.days;
  int get _totalRub => _planPriceRub + _framesExtraRub + _storageExtraRub;

  DateTime get _expiresAt => DateTime.now()
      .add(Duration(days: _retentionDays + _storageExtraDays));

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);

      // Step 1: create event (always starts as DRAFT)
      final created = await ref.read(createEventProvider({
        'name': widget.draft['name'],
        'event_type': widget.draft['event_type'],
        'frames_per_guest': _framesPerGuest,
        'reveal_mode': widget.draft['reveal_mode'],
        if (widget.draft['reveal_at'] != null) 'reveal_at': widget.draft['reveal_at'],
        if (widget.draft['start_at'] != null)  'start_at':  widget.draft['start_at'],
        'film': widget.draft['film'],
        'plan': _planId,
        if (_storageKey != 'base') 'storage_extension': _storageKey,
      }).future);

      final eventId = created['id'] as String;

      if (_totalRub == 0) {
        // Free plan: activate immediately
        await dio.post('events/$eventId/activate');
        if (!mounted) return;
        ref.invalidate(eventsProvider);
        context.go('/dashboard');
      } else {
        // Paid plan: get YooKassa checkout URL and open in browser
        final resp = await dio.post(
          'events/$eventId/checkout',
          data: {'plan': _planId},
        );
        final confirmUrl = resp.data['confirmation_url'] as String?;
        if (!mounted) return;
        ref.invalidate(eventsProvider);
        if (confirmUrl != null && confirmUrl.isNotEmpty) {
          final uri = Uri.parse(confirmUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        context.go('/dashboard');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractUserMessage(e),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
          backgroundColor: AppColors.shutter,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onBack: () => context.pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Kicker('ШАГ 6 · СМЕТА'),
                    _Title('Ваша смета'),
                    const _StepDesc(
                        'Выберите количество гостей — тариф и цена подстроятся автоматически'),
                    _GuestsCard(
                      guests: _guests,
                      tierIndex: _tierIndex,
                      tiersLength: _tiers.length,
                      onChanged: (i) => setState(() => _tierIndex = i),
                    ),
                    const SizedBox(height: 20),
                    _PlanCard(
                      planId: _planId,
                      priceRub: _planPriceRub,
                      retentionDays: _retentionDays,
                    ),
                    const SizedBox(height: 20),
                    _FramesSummary(
                      frames: _framesPerGuest,
                      extraRub: _framesExtraRub,
                    ),
                    const SizedBox(height: 20),
                    _StorageCard(
                      selected: _storageKey,
                      baseRetentionDays: _retentionDays,
                      options: _storageOptions,
                      onChanged: (v) => setState(() => _storageKey = v),
                    ),
                    const SizedBox(height: 24),
                    _TotalCard(
                      planId: _planId,
                      planPriceRub: _planPriceRub,
                      framesExtraRub: _framesExtraRub,
                      storageExtraRub: _storageExtraRub,
                      storageLabel: _storageOptions[_storageKey]!.label,
                      totalRub: _totalRub,
                      guests: _guests,
                      framesPerGuest: _framesPerGuest,
                      expiresAt: _expiresAt,
                    ),
                    const SizedBox(height: 24),
                    _SubmitCta(
                      totalRub: _totalRub,
                      loading: _loading,
                      onTap: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Topbar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          _IcBtn(icon: Icons.chevron_left, onTap: onBack),
          const Expanded(
            child: Text(
              'СМЕТА',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                letterSpacing: 1.32,
                color: AppColors.ink3,
              ),
            ),
          ),
          _IcBtn(
            icon: Icons.close,
            onTap: () => context.go('/dashboard'),
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}

class _IcBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  const _IcBtn({required this.icon, required this.onTap, this.iconSize = 22});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: AppColors.ink2, size: iconSize),
      ),
    );
  }
}

// ─── Guests slider ──────────────────────────────────────────────────────────

class _GuestsCard extends StatelessWidget {
  final int guests;
  final int tierIndex;
  final int tiersLength;
  final ValueChanged<int> onChanged;
  const _GuestsCard({
    required this.guests,
    required this.tierIndex,
    required this.tiersLength,
    required this.onChanged,
  });

  static const _tierLabels = ['5', '10', '25', '50', '75', '100', '150', '175', '200', '250'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.lgBR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ГОСТЕЙ',
              style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  letterSpacing: 0.18,
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$guests',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 56,
                    height: 1.0,
                    fontWeight: FontWeight.w600,
                    color: AppColors.amber,
                  )),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('гостей',
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              activeTrackColor: AppColors.amber,
              inactiveTrackColor: AppColors.paper3,
              thumbColor: AppColors.amber,
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: tierIndex.toDouble(),
              min: 0,
              max: (tiersLength - 1).toDouble(),
              divisions: tiersLength - 1,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (ctx, constraints) => SizedBox(
              height: 24,
              width: constraints.maxWidth,
              child: CustomPaint(
                painter: _TierRulerPainter(
                  labels: _tierLabels,
                  selectedIndex: tierIndex,
                  activeColor: AppColors.amber,
                  dimColor: AppColors.ink4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: AppColors.paper,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => const _CustomTierSheet(),
              );
            },
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.ink3),
                const SizedBox(width: 6),
                Text('Больше 250 гостей — по запросу',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.ink3,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.ink4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierRulerPainter extends CustomPainter {
  final List<String> labels;
  final int selectedIndex;
  final Color activeColor;
  final Color dimColor;

  const _TierRulerPainter({
    required this.labels,
    required this.selectedIndex,
    required this.activeColor,
    required this.dimColor,
  });

  double _x(int i, double w) => 8 + i / (labels.length - 1) * (w - 16);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final tickPaint = Paint()..strokeWidth = 1.2..strokeCap = StrokeCap.round;

    for (int i = 0; i < labels.length; i++) {
      final x = _x(i, w);
      final isActive = i <= selectedIndex;
      final isSel = i == selectedIndex;

      tickPaint.color = isSel
          ? activeColor
          : isActive
              ? activeColor.withValues(alpha: 0.65)
              : dimColor.withValues(alpha: 0.55);
      canvas.drawLine(Offset(x, 0), Offset(x, 6), tickPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'JetBrains Mono',
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
            color: isSel
                ? activeColor
                : isActive
                    ? activeColor.withValues(alpha: 0.8)
                    : dimColor.withValues(alpha: 0.75),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 10));
    }
  }

  @override
  bool shouldRepaint(covariant _TierRulerPainter old) =>
      old.selectedIndex != selectedIndex;
}

class _CustomTierSheet extends StatelessWidget {
  const _CustomTierSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.paper3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text('Больше 250 гостей',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              )),
          const SizedBox(height: 10),
          const Text(
            'Свадьбы, банкеты и корпоративы с большим числом гостей — '
            'считаем индивидуально. Напишите нам с деталями события.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.4,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: AppRadius.mdBR,
            ),
            child: Row(
              children: const [
                Icon(Icons.calculate_outlined, size: 18, color: AppColors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Формула: 7 690 ₽ + 30 ₽ × (гости − 250)',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
              ),
              child: const Text('Понятно',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plan card ──────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String planId;
  final int priceRub;
  final int retentionDays;
  const _PlanCard({
    required this.planId,
    required this.priceRub,
    required this.retentionDays,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = planId == 'free';
    final label = planId.toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.amber,
              borderRadius: AppRadius.pillBR,
            ),
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Тариф',
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 11, color: AppColors.ink3)),
                const SizedBox(height: 1),
                Text('Хранение $retentionDays дн.',
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppColors.ink2,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text(
            isFree ? 'Бесплатно' : '$priceRub ₽',
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Frames summary (readonly — выбор на шаге 2) ───────────────────────────

class _FramesSummary extends StatelessWidget {
  final int frames;
  final int extraRub;
  const _FramesSummary({required this.frames, required this.extraRub});

  @override
  Widget build(BuildContext context) {
    final isExt = frames > 30;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.mdBR,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.photo_camera_outlined,
                color: AppColors.amber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$frames кадров на гостя',
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  isExt
                      ? 'Плёнка «люкс» · сверх 30 кадров'
                      : 'Базовая длина плёнки',
                  style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          Text(
            extraRub > 0 ? '+$extraRub ₽' : 'Входит',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: extraRub > 0 ? AppColors.amber : AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Storage extensions ─────────────────────────────────────────────────────

class _StorageCard extends StatelessWidget {
  final String selected;
  final int baseRetentionDays;
  final Map<String, ({int days, int rub, String label})> options;
  final ValueChanged<String> onChanged;
  const _StorageCard({
    required this.selected,
    required this.baseRetentionDays,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.mdBR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_outlined,
                  size: 18, color: AppColors.ink3),
              const SizedBox(width: 8),
              const Text('СРОК ХРАНЕНИЯ',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      letterSpacing: 0.18,
                      color: AppColors.ink3,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Базовый — $baseRetentionDays дней. Можно докупить продление.',
              style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
          const SizedBox(height: 14),
          ...options.entries.map((e) {
            final key = e.key;
            final opt = e.value;
            final active = key == selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onChanged(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.amber.withValues(alpha: 0.08)
                        : AppColors.paper,
                    borderRadius: AppRadius.mdBR,
                    border: Border.all(
                      color: active ? AppColors.amber : AppColors.line,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active
                                ? AppColors.amber
                                : AppColors.ink4.withValues(alpha: 0.5),
                            width: active ? 5 : 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.label,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? AppColors.ink
                                      : AppColors.ink2),
                            ),
                            if (opt.days > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text('+${opt.days} дней хранения',
                                    style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: AppColors.ink3)),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        opt.rub == 0 ? 'Входит' : '+${opt.rub} ₽',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: opt.rub == 0
                              ? AppColors.ink3
                              : AppColors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Total ─────────────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final String planId;
  final int planPriceRub;
  final int framesExtraRub;
  final int storageExtraRub;
  final String storageLabel;
  final int totalRub;
  final int guests;
  final int framesPerGuest;
  final DateTime expiresAt;
  const _TotalCard({
    required this.planId,
    required this.planPriceRub,
    required this.framesExtraRub,
    required this.storageExtraRub,
    required this.storageLabel,
    required this.totalRub,
    required this.guests,
    required this.framesPerGuest,
    required this.expiresAt,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = planId == 'free' && totalRub == 0;
    final dateStr = DateFormat('d MMMM yyyy', 'ru').format(expiresAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: AppRadius.lgBR,
        border: Border.all(color: AppColors.ink, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ИТОГО',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                letterSpacing: -0.2,
              )),
          const SizedBox(height: 14),
          _TotalRow(
            label: 'Тариф ${planId.toUpperCase()} · до $guests гостей',
            value: planPriceRub == 0 ? 'Бесплатно' : '$planPriceRub ₽',
          ),
          if (framesExtraRub > 0) ...[
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Плёнка «люкс» $framesPerGuest × $guests',
              value: '+$framesExtraRub ₽',
              accent: true,
            ),
          ],
          if (storageExtraRub > 0) ...[
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Продление хранения · $storageLabel',
              value: '+$storageExtraRub ₽',
              accent: true,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: DashLine(),
          ),
          Row(
            children: [
              const Expanded(
                child: Text('К оплате',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
              ),
              Text(
                isFree ? 'Бесплатно' : '$totalRub ₽',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: AppRadius.smBR,
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: AppColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        color: AppColors.ink2,
                      ),
                      children: [
                        const TextSpan(text: 'Альбом хранится до '),
                        TextSpan(
                          text: dateStr,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const _TotalRow({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13.5,
              color: accent ? AppColors.ink : AppColors.ink2,
              fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 15,
            color: accent ? AppColors.amber : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class DashLine extends StatelessWidget {
  const DashLine({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashes = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          children: List.generate(dashes, (_) => Padding(
            padding: const EdgeInsets.only(right: dashSpace),
            child: Container(
              width: dashWidth,
              height: 1,
              color: AppColors.ink3.withValues(alpha: 0.4),
            ),
          )),
        );
      },
    );
  }
}

// ─── Submit ────────────────────────────────────────────────────────────────

class _SubmitCta extends StatelessWidget {
  final int totalRub;
  final bool loading;
  final VoidCallback onTap;
  const _SubmitCta({
    required this.totalRub,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = totalRub == 0
        ? 'Создать бесплатно'
        : 'Создать за $totalRub ₽';
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: AppSizes.buttonHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.amber,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.amber.withValues(alpha: 0.42),
              blurRadius: 20,
              offset: const Offset(0, 6),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
        ),
      ),
    );
  }
}

// ─── Тексты в стиле create_event ───────────────────────────────────────────

class _Kicker extends StatelessWidget {
  final String text;
  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              letterSpacing: 0.18,
              color: AppColors.amber,
              fontWeight: FontWeight.w500,
            )),
      );
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(text,
            style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.w500,
              fontSize: 30,
              height: 1.05,
              letterSpacing: -0.6,
              color: AppColors.ink,
            )),
      );
}

class _StepDesc extends StatelessWidget {
  final String text;
  const _StepDesc(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 20),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.ink3,
                height: 1.45)),
      );
}
