// Мини-виджет со статистикой попыток входа для хоста. Показывает 24-часовой
// снапшот и подсвечивает всплеск (suspicious=true).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

class JoinStatsCard extends ConsumerStatefulWidget {
  final String eventId;
  const JoinStatsCard({super.key, required this.eventId});

  @override
  ConsumerState<JoinStatsCard> createState() => _JoinStatsCardState();
}

class _JoinStatsCardState extends ConsumerState<JoinStatsCard> {
  bool _loading = true;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('events/${widget.eventId}/join-stats');
      if (!mounted) return;
      setState(() {
        _stats = Map<String, dynamic>.from(resp.data as Map);
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    final s = _stats;
    if (s == null || (s['total'] as int? ?? 0) == 0) return const SizedBox.shrink();

    final ok = s['ok'] as int? ?? 0;
    final badCode = s['bad_code'] as int? ?? 0;
    final badPin = s['bad_pin'] as int? ?? 0;
    final rateLimited = s['rate_limited'] as int? ?? 0;
    final uniqIps = s['unique_ips'] as int? ?? 0;
    final suspicious = s['suspicious'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: suspicious
            ? AppColors.shutter.withValues(alpha: 0.06)
            : AppColors.paper2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: suspicious
              ? AppColors.shutter.withValues(alpha: 0.5)
              : const Color(0x141A1714),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                suspicious ? Icons.warning_amber_rounded : Icons.analytics_outlined,
                size: 18,
                color: suspicious ? AppColors.shutter : AppColors.ink3,
              ),
              const SizedBox(width: 8),
              Text(
                'Попытки входа · 24ч',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _load,
                child: const Icon(Icons.refresh, size: 18, color: AppColors.ink3),
              ),
            ],
          ),
          if (suspicious) ...[
            const SizedBox(height: 8),
            Text(
              '⚠ Подозрительная активность — >20 неудачных попыток за час',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.shutter,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _stat('Успешно', ok, AppColors.success),
              _stat('Неверный код', badCode, AppColors.ink3),
              _stat('Неверный PIN', badPin, AppColors.shutter),
              if (rateLimited > 0)
                _stat('Заблокировано', rateLimited, AppColors.shutter),
              _stat('Уникальных IP', uniqIps, AppColors.ink2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x0D1A1714)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
