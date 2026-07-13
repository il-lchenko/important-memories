import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/tokens.dart';
import '../album_provider.dart';

/// Продление хранения альбома. Открывается: (а) из AlbumSettingsScreen,
/// (б) из push «Осталось N дней» по deep-link `im://extend/{eventId}`.
class ExtendStorageScreen extends ConsumerStatefulWidget {
  final String eventId;
  const ExtendStorageScreen({super.key, required this.eventId});

  @override
  ConsumerState<ExtendStorageScreen> createState() => _ExtendStorageScreenState();
}

class _ExtendStorageScreenState extends ConsumerState<ExtendStorageScreen> {
  String _selected = '6m'; // default = «выгодно»

  static const _options = <_ExtendOption>[
    _ExtendOption(id: '3m', label: '+ 3 месяца', days: 90, priceRub: 490, savingsHint: null),
    _ExtendOption(id: '6m', label: '+ 6 месяцев', days: 180, priceRub: 790, savingsHint: 'Скидка 40% к цене за месяц'),
    _ExtendOption(id: '1y', label: '+ 1 год', days: 365, priceRub: 1290, savingsHint: 'Скидка 65% к цене за месяц'),
  ];

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));

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
          'Продление хранения',
          style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
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
              ],
            ),
          ),
        ),
        data: (event) => Column(
          children: [
            Expanded(child: _buildBody(event)),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> event) {
    final title = (event['title'] as String?) ?? 'Событие';
    final expiresAt = event['expires_at'] as String?;
    final framesCount = event['frames_count'] as int? ?? 0;
    final guestsCount = event['guests_count'] as int? ?? 0;
    final daysLeft = _daysUntil(expiresAt);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExpireBanner(title: title, daysLeft: daysLeft, expiresAt: expiresAt, framesCount: framesCount, guestsCount: guestsCount),
          const SizedBox(height: 24),
          _Kicker('ВЫБЕРИТЕ СРОК ПРОДЛЕНИЯ'),
          const SizedBox(height: 12),
          ..._options.map((opt) => _ExtendOptionCard(
                opt: opt,
                selected: _selected == opt.id,
                fromDate: expiresAt,
                onTap: () => setState(() => _selected = opt.id),
              )),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Если не продлить, альбом сохраняется в архиве ещё 30 дней после истечения. После — удаляется навсегда',
                    style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3, height: 1.5,
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

  Widget _buildFooter(BuildContext context) {
    final opt = _options.firstWhere((o) => o.id == _selected);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Оплата через ЮKassa',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink3, fontWeight: FontWeight.w500)),
                  Text('${opt.priceRub} ₽',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.5,
                      )),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _proceed(context, opt),
              child: Container(
                height: AppSizes.buttonHeight,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.amber.withValues(alpha: 0.42),
                      blurRadius: 20, offset: const Offset(0, 6), spreadRadius: -4,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('Продлить и оплатить',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _proceed(BuildContext context, _ExtendOption opt) {
    // TODO: POST /events/{id}/extend с payload {period: opt.id} → YooKassa redirect
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Продление ${opt.label} за ${opt.priceRub} ₽ — оплата скоро')),
    );
  }

  static int _daysUntil(String? iso) {
    if (iso == null) return 0;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      return dt.difference(now).inDays;
    } catch (_) {
      return 0;
    }
  }
}

class _ExtendOption {
  final String id;
  final String label;
  final int days;
  final int priceRub;
  final String? savingsHint;
  const _ExtendOption({required this.id, required this.label, required this.days, required this.priceRub, this.savingsHint});
}

// ─── Виджеты в стиле create_event / event_detail ──────────────────────────────

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

class _ExpireBanner extends StatelessWidget {
  final String title;
  final int daysLeft;
  final String? expiresAt;
  final int framesCount;
  final int guestsCount;

  const _ExpireBanner({
    required this.title, required this.daysLeft,
    this.expiresAt, required this.framesCount, required this.guestsCount,
  });

  @override
  Widget build(BuildContext context) {
    final isUrgent = daysLeft <= 3 && daysLeft >= 0;
    final accent = isUrgent ? AppColors.shutter : AppColors.amber;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isUrgent ? Icons.warning_amber_rounded : Icons.schedule,
                  color: accent, size: 16),
              const SizedBox(width: 6),
              Text(
                isUrgent ? 'СКОРО ИСЧЕЗНЕТ' : 'ОСТАЛОСЬ ХРАНИТЬ',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono', fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.4, color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.3, letterSpacing: -0.3,
              ),
              children: [
                TextSpan(text: '«$title»\n'),
                TextSpan(text: 'исчезнет через '),
                TextSpan(
                  text: daysLeft > 0 ? _daysWord(daysLeft) : 'сегодня',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_formatDate(expiresAt!)} · $guestsCount гостей · $framesCount кадров',
              style: const TextStyle(
                fontFamily: 'JetBrains Mono', fontSize: 11, color: AppColors.ink3, letterSpacing: 0.2, fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _daysWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n дня';
    return '$n дней';
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('d MMMM y', 'ru').format(dt);
    } catch (_) {
      return '—';
    }
  }
}

class _ExtendOptionCard extends StatelessWidget {
  final _ExtendOption opt;
  final bool selected;
  final String? fromDate;
  final VoidCallback onTap;

  const _ExtendOptionCard({
    required this.opt, required this.selected, this.fromDate, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final untilDate = _computeUntil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.amber.withValues(alpha: 0.06) : AppColors.paper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.amber : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.amber : AppColors.paper3, width: 2),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10, height: 10,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.amber),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(opt.label,
                        style: TextStyle(
                          fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                          color: selected ? AppColors.ink : AppColors.ink2,
                        )),
                    if (untilDate != null) ...[
                      const SizedBox(height: 2),
                      Text('до $untilDate',
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono', fontSize: 11, color: AppColors.ink3, letterSpacing: 0.2,
                          )),
                    ],
                    if (opt.savingsHint != null) ...[
                      const SizedBox(height: 4),
                      Text(opt.savingsHint!.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono', fontSize: 9, fontWeight: FontWeight.w700,
                            color: Color(0xFF5BAA72), letterSpacing: 0.5,
                          )),
                    ],
                  ],
                ),
              ),
              Text('${opt.priceRub} ₽',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 18, fontWeight: FontWeight.w700,
                    color: selected ? AppColors.amber : AppColors.ink2, letterSpacing: -0.4,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  String? _computeUntil() {
    if (fromDate == null) return null;
    try {
      final base = DateTime.parse(fromDate!).toLocal();
      final until = base.add(Duration(days: opt.days));
      return DateFormat('d MMMM y', 'ru').format(until);
    } catch (_) {
      return null;
    }
  }
}
