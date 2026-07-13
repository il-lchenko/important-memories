import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../auth_provider.dart';

class AuthOtpScreen extends ConsumerStatefulWidget {
  final String email;
  const AuthOtpScreen({super.key, required this.email});

  @override
  ConsumerState<AuthOtpScreen> createState() => _AuthOtpScreenState();
}

class _AuthOtpScreenState extends ConsumerState<AuthOtpScreen> {
  final _cells = List.generate(6, (_) => TextEditingController());
  final _foci  = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _resendCountdown = 48;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() async {
    while (_resendCountdown > 0 && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _resendCountdown--);
    }
  }

  String get _code => _cells.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length < 6 || _loading) return;
    setState(() { _loading = true; _errorMsg = null; });
    try {
      await ref.read(authProvider.notifier).verifyCode(widget.email, _code);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = extractUserMessage(e));
        for (final c in _cells) { c.clear(); }
        _foci.first.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCellChanged(int index, String value) {
    if (_loading) return;
    if (value.length == 1 && index < 5) {
      _foci[index + 1].requestFocus();
    }
    if (value.isNotEmpty && index == 5) _verify();
  }

  @override
  void dispose() {
    for (final c in _cells) { c.dispose(); }
    for (final f in _foci) { f.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.paper2,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.chevron_left, color: AppColors.ink2, size: 22),
                ),
              ),
            ),
            // Auth content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.amber.withValues(alpha: 0.10),
                      ),
                      child: const Icon(Icons.mark_email_read_outlined, color: AppColors.amber, size: 28),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Подтверждение\nаккаунта',
                      style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.72,
                        height: 1.05,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          color: AppColors.ink3,
                          height: 1.5,
                        ),
                        children: [
                          const TextSpan(text: 'На почту '),
                          TextSpan(
                            text: widget.email,
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink2,
                            ),
                          ),
                          const TextSpan(text: ' отправлен 6-значный код. Введите его для входа'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // OTP cells
                    Row(
                      children: [
                        for (int i = 0; i < 6; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _OtpCell(
                              controller: _cells[i],
                              focusNode: _foci[i],
                              onChanged: (v) => _onCellChanged(i, v),
                              onBackspace: i > 0 ? () {
                                if (_cells[i].text.isEmpty) {
                                  _foci[i - 1].requestFocus();
                                  _cells[i - 1].clear();
                                }
                              } : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Resend
                    Center(
                      child: _resendCountdown > 0
                          ? Text.rich(
                              TextSpan(
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: AppColors.ink3,
                                ),
                                children: [
                                  const TextSpan(text: 'Отправить снова через '),
                                  TextSpan(
                                    text: '00:${_resendCountdown.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      fontFamily: 'JetBrains Mono',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTap: () async {
                                setState(() { _resendCountdown = 48; _errorMsg = null; });
                                _startCountdown();
                                try {
                                  await ref.read(authProvider.notifier).requestCode(widget.email);
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _errorMsg = extractUserMessage(e));
                                  }
                                }
                              },
                              child: const Text(
                                'Отправить снова',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: AppColors.amber,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                    ),
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 13,
                            color: AppColors.shutter,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: 20),
                      const Center(child: CircularProgressIndicator(color: AppColors.amber, strokeWidth: 2)),
                    ],
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

class _OtpCell extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBackspace;

  const _OtpCell({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / 1.15,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace?.call();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          maxLength: 1,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: AppColors.paper2,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
