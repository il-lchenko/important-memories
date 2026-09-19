import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../auth_provider.dart';

class AuthEmailScreen extends ConsumerStatefulWidget {
  const AuthEmailScreen({super.key});

  @override
  ConsumerState<AuthEmailScreen> createState() => _AuthEmailScreenState();
}

class _AuthEmailScreenState extends ConsumerState<AuthEmailScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()..onTap = () {
      launchUrl(Uri.parse('https://impomento.pro/offer'), mode: LaunchMode.externalApplication);
    };
    _privacyRecognizer = TapGestureRecognizer()..onTap = () {
      launchUrl(Uri.parse('https://impomento.pro/privacy'), mode: LaunchMode.externalApplication);
    };
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).requestCode(_emailCtrl.text.trim());
      if (mounted) {
        // Plain green toast «Код отправлен», плавно всплывает снизу и исчезает через 2 сек.
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Код отправлен на почту',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            duration: const Duration(milliseconds: 2200),
            elevation: 3,
          ),
        );
        context.push('/auth/otp?email=${Uri.encodeComponent(_emailCtrl.text.trim())}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extractUserMessage(e), style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
            backgroundColor: AppColors.shutter,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top bar: back + info (пересмотреть онбординг)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: context.canPop() ? () => context.pop() : null,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.paper2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.chevron_left, color: AppColors.ink, size: 22),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go('/onboarding'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.paper2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.help_outline, color: AppColors.ink3, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // main content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // decorative logo (centered, larger)
                      Image.asset(
                        'assets/brand/logo-F-light.png',
                        width: 176, height: 176,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(height: 22),
                      // title (centered, 2 lines) — "M" в ImpoMento амбер, как в брендовом lockup
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Вход\nв Impo'),
                            TextSpan(
                              text: 'M',
                              style: TextStyle(color: AppColors.amber),
                            ),
                            const TextSpan(text: 'ento'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                      const SizedBox(height: 10),

                      // subtitle
                      Text(
                        'Укажите вашу почту.\nВышлем на неё код для авторизации',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // email label
                      const Text(
                        'EMAIL',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          letterSpacing: 0.14,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // email field
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'your@email.com',
                          prefixIcon: Icon(Icons.mail_outline, color: AppColors.ink3, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Введите email';
                          if (!v.contains('@')) return 'Некорректный email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // button
                      SizedBox(
                        width: double.infinity,
                        height: AppSizes.buttonHeight,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Получить код'),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // guest shortcut
                      Center(
                        child: GestureDetector(
                          onTap: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('selected_role', 'guest');
                            if (!context.mounted) return;
                            context.go('/guest/entry');
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Продолжить без регистрации →',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: AppColors.ink3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // legal text
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.ink4,
                            height: 1.5,
                          ),
                          children: [
                            const TextSpan(text: 'Нажимая «Получить код», вы принимаете '),
                            TextSpan(
                              text: 'условия использования',
                              style: const TextStyle(
                                color: AppColors.amber,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.amber,
                              ),
                              recognizer: _termsRecognizer,
                            ),
                            const TextSpan(text: ' и '),
                            TextSpan(
                              text: 'политику конфиденциальности',
                              style: const TextStyle(
                                color: AppColors.amber,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.amber,
                              ),
                              recognizer: _privacyRecognizer,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),

                      if (kDebugMode) ...[
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: () => context.go('/dev'),
                          child: const Text(
                            '⚡ DEV: пропустить вход',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.ink4,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
