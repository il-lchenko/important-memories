import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';

class CodeInputScreen extends StatefulWidget {
  const CodeInputScreen({super.key});

  @override
  State<CodeInputScreen> createState() => _CodeInputScreenState();
}

class _CodeInputScreenState extends State<CodeInputScreen> {
  static const _len = 8;
  final _controllers = List.generate(_len, (_) => TextEditingController());
  final _focusNodes = List.generate(_len, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  void _onChanged(int i, String value) {
    if (value.length > 1) {
      // Pasted or autocompleted — distribute across cells
      final chars = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
      for (int j = 0; j < _len && j < chars.length; j++) {
        _controllers[i + j < _len ? i + j : _len - 1].text =
            j < chars.length ? chars[j] : '';
      }
      final next = (i + chars.length).clamp(0, _len - 1);
      _focusNodes[next].requestFocus();
      setState(() {});
      return;
    }
    if (value.isNotEmpty) {
      _controllers[i].text = value.toUpperCase();
      _controllers[i].selection =
          const TextSelection.collapsed(offset: 1);
      if (i < _len - 1) {
        _focusNodes[i + 1].requestFocus();
      } else {
        _submit();
      }
    } else if (i > 0) {
      _focusNodes[i - 1].requestFocus();
    }
    setState(() {});
  }

  bool get _canSubmit =>
      _controllers.every((c) => c.text.isNotEmpty);

  String get _code => _controllers.map((c) => c.text).join();

  void _submit() {
    if (!_canSubmit) return;
    context.go('/guest/landing/${_code.trim()}');
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
              child: _IconBtn(icon: Icons.arrow_back, onTap: () => context.pop()),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Код события',
                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                      letterSpacing: -0.64,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '8-значный код события — спросите у организатора или найдите его в деталях события',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.ink3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // OTP cells
                  Row(
                    children: [
                      for (int i = 0; i < _len; i++) ...[
                        if (i > 0) const SizedBox(width: 5),
                        Expanded(
                          child: KeyboardListener(
                            focusNode: FocusNode(),
                            onKeyEvent: (event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.backspace &&
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
                                keyboardType: TextInputType.visiblePassword,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9]')),
                                  UpperCaseTextFormatter(),
                                ],
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: filled ? AppColors.amber : AppColors.ink,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: filled
                                          ? AppColors.amber
                                          : const Color(0x201A1714),
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: AppColors.amber,
                                      width: 1.5,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.paper,
                                ),
                                onChanged: (v) => _onChanged(i, v),
                                onSubmitted: (_) {
                                  if (i < _len - 1) {
                                    _focusNodes[i + 1].requestFocus();
                                  } else {
                                    _submit();
                                  }
                                },
                              );
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14 + bottom),
              child: Column(
                children: [
                  _GhostBtn(
                    label: 'Открыть камеру для QR',
                    onTap: () => context.push('/guest/qr'),
                  ),
                  const SizedBox(height: 8),
                  _PrimaryBtn(
                    label: 'Войти в альбом',
                    enabled: _canSubmit,
                    onTap: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSizes.iconBtnSize,
        height: AppSizes.iconBtnSize,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: AppRadius.smBR,
        ),
        child: Icon(icon, size: 18, color: AppColors.ink2),
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: AppSizes.buttonHeight,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x201A1714), width: 1.5),
          borderRadius: AppRadius.mdBR,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Открыть камеру для QR',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _PrimaryBtn(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: AppSizes.buttonHeight,
        decoration: BoxDecoration(
          color: enabled ? AppColors.ink : AppColors.ink.withValues(alpha: 0.25),
          borderRadius: AppRadius.mdBR,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Войти в альбом',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
