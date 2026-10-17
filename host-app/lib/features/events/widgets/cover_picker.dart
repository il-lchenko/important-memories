import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../core/widgets/brand_icon.dart';
import '../../plus/plus_providers.dart';

/// Как задать обложку: из галереи, первый кадр альбома или выбранный кадр.
class CoverChoice {
  final String kind; // gallery | first | frame
  final String? frameId;
  const CoverChoice(this.kind, [this.frameId]);
}

Future<CoverChoice?> showCoverSheet(
  BuildContext context, {
  required String eventId,
  required int framesCount,
  required bool hasCover,
}) {
  return showModalBottomSheet<CoverChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => _CoverSheet(eventId: eventId, framesCount: framesCount, hasCover: hasCover),
  );
}

class _CoverSheet extends StatefulWidget {
  final String eventId;
  final int framesCount;
  final bool hasCover;
  const _CoverSheet({required this.eventId, required this.framesCount, required this.hasCover});

  @override
  State<_CoverSheet> createState() => _CoverSheetState();
}

class _CoverSheetState extends State<_CoverSheet> {
  bool _frames = false;

  Widget _tile(Widget icon, String title, String text, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              icon,
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(text, style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.ink3)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.framesCount > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.paper3, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            if (_frames) ...[
              Row(children: [
                IconButton(onPressed: () => setState(() => _frames = false), icon: const Icon(Icons.chevron_left, color: AppColors.ink)),
                Text('Выберите кадр', style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ]),
              const SizedBox(height: 8),
              SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: _FramesGrid(eventId: widget.eventId)),
            ] else ...[
              Text(widget.hasCover ? 'Сменить обложку' : 'Обложка альбома',
                  style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 14),
              _tile(const BrandIcon('gallery', size: 28), 'Загрузить из галереи', 'Любое фото с телефона',
                  () => Navigator.pop(context, const CoverChoice('gallery'))),
              _tile(const Icon(Icons.camera_alt_outlined, color: AppColors.amber, size: 26), 'Взять первый кадр альбома',
                  has ? 'Самый первый снятый кадр станет обложкой' : 'Появится после первого снимка',
                  has ? () => Navigator.pop(context, const CoverChoice('first')) : null),
              _tile(const Icon(Icons.camera_roll_outlined, color: AppColors.amber, size: 26), 'Выбрать из кадров', has ? 'Любой кадр из альбома' : 'Появится после первого снимка',
                  has ? () => setState(() => _frames = true) : null),
            ],
          ],
        ),
      ),
    );
  }
}

class _FramesGrid extends ConsumerWidget {
  final String eventId;
  const _FramesGrid({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumFramesProvider(eventId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
      error: (e, _) => Center(child: Text(extractUserMessage(e))),
      data: (a) {
        final frames = (a['items'] as List).cast<Map>();
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: frames.length,
          itemBuilder: (_, i) {
            final f = frames[i];
            final url = (f['thumbnail_url'] ?? f['preview_url'] ?? f['full_url']) as String?;
            return GestureDetector(
              onTap: () => Navigator.pop(context, CoverChoice('frame', f['id'] as String)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: url == null
                    ? Container(color: AppColors.paper3)
                    : CachedNetworkImage(imageUrl: url, cacheKey: Uri.parse(url).path, fit: BoxFit.cover, fadeInDuration: Duration.zero),
              ),
            );
          },
        );
      },
    );
  }
}

/// Плашка под обложкой, пока её нет: сразу загрузить или взять первый кадр.
class CoverPromptCard extends StatefulWidget {
  final String eventId;
  final int framesCount;
  final bool busy;
  final VoidCallback onGallery;
  final VoidCallback onFirstFrame;
  final VoidCallback onMore;
  const CoverPromptCard({
    super.key,
    required this.eventId,
    required this.framesCount,
    required this.busy,
    required this.onGallery,
    required this.onFirstFrame,
    required this.onMore,
  });

  @override
  State<CoverPromptCard> createState() => _CoverPromptCardState();
}

class _CoverPromptCardState extends State<CoverPromptCard> {
  bool _hidden = true;
  String get _key => 'cover_prompt_${widget.eventId}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _hidden = p.getBool(_key) ?? false);
    }).catchError((_) {
      if (mounted) setState(() => _hidden = false);
    });
  }

  Future<void> _hide() async {
    setState(() => _hidden = true);
    try {
      (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final has = widget.framesCount > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
      decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('ОБЛОЖКА', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _hide,
            icon: const Icon(Icons.close, size: 18, color: AppColors.ink3),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(has ? 'Сделайте первый кадр обложкой' : 'Добавьте обложку альбома',
                style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(
              has
                  ? 'В альбоме уже есть кадры. Одно нажатие, и самый первый станет обложкой, либо загрузите своё фото.'
                  : 'Загрузите фото сейчас. Либо после первого снимка мы предложим сделать его обложкой одним нажатием.',
              style: GoogleFonts.manrope(fontSize: 13.5, height: 1.45, color: AppColors.ink3),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: widget.busy ? null : (has ? widget.onFirstFrame : widget.onGallery),
                child: Text(has ? 'Взять первый кадр' : 'Загрузить из галереи'),
              ),
            ),
            if (has) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(onPressed: widget.busy ? null : widget.onMore, child: const Text('Другие способы')),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
