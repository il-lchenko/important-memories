import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/tokens.dart';

/// Router that picks the right widget for `block['type']`.
class MemoryBlockWidget extends StatelessWidget {
  final Map<String, dynamic> block;
  const MemoryBlockWidget({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final type = block['type'] as String? ?? 'tilted';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryHeader(block: block),
          const SizedBox(height: 12),
          _pickBlock(context, type),
        ],
      ),
    );
  }

  Widget _pickBlock(BuildContext context, String type) {
    // Server may still send collage_c for legacy — treat as collage_a.
    if (type == 'collage_c') type = 'collage_a';
    switch (type) {
      case 'tilted':
        return _TiltedStrip(block: block);
      case 'collage_a':
        return _CollageA(block: block);
      case 'collage_b':
        return _CollageB(block: block);
      case 'collage_d':
        return _CollageD(block: block);
      case 'collage_e':
        return _CollageE(block: block);
      case 'grid_6':
        return _Grid6Carousel(block: block);
      default:
        return _TiltedStrip(block: block);
    }
  }
}

// ─── Header (title + date/count) ──────────────────────────────────────────────

class _MemoryHeader extends StatelessWidget {
  final Map<String, dynamic> block;
  const _MemoryHeader({required this.block});

  void _openTarget(BuildContext context) {
    final kind = block['kind'] as String? ?? 'single';
    if (kind == 'single') {
      final eventId = block['event_id'] as String?;
      if (eventId != null) {
        GoRouter.of(context).push('/events/$eventId/album');
      }
    } else {
      final ids = (block['event_ids'] as List?)?.cast<String>() ?? [];
      if (ids.isEmpty) return;
      final title = (block['title'] as String?) ?? 'Подборка';
      GoRouter.of(context).push('/memories/collection', extra: {
        'title': title,
        'event_ids': ids,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventType = (block['event_type'] as String?) ?? '';
    final kind = block['kind'] as String? ?? 'single';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eventType.isNotEmpty && kind == 'single')
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              eventType.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.amber,
                letterSpacing: 1.0,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openTarget(context),
                child: Text(
                  (block['title'] as String?) ?? 'Кадры',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    letterSpacing: -0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _rightLabel(),
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.ink3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _rightLabel() {
    final albums = block['albums_count'] as int?;
    if (albums != null && albums > 0) return _albumsWord(albums);
    final raw = block['date_iso'] as String?;
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    return _formatDate(dt.toLocal());
  }

  static String _albumsWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n альбом';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n альбома';
    return '$n альбомов';
  }

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff <= 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (diff < 7) return '$diff ${_daysWord(diff)} назад';
    if (dt.year == now.year) {
      return DateFormat('d MMMM', 'ru').format(dt);
    }
    return DateFormat('d MMMM y', 'ru').format(dt);
  }

  static String _daysWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'дня';
    return 'дней';
  }
}

// ─── Photo tile (tap → open in original album) ────────────────────────────────

class _PhotoTile extends StatelessWidget {
  final Map<String, dynamic> thumb;
  final BorderRadius? radius;
  const _PhotoTile({
    required this.thumb,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final url = thumb['url'] as String?;
    final eventId = thumb['event_id'] as String?;
    final frameId = thumb['frame_id'] as String?;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (eventId == null) return;
        // Open the specific frame in fullscreen. FrameDetailScreen resolves
        // the actual index by frameId once the album loads.
        final path = frameId != null
            ? '/events/$eventId/album/frame/0?jumpFrameId=$frameId'
            : '/events/$eventId/album';
        GoRouter.of(context).push(path);
      },
      child: ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: SizedBox.expand(
          child: Container(
            color: AppColors.paper3,
            child: url == null
                ? const _PhotoPlaceholder()
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    fadeInDuration: const Duration(milliseconds: 120),
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, __) => Container(color: AppColors.paper3),
                    errorWidget: (_, __, ___) => const _PhotoPlaceholder(),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.paper3,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 24, color: AppColors.ink4),
      ),
    );
  }
}

List<Map<String, dynamic>> _thumbs(Map<String, dynamic> block) =>
    List<Map<String, dynamic>>.from(block['thumbs'] as List? ?? []);

// ─── Tilted strip (Once-style) — свайпаемая горизонтальная лента ─────────────

class _TiltedStrip extends StatelessWidget {
  final Map<String, dynamic> block;
  const _TiltedStrip({required this.block});

  static const _rotations = [-3.0, 1.4, -1.0, 2.6];
  static const _yOffsets = [-2.0, 3.0, -3.0, 2.0];
  static const _cardWidth = 92.0;
  static const _cardHeight = 116.0;

  @override
  Widget build(BuildContext context) {
    final thumbs = _thumbs(block);
    if (thumbs.isEmpty) return const SizedBox(height: 128);

    return SizedBox(
      height: 132,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: thumbs.length,
        itemBuilder: (ctx, i) {
          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 0, right: 0),
            child: Transform.translate(
              offset: Offset(i == 0 ? 0 : -8.0, _yOffsets[i % 4]),
              child: Transform.rotate(
                angle: _rotations[i % 4] * 3.14159 / 180,
                child: Container(
                  width: _cardWidth,
                  height: _cardHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.5),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _PhotoTile(
                    thumb: thumbs[i],
                    radius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Общий утил: скругление на каждое фото (равное со всех сторон) ────────────

BorderRadius get _photoRadius => BorderRadius.circular(6);

// ─── Общий Carousel для коллажей — все листаемые PageView ────────────────────

typedef _PageBuilder = Widget Function(List<Map<String, dynamic>> pageThumbs, int pageIndex);

class _CollageCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> thumbs;
  final int perPage;
  final double height;
  final _PageBuilder pageBuilder;
  final String seedKey; // для стабильного mirror-порядка per user

  const _CollageCarousel({
    required this.thumbs,
    required this.perPage,
    required this.height,
    required this.pageBuilder,
    required this.seedKey,
  });

  @override
  State<_CollageCarousel> createState() => _CollageCarouselState();
}

class _CollageCarouselState extends State<_CollageCarousel> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < widget.thumbs.length; i += widget.perPage) {
      final chunk = widget.thumbs.sublist(
        i,
        (i + widget.perPage).clamp(0, widget.thumbs.length),
      );
      if (chunk.length < widget.perPage) break; // не показываем неполные наборы
      pages.add(chunk);
    }
    if (pages.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: pages.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (ctx, i) => widget.pageBuilder(pages[i], i),
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? AppColors.amber : AppColors.ink4.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

// ─── Collage A: 1 big + 2 small — со случайным зеркалом (иногда big справа) ──

class _CollageA extends StatelessWidget {
  final Map<String, dynamic> block;
  const _CollageA({required this.block});

  Widget _page(List<Map<String, dynamic>> ts, int pageIndex) {
    // Deterministic mirror: чередуется по номеру страницы + id блока.
    final blockId = (block['event_id'] ?? block['title'] ?? '').toString();
    final mirror = (blockId.hashCode ^ pageIndex).isOdd;
    final big = Expanded(flex: 2, child: _PhotoTile(thumb: ts[0], radius: _photoRadius));
    final smalls = Expanded(
      child: Column(
        children: [
          Expanded(child: _PhotoTile(thumb: ts[1], radius: _photoRadius)),
          const SizedBox(height: 4),
          Expanded(child: _PhotoTile(thumb: ts[2], radius: _photoRadius)),
        ],
      ),
    );
    return SizedBox(
      height: 200,
      child: Row(
        children: mirror
            ? [smalls, const SizedBox(width: 4), big]
            : [big, const SizedBox(width: 4), smalls],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = _thumbs(block);
    if (ts.length < 3) return const SizedBox.shrink();
    return _CollageCarousel(
      thumbs: ts,
      perPage: 3,
      height: 200,
      pageBuilder: _page,
      seedKey: (block['event_id'] ?? block['title'] ?? '').toString(),
    );
  }
}

// ─── Collage B: 2×2 равных ────────────────────────────────────────────────────

class _CollageB extends StatelessWidget {
  final Map<String, dynamic> block;
  const _CollageB({required this.block});

  Widget _page(List<Map<String, dynamic>> ts, int _) {
    return SizedBox(
      height: 200,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _PhotoTile(thumb: ts[0], radius: _photoRadius)),
                const SizedBox(width: 4),
                Expanded(child: _PhotoTile(thumb: ts[1], radius: _photoRadius)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _PhotoTile(thumb: ts[2], radius: _photoRadius)),
                const SizedBox(width: 4),
                Expanded(child: _PhotoTile(thumb: ts[3], radius: _photoRadius)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = _thumbs(block);
    if (ts.length < 4) return const SizedBox.shrink();
    return _CollageCarousel(
      thumbs: ts,
      perPage: 4,
      height: 200,
      pageBuilder: _page,
      seedKey: (block['event_id'] ?? block['title'] ?? '').toString(),
    );
  }
}

// ─── Collage D: center accent (1 наклонённая карточка поверх 4-ки) ────────────

class _CollageD extends StatelessWidget {
  final Map<String, dynamic> block;
  const _CollageD({required this.block});

  Widget _page(List<Map<String, dynamic>> ts, int _) {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Opacity(opacity: 0.85, child: _PhotoTile(thumb: ts[0], radius: _photoRadius))),
                    const SizedBox(width: 4),
                    Expanded(child: Opacity(opacity: 0.85, child: _PhotoTile(thumb: ts[1], radius: _photoRadius))),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Opacity(opacity: 0.85, child: _PhotoTile(thumb: ts[2], radius: _photoRadius))),
                    const SizedBox(width: 4),
                    Expanded(child: Opacity(opacity: 0.85, child: _PhotoTile(thumb: ts[3], radius: _photoRadius))),
                  ],
                ),
              ),
            ],
          ),
          Transform.rotate(
            angle: -2 * 3.14159 / 180,
            child: FractionallySizedBox(
              widthFactor: 0.62,
              heightFactor: 0.68,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.40),
                      blurRadius: 22,
                      spreadRadius: 1,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.hardEdge,
                child: _PhotoTile(thumb: ts[4], radius: BorderRadius.circular(5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = _thumbs(block);
    if (ts.length < 5) return const SizedBox.shrink();
    return _CollageCarousel(
      thumbs: ts,
      perPage: 5,
      height: 220,
      pageBuilder: _page,
      seedKey: (block['event_id'] ?? block['title'] ?? '').toString(),
    );
  }
}

// ─── Collage E: 1 big square left + 3 stack right ─────────────────────────────

class _CollageE extends StatelessWidget {
  final Map<String, dynamic> block;
  const _CollageE({required this.block});

  Widget _page(List<Map<String, dynamic>> ts, int _) {
    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(flex: 8, child: _PhotoTile(thumb: ts[0], radius: _photoRadius)),
          const SizedBox(width: 4),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(child: _PhotoTile(thumb: ts[1], radius: _photoRadius)),
                const SizedBox(height: 4),
                Expanded(child: _PhotoTile(thumb: ts[2], radius: _photoRadius)),
                const SizedBox(height: 4),
                Expanded(child: _PhotoTile(thumb: ts[3], radius: _photoRadius)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = _thumbs(block);
    if (ts.length < 4) return const SizedBox.shrink();
    return _CollageCarousel(
      thumbs: ts,
      perPage: 4,
      height: 220,
      pageBuilder: _page,
      seedKey: (block['event_id'] ?? block['title'] ?? '').toString(),
    );
  }
}

// ─── Grid 6 carousel: 3×2, PageView, dot pager ───────────────────────────────

class _Grid6Carousel extends StatefulWidget {
  final Map<String, dynamic> block;
  const _Grid6Carousel({required this.block});

  @override
  State<_Grid6Carousel> createState() => _Grid6CarouselState();
}

class _Grid6CarouselState extends State<_Grid6Carousel> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ts = _thumbs(widget.block);
    if (ts.isEmpty) return const SizedBox.shrink();
    final pages = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < ts.length; i += 6) {
      pages.add(ts.sublist(i, (i + 6).clamp(0, ts.length)));
    }
    if (pages.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 214,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: pages.length,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (ctx, i) => _sixGrid(pages[i]),
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? AppColors.amber : AppColors.ink4.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _sixGrid(List<Map<String, dynamic>> pageThumbs) {
    // Ensure grid is 3×2 even if fewer thumbs — pad with empty tiles.
    final filled = <Widget>[];
    for (int i = 0; i < 6; i++) {
      if (i < pageThumbs.length) {
        filled.add(
          _PhotoTile(thumb: pageThumbs[i], radius: _photoRadius),
        );
      } else {
        filled.add(const SizedBox.shrink());
      }
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                Expanded(child: AspectRatio(aspectRatio: 1, child: filled[i])),
                if (i < 2) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              for (int i = 3; i < 6; i++) ...[
                Expanded(child: AspectRatio(aspectRatio: 1, child: filled[i])),
                if (i < 5) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
