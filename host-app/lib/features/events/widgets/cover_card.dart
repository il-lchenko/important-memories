import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api_client.dart';
import '../../../core/widgets/brand_icon.dart';
import '../../album/album_provider.dart';
import '../events_provider.dart';
import 'cover_picker.dart';

/// Обложка альбома с кнопкой «Добавить обложку» и плашкой-подсказкой (для соло-альбома).
class EventCoverCard extends ConsumerStatefulWidget {
  final String eventId;
  final Map<String, dynamic> event;
  const EventCoverCard({super.key, required this.eventId, required this.event});

  @override
  ConsumerState<EventCoverCard> createState() => _EventCoverCardState();
}

class _EventCoverCardState extends ConsumerState<EventCoverCard> {
  bool _busy = false;

  String? get _coverUrl => widget.event['cover_url'] as String?;
  int get _frames => widget.event['frames_count'] as int? ?? 0;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
      ref.invalidate(eventDetailProvider(widget.eventId));
      ref.invalidate(eventsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null || !mounted) return;
    await _run(() async {
      final bytes = await file.readAsBytes();
      final form = dio_pkg.FormData.fromMap({
        'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: 'cover.jpg', contentType: dio_pkg.DioMediaType('image', 'jpeg')),
      });
      await ref.read(dioProvider).post('events/${widget.eventId}/cover', data: form);
    });
  }

  Future<void> _fromFrame(String? id) => _run(() async {
        await ref.read(dioProvider).post('events/${widget.eventId}/cover/from-frame', data: {'frame_id': id});
      });

  Future<void> _sheet() async {
    final c = await showCoverSheet(context, eventId: widget.eventId, framesCount: _frames, hasCover: _coverUrl != null);
    if (c == null || !mounted) return;
    switch (c.kind) {
      case 'gallery':
        await _fromGallery();
      case 'first':
        await _fromFrame(null);
      case 'frame':
        await _fromFrame(c.frameId);
    }
  }

  Widget _pill({required String label, required bool big}) {
    return GestureDetector(
      onTap: _busy ? null : _sheet,
      child: Container(
        height: big ? 48 : 36,
        padding: EdgeInsets.symmetric(horizontal: big ? 20 : 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: big ? 0.32 : 0.25),
          borderRadius: BorderRadius.circular(24),
          border: big ? Border.all(color: Colors.white.withValues(alpha: 0.45)) : null,
        ),
        child: _busy
            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                BrandIcon('cover', size: big ? 26 : 22, ink: Colors.white),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontFamily: 'Manrope', fontSize: big ? 15 : 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _coverUrl;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(
        aspectRatio: 16 / 10,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            if (url != null)
              CachedNetworkImage(imageUrl: url, cacheKey: Uri.parse(url).path, fit: BoxFit.cover, fadeInDuration: Duration.zero)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A3828), Color(0xFF2A1810), Color(0xFF100806)]),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x88000000)], stops: [0.45, 1.0]),
              ),
            ),
            if (url == null)
              Center(child: _pill(label: 'Добавить обложку', big: true))
            else
              Positioned(top: 12, right: 12, child: _pill(label: 'Обложка', big: false)),
          ]),
        ),
      ),
      if (url == null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CoverPromptCard(
            eventId: widget.eventId,
            framesCount: _frames,
            busy: _busy,
            onGallery: _fromGallery,
            onFirstFrame: () => _fromFrame(null),
            onMore: _sheet,
          ),
        ),
    ]);
  }
}
