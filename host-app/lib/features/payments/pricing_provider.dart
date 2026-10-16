import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Цены и лимиты приходят с сервера (GET /pricing) — клиент их не хардкодит.
/// [Pricing.fallback] нужен только пока ответ не пришёл или сервер недоступен.
class PricingTier {
  final String plan;
  final int maxGuests;
  final int priceRub;
  final int retentionDays;
  const PricingTier(this.plan, this.maxGuests, this.priceRub, this.retentionDays);
}

class ExtendPrice {
  final String period;
  final int days;
  final int minRub;
  final int perGuestRub;
  const ExtendPrice(this.period, this.days, this.minRub, this.perGuestRub);

  int priceFor(int maxGuests) {
    final byGuests = perGuestRub * maxGuests;
    return byGuests > minRub ? byGuests : minRub;
  }
}

class Pricing {
  final List<PricingTier> tiers;
  final int customFromGuests;
  final int customBaseRub;
  final int customPerGuestRub;
  final int framesExtended;
  final int framesPricePerGuestRub;
  final List<ExtendPrice> extend;
  final List<ExtendPrice> soloExtend;
  final double upgradePremium;
  final int? freeActiveEvents;
  final int? freeEventsPerMonth;

  const Pricing({
    required this.tiers,
    required this.customFromGuests,
    required this.customBaseRub,
    required this.customPerGuestRub,
    required this.framesExtended,
    required this.framesPricePerGuestRub,
    required this.extend,
    this.soloExtend = const [],
    required this.upgradePremium,
    this.freeActiveEvents,
    this.freeEventsPerMonth,
  });

  static const fallback = Pricing(
    tiers: [
      PricingTier('free', 5, 0, 30),
      PricingTier('p10', 10, 249, 30),
      PricingTier('p25', 25, 449, 60),
      PricingTier('p50', 50, 1290, 90),
      PricingTier('p75', 75, 1990, 90),
      PricingTier('p100', 100, 2990, 120),
      PricingTier('p150', 150, 4490, 150),
      PricingTier('p175', 175, 5490, 180),
      PricingTier('p200', 200, 6290, 180),
      PricingTier('p250', 250, 7690, 240),
    ],
    customFromGuests: 251,
    customBaseRub: 7690,
    customPerGuestRub: 30,
    framesExtended: 45,
    framesPricePerGuestRub: 5,
    extend: [
      ExtendPrice('3m', 90, 490, 0),
      ExtendPrice('6m', 180, 790, 0),
      ExtendPrice('1y', 365, 1290, 0),
    ],
    upgradePremium: 1.15,
    freeActiveEvents: 2,
    freeEventsPerMonth: 4,
  );

  static int _rub(dynamic kopecks) => ((kopecks as num?) ?? 0) ~/ 100;

  factory Pricing.fromJson(Map<String, dynamic> j) {
    final custom = Map<String, dynamic>.from(j['custom'] as Map);
    final frames = Map<String, dynamic>.from(j['frames'] as Map);
    return Pricing(
      tiers: [
        for (final t in (j['tiers'] as List))
          PricingTier(
            t['plan'] as String,
            t['max_guests'] as int,
            _rub(t['price_kopecks']),
            t['retention_days'] as int,
          ),
      ],
      customFromGuests: custom['from_guests'] as int,
      customBaseRub: _rub(custom['base_price_kopecks']),
      customPerGuestRub: _rub(custom['per_guest_kopecks']),
      framesExtended: frames['extended_per_guest'] as int,
      framesPricePerGuestRub: _rub(frames['price_per_guest_kopecks']),
      extend: [
        for (final e in (j['extend'] as List))
          ExtendPrice(
            e['period'] as String,
            e['days'] as int,
            _rub(e['price_kopecks']),
            _rub(e['per_guest_kopecks']),
          ),
      ],
      soloExtend: [
        for (final e in ((j['solo_extend'] as List?) ?? const []))
          ExtendPrice(e['period'] as String, e['days'] as int, _rub(e['price_kopecks']), 0),
      ],
      upgradePremium: (j['upgrade_premium'] as num?)?.toDouble() ?? 1.15,
      freeActiveEvents: j['free_active_events'] as int?,
      freeEventsPerMonth: j['free_events_per_month'] as int?,
    );
  }

  PricingTier? tierFor(String plan) {
    for (final t in tiers) {
      if (t.plan == plan) return t;
    }
    return null;
  }

  /// Цена тарифа, покрывающего n гостей (для 250+ — по формуле).
  int priceForGuests(int n) {
    for (final t in tiers) {
      if (n <= t.maxGuests) return t.priceRub;
    }
    return customBaseRub + (n - (customFromGuests - 1)) * customPerGuestRub;
  }

  ExtendPrice? extendFor(String period) {
    for (final e in extend) {
      if (e.period == period) return e;
    }
    return null;
  }
}

final pricingProvider = FutureProvider<Pricing>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final resp = await dio.get('pricing');
    return Pricing.fromJson(Map<String, dynamic>.from(resp.data as Map));
  } catch (_) {
    return Pricing.fallback;
  }
});

/// Удобный доступ: актуальные цены или запасные, пока ответа нет.
Pricing pricingOf(WidgetRef ref) =>
    ref.watch(pricingProvider).valueOrNull ?? Pricing.fallback;
