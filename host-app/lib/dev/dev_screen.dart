import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/tokens.dart';

class DevScreen extends StatelessWidget {
  const DevScreen({super.key});

  static const _routes = [
    _R('Splash',               '/splash'),
    _R('Auth — Email',         '/auth/email'),
    _R('Auth — OTP',           '/auth/otp?email=test@example.com'),
    _R('Dashboard',            '/dashboard'),
    _R('Create Event',         '/events/create'),
    _R('Event Detail',         '/events/demo-event'),
    _R('Live Progress',        '/events/demo-event/progress'),
    _R('QR Fullscreen',        '/events/demo-event/qr'),
    _R('Reveal Countdown',     '/events/demo-event/reveal'),
    _R('Album',                '/events/demo-event/album'),
    _R('Frame Detail',         '/events/demo-event/album/frame/0'),
    _R('Profile',              '/profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 8),
            const Text(
              'DEV · все экраны',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                letterSpacing: 0.18,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Important\nMemories',
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                fontWeight: FontWeight.w500,
                fontSize: 36,
                height: 1.05,
                letterSpacing: -0.02 * 36,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 32),
            ..._routes.map((r) => _RouteButton(route: r)),
          ],
        ),
      ),
    );
  }
}

class _RouteButton extends StatelessWidget {
  final _R route;
  const _RouteButton({required this.route});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => context.push(route.path),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.paper2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  route.label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                route.path.length > 28 ? '…${route.path.substring(route.path.length - 20)}' : route.path,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  color: AppColors.ink4,
                  letterSpacing: 0.04,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
            ],
          ),
        ),
      ),
    );
  }
}

class _R {
  final String label;
  final String path;
  const _R(this.label, this.path);
}
