import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../events/events_provider.dart';

/// Экран ожидания подтверждения платежа YooKassa.
///
/// Открывается после `launchUrl` внешнего браузера — polling `/events/{id}`
/// каждые 3 секунды, до 60 секунд (20 попыток).
///
/// `successPredicate` — функция проверки успеха по данным события.
///  - checkout: `status == "active"`
///  - extend: `expires_at` выросла
///  - upgrade guests: `plan` изменился
///  - upgrade frames: `frames_per_guest == 45`
class PaymentWaitingScreen extends ConsumerStatefulWidget {
  final String eventId;
  final bool Function(Map<String, dynamic> eventJson) successPredicate;
  final String successMessage;
  final String returnPath;

  const PaymentWaitingScreen({
    super.key,
    required this.eventId,
    required this.successPredicate,
    this.successMessage = 'Оплата прошла',
    this.returnPath = '/dashboard',
  });

  @override
  ConsumerState<PaymentWaitingScreen> createState() => _PaymentWaitingScreenState();
}

class _PaymentWaitingScreenState extends ConsumerState<PaymentWaitingScreen> {
  static const _pollInterval = Duration(seconds: 3);
  static const _maxAttempts = 20;

  Timer? _timer;
  int _attempts = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // Первый poll — сразу, чтобы поймать быстрый webhook (mock-режим).
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_finished) return;
    _attempts++;
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('events/${widget.eventId}');
      final data = (resp.data as Map).cast<String, dynamic>();
      if (widget.successPredicate(data)) {
        _finish(success: true);
        return;
      }
    } catch (_) {
      // Ошибки сети во время polling — игнорируем, продолжаем попытки.
    }
    if (_attempts >= _maxAttempts) {
      _finish(success: false);
    }
  }

  void _finish({required bool success}) {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    if (!mounted) return;
    ref.invalidate(eventsProvider);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.successMessage,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
        backgroundColor: const Color(0xFF4CAF79),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      context.go('/events/${widget.eventId}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
          'Платёж ещё не подтверждён. Обычно занимает до 5 минут — можно проверить позже.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14),
        ),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      context.go(widget.returnPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: AppColors.amber,
                  strokeWidth: 2.4,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Ждём подтверждение оплаты',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontFeatures: [const FontFeature.liningFigures()],
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Обычно 5–10 секунд после оплаты в ЮKassa. '
                'Если платёж прошёл — вы увидите альбом автоматически.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  color: AppColors.ink3,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _finished ? null : () => _poll(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.ink, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Я уже оплатил — проверить сейчас',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _finished ? null : () => _finish(success: false),
                child: Text(
                  'Проверить позже',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
