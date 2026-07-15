import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';
import '../../../widgets/f_logo_animated.dart';
import '../auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _entry;
  bool _isFirstLaunch = true;
  bool _routing = false;

  static const _storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // Определяем: первый запуск (show button) или последующий (auto-nav через 1.5с).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLaunch());
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final hasRole = prefs.getString('selected_role') != null;
    if (!mounted) return;
    final isFirst = !onboardingDone && !hasRole;
    setState(() => _isFirstLaunch = isFirst);
    if (!isFirst) {
      // Быстрый splash для возвратов: 1.5 сек — увидел лого и полетели дальше.
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_routing) _continue();
      });
    }
  }

  Future<void> _continue() async {
    if (_routing || !mounted) return;
    setState(() => _routing = true);

    final token = await _storage.read(key: 'access_token');
    if (!mounted) return;

    if (token != null) {
      try {
        final dio = ref.read(dioProvider);
        await dio.get('users/me');
        if (!mounted) return;
        context.go('/dashboard');
        return;
      } catch (_) {
        await _storage.deleteAll();
        ref.read(authProvider.notifier).logout();
        if (!mounted) return;
      }
    }

    await _routeUnauthenticated();
  }

  Future<void> _routeUnauthenticated() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final selectedRole = prefs.getString('selected_role');
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;

    if (selectedRole == 'guest') {
      final guestEventId = await GuestPrefs.currentEventId() ?? '';
      final guestToken =
          guestEventId.isEmpty ? '' : await GuestPrefs.tokenFor(guestEventId);
      if (!mounted) return;
      if (guestToken.isNotEmpty && guestEventId.isNotEmpty) {
        context.go('/guest/home');
      } else {
        context.go('/guest/entry');
      }
    } else if (selectedRole == 'host') {
      context.go(onboardingDone ? '/auth/email' : '/onboarding');
    } else {
      // Первая сессия: онбординг сразу (без промежуточного role-selection —
      // выбор роли есть на онбординге финалом).
      context.go(onboardingDone ? '/role' : '/onboarding');
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            // ── Логотип: реальная анимация из logo-anim-F.html ──────────────
            const FLogoAnimated(size: 220, isDark: false),
            const SizedBox(height: 28),
            // ── Название: fade-in + сдвиг снизу ─────────────────────────────
            AnimatedBuilder(
              animation: _entry,
              builder: (_, __) {
                final t = _entry.value.clamp(0.0, 1.0);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 12),
                    child: Column(
                      children: [
                        Text(
                          'ImpoMento',
                          style: GoogleFonts.playfairDisplay(
                            fontFeatures: [const FontFeature.liningFigures()],
                            fontSize: 44,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'ОДНОРАЗОВАЯ КАМЕРА · ВАШИ МОМЕНТЫ',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            letterSpacing: 2.2,
                            color: AppColors.ink4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Spacer(flex: 4),
            // ── Кнопка «Продолжить» (только первый запуск) ──────────────────
            if (_isFirstLaunch)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                child: AnimatedBuilder(
                  animation: _entry,
                  builder: (_, __) {
                    final t = ((_entry.value - 0.4) / 0.6).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, (1 - t) * 20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _continue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.amber,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Начать',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const SizedBox(height: 56 + 40),
          ],
        ),
      ),
    );
  }

}
