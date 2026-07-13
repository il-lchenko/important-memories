import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';
import '../events_provider.dart';

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
              _CoverSection(eventId: eventId, event: event),
              _MetricsRow(eventId: eventId, event: event),
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

String _filmShortLabel(String? lut) {
  switch (lut) {
    case 'portra400': return 'P400';
    case 'fuji400h': return 'F400H';
    case 'cinestill': return 'CST';
    case 'ilford': return 'B&W';
    case 'original': return 'RAW';
    default: return 'P400';
  }
}

IconData _eventTypeIcon(String? type) => switch (type) {
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

// ─── cover ───────────────────────────────────────────────────────────────────

class _CoverSection extends ConsumerStatefulWidget {
  final String eventId;
  final Map<String, dynamic> event;
  const _CoverSection({required this.eventId, required this.event});

  @override
  ConsumerState<_CoverSection> createState() => _CoverSectionState();
}

class _CoverSectionState extends ConsumerState<_CoverSection> {
  bool _uploadingCover = false;

  void _shareAlbum() {
    final shortCode = widget.event['short_code'] as String? ?? '';
    if (shortCode.isEmpty) return;
    const guestBase = String.fromEnvironment('GUEST_PWA_URL', defaultValue: 'https://impomento.pro');
    final title = widget.event['title'] as String? ?? 'Альбом';
    Share.share('Посмотри наш альбом «$title»!\n$guestBase/g/$shortCode', subject: title);
  }

  Future<void> _uploadCover() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      final bytes = await file.readAsBytes();
      final dio = ref.read(dioProvider);
      final formData = dio_pkg.FormData.fromMap({
        'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: 'cover.jpg'),
      });
      await dio.post('events/${widget.eventId}/cover', data: formData);
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final coverUrl = widget.event['cover_url'] as String?;
    final title = widget.event['title'] as String? ?? '—';
    final status = widget.event['status'] as String? ?? 'draft';
    final eventType = widget.event['event_type'] as String? ?? 'other';
    final startAt = widget.event['start_at'] as String? ?? '';
    final endAt = widget.event['end_at'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Rounded cover card ──────────────────────────────────────────────
        Container(
          margin: EdgeInsets.fromLTRB(16, topPad + 10, 16, 0),
          height: 210,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl != null)
                  CachedNetworkImage(imageUrl: coverUrl, cacheKey: Uri.parse(coverUrl).path, fit: BoxFit.cover, fadeInDuration: Duration.zero)
                else ...[
                  Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.2), radius: 1.1,
                        colors: [Color(0xFFF3CDA0), Color(0xFFC97E4A), Color(0xFF6A3520), Color(0xFF1F1208)],
                        stops: [0.0, 0.5, 0.9, 1.0],
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
                    gradient: RadialGradient(radius: 1.1, colors: [Colors.transparent, Color(0x70000000)]),
                  ),
                ),
                // Bottom gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x88000000)],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
                // Top bar: back | spacer | share | upload
                Positioned(
                  top: 12, left: 12, right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _GlassBtn(icon: Icons.chevron_left, size: 22, onTap: () => context.pop()),
                      Row(
                        children: [
                          _GlassBtn(icon: Icons.ios_share, size: 20, onTap: _shareAlbum),
                          const SizedBox(width: 8),
                          _GlassBtn(
                            icon: _uploadingCover ? Icons.hourglass_bottom : Icons.add_photo_alternate_outlined,
                            size: 20,
                            onTap: _uploadingCover ? () {} : _uploadCover,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status badge (bottom-left of cover)
                Positioned(
                  bottom: 14, left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
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
                ),
                // Event type icon (bottom-right of cover)
                Positioned(
                  bottom: 14, right: 14,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.32),
                    ),
                    child: Icon(_eventTypeIcon(eventType), color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Info section below cover ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                  fontSize: 28, fontWeight: FontWeight.w500, letterSpacing: -0.5,
                  height: 1.1, color: AppColors.ink,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatDate(startAt)} — ${_formatDate(endAt)}',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 11,
                  letterSpacing: 0.8, color: AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── settings sheet ───────────────────────────────────────────────────────────

List<double> _filmMatrixForSettings(String id) => switch (id) {
  'portra400' => [1.12, 0.08, -0.05, 0, 0, 0, 1.05, 0, 0, 0, 0, -0.05, 0.85, 0, 0, 0, 0, 0, 1, 0],
  'fuji400h'  => [0.88, 0, 0.05, 0, 0, 0.04, 1.10, 0, 0, 0, 0, 0.06, 0.98, 0, 0, 0, 0, 0, 1, 0],
  'cinestill' => [1.18, 0.08, 0, 0, 0, 0, 0.88, 0, 0, 0, 0.10, 0, 0.80, 0, 0, 0, 0, 0, 1, 0],
  'ilford'    => [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0],
  _           => [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],
};

class _SettingsSheet extends ConsumerStatefulWidget {
  final String eventId;
  final Map<String, dynamic> event;
  const _SettingsSheet({required this.eventId, required this.event});

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  bool _deleting = false;

  String get _eventStatus => widget.event['status'] as String? ?? '';
  String get _currentTitle => widget.event['title'] as String? ?? '';
  bool get _isDraft => _eventStatus == 'draft';

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('Переименовать', style: GoogleFonts.ptSerif(fontSize: 20, color: AppColors.ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'Inter', color: AppColors.ink),
          decoration: const InputDecoration(border: UnderlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Сохранить', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber))),
        ],
      ),
    );
    ctrl.dispose();
    if (newTitle == null || newTitle.isEmpty || !mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}', data: {'title': newTitle});
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  Future<void> _editEventType() async {
    const types = [
      {'id': 'wedding',    'label': 'Свадьба',       'icon': Icons.favorite_border},
      {'id': 'birthday',   'label': 'День рождения', 'icon': Icons.cake},
      {'id': 'corporate',  'label': 'Корпоратив',    'icon': Icons.work_outline},
      {'id': 'party',      'label': 'Вечеринка',     'icon': Icons.local_bar},
      {'id': 'graduation', 'label': 'Выпускной',     'icon': Icons.school},
      {'id': 'travel',     'label': 'Путешествие',   'icon': Icons.flight},
      {'id': 'vacation',   'label': 'Отпуск',        'icon': Icons.beach_access},
      {'id': 'concert',    'label': 'Концерт',       'icon': Icons.music_note},
      {'id': 'other',      'label': 'Другое',        'icon': Icons.auto_fix_high},
    ];
    final current = widget.event['event_type'] as String? ?? 'other';
    String selected = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Тип события', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppColors.ink)),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.2,
              children: types.map((t) {
                final active = (t['id'] as String) == selected;
                return GestureDetector(
                  onTap: () => setD(() => selected = t['id'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: active ? AppColors.amber.withValues(alpha: 0.08) : AppColors.paper2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: active ? AppColors.amber : Colors.transparent, width: 1.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t['icon'] as IconData, size: 20, color: AppColors.ink2),
                        const SizedBox(height: 4),
                        Text(t['label'] as String, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: active ? AppColors.ink : AppColors.ink2), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Сохранить', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber))),
          ],
        ),
      ),
    );
    if (ok != true || selected == current || !mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}', data: {'event_type': selected});
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  Future<void> _editFilm() async {
    const films = [
      {'id': 'original',  'name': 'Без фильтра',      'desc': 'Фото как снято · Без обработки'},
      {'id': 'portra400', 'name': 'Kodak Portra 400', 'desc': 'Тёплые телесные тона · Лучше всего для свадеб'},
      {'id': 'fuji400h',  'name': 'Fuji 400H',        'desc': 'Холодные пастельные зелёные · Природа и портреты'},
      {'id': 'cinestill', 'name': 'Cinestill 800T',   'desc': 'Неоновые красные · Ночные и городские сцены'},
      {'id': 'ilford',    'name': 'Ilford HP5+',      'desc': 'Ч/Б · Классика документальной съёмки'},
    ];
    final settings = (widget.event['settings'] as Map<String, dynamic>?) ?? {};
    final current = settings['lut_preset'] as String? ?? 'portra400';
    String selected = current;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => Dialog(
          backgroundColor: AppColors.paper,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 48),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 16),
                    child: Text('Стиль плёнки', style: GoogleFonts.ptSerif(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: films.map((f) {
                          final active = f['id'] == selected;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () => setD(() => selected = f['id']!),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                height: 116,
                                decoration: BoxDecoration(
                                  color: active ? AppColors.amber.withValues(alpha: 0.06) : AppColors.paper2,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: active ? AppColors.amber : AppColors.line, width: active ? 2 : 1),
                                  boxShadow: active ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.15), blurRadius: 12)] : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: 96,
                                        child: ColorFiltered(
                                          colorFilter: ColorFilter.matrix(_filmMatrixForSettings(f['id']!)),
                                          child: CachedNetworkImage(
                                            imageUrl: _filmPhotoUrl(f['id']!),
                                            fit: BoxFit.cover,
                                            fadeInDuration: Duration.zero,
                                            errorWidget: (_, __, ___) => Container(color: AppColors.paper3),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(f['name']!, style: GoogleFonts.ptSerif(fontSize: 17, fontWeight: FontWeight.w700, color: active ? AppColors.ink : AppColors.ink2, height: 1.2)),
                                              const SizedBox(height: 6),
                                              Text(f['desc']!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3, height: 1.45)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12),
                                        child: Center(child: Icon(Icons.check_circle, color: active ? AppColors.amber : Colors.transparent, size: 18)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3))),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Сохранить', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.amber))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok != true || selected == current || !mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}/settings', data: {'lut_preset': selected});
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  Future<void> _editFrames() async {
    final settings = (widget.event['settings'] as Map<String, dynamic>?) ?? {};
    int frames = settings['frames_per_guest'] as int? ?? 24;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          backgroundColor: AppColors.paper,
          title: const Text('Кадров на гостя', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$frames', style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 48, fontWeight: FontWeight.w600, color: AppColors.amber)),
              Slider(value: frames.toDouble(), min: 6, max: 48, activeColor: AppColors.amber, inactiveColor: AppColors.paper3, onChanged: (v) => setD(() => frames = v.round())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Сохранить', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}/settings', data: {'frames_per_guest': frames});
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  Future<void> _editEventDates() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: now.subtract(const Duration(minutes: 5)), lastDate: now.add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null || !mounted) return;
    final d = date.toLocal();
    final startAt = DateTime(d.year, d.month, d.day, time.hour, time.minute);

    DateTime? endAt;
    final addEnd = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Дата окончания', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppColors.ink)),
        content: const Text('Добавить дату и время окончания?', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink2)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Пропустить', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Добавить', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber))),
        ],
      ),
    );
    if (addEnd == true && mounted) {
      final endDate = await showDatePicker(context: context, initialDate: startAt.add(const Duration(hours: 4)), firstDate: startAt, lastDate: startAt.add(const Duration(days: 7)));
      if (endDate != null && mounted) {
        final endTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(startAt.add(const Duration(hours: 4))));
        if (endTime != null && mounted) {
          final ed = endDate.toLocal();
          endAt = DateTime(ed.year, ed.month, ed.day, endTime.hour, endTime.minute);
        }
      }
    }
    if (!mounted) return;
    try {
      final dio = ref.read(dioProvider);
      final data = <String, dynamic>{'start_at': startAt.toUtc().toIso8601String()};
      if (endAt != null) data['end_at'] = endAt.toUtc().toIso8601String();
      await dio.patch('events/${widget.eventId}', data: data);
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
      if (mounted) {
        final d2 = startAt.day.toString().padLeft(2, '0');
        final mo2 = startAt.month.toString().padLeft(2, '0');
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('✓ Дата события: $d2.$mo2.${startAt.year}'), backgroundColor: AppColors.amber),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  Future<void> _editRevealTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now.add(const Duration(minutes: 5)), firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))));
    if (time == null || !mounted) return;
    final d = date.toLocal();
    final revealAt = DateTime(d.year, d.month, d.day, time.hour, time.minute);
    if (!revealAt.isAfter(DateTime.now())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите время в будущем')));
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}/settings', data: {'reveal_mode': 'delayed', 'reveal_at': revealAt.toUtc().toIso8601String()});
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
      if (mounted) {
        final h = revealAt.hour.toString().padLeft(2, '0');
        final mi = revealAt.minute.toString().padLeft(2, '0');
        final d2 = revealAt.day.toString().padLeft(2, '0');
        final mo2 = revealAt.month.toString().padLeft(2, '0');
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('✓ Открытие назначено на $d2.$mo2 в $h:$mi'), backgroundColor: AppColors.amber),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Удалить событие?', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppColors.ink)),
        content: const Text('Событие будет отменено. Фото останутся в базе до автоочистки', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink2)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Удалить', style: TextStyle(fontFamily: 'Inter', color: AppColors.shutter))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('events/${widget.eventId}');
      ref.invalidate(eventsProvider);
      if (mounted) {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go('/dashboard');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = (widget.event['settings'] as Map<String, dynamic>?) ?? {};
    final lut = settings['lut_preset'] as String? ?? 'portra400';
    final startAtStr = widget.event['start_at'] as String? ?? '';
    final endAtStr = widget.event['end_at'] as String? ?? '';
    String dateHint = 'Не задано';
    if (startAtStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(startAtStr).toLocal();
        dateHint = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${(dt.year % 100).toString().padLeft(2, '0')} в ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    if (endAtStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(endAtStr).toLocal();
        final end = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        dateHint = '$dateHint → $end';
      } catch (_) {}
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              Text('Настройки', style: GoogleFonts.ptSerif(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
            ]),
          ),
          const Divider(color: AppColors.line, height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SheetAction(icon: Icons.edit_outlined, label: 'Переименовать альбом', onTap: _rename),
                  _SheetAction(icon: Icons.category_outlined, label: 'Тип события', onTap: _editEventType),
                  _SheetAction(icon: Icons.photo_filter_outlined, label: 'Стиль плёнки', hint: _filmLabel(lut), onTap: _editFilm),
                  if (_isDraft) ...[
                    _SheetAction(icon: Icons.filter_frames_outlined, label: 'Кадров на гостя', hint: 'Только до активации', onTap: _editFrames),
                    _SheetAction(icon: Icons.calendar_today_outlined, label: 'Даты события', hint: dateHint, onTap: _editEventDates),
                  ],
                  _SheetAction(icon: Icons.timer_outlined, label: 'Время открытия альбома', hint: _revealMeta(settings), onTap: _editRevealTime),
                  const Divider(color: AppColors.line, height: 24),
                  _SheetAction(
                    icon: _deleting ? Icons.hourglass_bottom_outlined : Icons.delete_outline,
                    label: 'Удалить событие',
                    color: AppColors.shutter,
                    onTap: _deleting || _eventStatus == 'active' ? null : _delete,
                    hint: _eventStatus == 'active' ? 'Сначала завершите событие' : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── download row ─────────────────────────────────────────────────────────────

class _DownloadRow extends ConsumerStatefulWidget {
  final String eventId;
  const _DownloadRow({required this.eventId});

  @override
  ConsumerState<_DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends ConsumerState<_DownloadRow> {
  bool _loading = false;

  Future<void> _download() async {
    if (_loading) return;
    setState(() => _loading = true);
    String? finalStatus;
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post('events/${widget.eventId}/download');
      final jobId = res.data['job_id'] as String;
      String? downloadUrl;
      // Large albums can take a while — poll up to ~3 minutes.
      for (int i = 0; i < 90; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final poll = await dio.get('events/${widget.eventId}/download/$jobId');
        final s = poll.data['status'] as String?;
        finalStatus = s;
        if (s == 'ready' || s == 'empty' || s == 'failed') {
          downloadUrl = poll.data['download_url'] as String?;
          break;
        }
      }
      if (!mounted) return;
      if (downloadUrl != null) {
        final tempDir = await getTemporaryDirectory();
        final zipPath = '${tempDir.path}/im_album.zip';
        await dio_pkg.Dio().download(downloadUrl, zipPath);
        if (!mounted) return;
        await Share.shareXFiles([XFile(zipPath, mimeType: 'application/zip')], subject: 'Important Memories — архив фото');
      } else {
        final msg = finalStatus == 'empty'
            ? 'В альбоме ещё нет фото'
            : finalStatus == 'failed'
                ? 'Не удалось собрать архив — попробуйте позже'
                : finalStatus == 'pending' || finalStatus == null
                    ? 'Архив ещё собирается. Подождите и попробуйте снова.'
                    : 'Архив недоступен (status: $finalStatus)';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      icon: _loading ? Icons.hourglass_bottom_outlined : Icons.download_outlined,
      title: _loading ? 'Собирается архив...' : 'Скачать все фото',
      meta: 'ZIP архив всего альбома',
      onTap: _download,
    );
  }
}

String _filmPhotoUrl(String id) => switch (id) {
  'original'  => 'https://picsum.photos/seed/celebration99/300/300',
  'portra400' => 'https://picsum.photos/seed/wedding2024/300/300',
  'fuji400h'  => 'https://picsum.photos/seed/nature2024/300/300',
  'cinestill' => 'https://picsum.photos/seed/nightcity2024/300/300',
  'ilford'    => 'https://picsum.photos/seed/portrait2024/300/300',
  _           => 'https://picsum.photos/seed/event2024/300/300',
};

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final String? hint;
  const _SheetAction({required this.icon, required this.label, this.color, this.onTap, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? AppColors.ink4 : (color ?? AppColors.ink);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500, color: c)),
                  if (hint != null)
                    Text(hint!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
                ],
              ),
            ),
          ],
        ),
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
  final String eventId;
  final Map<String, dynamic> event;
  const _MetricsRow({required this.eventId, required this.event});

  @override
  Widget build(BuildContext context) {
    final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
    final maxGuests = settings['max_guests'] as int? ?? 0;
    final framesPerGuest = settings['frames_per_guest'] as int? ?? 0;
    final lut = settings['lut_preset'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.6), width: 1.4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _MetricItem(value: '$framesPerGuest', label: 'ФОТО'),
                  _MetricDivider(),
                  _MetricItem(value: '$maxGuests', label: 'ГОСТЕЙ'),
                  _MetricDivider(),
                  _MetricItem(value: _filmShortLabel(lut), label: 'ПЛЁНКА'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => context.push('/events/$eventId/album'),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -3,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 28),
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: const Icon(Icons.add, size: 12, color: AppColors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: AppColors.amber.withValues(alpha: 0.25),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String value;
  final String label;
  const _MetricItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
            letterSpacing: 0.3,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.ink3,
            letterSpacing: 1.3,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ─── action list helpers ──────────────────────────────────────────────────────

bool _isRevealed(Map<String, dynamic> event) {
  final status = event['status'] as String? ?? '';
  if (status == 'completed' || status == 'cancelled') return true;
  final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
  final revealAt = settings['reveal_at'] as String?;
  if (revealAt != null) {
    try {
      return DateTime.now().toUtc().isAfter(DateTime.parse(revealAt).toUtc());
    } catch (_) {}
  }
  return false;
}

void _onTapOpenAlbum(BuildContext context, Map<String, dynamic> event, String eventId) {
  if (_isRevealed(event)) {
    context.push('/events/$eventId/album');
    return;
  }
  final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
  final revealAt = settings['reveal_at'] as String?;
  if (revealAt == null) {
    _showRevealSheet(context, eventId, settings);
  } else {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FilmTimerSheet(eventId: eventId, settings: settings),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => context.push('/events/$eventId/qr'),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 14, offset: const Offset(0, 5), spreadRadius: -4)],
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_2, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'QR для гостей',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Открыть альбом — умная проверка проявки
          GestureDetector(
            onTap: () => _onTapOpenAlbum(context, event, eventId),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AppColors.amber.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 5), spreadRadius: -4)],
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Открыть альбом', style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            icon: Icons.people_outline,
            title: 'Гости',
            meta: 'Live-прогресс',
            onTap: () => context.push('/events/$eventId/progress'),
          ),
          if (status == 'active')
            _ActionRow(
              icon: Icons.lock_open_outlined,
              title: 'Открытие',
              meta: _revealMeta(settings),
              onTap: () => _showRevealSheet(context, eventId, settings),
            ),
          if (status == 'draft')
            _DevActivateRow(eventId: eventId, ref: ref),
          _ActionRow(
            icon: Icons.tune_outlined,
            title: 'Настройки',
            meta: 'Плёнка, название, расписание',
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => _SettingsSheet(eventId: eventId, event: event),
            ),
          ),
          _DownloadRow(eventId: eventId),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                    )
                  : const Icon(Icons.play_circle_outline, color: AppColors.amber, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('DEV: Активировать', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.amber)),
                  SizedBox(height: 2),
                  Text('Без оплаты — только для теста', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
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

  const _ActionRow({
    required this.icon, required this.title,
    required this.meta, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Icon(icon, color: AppColors.ink, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(meta, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
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
  if (revealMode == 'instant') return 'В любой момент';
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
      if (mounted) {
        final h = revealAt.hour.toString().padLeft(2, '0');
        final mi = revealAt.minute.toString().padLeft(2, '0');
        final d2 = revealAt.day.toString().padLeft(2, '0');
        final mo2 = revealAt.month.toString().padLeft(2, '0');
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('✓ Открытие назначено на $d2.$mo2 в $h:$mi'), backgroundColor: AppColors.amber),
        );
      }
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
            'Открытие альбома',
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
              fontSize: 22,
              fontWeight: FontWeight.w500, color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            scheduledLabel != null ? 'Запланировано на $scheduledLabel' : 'Выберите способ открытия',
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
                  : const Text('Открыть сейчас', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
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

// ─── film timer sheet (дата назначена, но ещё не пришла) ─────────────────────

class _FilmTimerSheet extends ConsumerStatefulWidget {
  final String eventId;
  final Map<String, dynamic> settings;
  const _FilmTimerSheet({required this.eventId, required this.settings});

  @override
  ConsumerState<_FilmTimerSheet> createState() => _FilmTimerSheetState();
}

class _FilmTimerSheetState extends ConsumerState<_FilmTimerSheet> {
  late Timer _ticker;
  Duration _remaining = Duration.zero;
  bool _revealing = false;
  bool _scheduling = false;

  @override
  void initState() {
    super.initState();
    _calcRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_calcRemaining);
    });
  }

  void _calcRemaining() {
    final raw = widget.settings['reveal_at'] as String?;
    if (raw == null) { _remaining = Duration.zero; return; }
    try {
      final diff = DateTime.parse(raw).toLocal().difference(DateTime.now());
      _remaining = diff.isNegative ? Duration.zero : diff;
    } catch (_) {
      _remaining = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _revealNow() async {
    setState(() => _revealing = true);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  Future<void> _reschedule() async {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите время в будущем')));
      return;
    }
    setState(() => _scheduling = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('events/${widget.eventId}/settings', data: {
        'reveal_mode': 'delayed',
        'reveal_at': revealAt.toUtc().toIso8601String(),
      });
      ref.invalidate(eventDetailProvider(widget.eventId));
      if (mounted) {
        final h = revealAt.hour.toString().padLeft(2, '0');
        final mi = revealAt.minute.toString().padLeft(2, '0');
        final d2 = revealAt.day.toString().padLeft(2, '0');
        final mo2 = revealAt.month.toString().padLeft(2, '0');
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('✓ Открытие перенесено на $d2.$mo2 в $h:$mi'), backgroundColor: AppColors.amber),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.settings['reveal_at'] as String?;
    String scheduledLabel = '';
    if (raw != null) {
      try {
        final dt = DateTime.parse(raw).toLocal();
        final d = dt.day.toString().padLeft(2, '0');
        final mo = dt.month.toString().padLeft(2, '0');
        final h = dt.hour.toString().padLeft(2, '0');
        final mi = dt.minute.toString().padLeft(2, '0');
        scheduledLabel = '$d.$mo в $h:$mi';
      } catch (_) {}
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 24),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(Icons.camera_roll_outlined, color: AppColors.amber, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            'Плёнка ещё проявляется',
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            scheduledLabel.isNotEmpty ? 'Проявка запланирована на $scheduledLabel' : 'Мероприятие ещё идёт',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  _fmt(_remaining),
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 44,
                    fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'до проявки',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink4, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _revealing ? null : _revealNow,
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: _revealing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Открыть сейчас', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _scheduling ? null : _reschedule,
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
                  : const Text('Изменить дату и время', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
            ),
          ),
        ],
      ),
    );
  }
}
