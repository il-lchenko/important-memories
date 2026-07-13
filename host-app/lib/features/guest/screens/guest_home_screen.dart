import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/tokens.dart';
import '../guest_provider.dart';

class GuestHomeScreen extends ConsumerWidget {
  const GuestHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(guestSessionProvider);
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
        error: (_, __) => _ErrorBody(),
        data: (session) {
          final event = session['event'] as Map<String, dynamic>? ?? {};
          final eventId = event['id'] as String? ?? '';
          final eventTitle = event['title'] as String? ?? 'Событие';
          final framesUsed = session['frames_used'] as int? ?? 0;
          final framesRemaining = session['frames_remaining'] as int? ?? 0;
          final framesTotal = framesUsed + framesRemaining;
          final eventStatus = event['status'] as String? ?? '';
          final isActive = eventStatus == 'active';

          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              eventTitle,
                              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                                fontSize: 28, fontWeight: FontWeight.w700,
                                letterSpacing: -0.5, height: 1.1, color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ВЫ — ГОСТЬ · $framesUsed КАДРОВ ИЗ $framesTotal',
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono', fontSize: 10,
                                letterSpacing: 1.2, color: AppColors.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/guest/profile'),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.paper2,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.person_outline, size: 18, color: AppColors.ink2),
                        ),
                      ),
                    ],
                  ),
                ),

                // Info banner
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.paper2,
                      borderRadius: AppRadius.mdBR,
                      border: Border.all(color: AppColors.paper3),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: AppColors.ink3),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Создайте аккаунт, чтобы сохранить событие и участвовать в других. Ваши $framesUsed кадров привяжутся автоматически',
                            style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 12,
                              color: AppColors.ink3, height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('selected_role', 'host');
                            if (!context.mounted) return;
                            context.go('/auth/email');
                          },
                          child: const Text(
                            'Создать →',
                            style: TextStyle(
                              fontFamily: 'Inter', fontSize: 12,
                              fontWeight: FontWeight.w600, color: AppColors.amber,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Mini frame grid (placeholder)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 3 / 4,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(
                        4,
                        (i) => ClipRRect(
                          borderRadius: AppRadius.smBR,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _gradients[i % _gradients.length],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, botPad + 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: eventId.isNotEmpty
                              ? () => context.push('/events/$eventId/album')
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink3,
                            side: const BorderSide(color: AppColors.paper3),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Альбом', style: TextStyle(fontFamily: 'Inter', fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (eventId.isNotEmpty && isActive && framesRemaining > 0)
                              ? () => context.push('/guest/camera/$eventId')
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.amber,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.paper3,
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text(
                            'Снять кадр',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const _gradients = [
    [Color(0xFFD4A574), Color(0xFF5A3E2E)],
    [Color(0xFFA08770), Color(0xFF3A2A20)],
    [Color(0xFFC8B094), Color(0xFF6B4E35)],
    [Color(0xFFB89478), Color(0xFF4A3528)],
  ];
}

class _ErrorBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.ink4),
            const SizedBox(height: 16),
            const Text(
              'Не удалось загрузить сессию',
              style: TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.ink2),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.go('/guest/entry'),
              child: const Text('Войти заново'),
            ),
          ],
        ),
      ),
    );
  }
}
