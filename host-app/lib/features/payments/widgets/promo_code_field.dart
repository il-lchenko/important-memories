import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

/// Универсальное поле «У меня есть промокод».
///
/// Отправляет `POST /promocodes/validate` для preview скидки без применения.
/// В случае успеха вызывает [onApplied] с (code, discountKopecks, finalAmountKopecks).
class PromoCodeField extends ConsumerStatefulWidget {
  final String? eventId;
  final String kind; // 'checkout' | 'extend' | 'upgrade'
  final String? plan;
  final String? period;
  final String? upgradeKind;
  final void Function(String code, int discountKopecks, int finalAmountKopecks) onApplied;
  final VoidCallback onCleared;

  const PromoCodeField({
    super.key,
    this.eventId,
    required this.kind,
    this.plan,
    this.period,
    this.upgradeKind,
    required this.onApplied,
    required this.onCleared,
  });

  @override
  ConsumerState<PromoCodeField> createState() => _PromoCodeFieldState();
}

class _PromoCodeFieldState extends ConsumerState<PromoCodeField> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _applied = false;
  String? _error;
  int _discount = 0;
  int _final = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post(
        'promocodes/validate',
        data: {
          'code': code,
          if (widget.eventId != null) 'event_id': widget.eventId,
          'kind': widget.kind,
          if (widget.plan != null) 'plan': widget.plan,
          if (widget.period != null) 'period': widget.period,
          if (widget.upgradeKind != null) 'upgrade_kind': widget.upgradeKind,
        },
      );
      final data = (resp.data as Map).cast<String, dynamic>();
      if (data['valid'] == true) {
        setState(() {
          _applied = true;
          _discount = (data['discount_kopecks'] as int?) ?? 0;
          _final = (data['final_amount_kopecks'] as int?) ?? 0;
        });
        widget.onApplied(code, _discount, _final);
      } else {
        setState(() => _error = (data['error'] as String?) ?? 'Промокод недействителен');
      }
    } on DioException catch (e) {
      setState(() => _error = extractUserMessage(e));
    } catch (e) {
      setState(() => _error = 'Не удалось проверить промокод');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear() {
    setState(() {
      _applied = false;
      _discount = 0;
      _final = 0;
      _error = null;
      _ctrl.clear();
    });
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    if (_applied) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4CAF79).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF4CAF79)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ctrl.text.trim().toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Скидка ${(_discount / 100).toStringAsFixed(0)} ₽',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Color(0xFF4CAF79),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.ink3),
              onPressed: _clear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.characters,
                enabled: !_loading,
                decoration: InputDecoration(
                  hintText: 'Промокод',
                  hintStyle: const TextStyle(
                    fontFamily: 'Inter', fontSize: 14, color: AppColors.ink4,
                  ),
                  filled: true,
                  fillColor: AppColors.paper2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500,
                  color: AppColors.ink, letterSpacing: 0.5,
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _loading ? null : _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Применить',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.shutter),
          ),
        ],
      ],
    );
  }
}
