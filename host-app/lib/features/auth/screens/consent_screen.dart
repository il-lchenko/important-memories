import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

/// Отдельный экран согласий по 152-ФЗ ст. 9 (в редакции с 01.09.2025).
///
/// Показывается ПОСЛЕ verify_otp (пользователь уже залогинен, есть access-token),
/// ДО перехода на /dashboard. Четыре независимых чекбокса — по одному на каждый
/// документ. Кнопка «Продолжить» активна только когда все четыре ✓.
///
/// При «Продолжить» шлём POST /api/v1/consent × 4 (по одному на doc_type)
/// и переходим на /dashboard.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  static const _docVersion = '2.2';

  bool _agreeOffer = false;
  bool _agreePrivacy = false;
  bool _agreeConsent = false;
  bool _agreeContentRules = false;
  bool _confirmAge = false;

  bool _loading = false;
  String? _errorMsg;

  bool get _allChecked =>
      _agreeOffer && _agreePrivacy && _agreeConsent && _agreeContentRules && _confirmAge;

  Future<void> _submit() async {
    if (!_allChecked || _loading) return;
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

  Future<void> _openDoc(String path) async {
    await launchUrl(
      Uri.parse('https://impomento.pro/$path'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.amber.withValues(alpha: 0.10),
                      ),
                      child: const Icon(
                        Icons.privacy_tip_outlined,
                        color: AppColors.amber,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Немного\nформальностей',
                      style: GoogleFonts.playfairDisplay(
                        fontFeatures: [const FontFeature.liningFigures()],
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.72,
                        height: 1.05,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Перед началом работы с ImpoMento подтвердите, что ознакомлены с четырьмя документами. Каждый — по клику.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.ink3,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _ConsentCheckbox(
                      checked: _agreeOffer,
                      onChanged: (v) => setState(() => _agreeOffer = v ?? false),
                      onLinkTap: () => _openDoc('offer'),
                      title: 'Публичная оферта',
                      subtitle: 'Условия оказания услуг, тарифы, возвраты',
                    ),
                    const SizedBox(height: 12),
                    _ConsentCheckbox(
                      checked: _agreePrivacy,
                      onChanged: (v) => setState(() => _agreePrivacy = v ?? false),
                      onLinkTap: () => _openDoc('privacy'),
                      title: 'Политика конфиденциальности',
                      subtitle: 'Какие данные и зачем мы обрабатываем',
                    ),
                    const SizedBox(height: 12),
                    _ConsentCheckbox(
                      checked: _agreeConsent,
                      onChanged: (v) => setState(() => _agreeConsent = v ?? false),
                      onLinkTap: () => _openDoc('consent'),
                      title: 'Согласие на обработку ПД',
                      subtitle: 'Отдельный документ по 152-ФЗ',
                    ),
                    const SizedBox(height: 12),
                    _ConsentCheckbox(
                      checked: _agreeContentRules,
                      onChanged: (v) => setState(() => _agreeContentRules = v ?? false),
                      onLinkTap: () => _openDoc('content-rules'),
                      title: 'Правила пользовательского контента',
                      subtitle: 'Что можно и нельзя загружать в альбомы',
                    ),
                    const SizedBox(height: 24),
                    _ConsentCheckbox(
                      checked: _confirmAge,
                      onChanged: (v) => setState(() => _confirmAge = v ?? false),
                      title: 'Возраст и согласие',
                      subtitle:
                          'Мне 18 лет и больше — либо мне 16–17, и мой законный представитель дал согласие на использование сервиса и оплату тарифа (ст. 26 ГК РФ)',
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
                  onPressed: (_allChecked && !_loading) ? _submit : null,
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

class _ConsentCheckbox extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final String title;
  final String subtitle;
  final VoidCallback? onLinkTap;

  const _ConsentCheckbox({
    required this.checked,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        decoration: BoxDecoration(
          color: checked ? AppColors.amber.withValues(alpha: 0.06) : AppColors.paper2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked ? AppColors.amber.withValues(alpha: 0.30) : AppColors.line,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                onChanged: onChanged,
                activeColor: AppColors.amber,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                side: const BorderSide(color: AppColors.ink3, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (onLinkTap != null)
                        GestureDetector(
                          onTap: onLinkTap,
                          child: const Text(
                            'открыть →',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.amber,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.ink3,
                      height: 1.4,
                    ),
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
