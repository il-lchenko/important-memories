import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

final _referralStatsProvider = FutureProvider.autoDispose((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('me/referrals');
  return (resp.data as Map).cast<String, dynamic>();
});

class ReferralsScreen extends ConsumerWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_referralStatsProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Приглашай друзей',
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()],
                fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
        error: (e, _) => Center(child: Text(extractUserMessage(e))),
        data: (data) {
          final code = data['referral_code'] as String?;
          final count = data['referrals_count'] as int? ?? 0;
          final earned = data['total_earned_kopecks'] as int? ?? 0;
          final pending = data['pending_promocodes_count'] as int? ?? 0;

          final url = code != null ? 'https://impomento.pro/?ref=$code' : '';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Оба получают по 20%',
                        style: GoogleFonts.playfairDisplay(
                            fontFeatures: [const FontFeature.liningFigures()],
                            fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink,
                            letterSpacing: -0.4)),
                    const SizedBox(height: 8),
                    const Text(
                      'Твой друг получает 20% скидку на первый платный альбом (от P25). '
                      'Как только он оплатит — тебе прилетит промокод 20% на следующий платёж.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13.5,
                          color: AppColors.ink2, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Твой реферальный код'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  if (code == null) return;
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Ссылка скопирована',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 14)),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.paper2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(code ?? '—',
                                style: const TextStyle(
                                    fontFamily: 'Inter', fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(url,
                                style: const TextStyle(
                                    fontFamily: 'Inter', fontSize: 12,
                                    color: AppColors.ink3)),
                          ],
                        ),
                      ),
                      const Icon(Icons.copy, size: 20, color: AppColors.ink3),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Твои результаты'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _StatCard(value: '$count', label: 'друзей')),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '${(earned / 100).toStringAsFixed(0)} ₽', label: 'сэкономлено')),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '$pending', label: 'ждёт применения')),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, letterSpacing: 0.4,
          color: AppColors.amber, fontWeight: FontWeight.w600));
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
            color: AppColors.paper2, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700,
                    color: AppColors.ink, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 11, color: AppColors.ink3)),
          ],
        ),
      );
}
