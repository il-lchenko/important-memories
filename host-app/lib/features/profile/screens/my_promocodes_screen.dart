import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

final _myPromocodesProvider = FutureProvider.autoDispose((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('me/promocodes');
  return (resp.data as List).cast<Map<String, dynamic>>();
});

class MyPromocodesScreen extends ConsumerWidget {
  const MyPromocodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myPromocodesProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Мои промокоды',
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()],
                fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
        error: (e, _) => Center(child: Text(extractUserMessage(e))),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'У вас пока нет промокодов.\nПригласите друзей — получите 20% на следующий платёж.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3, height: 1.5),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _PromoCard(promo: items[i]),
          );
        },
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  const _PromoCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    final code = promo['code'] as String;
    final discountType = promo['discount_type'] as String;
    final discountValue = promo['discount_value'] as int;
    final maxRedemptions = promo['max_redemptions'] as int?;
    final redemptionsCount = promo['redemptions_count'] as int? ?? 0;
    final expiresAt = promo['expires_at'] as String?;

    final discountLabel = discountType == 'percent'
        ? '$discountValue%'
        : '${(discountValue / 100).toStringAsFixed(0)} ₽';
    final exhausted = maxRedemptions != null && redemptionsCount >= maxRedemptions;
    final expiredAt = expiresAt != null ? DateTime.tryParse(expiresAt)?.toLocal() : null;
    final expired = expiredAt != null && expiredAt.isBefore(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (exhausted || expired) ? AppColors.line : AppColors.amber.withValues(alpha: 0.4),
          width: (exhausted || expired) ? 1 : 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code,
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700,
                        color: (exhausted || expired) ? AppColors.ink4 : AppColors.ink,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  exhausted
                      ? 'Использован'
                      : expired
                          ? 'Срок истёк'
                          : expiredAt != null
                              ? 'Скидка $discountLabel · до ${DateFormat('d MMM y', 'ru').format(expiredAt)}'
                              : 'Скидка $discountLabel',
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12,
                      color: (exhausted || expired) ? AppColors.ink4 : AppColors.ink3),
                ),
              ],
            ),
          ),
          if (!exhausted && !expired)
            IconButton(
              icon: const Icon(Icons.copy, size: 20, color: AppColors.ink3),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$code скопирован',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
            ),
        ],
      ),
    );
  }
}
