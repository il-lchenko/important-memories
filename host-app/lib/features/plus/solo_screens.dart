import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/tokens.dart';
import '../../utils/guest_prefs.dart';
import '../album/album_provider.dart';
import '../events/events_provider.dart';
import '../../core/widgets/brand_icon.dart';
import 'plus_providers.dart';

const _films = <(String, String)>[
  ('original', 'Без фильтра'),
  ('portra400', 'Portra 400'),
  ('fuji400h', 'Fuji 400H'),
  ('cinestill', 'Cinestill 800T'),
  ('ilford', 'Ilford HP5+'),
];

const _filmDesc = <String, String>{
  'original': 'Фото как снято · Без обработки',
  'portra400': 'Тёплые телесные тона · Лучше всего для свадеб',
  'fuji400h': 'Холодные пастельные зелёные · Природа и портреты',
  'cinestill': 'Неоновые красные · Ночные и городские сцены',
  'ilford': 'Ч/Б · Классика документальной съёмки',
};

TextStyle _display(double size, {FontWeight w = FontWeight.w600, Color color = AppColors.ink}) =>
    GoogleFonts.playfairDisplay(
      fontFeatures: [const FontFeature.liningFigures()],
      fontSize: size, fontWeight: w, color: color, letterSpacing: -0.4, height: 1.1,
    );

Widget _roundBack(BuildContext context) => InkWell(
      customBorder: const CircleBorder(),
      onTap: () => context.pop(),
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(color: AppColors.paper2, shape: BoxShape.circle),
        child: const Icon(Icons.chevron_left, color: AppColors.ink),
      ),
    );

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat('d MMMM yyyy', 'ru').format(d);
}

// ─── Создание соло-альбома ────────────────────────────────────────────────────

class SoloCreateScreen extends ConsumerStatefulWidget {
  const SoloCreateScreen({super.key});

  @override
  ConsumerState<SoloCreateScreen> createState() => _SoloCreateScreenState();
}

class _SoloCreateScreenState extends ConsumerState<SoloCreateScreen> {
  final _title = TextEditingController();
  String _film = 'original';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final resp = await ref.read(dioProvider).post('events/solo', data: {'title': title, 'lut_preset': _film});
      final id = (resp.data as Map)['id'] as String;
      ref.invalidate(eventsProvider);
      ref.invalidate(entitlementsProvider);
      if (!mounted) return;
      context.pushReplacement('/solo/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final left = ent?['solo_frames_left'] as int?;
    final perMonth = ent?['solo_frames_per_month'] as int?;
    final retention = ent?['solo_retention_days'] as int? ?? 90;
    final blocked = left != null && left <= 0;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Row(children: [_roundBack(context)]),
            const SizedBox(height: 18),
            Text('СОЛО-АЛЬБОМ',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
            const SizedBox(height: 4),
            Text('Новый альбом', style: _display(32)),
            const SizedBox(height: 22),
            TextField(
              controller: _title,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              style: _display(22, w: FontWeight.w500),
              decoration: const InputDecoration(hintText: 'Например, Грузия, осень', counterText: ''),
            ),
            const SizedBox(height: 22),
            Text('ПЛЁНКА',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in _films)
                ChoiceChip(
                  label: Text(f.$2, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600,
                      color: _film == f.$1 ? AppColors.paper : AppColors.ink2)),
                  selected: _film == f.$1,
                  showCheckmark: false,
                  selectedColor: AppColors.ink,
                  backgroundColor: AppColors.paper2,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _film = f.$1),
                ),
            ]),
            const SizedBox(height: 10),
            Text(_filmDesc[_film] ?? '',
                style: GoogleFonts.manrope(fontSize: 13, height: 1.4, color: AppColors.ink3)),
            const SizedBox(height: 22),
            if (left != null && perMonth != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.paper2, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  'В этом месяце можно снять ещё $left из $perMonth кадров во всех соло-альбомах. '
                  '${retention >= 1000 ? 'Альбом хранится, пока действует подписка.' : 'Альбом хранится ${(retention / 30).round()} мес., потом его можно продлить.'}',
                  style: GoogleFonts.manrope(fontSize: 13, height: 1.5, color: AppColors.ink2),
                ),
              ),
            const SizedBox(height: 22),
            SizedBox(
              height: AppSizes.buttonHeight,
              child: ElevatedButton(
                onPressed: (_title.text.trim().isEmpty || _busy || blocked) ? null : _create,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Создать альбом'),
              ),
            ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Лимит кадров на этот месяц исчерпан. Новые откроются с 1-го числа.',
                    style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Соло-альбом ──────────────────────────────────────────────────────────────

class SoloDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  const SoloDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<SoloDetailScreen> createState() => _SoloDetailScreenState();
}

class _SoloDetailScreenState extends ConsumerState<SoloDetailScreen> {
  bool _busy = false;
  bool _downloading = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String> _fingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    var fp = prefs.getString('device_fingerprint');
    if (fp != null && fp.isNotEmpty) return fp;
    final rnd = math.Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buf.write(rnd.nextInt(16).toRadixString(16));
    }
    fp = buf.toString();
    await prefs.setString('device_fingerprint', fp);
    return fp;
  }

  /// Владелец снимает в своём альбоме через гостевую сессию (под его аккаунтом).
  Future<void> _openCamera(String shortCode) async {
    if (_busy) return;
    final existing = await GuestPrefs.tokenFor(widget.eventId);
    if (existing.isEmpty) {
      setState(() => _busy = true);
      try {
        final resp = await ref.read(dioProvider).post('guest/sessions', data: {
          'short_code': shortCode,
          'fingerprint': await _fingerprint(),
        });
        final data = Map<String, dynamic>.from(resp.data as Map);
        final token = data['guest_token'] as String?;
        if (token == null) throw StateError('empty guest_token');
        final settings = (data['event'] as Map?)?['settings'] as Map?;
        await GuestPrefs.saveSession(
          eventId: widget.eventId,
          token: token,
          framesRemaining: data['frames_remaining'] as int? ?? 0,
          lutPreset: settings?['lut_preset'] as String?,
        );
      } catch (e) {
        _snack(extractUserMessage(e));
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (mounted) setState(() => _busy = false);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_guest_event_id', widget.eventId);
    if (!mounted) return;
    await context.push('/guest/camera/${widget.eventId}');
    if (!mounted) return;
    ref.invalidate(eventDetailProvider(widget.eventId));
    ref.invalidate(eventsProvider);
    ref.invalidate(entitlementsProvider);
  }

  Future<void> _downloadAll() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final dio = ref.read(dioProvider);
      final job = await dio.post('events/${widget.eventId}/download');
      final jobId = (job.data as Map)['job_id'] as String;
      for (var i = 0; i < 90; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final r = await dio.get('events/${widget.eventId}/download/$jobId');
        final d = Map<String, dynamic>.from(r.data as Map);
        final status = d['status'];
        if (status == 'ready' && d['download_url'] != null) {
          await launchUrl(Uri.parse(d['download_url'] as String), mode: LaunchMode.externalApplication);
          return;
        }
        if (status == 'empty') { _snack('В альбоме пока нет фото'); return; }
        if (status == 'failed') { _snack('Не удалось собрать архив'); return; }
      }
      _snack('Архив собирается слишком долго, попробуйте позже');
    } catch (e) {
      _snack(extractUserMessage(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Удалить альбом?', style: _display(20)),
        content: Text('Все кадры альбома будут удалены без возможности восстановления.',
            style: GoogleFonts.manrope(fontSize: 14, height: 1.45, color: AppColors.ink2)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.shutter)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).delete('events/${widget.eventId}');
      ref.invalidate(eventsProvider);
      ref.invalidate(entitlementsProvider);
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      _snack(extractUserMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: eventAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
          error: (e, _) => Center(child: Text(extractUserMessage(e))),
          data: (event) {
            final title = event['title'] as String? ?? 'Соло-альбом';
            final shortCode = event['short_code'] as String? ?? '';
            final frames = event['frames_count'] as int? ?? 0;
            final settings = (event['settings'] as Map?) ?? const {};
            final film = _films.firstWhere((f) => f.$1 == settings['lut_preset'], orElse: () => ('', '—')).$2;
            final used = ent?['solo_frames_used'] as int? ?? 0;
            final perMonth = ent?['solo_frames_per_month'] as int? ?? 0;
            final left = ent?['solo_frames_left'] as int?;
            final share = perMonth == 0 ? 0.0 : (used / perMonth).clamp(0.0, 1.0);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Row(children: [_roundBack(context)]),
                const SizedBox(height: 18),
                Text('СОЛО-АЛЬБОМ',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
                const SizedBox(height: 4),
                Text(title, style: _display(30, w: FontWeight.w500)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(children: [
                    Row(children: [
                      _Metric('$frames', 'кадров'),
                      _Metric(film, 'плёнка'),
                      _Metric(_fmtDate(event['expires_at'] as String?), 'хранится до'),
                    ]),
                    if (ent != null) ...[
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('КАДРОВ В ЭТОМ МЕСЯЦЕ',
                            style: GoogleFonts.inter(fontSize: 11, letterSpacing: 1.2, color: AppColors.ink3)),
                        Text('$used из $perMonth',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: share, minHeight: 8,
                          backgroundColor: AppColors.paper3,
                          valueColor: const AlwaysStoppedAnimation(AppColors.amber),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                _Rows([
                  _RowData(Icons.photo_camera_outlined, 'Снять кадр',
                      left != null && left <= 0 ? 'Лимит кадров на месяц исчерпан' : 'Плёночная камера',
                      () => _openCamera(shortCode)),
                  _RowData(Icons.photo_library_outlined, 'Добавить фото из галереи',
                      'Кнопка «Из галереи» под затвором камеры', () => _openCamera(shortCode), brand: 'gallery'),
                  _RowData(Icons.auto_stories_outlined, 'Открыть альбом', 'Все кадры',
                      () => context.push('/events/${widget.eventId}/album')),
                  _RowData(Icons.download_outlined, _downloading ? 'Собираем архив…' : 'Скачать все фото',
                      'ZIP со всеми кадрами', _downloadAll),
                  _RowData(Icons.lock_clock_outlined, 'Продлить хранение', 'Альбом останется доступен дольше',
                      () => context.push('/extend/${widget.eventId}')),
                  _RowData(Icons.delete_outline, 'Удалить альбом', null, _delete, danger: true),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10, letterSpacing: 1.2, color: AppColors.ink3)),
        ]),
      );
}

class _RowData {
  final IconData icon;
  final String title;
  final String? hint;
  final VoidCallback onTap;
  final bool danger;
  final String? brand;
  const _RowData(this.icon, this.title, this.hint, this.onTap, {this.danger = false, this.brand});
}

class _Rows extends StatelessWidget {
  final List<_RowData> rows;
  const _Rows(this.rows);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.line)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            InkWell(
              onTap: rows[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(children: [
                  if (rows[i].brand != null)
                    BrandIcon(rows[i].brand!, size: 26)
                  else
                    Icon(rows[i].icon, color: rows[i].danger ? AppColors.shutter : AppColors.amber, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(rows[i].title,
                          style: GoogleFonts.manrope(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: rows[i].danger ? AppColors.shutter : AppColors.ink)),
                      if (rows[i].hint != null)
                        Text(rows[i].hint!, style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink3)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.ink4, size: 20),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Тихий выход на экран подписки: используется, когда сервер просит «Плюс».
void openPlus(BuildContext context) => context.push('/plus');

/// Сообщение об ошибке сервера (409 «лимит») с кнопкой на «Плюс».
void showLimitSnack(BuildContext context, Object e) {
  final msg = extractUserMessage(e);
  final plusHint = e is DioException && (e.response?.statusCode == 409 || e.response?.statusCode == 403);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    action: plusHint ? SnackBarAction(label: 'Плюс', onPressed: () => openPlus(context)) : null,
  ));
}

/// Нужен ли пользователю баннер «лимит исчерпан».
bool soloBlocked(Map<String, dynamic>? ent) => ent != null && (ent['solo_frames_left'] as int? ?? 1) <= 0;

/// События (для подсказки в списке): соло-альбом открывается своим экраном.
String routeForEvent(Map<String, dynamic> event) =>
    event['kind'] == 'solo' ? '/solo/${event['id']}' : '/events/${event['id']}';
