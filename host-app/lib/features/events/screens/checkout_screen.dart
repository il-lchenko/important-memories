import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../events_provider.dart';

/// Смета создаваемого события: сетка гостей → итог → создать.
/// Открывается после шага 5 «Плёнка» из [CreateEventScreen].
class CheckoutScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> draft;
  const CheckoutScreen({super.key, required this.draft});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  static const _tiers = <int>[5, 10, 25, 50, 75, 100, 150, 175, 200, 250];
  static const _prices = <int>[0, 249, 449, 1290, 1990, 2990, 4490, 5490, 6290, 7690];

  int _tierIndex = 0; // FREE / 5 гостей по умолчанию
  bool _loading = false;

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

  int get _planPriceRub => _prices[_tierIndex];

  // Бесплатно: 2 мес, платные: 3 мес базово
  int get _retentionDays => _planId == 'free' ? 60 : 90;

  int get _framesPerGuest => (widget.draft['frames_per_guest'] as int?) ?? 30;

  DateTime get _expiresAt => DateTime.now().add(Duration(days: _retentionDays));

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);

      final created = await ref.read(createEventProvider({
        'name': widget.draft['name'],
        'event_type': widget.draft['event_type'],
        'frames_per_guest': _framesPerGuest,
        'reveal_mode': widget.draft['reveal_mode'],
        if (widget.draft['reveal_at'] != null) 'reveal_at': widget.draft['reveal_at'],
        if (widget.draft['start_at'] != null)  'start_at':  widget.draft['start_at'],
        'film': widget.draft['film'],
        'plan': _planId,
      }).future);

      final eventId = created['id'] as String;

      if (_planPriceRub == 0) {
        await dio.post('events/$eventId/activate');
        if (!mounted) return;
        ref.invalidate(eventsProvider);
        context.go('/dashboard');
      } else {
        final resp = await dio.post('events/$eventId/checkout', data: {'plan': _planId});
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(extractUserMessage(e), style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
        backgroundColor: AppColors.shutter,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
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
                    const _StepDesc('Выберите количество гостей — тариф и цена подстроятся автоматически'),
                    _GuestsTileGrid(
                      tierIndex: _tierIndex,
                      tiers: _tiers,
                      prices: _prices,
                      onChanged: (i) => setState(() => _tierIndex = i),
                    ),
                    const SizedBox(height: 20),
                    _TotalCard(
                      planId: _planId,
                      planPriceRub: _planPriceRub,
                      guests: _guests,
                      framesPerGuest: _framesPerGuest,
                      retentionDays: _retentionDays,
                      expiresAt: _expiresAt,
                    ),
                    const SizedBox(height: 24),
                    _SubmitCta(
                      totalRub: _planPriceRub,
                      loading: _loading,
                      onTap: _submit,
                    ),
                    const SizedBox(height: 12),
                    const _StorageHint(),
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
            child: Text('СМЕТА',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, letterSpacing: 1.32, color: AppColors.ink3)),
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
        decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(18)),
        child: Icon(icon, color: AppColors.ink2, size: iconSize),
      ),
    );
  }
}

// ─── Guest tiles grid (5×2) ─────────────────────────────────────────────────

class _GuestsTileGrid extends StatelessWidget {
  final int tierIndex;
  final List<int> tiers;
  final List<int> prices;
  final ValueChanged<int> onChanged;

  const _GuestsTileGrid({
    required this.tierIndex,
    required this.tiers,
    required this.prices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedGuests = tiers[tierIndex];
    final selectedPrice = prices[tierIndex];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(color: AppColors.paper2, borderRadius: AppRadius.lgBR),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ГОСТЕЙ',
              style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, letterSpacing: 0.18, color: AppColors.ink3, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          // 5 columns × 2 rows
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 52,
            ),
            itemCount: 10,
            itemBuilder: (ctx, i) {
              final active = i == tierIndex;
              final count = tiers[i];
              return GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  decoration: BoxDecoration(
                    color: active ? AppColors.amber.withValues(alpha: 0.10) : AppColors.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active ? AppColors.amber : AppColors.line,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? AppColors.amber : AppColors.ink2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // Price row below grid
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selectedPrice == 0 ? const Color(0xFFE8F5E9) : AppColors.amber.withValues(alpha: 0.06),
              borderRadius: AppRadius.mdBR,
              border: Border.all(
                color: selectedPrice == 0 ? const Color(0xFF4CAF79).withValues(alpha: 0.4) : AppColors.amber.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Text(
                  '$selectedGuests гостей',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const Spacer(),
                Text(
                  selectedPrice == 0 ? 'Бесплатно' : '$selectedPrice ₽',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: selectedPrice == 0 ? const Color(0xFF4CAF79) : AppColors.amber,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.paper,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => const _CustomTierSheet(),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 13, color: AppColors.ink4),
                const SizedBox(width: 6),
                Text('Больше 250 гостей — по запросу',
                    style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3,
                      decoration: TextDecoration.underline, decorationColor: AppColors.ink4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomTierSheet extends StatelessWidget {
  const _CustomTierSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.paper3, borderRadius: BorderRadius.circular(2))),
          Text('Больше 250 гостей', style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 10),
          const Text(
            'Свадьбы, банкеты и корпоративы с большим числом гостей — считаем индивидуально. Напишите нам с деталями события',
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.4, color: AppColors.ink2),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.paper2, borderRadius: AppRadius.mdBR),
            child: const Row(
              children: [
                Icon(Icons.calculate_outlined, size: 18, color: AppColors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Формула: 7 690 ₽ + 30 ₽ × (гости − 250)',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink2)),
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
                backgroundColor: AppColors.amber, foregroundColor: Colors.white, elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
              ),
              child: const Text('Понятно', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Total card ─────────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final String planId;
  final int planPriceRub;
  final int guests;
  final int framesPerGuest;
  final int retentionDays;
  final DateTime expiresAt;

  const _TotalCard({
    required this.planId,
    required this.planPriceRub,
    required this.guests,
    required this.framesPerGuest,
    required this.retentionDays,
    required this.expiresAt,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = planPriceRub == 0;
    final dateStr = DateFormat('d MMMM yyyy', 'ru').format(expiresAt);
    final retentionMonths = (retentionDays / 30).round();

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
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.2)),
          const SizedBox(height: 14),
          _TotalRow(
            label: 'Тариф · до $guests гостей',
            value: isFree ? 'Бесплатно' : '$planPriceRub ₽',
          ),
          const SizedBox(height: 8),
          _TotalRow(
            label: '$framesPerGuest кадров на гостя · включено',
            value: 'Входит',
            dim: true,
          ),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'Хранение $retentionMonths мес · базовое',
            value: 'Входит',
            dim: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: DashLine(),
          ),
          Row(
            children: [
              const Expanded(
                child: Text('К оплате',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
              Text(
                isFree ? 'Бесплатно' : '$planPriceRub ₽',
                style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.amber),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.paper2, borderRadius: AppRadius.smBR),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: AppColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.ink2),
                      children: [
                        const TextSpan(text: 'Альбом хранится до '),
                        TextSpan(text: dateStr, style: const TextStyle(fontWeight: FontWeight.w700)),
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
  final bool dim;
  const _TotalRow({required this.label, required this.value, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 13.5,
                  color: dim ? AppColors.ink3 : AppColors.ink2,
                  fontWeight: dim ? FontWeight.w400 : FontWeight.w500)),
        ),
        Text(value,
            style: TextStyle(
                fontFamily: 'JetBrains Mono', fontSize: 14,
                color: dim ? AppColors.ink4 : AppColors.ink,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class DashLine extends StatelessWidget {
  const DashLine({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const dashWidth = 4.0;
      const dashSpace = 3.0;
      final dashes = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
      return Row(
        children: List.generate(dashes, (_) => Padding(
          padding: const EdgeInsets.only(right: dashSpace),
          child: Container(width: dashWidth, height: 1, color: AppColors.ink3.withValues(alpha: 0.4)),
        )),
      );
    });
  }
}

// ─── Storage hint ───────────────────────────────────────────────────────────

class _StorageHint extends StatelessWidget {
  const _StorageHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 14, color: AppColors.ink4),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Продление хранения (+3/6/12 мес) и расширение плёнки (до 45 кадров) доступны в настройках альбома после создания',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink4, height: 1.45),
          ),
        ),
      ],
    );
  }
}

// ─── Submit ─────────────────────────────────────────────────────────────────

class _SubmitCta extends StatelessWidget {
  final int totalRub;
  final bool loading;
  final VoidCallback onTap;
  const _SubmitCta({required this.totalRub, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = totalRub == 0 ? 'Создать бесплатно' : 'Создать за $totalRub ₽';
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: AppSizes.buttonHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.amber,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppColors.amber.withValues(alpha: 0.42), blurRadius: 20, offset: const Offset(0, 6), spreadRadius: -4)],
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    );
  }
}

// ─── Текстовые компоненты ───────────────────────────────────────────────────

class _Kicker extends StatelessWidget {
  final String text;
  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, letterSpacing: 0.18, color: AppColors.amber, fontWeight: FontWeight.w500)),
  );
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Text(text, style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontWeight: FontWeight.w500, fontSize: 30, height: 1.05, letterSpacing: -0.6, color: AppColors.ink)),
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
