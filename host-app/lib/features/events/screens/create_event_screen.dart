import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../events_provider.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  int _step = 1;

  // Шаг 1
  final _nameCtrl = TextEditingController();
  String _eventType = 'wedding';

  // Шаг 2
  int _framesPerGuest = 24;

  // Шаг 3
  DateTime? _startAt;

  // Шаг 4
  DateTime? _revealAt;

  // Шаг 5
  String _film = 'portra400';

  // Шаг 6
  String _plan = 'p50';

  bool _loading = false;
  static const _totalSteps = 6;

  final _films = [
    {'id': 'original',  'name': 'Без фильтра',      'desc': 'Фото как снято · Без обработки'},
    {'id': 'portra400', 'name': 'Kodak Portra 400', 'desc': 'Тёплые телесные тона · Лучше всего для свадеб'},
    {'id': 'fuji400h',  'name': 'Fuji 400H',        'desc': 'Холодные пастельные зелёные · Природа и портреты'},
    {'id': 'cinestill', 'name': 'Cinestill 800T',   'desc': 'Неоновые красные · Ночные и городские сцены'},
    {'id': 'ilford',    'name': 'Ilford HP5+',      'desc': 'Ч/Б · Классика документальной съёмки'},
  ];

  final _plans = [
    {'id': 'free',      'guests': 'До 5 гостей',    'price': '0'},
    {'id': 'p10',       'guests': 'До 10 гостей',   'price': '150'},
    {'id': 'p25',       'guests': 'До 25 гостей',   'price': '450'},
    {'id': 'p50',       'guests': 'До 50 гостей',   'price': '1190', 'hit': 'true'},
    {'id': 'p100',      'guests': 'До 100 гостей',  'price': '2290'},
    {'id': 'p150',      'guests': 'До 150 гостей',  'price': '3890'},
    {'id': 'unlimited', 'guests': 'Больше 150',     'price': 'talk'},
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 1 && _nameCtrl.text.trim().isEmpty) return;
    if (_step < _totalSteps) {
      setState(() => _step++);
    } else {
      _create();
    }
  }

  void _back() {
    if (_step > 1) {
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  Future<void> _pickRevealAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 4)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 4))),
    );
    if (time == null || !mounted) return;
    final d = date.toLocal();
    final dt = DateTime(d.year, d.month, d.day, time.hour, time.minute);
    if (dt.isAfter(DateTime.now())) setState(() => _revealAt = dt);
  }

  Future<void> _pickStartAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(minutes: 5)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final d = date.toLocal();
    setState(() => _startAt = DateTime(d.year, d.month, d.day, time.hour, time.minute));
  }

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      final revealMode = _revealAt != null ? 'delayed' : 'instant';
      await ref.read(createEventProvider({
        'name': _nameCtrl.text.trim(),
        'event_type': _eventType,
        'frames_per_guest': _framesPerGuest,
        'reveal_mode': revealMode,
        if (_revealAt != null) 'reveal_at': _revealAt!.toUtc().toIso8601String(),
        if (_startAt != null) 'start_at': _startAt!.toUtc().toIso8601String(),
        'film': _film,
        'plan': _plan,
      }).future);
      if (mounted) {
        ref.invalidate(eventsProvider);
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractUserMessage(e), style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
            backgroundColor: AppColors.shutter,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
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
            _Topbar(step: _step, onBack: _back),
            _Stepper(current: _step, total: _totalSteps),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  children: [
                    _buildStep(),
                    _BottomCTA(
                      step: _step,
                      total: _totalSteps,
                      loading: _loading,
                      enabled: _step == 1 ? _nameCtrl.text.trim().isNotEmpty : true,
                      onNext: _next,
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

  Widget _buildStep() {
    return switch (_step) {
      1 => _Step1(
          nameCtrl: _nameCtrl,
          selectedType: _eventType,
          onTypeChanged: (t) => setState(() => _eventType = t),
          onNameChanged: (_) => setState(() {}),
        ),
      2 => _Step2(
          frames: _framesPerGuest,
          onFramesChanged: (v) => setState(() => _framesPerGuest = v),
        ),
      3 => _Step3(
          startAt: _startAt,
          onPickStart: _pickStartAt,
          onSkip: () => setState(() { _startAt = null; _step++; }),
        ),
      4 => _Step4Reveal(
          revealAt: _revealAt,
          onPickReveal: _pickRevealAt,
          onClearReveal: () => setState(() => _revealAt = null),
          onSkip: () => setState(() { _revealAt = null; _step++; }),
        ),
      5 => _Step5(
          films: _films,
          selected: _film,
          onChanged: (v) => setState(() => _film = v),
        ),
      6 => _Step6(
          plans: _plans,
          selected: _plan,
          onChanged: (v) => setState(() => _plan = v),
        ),
      _ => const SizedBox(),
    };
  }
}

// ─── Topbar ───────────────────────────────────────────────────────────────────

class _Topbar extends StatelessWidget {
  final int step;
  final VoidCallback onBack;
  const _Topbar({required this.step, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          _IcBtn(icon: Icons.chevron_left, onTap: onBack),
          const Expanded(
            child: Text(
              'НОВЫЙ АЛЬБОМ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                letterSpacing: 1.32,
                color: AppColors.ink3,
              ),
            ),
          ),
          _IcBtn(icon: Icons.close, onTap: () => context.go('/dashboard'), iconSize: 18),
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
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: AppColors.ink2, size: iconSize),
      ),
    );
  }
}

// ─── Stepper ──────────────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final int current;
  final int total;
  const _Stepper({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: List.generate(total, (i) {
          final isDone   = i + 1 < current;
          final isActive = i + 1 == current;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < total - 1 ? 5 : 0),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: isDone
                      ? AppColors.ink
                      : isActive
                          ? AppColors.ink.withValues(alpha: 0.6)
                          : const Color(0x1A1A1714),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Step 1: Название и тип ────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final TextEditingController nameCtrl;
  final String selectedType;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onNameChanged;

  const _Step1({
    required this.nameCtrl, required this.selectedType,
    required this.onTypeChanged, required this.onNameChanged,
  });

  static const _types = [
    {'id': 'wedding',    'label': 'Свадьба'},
    {'id': 'birthday',   'label': 'День\nрождения'},
    {'id': 'corporate',  'label': 'Корпоратив'},
    {'id': 'party',      'label': 'Вечеринка'},
    {'id': 'graduation', 'label': 'Выпускной'},
    {'id': 'travel',     'label': 'Путешествие'},
    {'id': 'vacation',   'label': 'Отпуск'},
    {'id': 'concert',    'label': 'Концерт'},
    {'id': 'other',      'label': 'Другое'},
  ];

  static IconData _iconFor(String id) => switch (id) {
    'wedding'    => Icons.favorite_border,
    'birthday'   => Icons.cake,
    'corporate'  => Icons.work_outline,
    'party'      => Icons.local_bar,
    'graduation' => Icons.school,
    'travel'     => Icons.flight,
    'vacation'   => Icons.beach_access,
    'concert'    => Icons.music_note,
    _            => Icons.auto_fix_high,
  };

  static Color _colorFor(String id) => switch (id) {
    'wedding'    => const Color(0xFFE8517A),
    'birthday'   => const Color(0xFFFF9B42),
    'corporate'  => const Color(0xFF5B9BD5),
    'party'      => const Color(0xFF9B59B6),
    'graduation' => const Color(0xFF4CAF79),
    'travel'     => const Color(0xFF26B9C4),
    'vacation'   => const Color(0xFFFFB347),
    'concert'    => const Color(0xFFE040FB),
    _            => AppColors.ink3,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker('ШАГ 1 · ОСНОВНОЕ'),
        _Title('Придумайте название\nдля события'),
        const _StepDesc('Название будет видно для всех гостей'),
        TextField(
          controller: nameCtrl,
          onChanged: onNameChanged,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 16, color: AppColors.ink),
          decoration: const InputDecoration(hintText: 'Например, Свадьба Ани и Миши'),
        ),
        const SizedBox(height: AppSpacing.s3),
        _StepSection('Тип события'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 72,
          ),
          itemCount: _types.length,
          itemBuilder: (ctx, i) {
            final t = _types[i];
            final active = t['id'] == selectedType;
            return GestureDetector(
              onTap: () => onTypeChanged(t['id']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: active ? AppColors.amber.withValues(alpha: 0.08) : AppColors.paper2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? AppColors.amber : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: active
                      ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.2), blurRadius: 8)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_iconFor(t['id']!), size: 22, color: _colorFor(t['id']!)),
                    const SizedBox(height: 6),
                    Text(
                      t['label']!,
                      style: TextStyle(
                        fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500,
                        color: active ? AppColors.ink : AppColors.ink2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.s4),
      ],
    );
  }
}

// ─── Step 2: Кадры ────────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  final int frames;
  final ValueChanged<int> onFramesChanged;

  const _Step2({required this.frames, required this.onFramesChanged});

  static const _frameValues = [6, 12, 18, 24, 30, 36, 42, 48];
  static const _thumbR = 7.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker('ШАГ 2 · КАДРЫ'),
        _Title('Длина плёнки\nкаждого гостя'),
        const _StepDesc('Как на одноразовой камере — больше кадров, больше воспоминаний'),

        _FilmFrameStrip(frames: frames, values: _frameValues),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          decoration: BoxDecoration(color: AppColors.paper2, borderRadius: AppRadius.lgBR),
          child: Column(
            children: [
              Text(
                '$frames',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 56,
                  fontWeight: FontWeight.w600, color: AppColors.amber,
                ),
              ),
              const Text(
                'кадров на гостя',
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3),
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: _thumbR),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: _thumbR),
                  activeTickMarkColor: Colors.transparent,
                  inactiveTickMarkColor: Colors.transparent,
                  activeTrackColor: AppColors.amber,
                  inactiveTrackColor: AppColors.paper3,
                  thumbColor: AppColors.amber,
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(
                  value: frames.toDouble(),
                  min: 6, max: 48,
                  divisions: 42,
                  onChanged: (v) => onFramesChanged(v.round()),
                ),
              ),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (ctx, constraints) => _FrameRuler(
                  totalWidth: constraints.maxWidth,
                  selected: frames,
                  values: _frameValues,
                  thumbRadius: _thumbR,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
      ],
    );
  }
}

// ─── Film frame strip visual ──────────────────────────────────────────────

class _FilmFrameStrip extends StatelessWidget {
  final int frames;
  final List<int> values;
  const _FilmFrameStrip({required this.frames, required this.values});

  static const _filmBg    = Color(0xFFDDD0B0);
  static const _lineColor = Color(0xFFC4A844);
  static const _holeColor = Color(0xFFF0E8D4);

  @override
  Widget build(BuildContext context) {
    final activeCount = values.where((v) => v <= frames).length;
    return Container(
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _filmBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _lineColor, width: 1),
      ),
      child: Stack(
        children: [
          // Sprocket holes top
          Positioned(
            top: 5, left: 0, right: 0,
            child: _SprocketRow(holeColor: _holeColor, lineColor: _lineColor),
          ),
          // Sprocket holes bottom
          Positioned(
            bottom: 5, left: 0, right: 0,
            child: _SprocketRow(holeColor: _holeColor, lineColor: _lineColor),
          ),
          // Frame cells
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
            child: Row(
              children: List.generate(values.length, (i) {
                final isActive = i < activeCount;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _lineColor.withValues(alpha: 0.55)
                            : const Color(0xFFB8AA8A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SprocketRow extends StatelessWidget {
  final Color holeColor;
  final Color lineColor;
  const _SprocketRow({required this.holeColor, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(14, (_) => Container(
        width: 7, height: 5,
        decoration: BoxDecoration(
          color: holeColor,
          borderRadius: BorderRadius.circular(1.5),
          border: Border.all(color: lineColor, width: 0.5),
        ),
      )),
    );
  }
}

// ─── Frame ruler (tick marks + labels) ───────────────────────────────────

class _FrameRuler extends StatelessWidget {
  final double totalWidth;
  final int selected;
  final List<int> values;
  final double thumbRadius;
  const _FrameRuler({
    required this.totalWidth, required this.selected,
    required this.values, required this.thumbRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: totalWidth,
      child: CustomPaint(
        painter: _FrameRulerPainter(
          selected: selected,
          values: values,
          thumbRadius: thumbRadius,
          activeColor: AppColors.amber,
          dimColor: AppColors.ink4,
        ),
      ),
    );
  }
}

class _FrameRulerPainter extends CustomPainter {
  final int selected;
  final List<int> values;
  final double thumbRadius;
  final Color activeColor;
  final Color dimColor;

  const _FrameRulerPainter({
    required this.selected, required this.values,
    required this.thumbRadius, required this.activeColor, required this.dimColor,
  });

  double _x(int v, double W) =>
      thumbRadius + (v - 6) / 42.0 * (W - 2 * thumbRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final minorPaint = Paint()..strokeWidth = 1.0..strokeCap = StrokeCap.round;
    final majorPaint = Paint()..strokeWidth = 1.5..strokeCap = StrokeCap.round;

    // Minor ticks at every integer between major values
    for (int v = 7; v <= 47; v++) {
      if (v % 6 == 0) continue;
      final x = _x(v, W);
      final isActive = v <= selected;
      minorPaint.color = isActive
          ? activeColor.withValues(alpha: 0.45)
          : dimColor.withValues(alpha: 0.35);
      canvas.drawLine(Offset(x, 0), Offset(x, 4), minorPaint);
    }

    // Major ticks + labels
    for (final v in values) {
      final x = _x(v, W);
      final isActive = v <= selected;
      final isSel = v == selected;

      majorPaint.color = isSel
          ? activeColor
          : isActive
              ? activeColor.withValues(alpha: 0.65)
              : dimColor.withValues(alpha: 0.55);
      canvas.drawLine(Offset(x, 0), Offset(x, 9), majorPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '$v',
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'JetBrains Mono',
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
            color: isSel
                ? activeColor
                : isActive
                    ? activeColor.withValues(alpha: 0.75)
                    : dimColor.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 13));
    }
  }

  @override
  bool shouldRepaint(covariant _FrameRulerPainter old) => old.selected != selected;
}

// ─── Step 3: Начало мероприятия ────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  final DateTime? startAt;
  final VoidCallback onPickStart;
  final VoidCallback onSkip;

  const _Step3({required this.startAt, required this.onPickStart, required this.onSkip});

  static String _formatDt(DateTime dt) {
    final months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    final m = months[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m · $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker('ШАГ 3 · НАЧАЛО'),
        _Title('Когда начинается\nмероприятие?'),
        const _StepDesc('Гости смогут снимать только с этого момента. Если не указать — доступ откроется сразу'),

        _MiniCalendar(selectedDate: startAt),
        const SizedBox(height: 12),

        if (startAt == null)
          GestureDetector(
            onTap: onPickStart,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s2),
              decoration: BoxDecoration(
                color: AppColors.paper2,
                borderRadius: AppRadius.mdBR,
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.event_outlined, color: AppColors.amber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Выбрать дату и время начала',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink2),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.ink4, size: 20),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: onPickStart,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s2),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.06),
                borderRadius: AppRadius.mdBR,
                border: Border.all(color: AppColors.amber, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.event, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Начало мероприятия', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
                        Text(
                          _formatDt(startAt!),
                          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: GestureDetector(
              onTap: onSkip,
              child: const Text(
                'Пропустить шаг',
                style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink3),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.s4),
      ],
    );
  }
}

// ─── Mini calendar widget ─────────────────────────────────────────────────

class _MiniCalendar extends StatelessWidget {
  final DateTime? selectedDate;
  const _MiniCalendar({this.selectedDate});

  static const _monthNames = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  static const _dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _redDate = Color(0xFFD54B3D);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final display = selectedDate ?? today;
    final year = display.year;
    final month = display.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startOffset = firstDay.weekday - 1; // 0 = Mon

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.lgBR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _monthNames[month],
                style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.ink),
              ),
              const Spacer(),
              if (selectedDate != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _redDate, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    '${selectedDate!.day} ${_monthNames[selectedDate!.month].substring(0, 3).toLowerCase()}',
                    style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '$year',
                style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: AppColors.ink3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: _dayNames.map((d) => Expanded(
              child: Center(
                child: Text(d, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppColors.ink4, fontWeight: FontWeight.w500)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 30,
            ),
            itemCount: startOffset + daysInMonth,
            itemBuilder: (ctx, i) {
              if (i < startOffset) return const SizedBox();
              final day = i - startOffset + 1;
              final date = DateTime(year, month, day);
              final isSel = selectedDate != null &&
                  date.day == selectedDate!.day &&
                  date.month == selectedDate!.month &&
                  date.year == selectedDate!.year;
              final isToday = date.day == today.day &&
                  date.month == today.month &&
                  date.year == today.year;
              final isSat = date.weekday == 6;
              final isSun = date.weekday == 7;

              return Center(
                child: Container(
                  width: 26, height: 26,
                  decoration: isSel
                      ? const BoxDecoration(color: _redDate, shape: BoxShape.circle)
                      : isToday
                          ? BoxDecoration(
                              border: Border.all(color: AppColors.amber, width: 1.5),
                              shape: BoxShape.circle,
                            )
                          : null,
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                        color: isSel
                            ? Colors.white
                            : isToday
                                ? AppColors.amber
                                : (isSat || isSun)
                                    ? _redDate.withValues(alpha: 0.55)
                                    : AppColors.ink2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Step 4: Дата проявки ─────────────────────────────────────────────────

class _Step4Reveal extends StatelessWidget {
  final DateTime? revealAt;
  final VoidCallback onPickReveal;
  final VoidCallback onClearReveal;
  final VoidCallback onSkip;

  const _Step4Reveal({
    required this.revealAt, required this.onPickReveal,
    required this.onClearReveal, required this.onSkip,
  });

  static String _formatDt(DateTime dt) {
    final months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    final m = months[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m · $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker('ШАГ 4 · ПРОЯВКА'),
        _Title('Когда проявится\nплёнка?'),
        const _StepDesc('Альбом с фото станет доступен после проявки. Выберите дату — или пропустите и проявите вручную'),

        const _RevealVisual(),
        const SizedBox(height: 12),

        if (revealAt == null)
          GestureDetector(
            onTap: onPickReveal,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s2),
              decoration: BoxDecoration(
                color: AppColors.paper2,
                borderRadius: AppRadius.mdBR,
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.timer_outlined, color: AppColors.amber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Выбрать дату и время проявки',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink2),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.ink4, size: 20),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: onPickReveal,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s2),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.06),
                borderRadius: AppRadius.mdBR,
                border: Border.all(color: AppColors.amber, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.timer, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Плёнка проявится', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
                        Text(
                          _formatDt(revealAt!),
                          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClearReveal,
                    child: const Icon(Icons.close, color: AppColors.ink4, size: 18),
                  ),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: GestureDetector(
              onTap: onSkip,
              child: const Text(
                'Пропустить шаг',
                style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink3),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.s4),
      ],
    );
  }
}

// ─── Step 5: Aesthetic / Плёнка ───────────────────────────────────────────

class _Step5 extends StatelessWidget {
  final List<Map<String, String>> films;
  final String selected;
  final ValueChanged<String> onChanged;
  const _Step5({required this.films, required this.selected, required this.onChanged});

  static String _photoUrl(String id) => switch (id) {
    'original'  => 'https://picsum.photos/seed/celebration99/300/300',
    'portra400' => 'https://picsum.photos/seed/wedding2024/300/300',
    'fuji400h'  => 'https://picsum.photos/seed/nature2024/300/300',
    'cinestill' => 'https://picsum.photos/seed/nightcity2024/300/300',
    'ilford'    => 'https://picsum.photos/seed/portrait2024/300/300',
    _           => 'https://picsum.photos/seed/event2024/300/300',
  };

  static List<double> _filmMatrix(String id) => switch (id) {
    'portra400' => [
      1.12,   0.08,  -0.05,  0,  0,
      0,      1.05,   0,     0,  0,
      0,     -0.05,   0.85,  0,  0,
      0,      0,      0,     1,  0,
    ],
    'fuji400h' => [
      0.88,   0,      0.05,  0,  0,
      0.04,   1.10,   0,     0,  0,
      0,      0.06,   0.98,  0,  0,
      0,      0,      0,     1,  0,
    ],
    'cinestill' => [
      1.18,   0.08,   0,     0,  0,
      0,      0.88,   0,     0,  0,
      0.10,   0,      0.80,  0,  0,
      0,      0,      0,     1,  0,
    ],
    'ilford' => [
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0,      0,      0,      1, 0,
    ],
    _ => [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker('ШАГ 5 · ЭСТЕТИКА'),
        _Title('Стиль плёнки'),
        const _StepDesc('Все фото гостей пройдут через один фильтр — выбирайте под настроение мероприятия'),
        ...films.map((f) {
          final active = f['id'] == selected;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s1),
            child: GestureDetector(
              onTap: () => onChanged(f['id']!),
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  color: active ? AppColors.amber.withValues(alpha: 0.06) : AppColors.paper2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? AppColors.amber : AppColors.line,
                    width: active ? 2 : 1,
                    strokeAlign: BorderSide.strokeAlignCenter,
                  ),
                  boxShadow: active
                      ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.18), blurRadius: 12)]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 90,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(_filmMatrix(f['id']!)),
                          child: Image.network(
                            _photoUrl(f['id']!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: _filmGradFallback(f['id']!),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(f['name']!, style: GoogleFonts.playfairDisplay(
                                fontSize: 17, fontWeight: FontWeight.w700,
                                color: active ? AppColors.ink : AppColors.ink2, height: 1.15,
                              )),
                              const SizedBox(height: 5),
                              Text(f['desc']!, style: const TextStyle(
                                fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3, height: 1.4,
                              )),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Center(
                          child: Icon(
                            Icons.check_circle,
                            color: active ? AppColors.amber : Colors.transparent,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.s4),
      ],
    );
  }

  List<Color> _filmGradFallback(String id) => switch (id) {
    'original'  => const [Color(0xFFF8F5F0), Color(0xFFD4C8B8), Color(0xFF8A7D6A)],
    'portra400' => const [Color(0xFFF0D4A0), Color(0xFFB07840), Color(0xFF5A2A0A)],
    'fuji400h'  => const [Color(0xFFC8E0C0), Color(0xFF608060), Color(0xFF1A3020)],
    'cinestill' => const [Color(0xFF301020), Color(0xFF8A2040), Color(0xFFF04060)],
    'ilford'    => const [Color(0xFFB0A8A0), Color(0xFF505050), Color(0xFF101010)],
    _           => [AppColors.paper3, AppColors.ink4],
  };
}

// ─── Step 6: Тарифы ───────────────────────────────────────────────────────

class _Step6 extends StatelessWidget {
  final List<Map<String, String>> plans;
  final String selected;
  final ValueChanged<String> onChanged;
  const _Step6({required this.plans, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker('ШАГ 6 · ТАРИФНЫЙ ПЛАН'),
        _Title('Выберите план'),
        const _StepDesc('Одна цена за всё событие. Гости не платят ничего — только организатор'),
        ...plans.map((p) {
          final active = p['id'] == selected;
          final isHit  = p['hit'] == 'true';
          final isTalk = p['price'] == 'talk';
          final isFree = p['price'] == '0';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onChanged(p['id']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: active ? AppColors.amber.withValues(alpha: 0.06) : AppColors.paper,
                  borderRadius: AppRadius.mdBR,
                  border: Border.all(color: active ? AppColors.amber : AppColors.line, width: active ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            p['guests']!,
                            style: TextStyle(
                              fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                              color: active ? AppColors.ink : AppColors.ink2,
                            ),
                          ),
                          if (isHit) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.amber, borderRadius: AppRadius.pillBR),
                              child: const Text('ХИТ', style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isFree ? 'Бесплатно' : isTalk ? 'По запросу' : '${p['price']} ₽',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono', fontSize: 15, fontWeight: FontWeight.w600,
                            color: active ? AppColors.amber : AppColors.ink2,
                          ),
                        ),
                        if (!isFree && !isTalk)
                          const Text('за ивент', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.ink4)),
                      ],
                    ),
                    if (active) ...[const SizedBox(width: 10), const Icon(Icons.check_circle, color: AppColors.amber, size: 20)],
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.s4),
      ],
    );
  }
}

// ─── Bottom CTA ───────────────────────────────────────────────────────────

class _BottomCTA extends StatelessWidget {
  final int step;
  final int total;
  final bool loading, enabled;
  final VoidCallback onNext;
  const _BottomCTA({required this.step, required this.total, required this.loading, required this.enabled, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled && !loading ? onNext : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: AppSizes.buttonHeight,
        decoration: BoxDecoration(
          color: enabled ? AppColors.amber : AppColors.paper3,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.42), blurRadius: 20, offset: const Offset(0, 6), spreadRadius: -4)]
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(
                  step < total ? 'Дальше →' : 'Создать альбом',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
        ),
      ),
    );
  }
}

// ─── Вспомогательные виджеты ──────────────────────────────────────────────

class _StepSection extends StatelessWidget {
  final String text;
  const _StepSection(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
  );
}

class _Kicker extends StatelessWidget {
  final String text;
  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(
      fontFamily: 'JetBrains Mono', fontSize: 11, letterSpacing: 0.18,
      color: AppColors.amber, fontWeight: FontWeight.w500,
    )),
  );
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Text(text, style: GoogleFonts.playfairDisplay(
      fontWeight: FontWeight.w500,
      fontSize: 30, height: 1.05, letterSpacing: -0.6, color: AppColors.ink,
    )),
  );
}

class _StepDesc extends StatelessWidget {
  final String text;
  const _StepDesc(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 20),
    child: Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink3, height: 1.45)),
  );
}

// ─── Reveal visual: фото на верёвочке ────────────────────────────────────

class _RevealVisual extends StatelessWidget {
  const _RevealVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.lgBR,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Верёвочка
          Positioned(
            top: 20, left: 0, right: 0,
            child: Container(height: 1, color: AppColors.ink3.withValues(alpha: 0.35)),
          ),
          // Фото
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _HangingPhoto(rotation: -0.07, opacity: 0.30),
              _HangingPhoto(rotation: 0.04,  opacity: 0.55),
              _HangingPhoto(rotation: -0.03, opacity: 1.00, revealed: true),
              _HangingPhoto(rotation: 0.05,  opacity: 0.60),
              _HangingPhoto(rotation: -0.05, opacity: 0.30),
            ],
          ),
        ],
      ),
    );
  }
}

class _HangingPhoto extends StatelessWidget {
  final double rotation;
  final double opacity;
  final bool revealed;
  const _HangingPhoto({required this.rotation, required this.opacity, this.revealed = false});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 1.5, height: 10, color: AppColors.ink3.withValues(alpha: 0.45)),
          Opacity(
            opacity: opacity,
            child: Container(
              width: 42, height: 52,
              decoration: BoxDecoration(
                color: revealed ? const Color(0xFFDDD0B0) : AppColors.paper3,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppColors.line, width: 1),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: revealed
                  ? Center(
                      child: Icon(Icons.favorite_rounded, color: AppColors.amber.withValues(alpha: 0.7), size: 18),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

