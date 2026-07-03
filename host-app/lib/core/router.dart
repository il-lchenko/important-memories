import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/auth_provider.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/onboarding_screen.dart';
import '../features/auth/screens/auth_email_screen.dart';
import '../features/auth/screens/auth_otp_screen.dart';
import '../features/events/screens/dashboard_screen.dart';
import '../features/events/screens/create_event_screen.dart';
import '../features/events/screens/checkout_screen.dart';
import '../features/events/screens/event_detail_screen.dart';
import '../features/events/screens/live_progress_screen.dart';
import '../features/events/screens/qr_fullscreen_screen.dart';
import '../features/events/screens/reveal_countdown_screen.dart';
import '../features/album/screens/album_screen.dart';
import '../features/album/screens/album_settings_screen.dart';
import '../features/album/screens/extend_storage_screen.dart';
import '../features/album/screens/frame_detail_screen.dart';
import '../features/memories/screens/memories_screen.dart';
import '../features/memories/screens/memory_collection_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import 'widgets/main_shell.dart';
import '../features/guest/screens/role_selection_screen.dart';
import '../features/guest/screens/guest_entry_screen.dart';
import '../features/guest/screens/qr_scanner_screen.dart';
import '../features/guest/screens/code_input_screen.dart';
import '../features/guest/screens/guest_landing_screen.dart';
import '../features/guest/screens/guest_camera_screen.dart';
import '../features/guest/screens/guest_home_screen.dart';
import '../features/guest/screens/sign_choice_screen.dart';
import '../features/guest/screens/caption_screen.dart';
import '../features/guest/screens/voice_record_screen.dart';
import '../features/guest/screens/guest_profile_screen.dart';
import '../dev/dev_screen.dart';

part 'router.g.dart';

const _storage = FlutterSecureStorage();

const _publicPaths = {'/splash', '/onboarding', '/auth/email', '/auth/otp', '/role'};

bool _isPublic(String path) =>
    _publicPaths.contains(path) ||
    path.startsWith('/auth/') ||
    path.startsWith('/guest/');

@riverpod
GoRouter appRouter(Ref ref) {
  // Mutable snapshot — updated via ref.listen without rebuilding the router
  AsyncValue<bool> authState = ref.read(authProvider);

  final router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      final path = state.matchedLocation;

      // Splash handles its own routing
      if (path == '/splash') return null;

      // Use the cached state if available, otherwise read storage directly
      bool isAuthed;
      if (authState is AsyncLoading) {
        final token = await _storage.read(key: 'access_token');
        isAuthed = token != null;
      } else {
        isAuthed = authState.valueOrNull ?? false;
      }

      if (!isAuthed && !_isPublic(path)) return '/auth/email';
      return null;
    },
    routes: [
      GoRoute(path: '/splash',       builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/onboarding',   builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: '/auth/email',   builder: (c, s) => const AuthEmailScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (c, s) => AuthOtpScreen(email: s.uri.queryParameters['email'] ?? ''),
      ),
      // Main tabs — wrapped in StatefulShellRoute so AppBottomNav stays static.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/memories', builder: (c, s) => const MemoriesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          ]),
        ],
      ),

      GoRoute(path: '/events/create', builder: (c, s) => const CreateEventScreen()),
      GoRoute(
        path: '/events/create/checkout',
        builder: (c, s) {
          final draft = (s.extra as Map?)?.cast<String, dynamic>() ?? const {};
          return CheckoutScreen(draft: draft);
        },
      ),
      GoRoute(
        path: '/events/:id',
        builder: (c, s) => EventDetailScreen(eventId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'progress',
            builder: (c, s) => LiveProgressScreen(eventId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'qr',
            builder: (c, s) => QrFullscreenScreen(eventId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'reveal',
            builder: (c, s) => RevealCountdownScreen(eventId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'album',
            builder: (c, s) => AlbumScreen(eventId: s.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'frame/:frameIndex',
                builder: (c, s) => FrameDetailScreen(
                  eventId: s.pathParameters['id']!,
                  frameIndex: int.tryParse(s.pathParameters['frameIndex'] ?? '0') ?? 0,
                  jumpFrameId: s.uri.queryParameters['jumpFrameId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (c, s) => AlbumSettingsScreen(eventId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/memories/collection',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final title = extra?['title'] as String? ?? 'Подборка';
          final ids = (extra?['event_ids'] as List?)?.cast<String>() ?? const [];
          return MemoryCollectionScreen(title: title, eventIds: ids);
        },
      ),
      GoRoute(
        path: '/extend/:eventId',
        builder: (c, s) => ExtendStorageScreen(eventId: s.pathParameters['eventId']!),
      ),
      GoRoute(path: '/dev',         builder: (c, s) => const DevScreen()),

      // Guest entry flow (public — no auth required)
      GoRoute(path: '/role',        builder: (c, s) => const RoleSelectionScreen()),
      GoRoute(path: '/guest/entry', builder: (c, s) => const GuestEntryScreen()),
      GoRoute(path: '/guest/qr',    builder: (c, s) => const QRScannerScreen()),
      GoRoute(path: '/guest/code',  builder: (c, s) => const CodeInputScreen()),
      GoRoute(
        path: '/guest/landing/:code',
        builder: (c, s) => GuestLandingScreen(code: s.pathParameters['code']!),
      ),
      GoRoute(path: '/guest/home',    builder: (c, s) => const GuestHomeScreen()),
      GoRoute(path: '/guest/profile', builder: (c, s) => const GuestProfileScreen()),
      GoRoute(
        path: '/guest/camera/:eventId',
        builder: (c, s) => GuestCameraScreen(eventId: s.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/guest/sign/:frameId',
        builder: (c, s) => SignChoiceScreen(frameId: s.pathParameters['frameId']!),
      ),
      GoRoute(
        path: '/guest/caption/:frameId',
        builder: (c, s) => CaptionScreen(frameId: s.pathParameters['frameId']!),
      ),
      GoRoute(
        path: '/guest/voice/:frameId',
        builder: (c, s) => VoiceRecordScreen(frameId: s.pathParameters['frameId']!),
      ),
    ],
  );

  // React to auth state changes: update local snapshot + navigate on logout
  ref.listen<AsyncValue<bool>>(authProvider, (prev, next) {
    authState = next;
    final wasAuthed = prev?.valueOrNull ?? false;
    final isAuthed = next.valueOrNull ?? false;
    if (wasAuthed && !isAuthed) {
      router.go('/auth/email');
    }
  });

  ref.onDispose(router.dispose);
  return router;
}
