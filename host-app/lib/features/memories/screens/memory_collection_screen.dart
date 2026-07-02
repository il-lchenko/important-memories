import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';
import '../memory_collection_provider.dart';

/// Мини-альбом из подборки (несколько альбомов одного типа события).
/// Открывается тапом на collection-блок в разделе «Кадры».
class MemoryCollectionScreen extends ConsumerWidget {
  final String title;
  final List<String> eventIds;

  const MemoryCollectionScreen({
    super.key,
    required this.title,
    required this.eventIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = eventIds.join(',');
    final framesAsync = ref.watch(memoryCollectionProvider(key));

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: framesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.amber, strokeWidth: 2),
        ),
        error: (e, _) => Center(
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
                  onPressed: () => ref.invalidate(memoryCollectionProvider(key)),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (frames) {
          if (frames.isEmpty) {
            return Center(
              child: Text(
                'Нет фото в этой подборке',
                style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink3),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.amber,
            backgroundColor: AppColors.paper,
            onRefresh: () async {
              ref.invalidate(memoryCollectionProvider(key));
              await ref.read(memoryCollectionProvider(key).future);
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                  child: Row(
                    children: [
                      Text(
                        _framesWord(frames.length),
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppColors.ink3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${eventIds.length} ${_albumsWord(eventIds.length)}',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppColors.ink3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: frames.length,
                    itemBuilder: (ctx, i) => _CollectionTile(frame: frames[i]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _framesWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n кадр';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n кадра';
    return '$n кадров';
  }

  static String _albumsWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'альбом';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'альбома';
    return 'альбомов';
  }
}

class _CollectionTile extends StatelessWidget {
  final Map<String, dynamic> frame;
  const _CollectionTile({required this.frame});

  @override
  Widget build(BuildContext context) {
    final url = (frame['thumbnail_url'] ?? frame['preview_url'] ?? frame['full_url']) as String?;
    final eventId = frame['event_id'] as String?;
    final frameId = frame['id'] as String?;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (eventId == null) return;
        final path = frameId != null
            ? '/events/$eventId/album/frame/0?jumpFrameId=$frameId'
            : '/events/$eventId/album';
        GoRouter.of(context).push(path);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          color: AppColors.paper3,
          child: url == null
              ? const Center(child: Icon(Icons.image_outlined, size: 24, color: AppColors.ink4))
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 120),
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, __) => Container(color: AppColors.paper3),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 24, color: AppColors.ink4),
                  ),
                ),
        ),
      ),
    );
  }
}
