import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/push_service.dart';
import 'core/theme.dart';
import 'core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  // Русская локаль для DateFormat в разделе «Кадры» и других экранах.
  await initializeDateFormatting('ru');
  // Увеличиваем кэш изображений: больше фото остаётся в памяти → нет мерцания при смене табов.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024; // 256 MB
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  // Firebase / FCM — no-op если firebase_options.dart ещё с заглушками.
  await PushService.initApp();
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    // Пуш-хендлеры (foreground / tap when in background / cold-start-from-notification).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.attachHandlers(ref.read(appRouterProvider));
    });
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (_) {}
    _linkSub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void _handleUri(Uri uri) {
    // https://impomento.pro/g/CODE[?p=1234] → /guest/landing/CODE (или /guest/pin/CODE если p= есть)
    // https://impomento.pro/i/TOKEN → invite (POST /guest/invites/TOKEN/join)
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'g') {
      final code = segments[1];
      final pin = uri.queryParameters['p'];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final router = ref.read(appRouterProvider);
        if (pin != null && RegExp(r'^\d{4}$').hasMatch(pin)) {
          // QR со встроенным PIN — открываем PIN-экран сразу с pin в extra,
          // экран автоматически сабмитит.
          router.go(
            '/guest/pin/$code',
            extra: {'guestName': null, 'eventTitle': null, 'prefilledPin': pin},
          );
        } else {
          router.go('/guest/landing/$code');
        }
      });
    } else if (segments.length >= 2 && segments[0] == 'i') {
      // https://impomento.pro/i/TOKEN → InviteJoinScreen
      final token = segments[1];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(appRouterProvider).go('/guest/invite/$token');
      });
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'ImpoMento',
      theme: buildAppTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
