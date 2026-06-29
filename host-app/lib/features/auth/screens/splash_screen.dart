import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';
import '../auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _pulse;
  late AnimationController _dots;

  static const _storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    Future.delayed(const Duration(seconds: 3), _checkAuth);
  }

  Future<void> _checkAuth() async {
    if (!mounted) return;

    final token = await _storage.read(key: 'access_token');
    if (!mounted) return;

    if (token != null) {
      try {
        // Validate token against backend (interceptor auto-refreshes if needed)
        final dio = ref.read(dioProvider);
        await dio.get('users/me');
        if (!mounted) return;
        context.go('/dashboard');
      } catch (_) {
        // Token invalid or expired and refresh failed — clear and re-login
        await _storage.deleteAll();
        ref.read(authProvider.notifier).logout();
        if (!mounted) return;
        await _routeUnauthenticated();
      }
      return;
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
      // No role chosen yet (first launch or upgrade from pre-guest APK) → role selection
      context.go('/role');
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    final spread = t < 0.5 ? t * 36.0 : (1.0 - t) * 36.0;
                    final alpha = 0.35 * (1.0 - t);
                    return Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.ink,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.amber.withValues(alpha: alpha),
                            blurRadius: 0,
                            spreadRadius: spread,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.amber,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.amber.withValues(alpha: 0.6),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Important\nMemories',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.64,
                    height: 1.05,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'DISPOSABLE · 2026',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    letterSpacing: 2.64,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 64, left: 0, right: 0,
            child: AnimatedBuilder(
              animation: _dots,
              builder: (_, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final phase = (_dots.value - i * 0.2 + 1.0) % 1.0;
                  final opacity = (phase < 0.4
                      ? phase / 0.4
                      : phase < 0.6
                          ? 1.0
                          : (1.0 - phase) / 0.4)
                      .clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.ink4.withValues(alpha: 0.25 + opacity * 0.75),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
