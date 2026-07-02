import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';
import '../memories_provider.dart';
import '../widgets/memory_blocks.dart';

/// Раздел «Кадры» — авто-подборки из альбомов юзера.
/// Блоки разных типов чередуются (см. analysis/mockups/memories/hybrid.html).
class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(memoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — только заголовок «Кадры» + поиск (пока-плейсхолдер).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
              decoration: BoxDecoration(
                color: AppColors.paper,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, 3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Кадры',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                        letterSpacing: -0.7,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: blocksAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.amber, strokeWidth: 2),
                ),
                error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(memoriesProvider)),
                data: (blocks) {
                  if (blocks.isEmpty) return const _EmptyState();
                  return RefreshIndicator(
                    color: AppColors.amber,
                    backgroundColor: AppColors.paper,
                    onRefresh: () async {
                      ref.invalidate(memoriesProvider);
                      await ref.read(memoriesProvider.future);
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: blocks.length,
                      itemBuilder: (ctx, i) => MemoryBlockWidget(block: blocks[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // bottomNavigationBar is provided by MainShell (StatefulShellRoute).
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 40, color: AppColors.ink4),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить',
              style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: const BoxDecoration(
                color: AppColors.paper2,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_outlined, size: 40, color: AppColors.ink3),
            ),
            const SizedBox(height: 20),
            Text(
              'Скоро здесь появятся кадры',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Автоматические подборки из ваших альбомов — свадьбы, дни рождения, вечеринки. Как только появятся альбомы с фотографиями, здесь соберётся живая лента.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.ink3,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => GoRouter.of(context).go('/dashboard'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'К альбомам',
                style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
