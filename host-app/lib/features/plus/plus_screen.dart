import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/tokens.dart';
import '../../core/widgets/brand_icon.dart';
import '../payments/utils/idempotency_key.dart';
import 'plus_providers.dart';

String _rub(int kopecks) {
  final v = kopecks / 100;
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
  return '${s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} ₽';
}

/// ImpoMento Плюс: что входит, цена, оформление, отмена и возобновление автопродления.
class PlusScreen extends ConsumerStatefulWidget {
  const PlusScreen({super.key});

  @override
  ConsumerState<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends ConsumerState<PlusScreen> with WidgetsBindingObserver {
  String _period = 'year';
  bool _busy = false;
  bool _waiting = false;
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waiting) _check();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refreshAll() {
    ref.invalidate(subscriptionProvider);
    ref.invalidate(entitlementsProvider);
    ref.invalidate(collectionsProvider);
  }

  Future<void> _check() async {
    try {
      final resp = await ref.read(dioProvider).get('me/subscription');
      if ((resp.data as Map)['plus'] == true) {
        _poll?.cancel();
        _refreshAll();
        if (!mounted) return;
        setState(() => _waiting = false);
        _snack('Плюс подключён. Спасибо!');
      }
    } catch (_) {}
  }

  void _startPolling() {
    _poll?.cancel();
    _polls = 0;
    setState(() => _waiting = true);
    _poll = Timer.periodic(const Duration(seconds: 3), (t) {
      _polls++;
      if (_polls > 60) {
        t.cancel();
        if (mounted) setState(() => _waiting = false);
        return;
      }
      _check();
    });
  }

  Future<void> _buy() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final resp = await ref.read(dioProvider).post(
            'subscription/checkout',
            data: {'period': _period},
            options: Options(headers: {'Idempotency-Key': newIdempotencyKey()}),
          );
      final url = resp.data['confirmation_url'] as String?;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (mounted) _startPolling();
      } else {
        _refreshAll();
      }
    } catch (e) {
      _snack(extractUserMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleRenew(bool resume) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post(resume ? 'subscription/resume' : 'subscription/cancel');
      _refreshAll();
      _snack(resume ? 'Автопродление включено' : 'Автопродление выключено');
    } catch (e) {
      _snack(extractUserMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _feature(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: SparkMark(size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.manrope(fontSize: 14, height: 1.45, color: AppColors.ink))),
        ]),
      );

  Widget _periodCard(String id, String label, int price, String hint) {
    final on = _period == id;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _period = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.paper2 : AppColors.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? AppColors.amber : AppColors.line, width: on ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: GoogleFonts.playfairDisplay(
                    fontFeatures: [const FontFeature.liningFigures()],
                    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink,
                  )),
              const SizedBox(height: 2),
              Text(hint, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3)),
            ]),
          ),
          Text(_rub(price),
              style: GoogleFonts.inter(
                fontFeatures: [const FontFeature.tabularFigures()],
                fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink,
              )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(subscriptionProvider);
    final plus = ref.watch(plusPricingProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: subAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
          error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(extractUserMessage(e)),
              TextButton(onPressed: () => ref.invalidate(subscriptionProvider), child: const Text('Повторить')),
            ]),
          ),
          data: (s) {
            final isPlus = s['plus'] == true && s['status'] != null;
            final enabled = s['enabled'] == true;
            final cancelAtEnd = s['cancel_at_period_end'] == true;
            final month = s['month_kopecks'] as int? ?? 0;
            final year = s['year_kopecks'] as int? ?? 0;
            final perMonth = (year / 12).round();
            final saving = month > 0 ? ((1 - year / (month * 12)) * 100).round() : 0;
            final endRaw = s['current_period_end'] as String?;
            final end = endRaw == null ? null : DateTime.tryParse(endRaw)?.toLocal();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Row(children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.canPop() ? context.pop() : context.go('/profile'),
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(color: AppColors.paper2, shape: BoxShape.circle),
                      child: const Icon(Icons.chevron_left, color: AppColors.ink, size: 22),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                Text(isPlus ? 'ПОДПИСКА АКТИВНА' : 'ПОДПИСКА',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
                const SizedBox(height: 4),
                Text('ImpoMento Плюс',
                    style: GoogleFonts.playfairDisplay(
                      fontFeatures: [const FontFeature.liningFigures()],
                      fontSize: 32, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.4,
                    )),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const BrandIcon('plus', size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text('Больше места для личных альбомов, подборки без границ и оформление, которого нет у других.',
                          style: GoogleFonts.manrope(fontSize: 13.5, height: 1.5, color: AppColors.ink3)),
                    ),
                  ]),
                ),
                if (isPlus)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.paper2,
                      borderRadius: BorderRadius.circular(20),
                      border: const Border(left: BorderSide(color: Color(0xFF4F7B53), width: 3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cancelAtEnd ? 'Не продлится' : 'Продлевается автоматически',
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(
                        'Действует до ${end == null ? '—' : DateFormat('d MMMM y', 'ru').format(end)}'
                        '${s['period'] == 'year' ? ' (годовая)' : ' (месячная)'}',
                        style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _toggleRenew(cancelAtEnd),
                        child: Text(cancelAtEnd ? 'Включить автопродление' : 'Отменить автопродление'),
                      ),
                    ]),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ЧТО ВХОДИТ',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
                    const SizedBox(height: 4),
                    if (plus != null && plus.isNotEmpty) ...[
                      _feature('Соло-альбомы: до ${plus['solo_frames_per_month']} кадров в месяц вместо ${plus['solo_free_frames_per_month']}, '
                          'хранятся, пока действует подписка (без неё ${((plus['solo_free_retention_days'] as int? ?? 90) / 30).round()} мес.)'),
                      _feature('События на 5 гостей: ${plus['events_active']} одновременно и ${plus['events_per_month']} в месяц '
                          'вместо ${plus['free_events_active']} и ${plus['free_events_per_month']}'),
                      _feature('Мини-альбомы без ограничения по числу (вместо ${plus['mini_free_albums']}), '
                          'до ${plus['mini_frames_per_album']} кадров в подборке вместо ${plus['mini_free_frames_per_album']}'),
                    ],
                    _feature('Дополнительные QR-стили, шрифты названия и темы оформления альбома'),
                    _feature('Все новые функции первыми'),
                  ]),
                ),
                const SizedBox(height: 14),
                if (!enabled)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(20)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Скоро', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text('Подписка пока не запущена: все возможности из списка работают без оплаты, пока мы заканчиваем подключение платежей.',
                          style: GoogleFonts.manrope(fontSize: 13, height: 1.45, color: AppColors.ink3)),
                    ]),
                  ),
                if (enabled && !(isPlus && !cancelAtEnd)) ...[
                  _periodCard('year', 'На год', year, '${_rub(perMonth)} в месяц, выгода $saving%'),
                  _periodCard('month', 'На месяц', month, 'Продлевается каждый месяц'),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: AppSizes.buttonHeight,
                    child: ElevatedButton(
                      onPressed: (_busy || _waiting) ? null : _buy,
                      child: (_busy || _waiting)
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Оформить за ${_rub(_period == 'year' ? year : month)}'),
                    ),
                  ),
                  if (_waiting)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Ждём подтверждения оплаты. После оплаты вернитесь в приложение.',
                          textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3)),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Оплата банковской картой с сохранением способа оплаты для автопродления. '
                    'Отменить можно в любой момент здесь же: доступ сохранится до конца оплаченного периода.',
                    style: GoogleFonts.manrope(fontSize: 12.5, height: 1.45, color: AppColors.ink3),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
