import 'dart:math' as math;

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

// Тайминг сплэша: 200мс пусто → 3400мс F-анимация (speed 1.5×, нормальный темп) →
// 100мс дельта до автоперехода (буквально «анимация закончилась → приложение»).
// Кнопка «Начать» — только на первом запуске, появляется в самом конце анимации.
// Для авторизованных юзеров — мгновенный переход в /dashboard без ожидания.
const Duration _splashStartDelay = Duration(milliseconds: 200);
const Duration _autoNavDelay = Duration(milliseconds: 3600);
const double _logoSpeed = 1.5;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  bool _isFirstLaunch = true;
  bool _routing = false;
  bool _showLogo = false;
  bool _showWordmark = false;
  bool _showSubtitle = false;
  bool _showButton = false;

  static const _storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();

    // Задержка старта — экран сначала показывается пустым, чтобы не «пол анимации уже прошло».
    Future.delayed(_splashStartDelay, () {
      if (mounted) setState(() => _showLogo = true);
    });
    // Wordmark — на 71% пути анимации (~2460мс при speed 1.5×).
    Future.delayed(_splashStartDelay + const Duration(milliseconds: 2460), () {
      if (mounted) setState(() => _showWordmark = true);
    });
    // Subtitle — сразу после wordmark.
    Future.delayed(_splashStartDelay + const Duration(milliseconds: 2930), () {
      if (mounted) setState(() => _showSubtitle = true);
    });
    // Кнопка «Начать» появляется в конце (за 200мс до автоперехода).
    Future.delayed(_autoNavDelay - const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _showButton = true);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLaunch());
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final hasRole = prefs.getString('selected_role') != null;
    String? token;
    try {
      token = await _storage.read(key: 'access_token');
    } catch (_) {
      try { await _storage.deleteAll(); } catch (_) {}
    }
    if (!mounted) return;
    final isFirst = !onboardingDone && !hasRole;
    setState(() => _isFirstLaunch = isFirst);
    if (token != null) {
      // Уже авторизован — мгновенный переход, без ожидания анимации.
      _continue();
    } else if (!isFirst) {
      // Не первый запуск — доиграем анимацию и уйдём автоматически.
      Future.delayed(_autoNavDelay, () {
        if (mounted && !_routing) _continue();
      });
    }
  }

  Future<void> _continue() async {
    if (_routing || !mounted) return;
    setState(() => _routing = true);

    String? token;
    try {
      token = await _storage.read(key: 'access_token');
    } catch (_) {
      try { await _storage.deleteAll(); } catch (_) {}
    }
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
      context.go(onboardingDone ? '/role' : '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Логотип F: 210dp на среднем телефоне, чуть больше на планшете. Не гигант.
    final logoSize = math.min(media.size.width * 0.48, 240.0);
    // Wordmark ~1.2× шире логотипа — визуально сбалансированная композиция.
    final wordmarkWidth = logoSize * 1.15;

    const fadeDuration = Duration(milliseconds: 600);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Stack(
          children: [
            // Всё лого-содержимое строго по центру экрана, друг под другом.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Резервируем место под лого, чтобы Column не «прыгал» после появления.
                  SizedBox(
                    width: logoSize,
                    height: logoSize,
                    child: _showLogo
                        ? FLogoAnimated(
                            size: logoSize,
                            isDark: false,
                            loop: false,
                            speed: _logoSpeed,
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 22),
                  AnimatedOpacity(
                    opacity: _showWordmark ? 1.0 : 0.0,
                    duration: fadeDuration,
                    curve: Curves.easeOut,
                    child: AnimatedSlide(
                      offset: _showWordmark ? Offset.zero : const Offset(0, 0.25),
                      duration: fadeDuration,
                      curve: Curves.easeOut,
                      child: Image.asset(
                        'assets/brand/wordmark-title-light.png',
                        width: wordmarkWidth,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedOpacity(
                    opacity: _showSubtitle ? 1.0 : 0.0,
                    duration: fadeDuration,
                    curve: Curves.easeOut,
                    child: Text(
                      'DISPOSABLE · 2026',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        letterSpacing: 4.4,
                        fontWeight: FontWeight.w500,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Кнопка «Начать» — только на первом запуске, появляется последней и плавно.
            if (_isFirstLaunch)
              Positioned(
                left: 32,
                right: 32,
                bottom: 44,
                child: AnimatedOpacity(
                  opacity: _showButton ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOut,
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _showButton ? _continue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: Center(
                        child: Text(
                          'Начать',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
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
