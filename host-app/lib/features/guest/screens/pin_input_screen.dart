// Экран ввода 4-значного PIN. Открывается когда backend вернул PIN_REQUIRED
// на POST /guest/sessions. При успехе перекидывает на камеру, как обычный
// join. При BAD_PIN показывает красную ошибку под ячейками, ячейки очищаются.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';
import '../guest_provider.dart';

class PinInputScreen extends ConsumerStatefulWidget {
  final String code;
  // Опционально: имя гостя пришло с landing (если анонимный). Не спрашиваем повторно.
  final String? guestName;
  // Опционально: заголовок события — для показа контекста «PIN для события X».
  final String? eventTitle;
  // Если пришли по QR со встроенным PIN (?p=1234) — автосабмит.
  final String? prefilledPin;

  const PinInputScreen({
    super.key,
    required this.code,
    this.guestName,
    this.eventTitle,
    this.prefilledPin,
  });

  @override
  ConsumerState<PinInputScreen> createState() => _PinInputScreenState();
}

class _PinInputScreenState extends ConsumerState<PinInputScreen> {
  static const _len = 4;
  final _controllers = List.generate(_len, (_) => TextEditingController());
  final _focusNodes = List.generate(_len, (_) => FocusNode());
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-submit если PIN пришёл из QR-кода.
    final pin = widget.prefilledPin;
    if (pin != null && pin.length == _len && RegExp(r'^\d{4}$').hasMatch(pin)) {
      for (int i = 0; i < _len; i++) {
        _controllers[i].text = pin[i];
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  void _onChanged(int i, String value) {
    if (value.length > 1) {
      // Paste of full PIN.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int j = 0; j < _len && j < digits.length; j++) {
        _controllers[j].text = digits[j];
      }
      if (digits.length >= _len) {
        _focusNodes[_len - 1].unfocus();
        _submit();
      } else {
        _focusNodes[digits.length].requestFocus();
      }
      setState(() {});
      return;
    }
    if (value.isNotEmpty) {
      _controllers[i].text = value;
      if (i < _len - 1) {
        _focusNodes[i + 1].requestFocus();
      } else {
        _focusNodes[i].unfocus();
        _submit();
      }
    } else if (i > 0) {
      _focusNodes[i - 1].requestFocus();
    }
    setState(() {});
  }

  bool get _canSubmit => _controllers.every((c) => c.text.isNotEmpty);

  String get _pin => _controllers.map((c) => c.text).join();

  void _clearAndFocusFirst() {
    for (final c in _controllers) { c.clear(); }
    _focusNodes[0].requestFocus();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fingerprint = await getDeviceFingerprint();
      final dio = ref.read(dioProvider);
      final resp = await dio.post('guest/sessions', data: {
        'short_code': widget.code,
        if (widget.guestName != null && widget.guestName!.isNotEmpty)
          'name': widget.guestName,
        'fingerprint': fingerprint,
        'pin': _pin,
      });
      final data = Map<String, dynamic>.from(resp.data as Map);
      final guestToken = data['guest_token'] as String;
      final guestName = data['name'] as String? ?? '';
      final event = data['event'] as Map;
      final eventId = event['id'] as String;
      final framesRemaining = data['frames_remaining'] as int? ?? 10;
      final settings = event['settings'] as Map? ?? {};
      final lutPreset = settings['lut_preset'] as String? ?? 'original';

      await GuestPrefs.saveSession(
        eventId: eventId,
        token: guestToken,
        framesRemaining: framesRemaining,
        lutPreset: lutPreset,
      );
      if (guestName.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('guest_name', guestName);
      }
      if (!mounted) return;
      context.go('/guest/camera/$eventId');
    } catch (e) {
      if (!mounted) return;
      final code = extractErrorCode(e);
      String msg;
      if (code == 'BAD_PIN') {
        msg = 'Неверный PIN. Проверьте у организатора.';
      } else if (code == 'RATE_LIMITED') {
        msg = 'Слишком много попыток. Попробуйте через час.';
      } else {
        msg = extractUserMessage(e);
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
      _clearAndFocusFirst();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: AppSizes.iconBtnSize,
                  height: AppSizes.iconBtnSize,
                  decoration: BoxDecoration(
                    color: AppColors.paper2,
                    borderRadius: AppRadius.smBR,
                  ),
                  child: const Icon(Icons.arrow_back, size: 18, color: AppColors.ink2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PIN события',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                      letterSpacing: -0.64,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.eventTitle != null
                        ? '«${widget.eventTitle}» защищён PIN. Введите 4 цифры от организатора.'
                        : 'Организатор включил защиту PIN. Введите 4 цифры.',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.ink3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      for (int i = 0; i < _len; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: KeyboardListener(
                            focusNode: FocusNode(),
                            onKeyEvent: (event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.backspace &&
                                  _controllers[i].text.isEmpty &&
                                  i > 0) {
                                _controllers[i - 1].clear();
                                _focusNodes[i - 1].requestFocus();
                                setState(() {});
                              }
                            },
                            child: Builder(builder: (context) {
                              final filled = _controllers[i].text.isNotEmpty;
                              return TextField(
                                controller: _controllers[i],
                                focusNode: _focusNodes[i],
                                textAlign: TextAlign.center,
                                maxLength: 2,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: filled ? AppColors.amber : AppColors.ink,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: _error != null
                                          ? AppColors.shutter
                                          : (filled
                                              ? AppColors.amber
                                              : const Color(0x201A1714)),
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: _error != null
                                          ? AppColors.shutter
                                          : AppColors.amber,
                                      width: 1.5,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.paper,
                                ),
                                onChanged: (v) => _onChanged(i, v),
                              );
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppColors.shutter,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14 + bottom),
              child: GestureDetector(
                onTap: (_canSubmit && !_loading) ? _submit : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: AppSizes.buttonHeight,
                  decoration: BoxDecoration(
                    color: (_canSubmit && !_loading)
                        ? AppColors.ink
                        : AppColors.ink.withValues(alpha: 0.25),
                    borderRadius: AppRadius.mdBR,
                  ),
                  alignment: Alignment.center,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Войти в альбом',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

