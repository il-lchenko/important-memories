import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/tokens.dart';
import '../album_provider.dart';

/// Настройки существующего альбома — расширение лимитов и продление хранения.
/// Открывается из шестерёнки в шапке AlbumScreen.
class AlbumSettingsScreen extends ConsumerWidget {
  final String eventId;
  const AlbumSettingsScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Настройки альбома',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppColors.ink3, size: 40),
                const SizedBox(height: 12),
                const Text('Не удалось загрузить',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.ink2)),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => ref.invalidate(eventDetailProvider(eventId)),
                  child: const Text('Повторить',
                      style: TextStyle(fontFamily: 'Inter', color: AppColors.amber, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
        data: (event) => _Content(eventId: eventId, event: event),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> event;
  const _Content({required this.eventId, required this.event});

  @override
  Widget build(BuildContext context) {
    final settings = (event['settings'] as Map<String, dynamic>?) ?? {};
    final title = (event['title'] as String?) ?? 'Событие';
    final status = event['status'] as String? ?? 'draft';
    final maxGuests = settings['max_guests'] as int? ?? 5;
    final framesPerGuest = settings['frames_per_guest'] as int? ?? 30;
    final guestsCount = event['guests_count'] as int? ?? 0;
    final framesCount = event['frames_count'] as int? ?? 0;
    final expiresAt = event['expires_at'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kicker('ТЕКУЩИЙ ПЛАН'),
          const SizedBox(height: 8),
          _CurrentCard(
            title: title,
            status: status,
            maxGuests: maxGuests,
            framesPerGuest: framesPerGuest,
            guestsCount: guestsCount,
            framesCount: framesCount,
            expiresAt: expiresAt,
          ),
          const SizedBox(height: 24),
          _Kicker('РАСШИРИТЬ ЛИМИТЫ'),
          const SizedBox(height: 12),
          _UpgradeRow(
            icon: Icons.people_outline,
            title: 'Больше гостей',
            meta: _nextGuestsUpgradeMeta(maxGuests),
            price: _nextGuestsUpgradePrice(maxGuests),
            onTap: () => _showGuestsUpgradeSheet(context, eventId, maxGuests),
          ),
          if (framesPerGuest < 45)
            _UpgradeRow(
              icon: Icons.photo_camera_outlined,
              title: '45 кадров на гостя',
              meta: 'Больше свободы для съёмки · сейчас $framesPerGuest',
              price: '+ ${maxGuests * 5} ₽',
              onTap: () => _upgradeFrames(context, eventId),
            ),
          _UpgradeRow(
            icon: Icons.event_available_outlined,
            title: 'Продлить хранение',
            meta: expiresAt != null ? 'Сейчас до ${_formatDate(expiresAt)}' : '+3 мес / +6 мес / +1 год',
            price: 'от 490 ₽',
            onTap: () => context.push('/extend/$eventId'),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.only(top: 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.paper3, style: BorderStyle.solid, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ОПАСНАЯ ЗОНА',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 11,
                    letterSpacing: 0.18,
                    color: AppColors.shutter,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _DangerRow(
                  icon: Icons.delete_outline,
                  title: 'Удалить событие',
                  meta: 'Все фото и данные будут удалены',
                  onTap: () => _confirmDelete(context, eventId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd.MM.yy', 'ru').format(dt);
    } catch (_) {
      return '—';
    }
  }

  static String _nextGuestsUpgradeMeta(int current) {
    // Показываем следующие 2 варианта в мета.
    final next = _nextTiers(current);
    if (next.isEmpty) return 'Больше 250 · по запросу';
    return next.map((n) => 'до $n').join(' · ');
  }

  static String _nextGuestsUpgradePrice(int current) {
    // Минимальная цена следующего апгрейда (× 1.15 премия по бизнес-плану v3.2).
    final tiers = <int, int>{
      5: 249, 10: 449, 25: 1290, 50: 1990, 75: 2990,
      100: 4490, 150: 5490, 175: 6290, 200: 7690, 250: 0,
    };
    final currentPrice = _priceForGuests(current);
    final next = _nextTiers(current);
    if (next.isEmpty) return 'по запросу';
    final nextPrice = tiers[next.first] ?? 0;
    if (nextPrice == 0) return 'по запросу';
    final delta = ((nextPrice - currentPrice) * 1.15).round();
    return 'от $delta ₽';
  }

  static int _priceForGuests(int n) {
    if (n <= 5) return 0;
    if (n <= 10) return 249;
    if (n <= 25) return 449;
    if (n <= 50) return 1290;
    if (n <= 75) return 1990;
    if (n <= 100) return 2990;
    if (n <= 150) return 4490;
    if (n <= 175) return 5490;
    if (n <= 200) return 6290;
    if (n <= 250) return 7690;
    return 7690 + (n - 250) * 30;
  }

  static List<int> _nextTiers(int current) {
    const all = [10, 25, 50, 75, 100, 150, 175, 200, 250];
    final next = all.where((t) => t > current).take(2).toList();
    return next;
  }

  static void _showGuestsUpgradeSheet(BuildContext context, String eventId, int current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => _GuestsUpgradeSheet(eventId: eventId, currentMax: current),
    );
  }

  static void _upgradeFrames(BuildContext context, String eventId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Оплата 45 кадров — скоро')),
    );
  }

  static void _confirmDelete(BuildContext context, String eventId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('Удалить событие?',
            style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink)),
        content: const Text(
          'Все фото, голосовые заметки и подписи будут удалены безвозвратно.',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: DELETE /events/{id}
            },
            child: const Text('Удалить', style: TextStyle(fontFamily: 'Inter', color: AppColors.shutter, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Виджет-блоки в стиле create_event_screen / event_detail ────────────────

class _Kicker extends StatelessWidget {
  final String text;
  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono', fontSize: 11, letterSpacing: 0.18,
          color: AppColors.amber, fontWeight: FontWeight.w500,
        ),
      );
}

class _CurrentCard extends StatelessWidget {
  final String title;
  final String status;
  final int maxGuests;
  final int framesPerGuest;
  final int guestsCount;
  final int framesCount;
  final String? expiresAt;

  const _CurrentCard({
    required this.title,
    required this.status,
    required this.maxGuests,
    required this.framesPerGuest,
    required this.guestsCount,
    required this.framesCount,
    this.expiresAt,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = status == 'active'
        ? const Color(0xFFC9881E)
        : status == 'completed'
            ? const Color(0xFF5BAA72)
            : AppColors.ink3;
    final label = status == 'active' ? 'ЗАПИСЬ ИДЁТ'
        : status == 'completed' ? 'ПРОЯВЛЕНО'
        : status == 'draft' ? 'ЧЕРНОВИК'
        : status.toUpperCase();
    final progressPercent = maxGuests > 0 ? (guestsCount / maxGuests).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: dotColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 24, fontWeight: FontWeight.w600,
              color: AppColors.ink, letterSpacing: -0.4, height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatCell(label: 'Гостей до', value: '$maxGuests')),
              Expanded(child: _StatCell(label: 'Кадров', value: '$framesPerGuest')),
              if (expiresAt != null)
                Expanded(child: _StatCell(label: 'До', value: _shortDate(expiresAt!))),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressPercent,
              minHeight: 5,
              backgroundColor: AppColors.paper3,
              valueColor: const AlwaysStoppedAnimation(AppColors.amber),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$guestsCount / $maxGuests гостей',
                style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, color: AppColors.ink3, fontWeight: FontWeight.w500),
              ),
              Text(
                '$framesCount кадров загружено',
                style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, color: AppColors.ink3, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd.MM.yy', 'ru').format(dt);
    } catch (_) {
      return '—';
    }
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono', fontSize: 10, letterSpacing: 0.6,
                color: AppColors.ink3, fontWeight: FontWeight.w500,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono', fontSize: 20, fontWeight: FontWeight.w700,
                color: AppColors.ink, letterSpacing: -0.3,
              )),
        ],
      );
}

// ─── Upgrade row — как _ActionRow из event_detail_screen, но с ценой справа ─

class _UpgradeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String meta;
  final String price;
  final VoidCallback onTap;

  const _UpgradeRow({
    required this.icon, required this.title,
    required this.meta, required this.price, required this.onTap,
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
                  Text(title,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(price,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.amber, letterSpacing: -0.2,
                )),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.ink4, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  const _DangerRow({required this.icon, required this.title, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.shutter.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.shutter.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.shutter, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.shutter)),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.shutter, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet выбора следующего тира гостей ─────────────────────────────

class _GuestsUpgradeSheet extends StatelessWidget {
  final String eventId;
  final int currentMax;
  const _GuestsUpgradeSheet({required this.eventId, required this.currentMax});

  static const _tiers = [
    (10,   249),
    (25,   449),
    (50,  1290),
    (75,  1990),
    (100, 2990),
    (150, 4490),
    (175, 5490),
    (200, 6290),
    (250, 7690),
  ];

  @override
  Widget build(BuildContext context) {
    final currentPrice = _priceForGuests(currentMax);
    final available = _tiers.where((t) => t.$1 > currentMax).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.paper3, borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Расширить до',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Сейчас у вас до $currentMax гостей. Доплата = разница цены × 1.15',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink3, height: 1.4),
              ),
              const SizedBox(height: 20),
              ...available.map((t) {
                final delta = ((t.$2 - currentPrice) * 1.15).round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _UpgradeRow(
                    icon: Icons.people_outline,
                    title: 'До ${t.$1} гостей',
                    meta: '${t.$2} ₽ базовый — вы платите разницу',
                    price: '+ $delta ₽',
                    onTap: () {
                      Navigator.of(context).pop();
                      // TODO: POST /events/{id}/upgrade с plan = pN + YooKassa
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Апгрейд до ${t.$1} гостей за $delta ₽ — оплата скоро')),
                      );
                    },
                  ),
                );
              }),
              if (available.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Больше 250 гостей — свяжитесь с поддержкой',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static int _priceForGuests(int n) {
    if (n <= 5) return 0;
    if (n <= 10) return 249;
    if (n <= 25) return 449;
    if (n <= 50) return 1290;
    if (n <= 75) return 1990;
    if (n <= 100) return 2990;
    if (n <= 150) return 4490;
    if (n <= 175) return 5490;
    if (n <= 200) return 6290;
    if (n <= 250) return 7690;
    return 7690 + (n - 250) * 30;
  }
}
