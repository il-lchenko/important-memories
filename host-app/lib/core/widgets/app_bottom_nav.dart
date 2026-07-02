import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../tokens.dart';

/// Shared bottom navigation bar. Used in `MainShell` (StatefulShellRoute).
/// The `onTap` callback receives the tapped tab — the shell then calls
/// `navigationShell.goBranch(tab.index)` to switch branches without rebuilding
/// the bar itself.
class AppBottomNav extends StatelessWidget {
  final AppNavTab active;
  final ValueChanged<AppNavTab>? onTap;
  const AppBottomNav({super.key, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -3),
            blurRadius: 6,
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24, 10, 24, 14 + bottomInset),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavItem(
            icon: Icons.collections_bookmark_outlined,
            iconActive: Icons.collections_bookmark,
            label: 'Альбомы',
            isActive: active == AppNavTab.albums,
            onTap: () => _handleTap(context, AppNavTab.albums),
          ),
          _NavItem(
            icon: Icons.auto_awesome_outlined,
            iconActive: Icons.auto_awesome,
            label: 'Кадры',
            isActive: active == AppNavTab.memories,
            onTap: () => _handleTap(context, AppNavTab.memories),
          ),
          _NavItem(
            icon: Icons.person_outline,
            iconActive: Icons.person,
            label: 'Профиль',
            isActive: active == AppNavTab.profile,
            onTap: () => _handleTap(context, AppNavTab.profile),
          ),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, AppNavTab tab) {
    if (onTap != null) {
      onTap!(tab);
      return;
    }
    // Fallback: raw go — used when a screen renders AppBottomNav outside a shell.
    final path = switch (tab) {
      AppNavTab.albums => '/dashboard',
      AppNavTab.memories => '/memories',
      AppNavTab.profile => '/profile',
    };
    if (GoRouterState.of(context).uri.path == path) return;
    context.go(path);
  }
}

enum AppNavTab { albums, memories, profile }

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData iconActive;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.iconActive,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppColors.amber : Colors.transparent,
              ),
            ),
            const SizedBox(height: 5),
            Icon(
              isActive ? iconActive : icon,
              color: isActive ? AppColors.ink : AppColors.ink3,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? AppColors.ink : AppColors.ink3,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
