import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/tokens.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _chooseHost(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_role', 'host');
    if (!context.mounted) return;
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    context.go(onboardingDone ? '/auth/email' : '/onboarding');
  }

  Future<void> _chooseGuest(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_role', 'guest');
    if (!context.mounted) return;
    context.go('/guest/entry');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Spacer(),
            // Logo
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.ink,
                    ),
                    child: Center(
                      child: Container(
                        width: 14, height: 14,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 8),
                  const Text(
                    'ОДНОРАЗОВАЯ КАМЕРА · ВАШИ МОМЕНТЫ',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9,
                      letterSpacing: 1.4,
                      color: AppColors.ink4,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Buttons
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14 + bottom),
              child: Column(
                children: [
                  _RoleButton(
                    label: 'Войти или создать аккаунт',
                    icon: Icons.person_add_outlined,
                    filled: true,
                    onTap: () => _chooseHost(context),
                  ),
                  const SizedBox(height: 10),
                  _RoleButton(
                    label: 'Продолжить без регистрации',
                    filled: false,
                    onTap: () => _chooseGuest(context),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Без регистрации — снимать и смотреть один альбом.\nС аккаунтом — создавать события и видеть историю.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.ink4,
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

class _RoleButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: AppSizes.buttonHeight,
        decoration: BoxDecoration(
          color: filled ? AppColors.amber : Colors.transparent,
          border: filled
              ? null
              : Border.all(color: const Color(0x201A1714), width: 1.5),
          borderRadius: AppRadius.mdBR,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: filled ? Colors.white : AppColors.ink),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
