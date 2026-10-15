import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

/// Экран согласий по 152-ФЗ — одна фраза + ссылка на страницу с документами.
///
/// Показывается ПОСЛЕ verify_otp, ДО перехода на /dashboard. Никаких чекбоксов —
/// само нажатие «Продолжить» = согласие (паттерн web PWA landing).
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  static const _docVersion = '2.4';
  bool _loading = false;
  String? _errorMsg;

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final dio = ref.read(dioProvider);
      const docTypes = ['offer', 'privacy', 'consent', 'content_rules', 'age_confirmation'];
      for (final docType in docTypes) {
        await dio.post('consent', data: {
          'doc_type': docType,
          'doc_version': _docVersion,
        });
      }
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = extractUserMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTerms() async {
    await launchUrl(
      Uri.parse('https://impomento.pro/terms'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Почти всё готово',
                      style: GoogleFonts.playfairDisplay(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        fontSize: 32,
                        height: 1.1,
                        letterSpacing: -0.64,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 16),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          height: 1.55,
                          color: AppColors.ink2,
                        ),
                        children: [
                          const TextSpan(text: 'Нажимая «Продолжить», вы соглашаетесь с '),
                          TextSpan(
                            text: 'условиями сервиса',
                            style: const TextStyle(
                              color: AppColors.amber,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.amber,
                            ),
                            recognizer: TapGestureRecognizerFactory.of(_openTerms),
                          ),
                          const TextSpan(text: ' и подтверждаете, что вам исполнилось 14 лет.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Организатор события отвечает за приглашение гостей и обработку общего альбома.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.ink3,
                        height: 1.5,
                      ),
                    ),
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMsg!,
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    disabledBackgroundColor: AppColors.paper3,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: AppColors.ink4,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Продолжить',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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

/// Helper для tap-recognizer в RichText без внешних зависимостей.
class TapGestureRecognizerFactory {
  static _TapWrapper of(VoidCallback onTap) => _TapWrapper(onTap);
}

class _TapWrapper extends TapGestureRecognizer {
  _TapWrapper(VoidCallback onTap) {
    this.onTap = onTap;
  }
}
