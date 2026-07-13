import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../album_provider.dart';

class FrameDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  final int frameIndex;
  final String? jumpFrameId;
  const FrameDetailScreen({
    super.key,
    required this.eventId,
    required this.frameIndex,
    this.jumpFrameId,
  });

  @override
  ConsumerState<FrameDetailScreen> createState() => _FrameDetailScreenState();
}

class _FrameDetailScreenState extends ConsumerState<FrameDetailScreen> {
  late int _current;
  bool _isPolaroid = false;
  bool _jumped = false;
  // Локальный поворот: применяется визуально, при первом изменении показывается toast «Сохранить ротацию».
  // Если не сохранять — при смене кадра сбрасывается на серверный rotation.
  int _localRotation = 0;
  bool _rotationDirty = false;
  bool _savingRotation = false;
  bool _deleting = false;
  String _selectedRole = 'host';

  @override
  void initState() {
    super.initState();
    _current = widget.frameIndex;
    _loadRole();
  }

  /// If `jumpFrameId` is provided (from Memories tap), find its index in the
  /// loaded album frames and switch `_current` to it. Called from build() once
  /// frames are available.
  void _maybeJump(List frames) {
    if (_jumped || widget.jumpFrameId == null || frames.isEmpty) return;
    final target = widget.jumpFrameId;
    for (int i = 0; i < frames.length; i++) {
      final f = frames[i];
      if (f is Map && f['id']?.toString() == target) {
        _jumped = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _current != i) setState(() => _current = i);
        });
        return;
      }
    }
    _jumped = true; // frame not found — stop trying
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('selected_role') ?? 'host';
    if (mounted) setState(() => _selectedRole = role);
  }

  void _prev() {
    if (_current > 0) {
      setState(() {
        _current--;
        _resetRotationLocal();
      });
    }
  }

  void _next(int total) {
    if (_current < total - 1) {
      setState(() {
        _current++;
        _resetRotationLocal();
      });
    }
  }

  void _resetRotationLocal() {
    _localRotation = 0;
    _rotationDirty = false;
  }

  void _rotate(int baseRotation) {
    setState(() {
      // baseRotation — что сохранено на сервере. Локальная ротация суммируется поверх.
      final next = ((_localRotation + 90) % 360);
      _localRotation = next;
      _rotationDirty = (next + baseRotation) % 360 != baseRotation % 360;
    });
  }

  Future<void> _saveRotation(String frameId, int currentServerRotation) async {
    if (_savingRotation) return;
    setState(() => _savingRotation = true);
    final newRotation = (currentServerRotation + _localRotation) % 360;
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        'events/${widget.eventId}/frames/$frameId/rotation',
        data: {'rotation': newRotation},
      );
      ref.invalidate(eventAlbumProvider(widget.eventId));
      if (mounted) {
        setState(() {
          _rotationDirty = false;
          _localRotation = 0; // после save сервер вернёт новое значение
          _savingRotation = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ротация сохранена')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingRotation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractUserMessage(e))),
        );
      }
    }
  }

  Future<void> _deleteFrame(String frameId, int total) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text('Удалить кадр?',
          style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.ink)),
        content: const Text(
          'Кадр пропадёт из альбома навсегда. Гости его больше не увидят',
          style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink3, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить', style: TextStyle(fontFamily: 'Inter', color: AppColors.shutter, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('events/${widget.eventId}/frames/$frameId');
      ref.invalidate(eventAlbumProvider(widget.eventId));
      ref.invalidate(eventAlbumMetaProvider(widget.eventId));
      if (mounted) {
        // Если это был последний кадр или удалили текущий — вернёмся назад
        if (total <= 1) {
          context.pop();
        } else {
          setState(() {
            _deleting = false;
            if (_current >= total - 1) _current = total - 2;
            _resetRotationLocal();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractUserMessage(e))),
        );
      }
    }
  }

  Future<void> _sharePhoto(String url) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/im_frame.jpg';
      await Dio().download(url, filePath);
      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'image/jpeg')],
        text: 'Кадр из Important Memories',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось поделиться фото')),
        );
      }
    }
  }

  Future<void> _savePhoto(String url) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет доступа к галерее')));
          return;
        }
      }
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/im_frame_save.jpg';
      await Dio().download(url, filePath);
      await Gal.putImage(filePath, album: 'Important Memories');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено в галерею')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось сохранить фото')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final framesAsync = ref.watch(eventAlbumProvider(widget.eventId));

    return framesAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator(color: AppColors.amber)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.ink3, size: 40),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => ref.invalidate(eventAlbumProvider(widget.eventId)),
                child: const Text('Повторить', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber)),
              ),
            ],
          ),
        ),
      ),
      data: (frames) {
        if (frames.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.paper,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined, color: AppColors.ink3, size: 40),
                  const SizedBox(height: 12),
                  const Text('Кадров нет', style: TextStyle(fontFamily: 'Inter', color: AppColors.ink2)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Text('Назад', style: TextStyle(fontFamily: 'Inter', color: AppColors.amber)),
                  ),
                ],
              ),
            ),
          );
        }

        _maybeJump(frames);
        final total = frames.length;
        final safeIdx = _current.clamp(0, total - 1);
        final frame = frames[safeIdx];
        final frameId = frame['id'] as String? ?? '';
        final guestName = frame['guest_name'] as String? ?? '';
        final guestId = frame['guest_id'] as String? ?? '';
        final guestAvatarUrl = frame['guest_avatar_url'] as String?;
        final capturedAtRaw = frame['captured_at'];
        final uploadedAtRaw = frame['uploaded_at'];
        final dt = _frameDateTime(capturedAtRaw) ?? _frameDateTime(uploadedAtRaw);
        final serverRotation = (frame['rotation'] as num?)?.toInt() ?? 0;
        final effectiveRotation = (serverRotation + _localRotation) % 360;
        final caption = (frame['caption'] as String?)?.trim();
        final voiceUrl = frame['voice_url'] as String?;
        final voicePeaks = (frame['voice_peaks'] as List?)?.cast<num>().map((n) => n.toDouble()).toList();
        final voiceDurationMs = (frame['voice_duration_ms'] as num?)?.toInt();

        return Scaffold(
          backgroundColor: AppColors.paper,
          body: SafeArea(
            child: Column(
              children: [
                // Topbar
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0x1A1A1714))),
                  ),
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      _IcBtn(onTap: () => context.pop(), icon: Icons.chevron_left),
                      Expanded(
                        child: Text(
                          'КАДР ${safeIdx + 1} / $total',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 11,
                            letterSpacing: 1.32,
                            color: AppColors.ink3,
                          ),
                        ),
                      ),
                      _IcBtn(
                        onTap: () => setState(() => _isPolaroid = !_isPolaroid),
                        icon: _isPolaroid
                            ? Icons.photo_size_select_large_outlined
                            : Icons.crop_portrait_rounded,
                        iconSize: 20,
                      ),
                    ],
                  ),
                  ),
                ),
                // Frame progress bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
                  child: Row(
                    children: List.generate(
                      math.min(total, 24),
                      (i) => Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i <= (safeIdx % 24)
                                ? AppColors.amber
                                : const Color(0x1F1A1714),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Photo area + nav arrows
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -200) _next(total);
                      if (v > 200) _prev();
                    },
                    child: SizedBox.expand(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _isPolaroid
                              ? _PolaroidBig(
                                  key: ValueKey('p$safeIdx'),
                                  frame: frame,
                                  guestName: guestName,
                                  rotationDeg: effectiveRotation,
                                )
                              : _FullFrame(
                                  key: ValueKey('f$safeIdx'),
                                  frame: frame,
                                  rotationDeg: effectiveRotation,
                                ),
                          Positioned(
                            left: 0, top: 0, bottom: 0,
                            child: Center(
                              child: _NavArrow(direction: -1, enabled: safeIdx > 0, onTap: _prev),
                            ),
                          ),
                          Positioned(
                            right: 0, top: 0, bottom: 0,
                            child: Center(
                              child: _NavArrow(direction: 1, enabled: safeIdx < total - 1, onTap: () => _next(total)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Caption — сразу под фото, с воздухом. Растёт по длине подписи.
                // В полароид-режиме подпись уже РИСУЕТСЯ в белом поле _PolaroidBig,
                // здесь не дублируем.
                if (!_isPolaroid && caption != null && caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 22, 26, 10),
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.caveat(
                        fontStyle: FontStyle.italic,
                        fontSize: 26,
                        height: 1.28,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                // Voice player — тот же ритм что и caption: с воздухом под фото.
                if ((caption == null || caption.isEmpty) && voiceUrl != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                    child: _VoicePlayer(
                      key: ValueKey(voiceUrl),
                      url: voiceUrl,
                      peaks: voicePeaks,
                      durationMs: voiceDurationMs ?? 0,
                    ),
                  ),
                // Meta bar — author left, time + date right (with icons)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: guestId.isEmpty
                            ? null
                            : () => _showGuestProfileSheet(
                                  context, guestId, guestName, guestAvatarUrl, frames,
                                ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MiniAvatar(url: guestAvatarUrl, name: guestName),
                            const SizedBox(width: 8),
                            Text(
                              guestName.isNotEmpty ? guestName.toUpperCase() : '—',
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 10,
                                letterSpacing: 1.4,
                                color: AppColors.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dt != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time, size: 11, color: AppColors.ink3),
                            const SizedBox(width: 4),
                            Text(
                              dt.time,
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 10,
                                letterSpacing: 1.4,
                                color: AppColors.ink3,
                              ),
                            ),
                            Container(
                              width: 1, height: 10,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: AppColors.line,
                            ),
                            const Icon(Icons.calendar_today_outlined, size: 11, color: AppColors.ink3),
                            const SizedBox(width: 4),
                            Text(
                              dt.date,
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 10,
                                letterSpacing: 1.4,
                                color: AppColors.ink3,
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                          '—',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            letterSpacing: 1.4,
                            color: AppColors.ink3,
                          ),
                        ),
                    ],
                  ),
                ),
                // Toast «Сохранить ротацию» — над action bar, появляется когда rotation dirty
                if (_rotationDirty &&
                    (_selectedRole == 'host' || (frame['is_mine'] as bool? ?? false)))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 8)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.rotate_right, size: 18, color: AppColors.amber),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Сохранить ротацию снимка в альбоме?',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.paper, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _savingRotation ? null : () => _saveRotation(frameId, serverRotation),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _savingRotation ? '...' : 'Сохранить',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Actions row
                Builder(builder: (context) {
                  final canEdit = _selectedRole == 'host' ||
                      (frame['is_mine'] as bool? ?? false);
                  return Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.paper2,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (canEdit)
                          _ActionBtn(
                            icon: Icons.rotate_right,
                            onTap: () => _rotate(serverRotation),
                          ),
                        _ActionBtn(
                          icon: Icons.ios_share,
                          onTap: frame['full_url'] != null
                              ? () => _sharePhoto(frame['full_url'] as String)
                              : null,
                        ),
                        _ActionBtn(
                          icon: Icons.download_outlined,
                          onTap: frame['full_url'] != null
                              ? () => _savePhoto(frame['full_url'] as String)
                              : null,
                        ),
                        if (canEdit)
                          _ActionBtn(
                            icon: Icons.delete_outline,
                            red: true,
                            onTap: _deleting ? null : () => _deleteFrame(frameId, total),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

/// Returns (time HH:mm, date dd.MM.yyyy) parsed from the raw timestamp, or null on failure.
({String time, String date})? _frameDateTime(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  // Some servers emit "YYYY-MM-DD HH:MM:SS" with a space — Dart wants ISO-8601 'T'.
  final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  try {
    final dt = DateTime.parse(normalized).toLocal();
    // Numeric format — no locale dependency.
    return (
      time: DateFormat('HH:mm').format(dt),
      date: DateFormat('dd.MM.yyyy').format(dt),
    );
  } catch (_) {
    return null;
  }
}

// ─── widgets ──────────────────────────────────────────────────────────────────

class _IcBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final double iconSize;
  const _IcBtn({required this.onTap, required this.icon, this.iconSize = 22});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: AppColors.ink2, size: iconSize),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final int direction;
  final bool enabled;
  final VoidCallback onTap;
  const _NavArrow({required this.direction, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Icon(
          direction < 0 ? Icons.chevron_left : Icons.chevron_right,
          color: enabled ? AppColors.ink2 : AppColors.ink4.withValues(alpha: 0.4),
          size: 30,
        ),
      ),
    );
  }
}

class _PolaroidBig extends StatelessWidget {
  final Map<String, dynamic> frame;
  final String guestName;
  final int rotationDeg;
  const _PolaroidBig({super.key, required this.frame, required this.guestName, this.rotationDeg = 0});

  static const _fallback = [
    Color(0xFFF3CDA0), Color(0xFFC97E4A), Color(0xFF6A3520), Color(0xFF1F1208),
  ];

  @override
  Widget build(BuildContext context) {
    final url = frame['full_url'] as String?;
    final captionText = (frame['caption'] as String? ?? '').trim();
    final hasCaption = captionText.isNotEmpty;
    // Fallback на имя; для полароида это визуально приятнее чем прочерк.
    final label = hasCaption
        ? captionText
        : (guestName.isNotEmpty ? guestName : '—');

    return Transform.rotate(
      angle: -1.5 * math.pi / 180,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.all(Radius.circular(4)),
          boxShadow: [
            BoxShadow(color: Color(0x471A1714), blurRadius: 48, offset: Offset(0, 24), spreadRadius: -12),
            BoxShadow(color: Color(0x141A1714), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: AnimatedRotation(
                  turns: rotationDeg / 360.0,
                  duration: const Duration(milliseconds: 240),
                  child: url != null
                      ? CachedNetworkImage(imageUrl: url, cacheKey: Uri.parse(url).path, fit: BoxFit.cover, fadeInDuration: Duration.zero)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0, -0.2),
                              radius: 1.2,
                              colors: _fallback,
                              stops: [0.0, 0.4, 0.8, 1.0],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // Белая зона: только caption. Если нет — короткая пустая полоска (классический полароид).
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 16),
              child: hasCaption
                  ? Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.caveat(
                        fontSize: 22,
                        fontStyle: FontStyle.italic,
                        height: 1.26,
                        color: AppColors.ink2,
                      ),
                    )
                  : const SizedBox(height: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullFrame extends StatelessWidget {
  final Map<String, dynamic> frame;
  final int rotationDeg;
  const _FullFrame({super.key, required this.frame, this.rotationDeg = 0});

  static const _fallback = [
    Color(0xFFF3CDA0), Color(0xFFC97E4A), Color(0xFF6A3520), Color(0xFF1F1208),
  ];

  @override
  Widget build(BuildContext context) {
    final url = (frame['preview_url'] as String?) ?? (frame['full_url'] as String?);
    final w = (frame['width'] as num?)?.toDouble() ?? 3.0;
    final h = (frame['height'] as num?)?.toDouble() ?? 4.0;

    // RotatedBox changes the layout box (unlike Transform.rotate which is paint-only).
    // This prevents ClipRect from clipping pre-rotation content at the wrong axis.
    return FractionallySizedBox(
      widthFactor: 0.95,
      heightFactor: 0.95,
      child: Center(
        child: RotatedBox(
          quarterTurns: rotationDeg ~/ 90,
          child: AspectRatio(
            aspectRatio: w / h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: url != null
                  ? CachedNetworkImage(
                      imageUrl: url,
                      cacheKey: Uri.parse(url).path,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -0.2),
                          radius: 1.2,
                          colors: _fallback,
                          stops: [0.0, 0.4, 0.8, 1.0],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final bool red;
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, this.red = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1.0,
        child: Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(icon, size: 26, color: red ? AppColors.shutter : AppColors.ink),
        ),
      ),
    );
  }
}

/// Capsule-style voice player matching mockup: round play button + waveform + duration.
/// Played portion of the waveform shifts to shutter color (red) for visual progress.
class _VoicePlayer extends StatefulWidget {
  final String url;
  final List<double>? peaks;
  final int durationMs;
  const _VoicePlayer({super.key, required this.url, required this.peaks, required this.durationMs});

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  bool _ready = false;
  bool _playing = false;
  double _progress = 0; // 0..1
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      if (!mounted) return;
      setState(() => _ready = true);
      _posSub = _player.positionStream.listen((pos) {
        final total = _player.duration ?? Duration(milliseconds: widget.durationMs);
        if (total.inMilliseconds > 0 && mounted) {
          setState(() => _progress = pos.inMilliseconds / total.inMilliseconds);
        }
      });
      _stateSub = _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
        if (s.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
          if (mounted) setState(() => _progress = 0);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_ready) return;
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSec = (widget.durationMs / 1000).round();
    final peaks = widget.peaks ?? List.filled(20, 0.4);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                color: AppColors.amber,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white, size: 18,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 24,
              child: CustomPaint(
                painter: _WaveformPainter(peaks: peaks, progress: _progress),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '0:${totalSec.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontFamily: 'JetBrains Mono', fontSize: 10, color: AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  _WaveformPainter({required this.peaks, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final barW = 3.0;
    final gap = 2.0;
    final available = size.width;
    final maxBars = ((available + gap) / (barW + gap)).floor();
    final step = (peaks.length / maxBars).ceil().clamp(1, peaks.length);
    final amberPaint = Paint()..color = AppColors.amber..style = PaintingStyle.fill;
    final playedPaint = Paint()..color = AppColors.shutter..style = PaintingStyle.fill;
    int barIdx = 0;
    for (int i = 0; i < peaks.length; i += step) {
      double sum = 0; int count = 0;
      for (int j = 0; j < step && (i + j) < peaks.length; j++) {
        sum += peaks[i + j]; count++;
      }
      final avg = count > 0 ? sum / count : 0;
      final h = math.max(4.0, avg * size.height);
      final x = barIdx * (barW + gap);
      if (x + barW > size.width) break;
      final isPlayed = (barIdx / maxBars) < progress;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, barW, h),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, isPlayed ? playedPaint : amberPaint);
      barIdx++;
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress || old.peaks != peaks;
}

// ─── Guest avatar + profile sheet ──────────────────────────────────────────────
class _MiniAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  const _MiniAvatar({required this.url, required this.name, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.paper2,
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.35),
          width: 1,
        ),
        image: url != null
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              initial,
              style: GoogleFonts.playfairDisplay(
                fontSize: size * 0.5,
                fontWeight: FontWeight.w600,
                color: AppColors.amber,
              ),
            )
          : null,
    );
  }
}

void _showGuestProfileSheet(
  BuildContext context,
  String guestId,
  String guestName,
  String? avatarUrl,
  List<Map<String, dynamic>> frames,
) {
  final myFrames = frames.where((f) => f['guest_id'] == guestId).toList();
  final framesCount = myFrames.length;
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.of(ctx).padding.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.ink4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _MiniAvatar(url: avatarUrl, name: guestName, size: 84),
            const SizedBox(height: 14),
            Text(
              guestName.isNotEmpty ? guestName : 'Гость',
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              framesCount == 1
                  ? '1 кадр в этом альбоме'
                  : '$framesCount кадров в этом альбоме',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.ink3,
              ),
            ),
            const SizedBox(height: 24),
            if (framesCount > 0)
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: math.min(framesCount, 12),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = myFrames[i];
                    final url = (f['thumbnail_url'] ?? f['preview_url']) as String?;
                    return Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                        color: AppColors.paper2,
                        borderRadius: BorderRadius.circular(6),
                        image: url != null
                            ? DecorationImage(
                                image: NetworkImage(url),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}
