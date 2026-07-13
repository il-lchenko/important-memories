import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';

class RevealCountdownScreen extends ConsumerStatefulWidget {
  final String eventId;
  const RevealCountdownScreen({super.key, required this.eventId});

  @override
  ConsumerState<RevealCountdownScreen> createState() => _RevealCountdownScreenState();
}

class _RevealCountdownScreenState extends ConsumerState<RevealCountdownScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _initialized = false;
  DateTime? _revealAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recalc();
  }

  void _recalc() {
    final ra = _revealAt;
    if (ra == null || !mounted) return;
    final diff = ra.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
      if (_remaining.inSeconds == 0) _timer?.cancel();
    });
  }

  void _startTimer(DateTime revealAt) {
    _revealAt = revealAt;
    _timer?.cancel();
    // Recalculate from wall-clock each tick — prevents drift from subtraction
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _recalc());
  }

  String _fmt(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));
    final progressAsync = ref.watch(eventProgressProvider(widget.eventId));

    return eventAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.dark,
        body: const Center(child: CircularProgressIndicator(color: AppColors.drAmber)),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: AppColors.dark,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: GestureDetector(
                  onTap: () => context.pop(),
                  child: _backBtn(),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Не удалось загрузить данные',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.drText),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      data: (event) {
        final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
        final revealAtStr = settings['reveal_at'] as String?;
        final eventStatus = event['status'] as String? ?? 'active';
        final lut = settings['lut_preset'] as String? ?? 'portra400';
        final totalFrames = progressAsync.maybeWhen(
          data: (p) => p['total_frames'] as int? ?? 0,
          orElse: () => 0,
        );

        DateTime? revealAt;
        if (revealAtStr != null) {
          revealAt = DateTime.tryParse(revealAtStr)?.toLocal();
          if (revealAt != null && !_initialized) {
            // Compute remaining synchronously so first frame shows correct time
            final diff = revealAt.difference(DateTime.now());
            _remaining = diff.isNegative ? Duration.zero : diff;
            _initialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startTimer(revealAt!);
            });
          }
        }

        // revealed only when host explicitly completed the event OR timed countdown finished
        // 'instant' reveal_mode means guests see photos live, but host decides when to open album
        final revealed = eventStatus == 'completed' ||
            eventStatus == 'cancelled' ||
            (_initialized && _remaining.inSeconds == 0);
        final h = _remaining.inHours;
        final m = _remaining.inMinutes.remainder(60);
        final s = _remaining.inSeconds.remainder(60);

        final filmLabel = _filmLabel(lut);
        final revealDateLabel = revealAt != null
            ? '${revealAt.day.toString().padLeft(2, '0')}·${revealAt.month.toString().padLeft(2, '0')}·${revealAt.year % 100} в ${_fmt(revealAt.hour)}:${_fmt(revealAt.minute)}'
            : '';

        // When no reveal time is set — guide host to use the reveal sheet
        if (revealAt == null && !revealed) {
          return Scaffold(
            backgroundColor: AppColors.dark,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(onTap: () => context.pop(), child: _backBtn()),
                    const Spacer(),
                    const Text(
                      'ОТКРЫТИЕ',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, letterSpacing: 1.98, color: AppColors.drAmber),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Плёнку можно\nпроявить',
                      style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 36, fontWeight: FontWeight.w500, letterSpacing: -0.72, height: 1.1, color: AppColors.drText),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Время проявления не задано. Вернитесь к событию и нажмите «Проявить сейчас» или укажите дату и время',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Color(0x80F0E6D2), height: 1.5),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: double.infinity, height: AppSizes.buttonHeight,
                        decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(16)),
                        alignment: Alignment.center,
                        child: const Text('Вернуться к событию', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.dark,
          body: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _RevealBgPainter())),
              SafeArea(
                child: revealed
                    ? _RevealedContent(eventId: widget.eventId, totalFrames: totalFrames)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: GestureDetector(
                              onTap: () => context.pop(),
                              child: _backBtn(),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ОТКРОЕТСЯ ЧЕРЕЗ',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      letterSpacing: 1.98,
                                      color: AppColors.drAmber,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Плёнка ещё\nпроявляется',
                                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                                      fontSize: 32,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.64,
                                      height: 1.1,
                                      color: AppColors.drText,
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  Row(
                                    children: [
                                      Expanded(child: _ClockBox(value: _fmt(h), label: 'ЧАСОВ')),
                                      const SizedBox(width: 10),
                                      Expanded(child: _ClockBox(value: _fmt(m), label: 'МИНУТ')),
                                      const SizedBox(width: 10),
                                      Expanded(child: _ClockBox(value: _fmt(s), label: 'СЕКУНД')),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  if (revealDateLabel.isNotEmpty)
                                    Text(
                                      'Откроется $revealDateLabel',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        letterSpacing: 1.54,
                                        color: Color(0x80F0E6D2),
                                      ),
                                    ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: AppColors.drAmber.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(16),
                                      border: const Border(
                                        left: BorderSide(color: AppColors.drAmber, width: 2),
                                      ),
                                    ),
                                    child: Text(
                                      'Гости снимали не для сториз. Они снимали для вас — и для себя',
                                      style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                                        fontSize: 17,
                                        height: 1.4,
                                        color: AppColors.drText,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        totalFrames > 0 ? '$totalFrames КАДРОВ' : '— КАДРОВ',
                                        style: _metaStyle,
                                      ),
                                      Text(filmLabel, style: _metaStyle),
                                    ],
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
      },
    );
  }

  Widget _backBtn() => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.drAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.drAmber.withValues(alpha: 0.2)),
        ),
        child: const Icon(Icons.chevron_left, color: AppColors.drAmber, size: 22),
      );

  static const _metaStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    letterSpacing: 1.54,
    color: Color(0x73F0E6D2),
  );
}

// ─── widgets ─────────────────────────────────────────────────────────────────

class _ClockBox extends StatelessWidget {
  final String value;
  final String label;
  const _ClockBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / 1.1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.drAmber.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.drAmber.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 56,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: -1.12,
                color: AppColors.drText,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                letterSpacing: 2.0,
                color: AppColors.drAmber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevealedContent extends StatelessWidget {
  final String eventId;
  final int totalFrames;
  const _RevealedContent({required this.eventId, required this.totalFrames});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.12),
                  blurRadius: 0,
                  spreadRadius: 12,
                ),
              ],
            ),
            child: const Icon(Icons.star_rounded, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            'Плёнка проявлена!',
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
              fontSize: 32,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.64,
              color: AppColors.drText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            totalFrames > 0 ? '$totalFrames кадров ждут вас' : 'Альбом готов',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: AppColors.drAmber,
            ),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () => context.push('/events/$eventId/album'),
            child: Container(
              width: double.infinity,
              height: AppSizes.buttonHeight,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'Открыть альбом',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

String _filmLabel(String lut) {
  switch (lut) {
    case 'portra400': return 'PORTRA 400';
    case 'fuji400h': return 'FUJI 400H';
    case 'cinestill': return 'CINESTILL';
    case 'ilford': return 'ILFORD HP5+';
    case 'original': return 'БЕЗ ФИЛЬТРА';
    default: return lut.toUpperCase();
  }
}

class _RevealBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.6),
          radius: 1.0,
          colors: const [Color(0x26FFB347), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.4, 0.6),
          radius: 1.1,
          colors: const [Color(0x1FD54B3D), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
