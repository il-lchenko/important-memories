// Карточка «PIN входа» для event_detail. Показывает состояние, позволяет
// включить/выключить/сгенерировать новый PIN и скопировать. QR-код обновляется
// автоматически (backend отдаёт URL с ?p=PIN, если pin_enabled).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';

class PinCard extends ConsumerStatefulWidget {
  final String eventId;
  const PinCard({super.key, required this.eventId});

  @override
  ConsumerState<PinCard> createState() => _PinCardState();
}

class _PinCardState extends ConsumerState<PinCard> {
  bool _loading = true;
  bool _mutating = false;
  bool _enabled = false;
  String? _pin;
  bool _hidden = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('events/${widget.eventId}/pin');
      final data = Map<String, dynamic>.from(resp.data as Map);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _enabled = data['pin_enabled'] as bool? ?? false;
        _pin = data['entry_pin'] as String?;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractUserMessage(e);
      });
    }
  }

  Future<void> _mutate({required bool enabled, String? pin}) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.patch(
        'events/${widget.eventId}/pin',
        data: {'enabled': enabled, if (pin != null) 'pin': pin},
      );
      final data = Map<String, dynamic>.from(resp.data as Map);
      if (!mounted) return;
      setState(() {
        _enabled = data['pin_enabled'] as bool? ?? false;
        _pin = data['entry_pin'] as String?;
        _mutating = false;
        _error = null;
      });
      // Пере-запрашиваем детали события — pin_enabled используется в других виджетах.
      ref.invalidate(eventDetailProvider(widget.eventId));
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _mutating = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mutating = false;
        _error = extractUserMessage(e);
      });
    }
  }

  void _copyPin() {
    if (_pin == null) return;
    Clipboard.setData(ClipboardData(text: _pin!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'PIN скопирован',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.paper),
        ),
        backgroundColor: AppColors.dark3,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x141A1714)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _enabled ? Icons.lock_outline : Icons.lock_open,
                size: 18,
                color: _enabled ? AppColors.amber : AppColors.ink3,
              ),
              const SizedBox(width: 8),
              Text(
                'PIN входа',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              if (_loading || _mutating)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                )
              else
                Switch(
                  value: _enabled,
                  activeColor: AppColors.amber,
                  onChanged: (v) => _mutate(enabled: v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _enabled
                ? 'Гости вводят 4 цифры дополнительно к коду события. Защита от случайного попадания в чужой альбом.'
                : 'Только код события. Без PIN — сканирование QR открывает альбом сразу.',
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.45,
              color: AppColors.ink3,
            ),
          ),
          if (_enabled && _pin != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x1FC9881E)),
              ),
              child: Row(
                children: [
                  Text(
                    _hidden ? '• • • •' : _pin!,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.amber,
                      letterSpacing: 8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _hidden ? 'Показать' : 'Скрыть',
                    icon: Icon(
                      _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.ink3,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                  IconButton(
                    tooltip: 'Скопировать',
                    icon: const Icon(Icons.copy, size: 18, color: AppColors.ink3),
                    onPressed: _copyPin,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _mutating ? null : () => _mutate(enabled: true, pin: null),
                  icon: const Icon(Icons.refresh, size: 16, color: AppColors.ink2),
                  label: Text(
                    'Новый PIN',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.shutter),
            ),
          ],
        ],
      ),
    );
  }
}
