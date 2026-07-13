import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';
import '../album_provider.dart';

class AlbumScreen extends ConsumerStatefulWidget {
  final String eventId;
  const AlbumScreen({super.key, required this.eventId});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  int _modeIndex = 0;
  static const _modes = ['Журнал', 'Ретро', 'Полароид'];

  bool _openingCamera = false;

  int _gridColumns = 2; // 2 | 3 | 4, только для режима Журнал
  final Map<int, Offset> _pointers = {};
  double _pinchStartDist = 0;
  bool _pinchHandled = false;

  final _scrollCtrl = ScrollController();
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.hasClients && _scrollCtrl.offset > 56;
      if (show != _titleVisible) setState(() => _titleVisible = show);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));
    final framesAsync = ref.watch(eventAlbumProvider(widget.eventId));
    final metaAsync = ref.watch(eventAlbumMetaProvider(widget.eventId));
    final isAdminPreview = metaAsync.maybeWhen(
      data: (m) => m['is_admin_preview'] as bool? ?? false,
      orElse: () => false,
    );
    final revealAtRaw = eventAsync.maybeWhen(
      data: (e) {
        final settings = e['settings'] as Map?;
        return settings?['reveal_at']?.toString();
      },
      orElse: () => null,
    );

    final title = eventAsync.maybeWhen(
      data: (e) => e['title'] as String? ?? 'Альбом',
      orElse: () => 'Альбом',
    );
    final shortCode = eventAsync.maybeWhen(
      data: (e) => e['short_code'] as String? ?? '',
      orElse: () => '',
    );
    const guestBase = String.fromEnvironment('GUEST_PWA_URL', defaultValue: 'https://impomento.pro');
    final shareUrl = shortCode.isNotEmpty ? '$guestBase/g/$shortCode' : null;

    final frames = framesAsync.maybeWhen(
      data: (f) => f,
      orElse: () => <Map<String, dynamic>>[],
    );

    final frameCount = framesAsync.maybeWhen(
      data: (f) => f.length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fixed topbar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _IcBtn(icon: Icons.chevron_left, onTap: () => context.pop()),
                      IgnorePointer(
                        ignoring: _titleVisible,
                        child: AnimatedOpacity(
                          opacity: _titleVisible ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Row(
                            children: [
                              if (_modeIndex == 0) ...[
                                _IcBtn(
                                  icon: Icons.dashboard_customize_outlined,
                                  onTap: () => showDialog(
                                    context: context,
                                    barrierColor: Colors.black.withValues(alpha: 0.35),
                                    builder: (_) => _GridFormatDialog(
                                      currentColumns: _gridColumns,
                                      onSelect: (c) => setState(() => _gridColumns = c),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              _IcBtn(
                                icon: Icons.ios_share,
                                onTap: shareUrl != null
                                    ? () => Share.share('Посмотри нашу плёнку «$title»!\n$shareUrl', subject: title)
                                    : () {},
                              ),
                              const SizedBox(width: 8),
                              _IcBtn(
                                icon: Icons.tune,
                                onTap: () => context.push('/events/${widget.eventId}/settings'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedOpacity(
                    opacity: _titleVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isAdminPreview) _AdminPreviewBanner(revealAtRaw: revealAtRaw),
            // Scrollable header + photos
            Expanded(
              child: Listener(
                onPointerDown: (e) {
                  _pointers[e.pointer] = e.localPosition;
                  if (_pointers.length == 2) {
                    final ps = _pointers.values.toList();
                    _pinchStartDist = (ps[0] - ps[1]).distance;
                    _pinchHandled = false;
                  }
                },
                onPointerMove: (e) {
                  if (_modeIndex != 0 || _pinchHandled) return;
                  _pointers[e.pointer] = e.localPosition;
                  if (_pointers.length == 2 && _pinchStartDist > 10) {
                    final ps = _pointers.values.toList();
                    final scale = (ps[0] - ps[1]).distance / _pinchStartDist;
                    if (scale > 1.28 && _gridColumns > 2) {
                      setState(() { _gridColumns--; _pinchHandled = true; });
                    } else if (scale < 0.72 && _gridColumns < 4) {
                      setState(() { _gridColumns++; _pinchHandled = true; });
                    }
                  }
                },
                onPointerUp: (e) => _pointers.remove(e.pointer),
                onPointerCancel: (e) => _pointers.remove(e.pointer),
                child: NestedScrollView(
                key: ValueKey(_modeIndex),
                controller: _scrollCtrl,
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                                        fontSize: 30, fontWeight: FontWeight.w700,
                                        letterSpacing: -0.5, height: 1.1, color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      framesAsync.isLoading
                                          ? 'ЗАГРУЗКА...'
                                          : '$frameCount КАДРОВ · ПРОЯВЛЕНО',
                                      style: const TextStyle(
                                        fontFamily: 'JetBrains Mono', fontSize: 11,
                                        letterSpacing: 1.54, color: AppColors.ink3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _HeaderCamBtn(
                                loading: _openingCamera,
                                onTap: _openingCamera ? null : () => _openCamera(shortCode),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                          child: _ViewSwitcher(
                            modes: _modes,
                            selectedIndex: _modeIndex,
                            onChanged: (i) => setState(() => _modeIndex = i),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                body: _buildBody(frames, frameCount),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  /// Открыть встроенную камеру для этого события.
  /// Гость — у него уже есть guest_token, идём напрямую.
  /// Хост / приглашённый юзер без guest_token — тихо POST /guest/sessions
  /// (под Bearer'ом), сохраняем token+frames_remaining+lut_preset, потом камера.
  Future<void> _openCamera(String shortCode) async {
    final existingToken = await GuestPrefs.tokenFor(widget.eventId);
    if (existingToken.isNotEmpty) {
      // Уже есть сессия для этого события — просто открываем камеру.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_guest_event_id', widget.eventId);
      if (!mounted) return;
      await context.push('/guest/camera/${widget.eventId}');
      // После возврата с камеры — обновить альбом (новые кадры).
      if (mounted) {
        ref.invalidate(eventAlbumProvider(widget.eventId));
        ref.invalidate(eventAlbumMetaProvider(widget.eventId));
      }
      return;
    }

    if (shortCode.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось определить код события')),
      );
      return;
    }

    setState(() => _openingCamera = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post(
        'guest/sessions',
        data: {
          'short_code': shortCode,
          'fingerprint': await _deviceFingerprint(),
          // name можно не передавать — backend подставит display_name юзера
        },
      );
      final data = Map<String, dynamic>.from(resp.data as Map);
      final token = data['guest_token'] as String?;
      final event = data['event'] as Map?;
      final settings = event == null ? null : event['settings'] as Map?;
      final lutPreset = settings == null ? null : settings['lut_preset'] as String?;
      // frames_remaining из backend; если 0 — берём frames_per_guest как стартовое значение
      var framesRemaining = data['frames_remaining'] as int? ?? 0;
      if (framesRemaining == 0) {
        final fpg = settings?['frames_per_guest'] as int?;
        if (fpg != null && fpg > 0) framesRemaining = fpg;
      }

      if (token == null) throw StateError('Empty guest_token in response');

      await GuestPrefs.saveSession(
        eventId: widget.eventId,
        token: token,
        framesRemaining: framesRemaining,
        lutPreset: lutPreset,
      );

      if (!mounted) return;
      await context.push('/guest/camera/${widget.eventId}');
      // После возврата с камеры — обновить альбом (новые кадры).
      if (mounted) {
        ref.invalidate(eventAlbumProvider(widget.eventId));
        ref.invalidate(eventAlbumMetaProvider(widget.eventId));
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(extractUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  Future<String> _deviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    var fp = prefs.getString('device_fingerprint');
    if (fp != null && fp.isNotEmpty) return fp;
    // 32 случайных hex-символа — достаточно для уникальности
    final rnd = math.Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buf.write(rnd.nextInt(16).toRadixString(16));
    }
    fp = buf.toString();
    await prefs.setString('device_fingerprint', fp);
    return fp;
  }

  Widget _buildBody(List<Map<String, dynamic>> frames, int count) {
    if (ref.watch(eventAlbumProvider(widget.eventId)).isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.amber));
    }
    if (frames.isEmpty) return const _EmptyAlbum();
    switch (_modeIndex) {
      case 0: return _MagazineGrid(eventId: widget.eventId, frames: frames, columns: _gridColumns);
      case 1: return _RetroLayout(eventId: widget.eventId, frames: frames);
      case 2: return _PolaroidFeed(eventId: widget.eventId, frames: frames);
      default: return const SizedBox();
    }
  }
}

// ─── shared utils ─────────────────────────────────────────────────────────────

const _filmGrads = <List<Color>>[
  [Color(0xFFF0C896), Color(0xFFC97E4A), Color(0xFF5A2A14)],
  [Color(0xFFE8B888), Color(0xFFB06A3A), Color(0xFF3A1E10)],
  [Color(0xFFD4955F), Color(0xFF8C4A28), Color(0xFF2A1810)],
  [Color(0xFFF5D4A5), Color(0xFFB8804A), Color(0xFF4A2812)],
  [Color(0xFFC98A5A), Color(0xFF6E3A1A), Color(0xFF1A0E08)],
  [Color(0xFFE0A878), Color(0xFF9A5A2A), Color(0xFF3A1E10)],
];

String _guestName(Map<String, dynamic> f) => f['guest_name'] as String? ?? '';
String _caption(Map<String, dynamic> f) => (f['caption'] as String? ?? '').trim();

/// Возвращает caption (если есть) или имя гостя. Используется во всех местах,
/// где на полароидах/оверлеях раньше писалось только имя.
String _captionOrName(Map<String, dynamic> f) {
  final c = _caption(f);
  return c.isNotEmpty ? c : _guestName(f);
}

String _frameTime(Map<String, dynamic> f) {
  final raw = f['captured_at'] as String?;
  if (raw == null) return '';
  try {
    final dt = DateTime.parse(raw).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '';
  }
}

// ─── empty state ──────────────────────────────────────────────────────────────

class _EmptyAlbum extends StatelessWidget {
  const _EmptyAlbum();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: AppColors.paper2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line, width: 1),
              ),
              child: const Icon(Icons.camera_roll_outlined, size: 36, color: AppColors.ink3),
            ),
            const SizedBox(height: 28),
            Text(
              'Плёнка ещё пуста',
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                fontSize: 22, fontWeight: FontWeight.w600,
                color: AppColors.ink2, letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Когда гости сделают снимки,\nони проявятся здесь',
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Colors.transparent, AppColors.line, Colors.transparent]),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '[ 0 КАДРОВ ]',
              style: TextStyle(
                fontFamily: 'JetBrains Mono', fontSize: 11,
                letterSpacing: 2, color: AppColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Показывает реальное фото или gradient-заглушку.
class _FrameImage extends StatelessWidget {
  final Map<String, dynamic>? frame;
  final int fallbackIndex;

  const _FrameImage({this.frame, required this.fallbackIndex});

  @override
  Widget build(BuildContext context) {
    // Приоритет: preview (2560px q=92) → thumbnail (сжатый) → full. Preview даёт
    // хорошее качество даже в маленькой сетке — иначе видно артефакты JPEG.
    final url = (frame?['preview_url'] as String?)
        ?? (frame?['thumbnail_url'] as String?)
        ?? (frame?['full_url'] as String?);
    final grad = _filmGrads[fallbackIndex % _filmGrads.length];
    final quarterTurns = ((frame?['rotation'] as num?)?.toInt() ?? 0) ~/ 90;

    if (url != null) {
      return RotatedBox(
        quarterTurns: quarterTurns,
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: Uri.parse(url).path,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, __) => _GradientFill(grad: grad, index: fallbackIndex),
          errorWidget: (_, __, ___) => _GradientFill(grad: grad, index: fallbackIndex),
        ),
      );
    }
    return _GradientFill(grad: grad, index: fallbackIndex);
  }
}

class _GradientFill extends StatelessWidget {
  final List<Color> grad;
  final int index;
  const _GradientFill({required this.grad, required this.index});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(index.isEven ? -0.2 : 0.3, index % 3 == 0 ? -0.4 : 0.4),
              radius: 1.3,
              colors: grad,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.1,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.38)],
            ),
          ),
        ),
      ],
    );
  }
}

class _IcBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IcBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppColors.ink, size: 22),
      ),
    );
  }
}

class _HeaderCamBtn extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _HeaderCamBtn({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.amber,
          boxShadow: [
            BoxShadow(
              color: AppColors.amber.withValues(alpha: 0.4),
              blurRadius: 14,
              spreadRadius: -2,
            ),
            const BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 28,
                    color: Colors.white,
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 12,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  final List<String> modes;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const _ViewSwitcher({required this.modes, required this.selectedIndex, required this.onChanged});

  static const _icons = [
    Icons.grid_view_rounded,
    Icons.photo_album_outlined,
    Icons.crop_portrait_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: List.generate(modes.length, (i) {
          final active = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 36,
                decoration: BoxDecoration(
                  color: active ? AppColors.paper : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active
                      ? const [
                          BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
                          BoxShadow(color: Color(0x0A000000), blurRadius: 0, spreadRadius: 1),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icons[i], size: 14, color: active ? AppColors.amber : AppColors.ink3),
                    const SizedBox(width: 5),
                    Text(
                      modes[i],
                      style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: active ? AppColors.ink : AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── magazine mode ────────────────────────────────────────────────────────────

class _MagazineGrid extends StatelessWidget {
  final String eventId;
  final List<Map<String, dynamic>> frames;
  final int columns;
  const _MagazineGrid({required this.eventId, required this.frames, this.columns = 2});

  @override
  Widget build(BuildContext context) {
    final count = frames.length;
    final isLarge = columns == 2;
    final isMedium = columns == 3;
    final spacing = isLarge ? 6.0 : 4.0;
    final pad = isLarge ? 14.0 : 8.0;
    final radius = isLarge ? 8.0 : 6.0;
    final aspect = isLarge ? 3.0 / 4.0 : (isMedium ? 2.0 / 3.0 : 1.0);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 6, pad, 90),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemCount: count,
          itemBuilder: (ctx, i) {
            final frame = i < frames.length ? frames[i] : null;
            final time = (frame != null && isLarge) ? _frameTime(frame) : '';
            final label = (frame != null && isLarge) ? _captionOrName(frame) : '';
            final isCaption = frame != null && isLarge && _caption(frame).isNotEmpty;
            return GestureDetector(
              onTap: () => context.push('/events/$eventId/album/frame/$i'),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: AppColors.line, width: 0.5),
                  boxShadow: isLarge
                      ? const [
                          BoxShadow(color: Color(0x141A1714), blurRadius: 8, offset: Offset(0, 3)),
                          BoxShadow(color: Color(0x0A1A1714), blurRadius: 2, offset: Offset(0, 1)),
                        ]
                      : const [
                          BoxShadow(color: Color(0x0A1A1714), blurRadius: 4, offset: Offset(0, 2)),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius - 0.5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _FrameImage(frame: frame, fallbackIndex: i),
                      if (time.isNotEmpty)
                        Positioned(
                          top: 8, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              time,
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono', fontSize: 9, color: Color(0xD9FFD2AA),
                              ),
                            ),
                          ),
                        ),
                      if (label.isNotEmpty)
                        Positioned(
                          bottom: 8, left: 10, right: 10,
                          child: Text(
                            label,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.caveat(
                              fontSize: isCaption ? 18 : 19,
                              fontStyle: isCaption ? FontStyle.italic : FontStyle.normal,
                              height: 1.15,
                              color: Colors.white,
                              shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1))],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── retro mode ───────────────────────────────────────────────────────────────

class _RetroLayout extends StatelessWidget {
  final String eventId;
  final List<Map<String, dynamic>> frames;
  const _RetroLayout({required this.eventId, required this.frames});

  Map<String, dynamic>? _f(int i) => i < frames.length ? frames[i] : null;
  String _hw(int i) {
    final f = _f(i);
    if (f == null) return '';
    return _caption(f);
  }
  bool _isCaption(int i) {
    final f = _f(i);
    return f != null && _caption(f).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final count = frames.length;
    final availW = MediaQuery.of(context).size.width - 40;
    final s = (availW / 350).clamp(0.72, 1.0);

    return SingleChildScrollView(
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildRows(context, count, s),
        ),
      ),
    );
  }

  List<Widget> _buildRows(BuildContext context, int count, double s) {
    // Stable seed per event so layout is consistent but unique per album
    final seed = eventId.codeUnits.fold(0, (acc, c) => acc * 31 + c) ^ (count * 97);
    final rng = math.Random(seed);
    final widgets = <Widget>[];
    int i = 0;

    while (i < count) {
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: (rng.nextInt(12) + 6).toDouble()));
      }
      final remaining = count - i;
      if (remaining >= 2 && rng.nextInt(5) > 1) {
        widgets.add(_rowDouble(context, i, s, rng));
        i += 2;
      } else {
        widgets.add(_rowSingle(context, i, s, rng));
        i++;
      }
    }
    return widgets;
  }

  Color? _rndTape(math.Random rng) {
    switch (rng.nextInt(6)) {
      case 2: return AppColors.amber;
      case 3: return const Color(0xFFD54B3D);
      case 4: return const Color(0xFFF6F2E8);
      default: return null;
    }
  }

  Widget _rowSingle(BuildContext context, int i, double s, math.Random rng) {
    const sizes = [[300.0, 215.0], [250.0, 305.0], [275.0, 205.0], [230.0, 280.0]];
    final chosen = sizes[rng.nextInt(sizes.length)];
    final w = chosen[0] * s;
    final h = chosen[1] * s;
    final deg = rng.nextDouble() * 28 - 14;
    final alignIdx = rng.nextInt(3);
    final aligns = [MainAxisAlignment.start, MainAxisAlignment.center, MainAxisAlignment.end];
    final xPad = (rng.nextDouble() * 18 + 4) * s;
    final tape = _rndTape(rng);
    final allCorners = rng.nextBool();
    final hw = _hw(i);

    return Row(
      mainAxisAlignment: aligns[alignIdx],
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: alignIdx == 0 ? xPad : 0,
            right: alignIdx == 2 ? xPad : 0,
          ),
          child: _RetroCard(
            w: w, h: h, deg: deg, gi: i % 6, frame: _f(i),
            allCorners: allCorners, tape: tape,
            hw: hw.isNotEmpty ? hw : null,
            hwItalic: _isCaption(i),
            onTap: () => context.push('/events/$eventId/album/frame/$i'),
          ),
        ),
      ],
    );
  }

  Widget _rowDouble(BuildContext context, int i, double s, math.Random rng) {
    final wL = (rng.nextDouble() * 55 + 145) * s;
    final hL = (rng.nextDouble() * 70 + 160) * s;
    final degL = rng.nextDouble() * 28 - 14;

    final wR = (rng.nextDouble() * 55 + 135) * s;
    final hR = (rng.nextDouble() * 70 + 150) * s;
    final degR = rng.nextDouble() * 28 - 14;

    final topOffset = (rng.nextDouble() * 44) * s;
    final leftFirst = rng.nextBool();
    final leftPad = (rng.nextDouble() * 10 + 2) * s;
    final gap = (rng.nextDouble() * 8 + 3) * s;
    final tapeL = _rndTape(rng);
    final tapeR = _rndTape(rng);
    final allCornersL = rng.nextBool();

    final cardI = _RetroCard(
      w: wL, h: hL, deg: degL, gi: i % 6, frame: _f(i),
      allCorners: allCornersL, tape: tapeL,
      hw: _hw(i).isNotEmpty ? _hw(i) : null,
      hwItalic: _isCaption(i),
      onTap: () => context.push('/events/$eventId/album/frame/$i'),
    );
    final cardJ = Padding(
      padding: EdgeInsets.only(top: topOffset),
      child: _RetroCard(
        w: wR, h: hR, deg: degR, gi: (i + 1) % 6, frame: _f(i + 1),
        tape: tapeR,
        hw: _hw(i + 1).isNotEmpty ? _hw(i + 1) : null,
        hwItalic: _isCaption(i + 1),
        onTap: () => context.push('/events/$eventId/album/frame/${i + 1}'),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: leftPad),
        if (leftFirst) ...[cardI, SizedBox(width: gap), cardJ]
        else ...[cardJ, SizedBox(width: gap), cardI],
      ],
    );
  }
}

class _RetroCard extends StatelessWidget {
  final double w, h, deg;
  final int gi;
  final Map<String, dynamic>? frame;
  final bool allCorners;
  final Color? tape;
  final String? hw;
  final bool hwItalic;
  final VoidCallback? onTap;

  const _RetroCard({
    required this.w, required this.h, required this.deg, required this.gi,
    this.frame, this.allCorners = false,
    this.tape, this.hw, this.hwItalic = false, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: deg * math.pi / 180,
        child: SizedBox(
          width: w, height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: w, height: h,
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(color: Color(0x2E1A1714), blurRadius: 10, offset: Offset(0, 4)),
                    BoxShadow(color: Color(0x141A1714), blurRadius: 2, offset: Offset(0, 1)),
                  ],
                ),
                child: ClipRect(
                  child: SizedBox.expand(
                    child: _FrameImage(frame: frame, fallbackIndex: gi),
                  ),
                ),
              ),
              if (hw != null)
                Positioned(
                  bottom: 6, left: 10, right: 10,
                  child: Transform.rotate(
                    angle: -2 * math.pi / 180,
                    child: Text(
                      hw!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.caveat(
                        fontSize: hwItalic ? 15 : 18,
                        fontStyle: hwItalic ? FontStyle.italic : FontStyle.normal,
                        height: 1.15,
                        color: Colors.white,
                        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              if (allCorners) ...[
                const Positioned(top: -2, left: -2, child: _Corner(deg: 0)),
                const Positioned(top: -2, right: -2, child: _Corner(deg: 90)),
                const Positioned(bottom: -2, left: -2, child: _Corner(deg: -90)),
                const Positioned(bottom: -2, right: -2, child: _Corner(deg: 180)),
              ],
              if (tape != null)
                Positioned(
                  top: -9, left: w * 0.2,
                  child: Transform.rotate(
                    angle: -3 * math.pi / 180,
                    child: _Tape(color: tape!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final double deg;
  const _Corner({required this.deg});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: deg * math.pi / 180,
      child: CustomPaint(size: const Size(18, 18), painter: _CornerPainter()),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2D1A0E)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Tape extends StatelessWidget {
  final Color color;
  const _Tape({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 18,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.58),
        boxShadow: const [BoxShadow(color: Color(0x1A1A1714), blurRadius: 2, offset: Offset(0, 1))],
      ),
    );
  }
}

// ─── polaroid mode ────────────────────────────────────────────────────────────

class _PolaroidFeed extends StatelessWidget {
  final String eventId;
  final List<Map<String, dynamic>> frames;
  const _PolaroidFeed({required this.eventId, required this.frames});

  static const _rots = [-3.5, 3.0, -2.0, 4.0, -2.8, 2.5];

  @override
  Widget build(BuildContext context) {
    final count = frames.length;
    return SingleChildScrollView(
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
        child: Column(
          children: [
            for (int i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              _buildCard(context, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, int i) {
    final deg = _rots[i % _rots.length];
    final frame = i < frames.length ? frames[i] : null;
    final caption = frame != null ? _caption(frame) : '';
    final name = frame != null ? _guestName(frame) : '';
    final time = frame != null ? _frameTime(frame) : '';
    final hasCaption = caption.isNotEmpty;

    return Center(
      child: Transform.rotate(
        angle: deg * math.pi / 180,
        child: GestureDetector(
          onTap: () => context.push('/events/$eventId/album/frame/$i'),
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Color(0x381A1714), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -6),
                BoxShadow(color: Color(0x141A1714), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: _FrameImage(frame: frame, fallbackIndex: i),
                    ),
                  ),
                ),
                // Белая зона полароида: только caption (растёт по длине). Имя не пишем.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasCaption)
                        Text(
                          caption,
                          overflow: TextOverflow.visible,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.caveat(
                            fontSize: 22,
                            fontStyle: FontStyle.italic,
                            height: 1.22,
                            color: AppColors.ink2,
                          ),
                        )
                      else
                        const SizedBox(height: 14),
                      if (frame != null && time.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            time,
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono', fontSize: 10,
                              letterSpacing: 0.6, color: AppColors.ink3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── grid format dialog ───────────────────────────────────────────────────────

class _GridFormatDialog extends StatefulWidget {
  final int currentColumns;
  final ValueChanged<int> onSelect;
  const _GridFormatDialog({required this.currentColumns, required this.onSelect});

  @override
  State<_GridFormatDialog> createState() => _GridFormatDialogState();
}

class _GridFormatDialogState extends State<_GridFormatDialog> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentColumns;
  }

  void _confirm() {
    widget.onSelect(_selected);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Формат журнала',
                  style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.close, size: 18, color: AppColors.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Сколько фото показывать в ряд',
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FormatOption(columns: 2, label: 'Крупный', desc: '2 в ряд', isActive: _selected == 2, onTap: () => setState(() => _selected = 2)),
                const SizedBox(width: 10),
                _FormatOption(columns: 3, label: 'Средний', desc: '3 в ряд', isActive: _selected == 3, onTap: () => setState(() => _selected = 3)),
                const SizedBox(width: 10),
                _FormatOption(columns: 4, label: 'Мелкий',  desc: '4 в ряд', isActive: _selected == 4, onTap: () => setState(() => _selected = 4)),
              ],
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _confirm,
              child: Container(
                height: 50,
                decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text(
                    'Выбрать',
                    style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  final int columns;
  final String label;
  final String desc;
  final bool isActive;
  final VoidCallback onTap;
  const _FormatOption({required this.columns, required this.label, required this.desc, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFF5EDD8) : AppColors.paper2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isActive ? AppColors.amber : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              _FormatPreview(columns: columns),
              const SizedBox(height: 14),
              Text(
                label,
                style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: isActive ? AppColors.amber : AppColors.ink),
              ),
              const SizedBox(height: 3),
              Text(desc, style: GoogleFonts.manrope(fontSize: 11, color: AppColors.ink3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatPreview extends StatelessWidget {
  final int columns;
  const _FormatPreview({required this.columns});

  static const _grads = <List<Color>>[
    [Color(0xFFF0C896), Color(0xFF8C5A2A)],
    [Color(0xFFD4C0A0), Color(0xFF6A4020)],
    [Color(0xFFE8B880), Color(0xFF5A3818)],
    [Color(0xFFC8A870), Color(0xFF4A2810)],
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      const gap = 3.0;
      final totalGaps = gap * (columns - 1);
      final itemW = (box.maxWidth - totalGaps) / columns;
      final itemH = columns == 4 ? itemW : itemW * (4.0 / 3.0);

      return SizedBox(
        height: itemH,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(columns * 2 - 1, (i) {
            if (i.isOdd) return const SizedBox(width: gap);
            final idx = i ~/ 2;
            final colors = _grads[idx % _grads.length];
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: itemW,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.2,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2, left: 2,
                      child: Container(
                        width: itemW * 0.45, height: itemH * 0.22,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.28), Colors.transparent]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      );
    });
  }
}

class _AdminPreviewBanner extends StatelessWidget {
  final String? revealAtRaw;
  const _AdminPreviewBanner({required this.revealAtRaw});

  String? _formatRevealAt() {
    if (revealAtRaw == null || revealAtRaw!.isEmpty) return null;
    try {
      final dt = DateTime.parse(revealAtRaw!).toLocal();
      return DateFormat('d MMMM в HH:mm', 'ru').format(dt);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final whenStr = _formatRevealAt();
    final guestText = whenStr != null
        ? 'Гости увидят альбом $whenStr'
        : 'Гости увидят альбом после проявления фото';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.shutter.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: AppColors.shutter, width: 3)),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'АДМИН‑РЕЖИМ',
            style: TextStyle(
              fontFamily: 'JetBrains Mono', fontSize: 9,
              letterSpacing: 1.2, color: AppColors.shutter, fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Альбом видите только вы',
            style: GoogleFonts.manrope(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            guestText,
            style: const TextStyle(
              fontFamily: 'Inter', fontSize: 11, color: AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
