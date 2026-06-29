import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';
import '../guest_provider.dart';

class GuestProfileScreen extends ConsumerStatefulWidget {
  const GuestProfileScreen({super.key});

  @override
  ConsumerState<GuestProfileScreen> createState() => _GuestProfileScreenState();
}

class _GuestProfileScreenState extends ConsumerState<GuestProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_role');
    await prefs.remove('guest_name');
    await GuestPrefs.clearAll();
    if (!mounted) return;
    context.go('/role');
  }

  void _showRenameSheet(String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.lg),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        bool saving = false;
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Изменить имя',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Только для этого события',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLength: 40,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Ваше имя',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.paper2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: saving ? null : () async {
                    final newName = ctrl.text.trim();
                    if (newName.isEmpty) return;
                    setSt(() => saving = true);
                    try {
                      final eventId = await GuestPrefs.currentEventId() ?? '';
                      final token = eventId.isEmpty
                          ? ''
                          : await GuestPrefs.tokenFor(eventId);
                      final dio = ref.read(dioProvider);
                      await dio.patch(
                        'guest/sessions/me',
                        data: {'name': newName},
                        options: Options(headers: {'X-Guest-Token': token}),
                      );
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('guest_name', newName);
                      ref.invalidate(guestSessionProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (_) {
                      setSt(() => saving = false);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    decoration: BoxDecoration(
                      color: saving ? AppColors.ink3 : AppColors.amber,
                      borderRadius: AppRadius.mdBR,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      saving ? 'Сохраняем...' : 'Сохранить',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(guestSessionProvider);
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          SizedBox(height: top + 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.paper2,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.chevron_left, color: AppColors.ink2, size: 24),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Профиль',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Content
          Expanded(
            child: sessionAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.amber),
              ),
              error: (_, __) => _buildOffline(context, bottom),
              data: (session) {
                final name = session['name'] as String? ?? '—';
                final event = session['event'] as Map<String, dynamic>? ?? {};
                final eventTitle = event['title'] as String? ?? 'Событие';
                final framesUsed = session['frames_used'] as int? ?? 0;
                final framesRemaining = session['frames_remaining'] as int? ?? 0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Role badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'АНОНИМНЫЙ ГОСТЬ',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            letterSpacing: 1.3,
                            color: AppColors.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Name
                      Text(
                        name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 32,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                          letterSpacing: -0.5,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        eventTitle,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$framesUsed из ${framesUsed + framesRemaining} кадров снято',
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          letterSpacing: 1.1,
                          color: AppColors.ink4,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Actions
                      _ProfileRow(
                        icon: Icons.edit_outlined,
                        label: 'Изменить имя',
                        onTap: () => _showRenameSheet(name),
                      ),
                      const _Divider(),
                      _ProfileRow(
                        icon: Icons.person_add_outlined,
                        label: 'Создать аккаунт',
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('selected_role', 'host');
                          if (!context.mounted) return;
                          context.go('/auth/email');
                        },
                      ),
                      const SizedBox(height: 32),

                      // Sign out
                      GestureDetector(
                        onTap: _signingOut ? null : _signOut,
                        child: Container(
                          width: double.infinity,
                          height: AppSizes.buttonHeight,
                          decoration: BoxDecoration(
                            color: AppColors.shutter.withValues(alpha: 0.08),
                            borderRadius: AppRadius.mdBR,
                            border: Border.all(
                              color: AppColors.shutter.withValues(alpha: 0.2),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _signingOut ? 'Выходим...' : 'Выйти',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.shutter,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: bottom + 16),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffline(BuildContext context, double bottom) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_outlined, size: 40, color: AppColors.ink4),
          const SizedBox(height: 16),
          const Text(
            'Нет соединения',
            style: TextStyle(fontFamily: 'Inter', fontSize: 15, color: AppColors.ink2),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _signingOut ? null : _signOut,
            child: Container(
              width: double.infinity,
              height: AppSizes.buttonHeight,
              decoration: BoxDecoration(
                color: AppColors.shutter.withValues(alpha: 0.08),
                borderRadius: AppRadius.mdBR,
                border: Border.all(color: AppColors.shutter.withValues(alpha: 0.2)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Выйти',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.shutter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ProfileRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink2),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.line);
  }
}
