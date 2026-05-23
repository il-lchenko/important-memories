import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return eventAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.paper,
        body: const Center(child: CircularProgressIndicator(color: AppColors.amber)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.ink3, size: 40),
              const SizedBox(height: 12),
              Text('Ошибка загрузки', style: const TextStyle(fontFamily: 'Inter', color: AppColors.ink2)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => ref.invalidate(eventDetailProvider(eventId)),
                child: const Text('Повторить', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber)),
              ),
            ],
          ),
        ),
      ),
      data: (event) => Scaffold(
        backgroundColor: AppColors.paper,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverSection(event: event),
              _MetricsRow(event: event),
              _ActionList(eventId: eventId, event: event),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

String _formatDate(String isoStr) {
  try {
    final dt = DateTime.parse(isoStr).toLocal();
    return DateFormat('dd·MM·yy').format(dt);
  } catch (_) {
    return '—';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'active': return 'ИДЁТ';
    case 'completed': return 'ЗАВЕРШЁН';
    case 'draft': return 'ЧЕРНОВИК';
    case 'cancelled': return 'ОТМЕНЁН';
    default: return status.toUpperCase();
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'active': return AppColors.shutter;
    case 'completed': return AppColors.success;
    case 'draft': return AppColors.amber;
    default: return AppColors.ink3;
  }
}

String _planLabel(String? plan) {
  switch (plan) {
    case 'free': return 'FREE';
    case 'p50': return 'СТАНДАРТ';
    case 'p150': return 'ПРО';
    case 'unlimited': return 'UNLIM';
    default: return (plan ?? 'free').toUpperCase();
  }
}

String _filmLabel(String? lut) {
  switch (lut) {
    case 'portra400': return 'PORTRA 400';
    case 'fuji400h': return 'FUJI 400H';
    case 'cinestill': return 'CINESTILL';
    case 'ilford': return 'ILFORD';
    case 'original': return 'БЕЗ ФИЛЬТРА';
    default: return (lut ?? 'PORTRA 400').toUpperCase();
  }
}

// ─── cover ───────────────────────────────────────────────────────────────────

class _CoverSection extends StatelessWidget {
  final Map<String, dynamic> event;
  const _CoverSection({required this.event});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final coverUrl = event['cover_url'] as String?;
    final title = event['title'] as String? ?? '—';
    final status = event['status'] as String? ?? 'draft';
    final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
    final lut = settings['lut_preset'] as String?;
    final startAt = event['start_at'] as String? ?? '';
    final endAt = event['end_at'] as String? ?? '';

    return SizedBox(
      height: 280 + topPad,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover image or gradient fallback
          if (coverUrl != null)
            Image.network(coverUrl, fit: BoxFit.cover)
          else ...[
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [Color(0xFFF3CDA0), Color(0xFFC97E4A), Color(0xFF6A3520), Color(0xFF1F1208)],
                  stops: [0.0, 0.5, 0.9, 1.0],
                ),
              ),
            ),
            Positioned(
              left: MediaQuery.of(context).size.width * 0.38,
              top: (280 + topPad) * 0.30,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.24,
                height: (280 + topPad) * 0.55,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(colors: [Color(0xB2F5E1C3), Colors.transparent]),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-1, -1), radius: 0.8,
                  colors: [Color(0x8CFFB347), Colors.transparent],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1, 1), radius: 0.8,
                  colors: [Color(0x8CD54B3D), Colors.transparent],
                ),
              ),
            ),
          ],
          // Vignette
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(radius: 1.1, colors: [Colors.transparent, Color(0x8C000000)]),
            ),
          ),
          // Dark gradient from bottom
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x99000000)],
                stops: [0.4, 1.0],
              ),
            ),
          ),
          // Glass buttons
          Positioned(
            top: topPad + 16, left: 16, right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlassBtn(icon: Icons.chevron_left, size: 22, onTap: () => context.pop()),
                _GlassBtn(icon: Icons.more_horiz, size: 20, onTap: () {}),
              ],
            ),
          ),
          // Title overlay
          Positioned(
            bottom: 18, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor(status)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _statusLabel(status),
                        style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 10,
                          fontWeight: FontWeight.w600, letterSpacing: 1.4, color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: GoogleFonts.fraunces(
                    fontSize: 30, fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500, letterSpacing: -0.6,
                    height: 1.05, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatDate(startAt)} — ${_formatDate(endAt)} · ${_filmLabel(lut)}',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 12,
                    letterSpacing: 0.96, color: Color(0xD9F6F2E8),
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

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _GlassBtn({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.25)),
        child: Icon(icon, color: AppColors.paper, size: size),
      ),
    );
  }
}

// ─── metrics ──────────────────────────────────────────────────────────────────

class _MetricsRow extends StatelessWidget {
  final Map<String, dynamic> event;
  const _MetricsRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
    final maxGuests = settings['max_guests'] as int? ?? 0;
    final framesPerGuest = settings['frames_per_guest'] as int? ?? 0;
    final plan = _planLabel(settings['plan'] as String? ?? 'free');

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _Metric(value: '$maxGuests', label: 'ГОСТЕЙ МАК')),
            const VerticalDivider(width: 1, color: AppColors.line),
            Expanded(child: _Metric(value: '$framesPerGuest', label: 'КАД/ГОСТЬ')),
            const VerticalDivider(width: 1, color: AppColors.line),
            Expanded(child: _Metric(value: plan, label: 'ПЛАН')),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono', fontSize: 22,
              fontWeight: FontWeight.w500, color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono', fontSize: 10,
              letterSpacing: 1.2, color: AppColors.ink3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── action list ──────────────────────────────────────────────────────────────

class _ActionList extends ConsumerWidget {
  final String eventId;
  final Map<String, dynamic> event;
  const _ActionList({required this.eventId, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = event['status'] as String? ?? 'draft';
    final settings = (event['settings'] as Map<String, dynamic>?) ?? {};

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.qr_code_rounded,
            title: 'QR для стенда',
            meta: 'Раскрыть на весь экран',
            onTap: () => context.push('/events/$eventId/qr'),
          ),
          _ActionRow(
            icon: Icons.people_outline,
            title: 'Гости',
            meta: 'Live-прогресс',
            onTap: () => context.push('/events/$eventId/progress'),
          ),
          _ActionRow(
            icon: Icons.photo_library_outlined,
            title: 'Альбом',
            meta: 'Открыть',
            onTap: () => context.push('/events/$eventId/album'),
          ),
          if (status == 'active')
            _ActionRow(
              icon: Icons.lock_open_outlined,
              title: 'Проявка',
              meta: _revealMeta(settings),
              onTap: () => _showRevealSheet(context, eventId, settings),
              isLast: true,
            ),
          if (status == 'draft')
            _DevActivateRow(eventId: eventId, ref: ref),
        ],
      ),
    );
  }
}

class _DevActivateRow extends StatefulWidget {
  final String eventId;
  final WidgetRef ref;
  const _DevActivateRow({required this.eventId, required this.ref});

  @override
  State<_DevActivateRow> createState() => _DevActivateRowState();
}

class _DevActivateRowState extends State<_DevActivateRow> {
  bool _loading = false;

  Future<void> _activate() async {
    setState(() => _loading = true);
    try {
      final dio = widget.ref.read(dioProvider);
      await dio.post('events/${widget.eventId}/activate');
      widget.ref.invalidate(eventDetailProvider(widget.eventId));
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
    return GestureDetector(
      onTap: _loading ? null : _activate,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                    )
                  : const Icon(Icons.play_circle_outline, color: AppColors.amber, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DEV: Активировать', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.amber)),
                  SizedBox(height: 2),
                  Text('Без оплаты — только для теста', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.amber),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final bool isLast;

  const _ActionRow({
    required this.icon, required this.title,
    required this.meta, required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: isLast
            ? null
            : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.ink, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(meta, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.ink4, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── reveal helpers ───────────────────────────────────────────────────────────

String _revealMeta(Map<String, dynamic> settings) {
  final revealMode = settings['reveal_mode'] as String? ?? 'instant';
  final revealAt = settings['reveal_at'] as String?;
  if (revealMode == 'instant') return 'Мгновенная проявка';
  if (revealAt != null) {
    try {
      final dt = DateTime.parse(revealAt).toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final y = (dt.year % 100).toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$d.$mo.$y в $h:$mi';
    } catch (_) {}
  }
  return 'Не настроено';
}

void _showRevealSheet(BuildContext context, String eventId, Map<String, dynamic> settings) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _RevealSheet(eventId: eventId, settings: settings),
  );
}

class _RevealSheet extends ConsumerStatefulWidget {
  final String eventId;
  final Map<String, dynamic> settings;
  const _RevealSheet({required this.eventId, required this.settings});

  @override
  ConsumerState<_RevealSheet> createState() => _RevealSheetState();
}

class _RevealSheetState extends ConsumerState<_RevealSheet> {
  bool _revealing = false;
  bool _scheduling = false;
  String? _error;

  Future<void> _revealNow() async {
    setState(() { _revealing = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      await dio.post('events/${widget.eventId}/reveal');
      ref.invalidate(eventDetailProvider(widget.eventId));
      if (mounted) {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.push('/events/${widget.eventId}/album');
      }
    } catch (e) {
      if (mounted) setState(() => _error = extractUserMessage(e));
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  Future<void> _scheduleReveal() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null || !mounted) return;
    final d = date.toLocal();
    final revealAt = DateTime(d.year, d.month, d.day, time.hour, time.minute);
    if (!revealAt.isAfter(DateTime.now())) {
      setState(() => _error = 'Выберите время в будущем');
      return;
    }
    setState(() { _scheduling = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}/settings', data: {
        'reveal_mode': 'delayed',
        'reveal_at': revealAt.toUtc().toIso8601String(),
      });
      ref.invalidate(eventDetailProvider(widget.eventId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = extractUserMessage(e));
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final revealAt = widget.settings['reveal_at'] as String?;
    String? scheduledLabel;
    if (revealAt != null) {
      try {
        final dt = DateTime.parse(revealAt).toLocal();
        final d = dt.day.toString().padLeft(2, '0');
        final mo = dt.month.toString().padLeft(2, '0');
        final y = (dt.year % 100).toString().padLeft(2, '0');
        final h = dt.hour.toString().padLeft(2, '0');
        final mi = dt.minute.toString().padLeft(2, '0');
        scheduledLabel = '$d.$mo.$y в $h:$mi';
      } catch (_) {}
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(
            'Проявка альбома',
            style: GoogleFonts.fraunces(
              fontSize: 22, fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500, color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            scheduledLabel != null ? 'Запланировано на $scheduledLabel' : 'Выберите способ проявки',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3),
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.shutter),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _revealing ? null : _revealNow,
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: _revealing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Проявить сейчас', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _scheduling ? null : _scheduleReveal,
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(
                color: AppColors.paper2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              alignment: Alignment.center,
              child: _scheduling
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber))
                  : Text(
                      scheduledLabel != null ? 'Изменить дату и время' : 'Назначить дату и время',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
