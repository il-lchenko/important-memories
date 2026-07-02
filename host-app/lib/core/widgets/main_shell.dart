import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../tokens.dart';
import 'app_bottom_nav.dart';

/// Shell that keeps `AppBottomNav` static across tab switches.
/// The child (per-branch Navigator) is what animates — the bar stays put.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper2,
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        active: AppNavTab.values[navigationShell.currentIndex],
        onTap: (tab) => navigationShell.goBranch(
          tab.index,
          initialLocation: tab.index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
