import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/device_rotation.dart';
import '../../../utils/film_lut.dart';
import '../../../utils/guest_prefs.dart';

// ── Recent shots storage ─────────────────────────────────────────────────────
class _RecentShot {
  final String thumbDataUrl; // base64 jpeg ~160px для отрисовки в стеке
  final String filePath; // полный jpeg на диске для preview
  final int frameNum;
  final double ratio;
  const _RecentShot({
    required this.thumbDataUrl,
    required this.filePath,
    required this.frameNum,
    required this.ratio,
  });

  Map<String, Object> toJson() => {
        'url': thumbDataUrl,
        'path': filePath,
        'frameNum': frameNum,
        'ratio': ratio,
      };

  static _RecentShot? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = j['url'];
    final path = j['path'];
    final fn = j['frameNum'];
    final r = j['ratio'];
    if (url is! String || path is! String || fn is! int || r is! num) {
      return null;
    }
    return _RecentShot(
      thumbDataUrl: url,
      filePath: path,
      frameNum: fn,
      ratio: r.toDouble(),
    );
  }
}

const int _kRecentLimit = 3;
String _recentKey(String eventId) => 'im_recent_$eventId';

Future<List<_RecentShot>> _loadRecentShots(String eventId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_recentKey(eventId));
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list
        .map(_RecentShot.fromJson)
        .whereType<_RecentShot>()
        .take(_kRecentLimit)
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> _saveRecentShots(String eventId, List<_RecentShot> shots) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = jsonEncode(
    shots.take(_kRecentLimit).map((s) => s.toJson()).toList(),
  );
  await prefs.setString(_recentKey(eventId), raw);
}

// Top-level for compute() — builds 160px thumbnail from jpeg bytes.
String _buildThumbDataUrl(Map<String, Object> params) {
  final bytes = params['bytes'] as Uint8List;
  final maxSize = (params['maxSize'] as int?) ?? 160;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return '';
  final longer = decoded.width > decoded.height ? decoded.width : decoded.height;
  final scale = longer > maxSize ? maxSize / longer : 1.0;
  final thumb = scale < 1
      ? img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.linear,
        )
      : decoded;
  final jpg = img.encodeJpg(thumb, quality: 70);
  return 'data:image/jpeg;base64,${base64Encode(jpg)}';
}

// ─── Quarter → isLandscape helper ────────────────────────────────────────────
bool _quarterIsLandscape(int q) => q == 1 || q == 3;

// ─────────────────────────────────────────────────────────────────────────────
// Main camera screen
// ─────────────────────────────────────────────────────────────────────────────
class GuestCameraScreen extends ConsumerStatefulWidget {
  final String eventId;
  const GuestCameraScreen({super.key, required this.eventId});

  @override
  ConsumerState<GuestCameraScreen> createState() => _GuestCameraScreenState();
}

class _GuestCameraScreenState extends ConsumerState<GuestCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _ctrl;
  int _camIdx = 0;
  bool _initialized = false;
  bool _isInitializing = false;
  FlashMode _flash = FlashMode.off;
  bool _isCapturing = false;
  int _framesRemaining = 0;
  int _framesTotal = 0;
  String _lutPreset = 'original';
  List<_RecentShot> _recentShots = [];
  _PreviewData? _preview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadPrefs().then((_) => _initCamera());
  }

  Future<void> _loadPrefs() async {
    final frames = await GuestPrefs.framesRemainingFor(widget.eventId);
    final lut = await GuestPrefs.lutPresetFor(widget.eventId);
    final recent = await _loadRecentShots(widget.eventId);
    // Закрепляем event как «текущий» — нужен sign/caption/voice экранам.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_guest_event_id', widget.eventId);
    final total = prefs.getInt('gs_frames_total_${widget.eventId}') ?? frames;
    if (!mounted) return;
    setState(() {
      _framesRemaining = frames;
      _framesTotal = total > 0 ? total : frames;
      _lutPreset = lut;
      _recentShots = recent;
    });
  }

  Future<void> _initCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted || !mounted) return;
      // Retry: после возврата с другого экрана availableCameras() может вернуть
      // пустой список, пока system camera service не освободит ресурс.
      for (int attempt = 0; attempt < 5; attempt++) {
        _cameras = await availableCameras();
        if (_cameras.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
      }
      if (_cameras.isEmpty || !mounted) return;
      await _startController(_camIdx);
    } finally {
      _isInitializing = false;
    }
  }

  /// Проверка из build() — если камера потеряна (после возврата с другого
  /// экрана / системного очищения), переподнимаем без блокировки UI.
  void _maybeReinit() {
    if (_initialized || _isInitializing || _preview != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_initialized && !_isInitializing && _preview == null) {
        _initCamera();
      }
    });
  }

  /// Показывает SnackBar с подтверждением «Подписано» / «Голос записан»
  /// после возврата с caption/voice экранов.
  bool _toastShown = false;
  void _showPendingToast() {
    if (_toastShown) return;
    _toastShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final txt = prefs.getString('pending_sign_toast');
      if (txt == null || txt.isEmpty) return;
      await prefs.remove('pending_sign_toast');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.drAmber, size: 20),
              const SizedBox(width: 10),
              Text(
                txt,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.drText,
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.dark3,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    });
  }

  DeviceOrientation _orientationFor(int quarter) {
    // Маппинг наших четвертей в Flutter DeviceOrientation.
    // q=1: top — слева (наклон НАЛЕВО) → landscapeRight
    // q=3: top — справа (наклон НАПРАВО) → landscapeLeft
    switch (quarter) {
      case 1:
        return DeviceOrientation.landscapeRight;
      case 2:
        return DeviceOrientation.portraitDown;
      case 3:
        return DeviceOrientation.landscapeLeft;
      default:
        return DeviceOrientation.portraitUp;
    }
  }

  Future<void> _startController(int idx) async {
    final old = _ctrl;
    if (mounted) setState(() => _initialized = false);
    await old?.dispose();
    // Дать камере GPU/HAL чуть отдохнуть после dispose.
    await Future.delayed(const Duration(milliseconds: 80));

    CameraController? ctrl;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        ctrl = CameraController(
          _cameras[idx],
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await ctrl.initialize();
        break;
      } catch (_) {
        await ctrl?.dispose();
        ctrl = null;
        if (attempt == 2 || !mounted) return;
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    if (ctrl == null || !mounted) {
      ctrl?.dispose();
      return;
    }
    await ctrl.setFlashMode(_flash);
    setState(() {
      _ctrl = ctrl;
      _initialized = true;
    });
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _isCapturing) return;
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _startController(_camIdx);
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _ctrl?.setFlashMode(next);
    setState(() => _flash = next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (state == AppLifecycleState.resumed) {
      // Пере-принудить portrait — Android при переключении может сбросить lock
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(_camIdx);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _shoot() async {
    if (_isCapturing || !_initialized || _ctrl == null) return;
    if (_framesRemaining <= 0) {
      _showNoFrames();
      return;
    }

    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() => _isCapturing = true);

    try {
      // Зафиксировать ориентацию съёмки по физическому повороту телефона,
      // чтобы горизонтальное фото снималось горизонтально.
      final quarter = ref.read(deviceRotationProvider);
      try {
        await _ctrl!.lockCaptureOrientation(_orientationFor(quarter));
      } catch (_) {}
      final file = await _ctrl!.takePicture();
      try {
        await _ctrl!.unlockCaptureOrientation();
      } catch (_) {}
      final rawBytes = await file.readAsBytes();

      // Process: bakeOrientation + resize + film filter (in isolate).
      // maxSize 2560 = 2.5K — качество остаётся высоким, но isolate работает в ~2x быстрее.
      // Дальше на сервере thumbnail worker сжимает до нужных размеров.
      final result = await compute(
        processImageInIsolate,
        {
          'bytes': rawBytes,
          'preset': _lutPreset,
          'maxSize': 2560,
          'quarter': quarter,
        },
      );
      final processed = result['bytes'] as Uint8List;
      final width = result['width'] as int;
      final height = result['height'] as int;
      final ratio = width / height;

      // Optimistically decrement counter for snappy UI.
      final newRemaining = (_framesRemaining - 1).clamp(0, 999);
      await GuestPrefs.setFramesRemainingFor(widget.eventId, newRemaining);

      final frameNum = _framesTotal > 0
          ? (_framesTotal - newRemaining)
          : (_recentShots.length + 1);

      // Build thumb (~160px JPEG base64) for recent stack.
      final thumbDataUrl = await compute(
        _buildThumbDataUrl,
        {'bytes': processed, 'maxSize': 160},
      );

      // Сохранить полный jpeg на диск (для открытия в полном качестве).
      final dir = await getApplicationSupportDirectory();
      final recentDir = Directory('${dir.path}/recent_${widget.eventId}');
      if (!await recentDir.exists()) {
        await recentDir.create(recursive: true);
      }
      final filePath =
          '${recentDir.path}/${DateTime.now().millisecondsSinceEpoch}_$frameNum.jpg';
      await File(filePath).writeAsBytes(processed);

      // Save recent shots.
      final newShots = [
        _RecentShot(
          thumbDataUrl: thumbDataUrl,
          filePath: filePath,
          frameNum: frameNum,
          ratio: ratio,
        ),
        ..._recentShots,
      ].take(_kRecentLimit).toList();
      // Удалить файлы старых recent (которые выпали за лимит).
      for (final s in _recentShots) {
        if (!newShots.any((n) => n.filePath == s.filePath)) {
          try {
            await File(s.filePath).delete();
          } catch (_) {}
        }
      }
      await _saveRecentShots(widget.eventId, newShots);

      // Kick off upload in background; preview shows immediately.
      final uploadFuture = _upload(processed, width, height);

      if (!mounted) return;
      setState(() {
        _framesRemaining = newRemaining;
        _recentShots = newShots;
        _isCapturing = false;
        _preview = _PreviewData(
          bytes: processed,
          ratio: ratio,
          frameNum: frameNum,
          status: _UploadStatus.pending,
          uploadFuture: uploadFuture,
        );
      });

      uploadFuture.then((frameId) {
        if (!mounted) return;
        setState(() {
          final p = _preview;
          if (p == null) return;
          _preview = p.copyWith(
            frameId: frameId,
            status: _UploadStatus.ok,
          );
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          final p = _preview;
          if (p == null) return;
          _preview = p.copyWith(status: _UploadStatus.failed);
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractUserMessage(e)),
          backgroundColor: AppColors.dark3,
        ),
      );
    }
  }

  Future<String> _upload(Uint8List bytes, int width, int height) async {
    final guestToken = await GuestPrefs.tokenFor(widget.eventId);
    final guestOpts = Options(headers: {'X-Guest-Token': guestToken});
    final dio = ref.read(dioProvider);

    final presignResp = await dio.post(
      'guest/frames/presign',
      data: {'content_type': 'image/jpeg', 'size_bytes': bytes.length},
      options: guestOpts,
    );
    final frameId = presignResp.data['frame_id'] as String;
    final uploadUrl = presignResp.data['upload_url'] as String;

    final s3Dio = Dio();
    await s3Dio.put(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'Content-Type': 'image/jpeg',
          'Content-Length': bytes.length.toString(),
        },
        validateStatus: (s) => s != null && s < 300,
      ),
    );

    await dio.post(
      'guest/frames/',
      data: {
        'frame_id': frameId,
        'captured_at': DateTime.now().toUtc().toIso8601String(),
        'width': width,
        'height': height,
      },
      options: guestOpts,
    );

    return frameId;
  }

  void _showNoFrames() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text(
          'Кадры закончились',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        content: const Text(
          'Вы использовали все отведённые кадры.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.ink3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/events/${widget.eventId}/album');
            },
            child: const Text(
              'Открыть альбом',
              style: TextStyle(color: AppColors.amber, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quarter = ref.watch(deviceRotationProvider);
    final isLandscape = _quarterIsLandscape(quarter);
    final iconTurns = rotationTurnsFor(quarter);

    _maybeReinit();
    _showPendingToast();

    return PopScope(
      // Свайп-назад на экране «снятого кадра» должен убирать превью,
      // а не выходить из приложения. На камере без превью — обычный pop.
      canPop: _preview == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_preview != null) {
          setState(() => _preview = null);
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.dark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CameraLayer(
            ctrl: _ctrl,
            initialized: _initialized,
            flash: _flash,
            cameras: _cameras,
            iconTurns: iconTurns,
            isLandscape: isLandscape,
            lutPreset: _lutPreset,
            framesRemaining: _framesRemaining,
            isCapturing: _isCapturing,
            recentShots: _recentShots,
            onBack: () => context.pop(),
            onToggleFlash: _toggleFlash,
            onFlip: _flipCamera,
            onShutter: _shoot,
            onOpenRecent: (s) async {
              Uint8List? full;
              try {
                full = await File(s.filePath).readAsBytes();
              } catch (_) {
                full = null;
              }
              if (!mounted) return;
              setState(() {
                _preview = _PreviewData(
                  bytes: full,
                  ratio: s.ratio,
                  frameNum: s.frameNum,
                  status: _UploadStatus.ok,
                  thumbDataUrl: full == null ? s.thumbDataUrl : null,
                  canSign: false,
                );
              });
            },
          ),

          if (_preview != null)
            _FramePreview(
              data: _preview!,
              onShootMore: () => setState(() => _preview = null),
              onSign: () async {
                final p = _preview;
                if (p == null) return;
                String? frameId = p.frameId;
                if (frameId == null && p.uploadFuture != null) {
                  try {
                    frameId = await p.uploadFuture;
                  } catch (_) {}
                }
                if (!mounted) return;
                if (frameId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Кадр не загрузился. Проверьте интернет и попробуйте снова.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                        ),
                      ),
                      backgroundColor: AppColors.dark3,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                final guestName = prefs.getString('guest_name') ?? 'Гость';
                if (!mounted) return;
                context.push(
                  '/guest/sign/$frameId',
                  extra: {
                    'photoBytes': p.bytes,
                    'ratio': p.ratio,
                    'frameNum': p.frameNum,
                    'guestName': guestName,
                  },
                );
              },
            ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview data
// ─────────────────────────────────────────────────────────────────────────────
enum _UploadStatus { pending, ok, failed }

class _PreviewData {
  final Uint8List? bytes;
  final String? thumbDataUrl; // for opening from recent stack (no full bytes)
  final double ratio;
  final int frameNum;
  final _UploadStatus status;
  final String? frameId;
  final Future<String>? uploadFuture;
  final bool canSign;

  const _PreviewData({
    this.bytes,
    this.thumbDataUrl,
    required this.ratio,
    required this.frameNum,
    required this.status,
    this.frameId,
    this.uploadFuture,
    this.canSign = true,
  });

  _PreviewData copyWith({
    _UploadStatus? status,
    String? frameId,
  }) =>
      _PreviewData(
        bytes: bytes,
        thumbDataUrl: thumbDataUrl,
        ratio: ratio,
        frameNum: frameNum,
        status: status ?? this.status,
        frameId: frameId ?? this.frameId,
        uploadFuture: uploadFuture,
        canSign: canSign,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera layer (everything except preview)
// ─────────────────────────────────────────────────────────────────────────────
class _CameraLayer extends StatelessWidget {
  final CameraController? ctrl;
  final bool initialized;
  final FlashMode flash;
  final List<CameraDescription> cameras;
  final double iconTurns;
  final bool isLandscape;
  final String lutPreset;
  final int framesRemaining;
  final bool isCapturing;
  final List<_RecentShot> recentShots;
  final VoidCallback onBack;
  final VoidCallback onToggleFlash;
  final VoidCallback onFlip;
  final VoidCallback onShutter;
  final void Function(_RecentShot) onOpenRecent;

  const _CameraLayer({
    required this.ctrl,
    required this.initialized,
    required this.flash,
    required this.cameras,
    required this.iconTurns,
    required this.isLandscape,
    required this.lutPreset,
    required this.framesRemaining,
    required this.isCapturing,
    required this.recentShots,
    required this.onBack,
    required this.onToggleFlash,
    required this.onFlip,
    required this.onShutter,
    required this.onOpenRecent,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        // ── Top bar (film label / orientation indicator — НЕ вращаются) ─────
        Container(
          padding: EdgeInsets.only(top: topPad, left: 12, right: 12, bottom: 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Colors.transparent],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                _CamBtn(icon: Icons.arrow_back, onTap: onBack),
                const SizedBox(width: 8),
                _FilmLabel(lutPreset: lutPreset),
                const Spacer(),
                Container(
                  width: AppSizes.iconBtnSize,
                  height: AppSizes.iconBtnSize,
                  decoration: BoxDecoration(
                    color: isLandscape
                        ? AppColors.drAmber.withValues(alpha: 0.18)
                        : const Color(0x59000000),
                    borderRadius: AppRadius.pillBR,
                    border: Border.all(
                      color: isLandscape
                          ? AppColors.drAmber.withValues(alpha: 0.4)
                          : const Color(0x1FFFFFFF),
                    ),
                  ),
                  child: Icon(
                    Icons.screen_rotation_outlined,
                    size: 18,
                    color: isLandscape
                        ? AppColors.drAmber
                        : AppColors.drText.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Camera box — статично 3/4 (не крутится с физическим повертом) ──
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (initialized && ctrl != null)
                ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: ctrl!.value.previewSize?.height ?? 1,
                        height: ctrl!.value.previewSize?.width ?? 1,
                        child: CameraPreview(ctrl!),
                      ),
                    ),
                  ),
                )
              else
                const ColoredBox(color: Color(0xFF050302)),
              ..._cornerBrackets(),
              if (isCapturing) const _CaptureOverlay(),
            ],
          ),
        ),

        // ── Control area: flash/flip, шторка, counter/recent ─────────────────
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, botPad),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RotatingIcon(
                      turns: iconTurns,
                      child: _BigCamBtn(
                        icon: flash == FlashMode.off
                            ? Icons.flash_off_outlined
                            : Icons.flash_on,
                        onTap: onToggleFlash,
                        active: flash != FlashMode.off,
                      ),
                    ),
                    _RotatingIcon(
                      turns: iconTurns,
                      child: cameras.length > 1
                          ? _BigCamBtn(
                              icon: Icons.cameraswitch_outlined,
                              onTap: onFlip,
                            )
                          : const SizedBox(width: 52, height: 52),
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                GestureDetector(
                  onTap: isCapturing ? null : onShutter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 72,
                    height: 72,
                    transform: Matrix4.identity()
                      ..scale(isCapturing ? 0.88 : 1.0),
                    transformAlignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.drText,
                      border: Border.all(
                        color: AppColors.drAmber.withValues(alpha: 0.35),
                        width: 2,
                      ),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0x73000000),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: AppColors.drAmber.withValues(alpha: 0.3),
                          blurRadius: 0,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: AppColors.drAmber.withValues(alpha: 0.35),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _RotatingIcon(
                      turns: iconTurns,
                      child: _FilmCounter(remaining: framesRemaining),
                    ),
                    _RotatingIcon(
                      turns: iconTurns,
                      child: _RecentStack(
                        shots: recentShots,
                        onOpen: onOpenRecent,
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _cornerBrackets() {
    Widget bracket({
      bool top = false,
      bool bottom = false,
      bool left = false,
      bool right = false,
    }) {
      const c = Color(0x80FFB347);
      const w = 1.5;
      return Positioned(
        top: top ? 7 : null,
        bottom: bottom ? 7 : null,
        left: left ? 7 : null,
        right: right ? 7 : null,
        child: IgnorePointer(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              border: Border(
                top: top ? const BorderSide(color: c, width: w) : BorderSide.none,
                bottom: bottom
                    ? const BorderSide(color: c, width: w)
                    : BorderSide.none,
                left:
                    left ? const BorderSide(color: c, width: w) : BorderSide.none,
                right: right
                    ? const BorderSide(color: c, width: w)
                    : BorderSide.none,
              ),
            ),
          ),
        ),
      );
    }

    return [
      bracket(top: true, left: true),
      bracket(top: true, right: true),
      bracket(bottom: true, left: true),
      bracket(bottom: true, right: true),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Film label chip (PORTRA 400 · ƒ 2.8)
// ─────────────────────────────────────────────────────────────────────────────
class _FilmLabel extends StatelessWidget {
  final String lutPreset;
  const _FilmLabel({required this.lutPreset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: AppRadius.smBR,
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.shutter,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            filmLabel(lutPreset),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              letterSpacing: 1.4,
              color: const Color(0xA6FFB347),
            ),
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 10, color: const Color(0x38FFB347)),
          const SizedBox(width: 6),
          Text(
            'ƒ 2.8',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              letterSpacing: 1.4,
              color: const Color(0xA6FFB347).withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame counter — film strip with holes left/right + number
// ─────────────────────────────────────────────────────────────────────────────
class _FilmCounter extends StatelessWidget {
  final int remaining;
  const _FilmCounter({required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      decoration: BoxDecoration(
        color: const Color(0x73000000),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x1AFFB347)),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilmHoles(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: Text(
                  '$remaining',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.drAmber,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            _FilmHoles(),
          ],
        ),
      ),
    );
  }
}

class _FilmHoles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      color: const Color(0x73000000),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          3,
          (_) => Container(
            width: 6,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent shots stack (3 mini polaroids)
// ─────────────────────────────────────────────────────────────────────────────
class _RecentStack extends StatelessWidget {
  final List<_RecentShot> shots;
  final void Function(_RecentShot) onOpen;
  const _RecentStack({required this.shots, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 66,
      child: Stack(
        children: [
          for (final slot in const [2, 1, 0])
            _buildSlot(slot),
        ],
      ),
    );
  }

  Widget _buildSlot(int slot) {
    final shot = slot < shots.length ? shots[slot] : null;
    const rotations = [0.0056, -0.0111, 0.0167]; // turns ≈ 2°, -4°, 6°
    const offsets = [
      Offset(24, 10),
      Offset(12, 5),
      Offset(0, 0),
    ];
    final isTop = slot == 0;
    final offset = offsets[slot];

    final card = Transform.rotate(
      angle: rotations[slot] * 6.2831853, // turns → radians
      child: Container(
        width: 50,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: shot != null ? const Color(0xFFF5EAD0) : const Color(0x26F5EAD0),
          borderRadius: BorderRadius.circular(2),
          boxShadow: shot != null
              ? [
                  const BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: ColoredBox(
              color: shot != null ? Colors.black : const Color(0x0FFFB347),
              child: shot != null
                  ? Image.memory(
                      _dataUrlToBytes(shot.thumbDataUrl),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );

    return Positioned(
      right: offset.dx,
      top: offset.dy,
      child: IgnorePointer(
        ignoring: !(isTop && shot != null),
        child: GestureDetector(
          onTap: (isTop && shot != null) ? () => onOpen(shot) : null,
          child: card,
        ),
      ),
    );
  }

  static Uint8List _dataUrlToBytes(String dataUrl) {
    final i = dataUrl.indexOf(',');
    if (i < 0) return Uint8List(0);
    try {
      return base64Decode(dataUrl.substring(i + 1));
    } catch (_) {
      return Uint8List(0);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame preview (polaroid + actions)
// ─────────────────────────────────────────────────────────────────────────────
class _FramePreview extends StatefulWidget {
  final _PreviewData data;
  final VoidCallback onShootMore;
  final Future<void> Function() onSign;
  const _FramePreview({
    required this.data,
    required this.onShootMore,
    required this.onSign,
  });

  @override
  State<_FramePreview> createState() => _FramePreviewState();
}

class _FramePreviewState extends State<_FramePreview> {
  bool _signLoading = false;
  String? _guestName;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _guestName = prefs.getString('guest_name') ?? 'Гость');
    });
  }

  Future<void> _handleSign() async {
    setState(() => _signLoading = true);
    try {
      await widget.onSign();
    } finally {
      if (mounted) setState(() => _signLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final isLandscape = d.ratio > 1;
    final cardWidth = isLandscape ? 300.0 : 240.0;

    Widget imageWidget;
    if (d.bytes != null) {
      imageWidget = Image.memory(d.bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (d.thumbDataUrl != null) {
      imageWidget = Image.memory(
        _RecentStack._dataUrlToBytes(d.thumbDataUrl!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      imageWidget = const ColoredBox(color: Colors.black);
    }

    return Material(
      color: AppColors.dark,
      child: Padding(
        padding: EdgeInsets.only(top: topPad, bottom: botPad),
        child: Column(
          children: [
            const SizedBox(height: 18),
            Text(
              'КАДР ${d.frameNum} · МОМЕНТ ЗАПЕЧАТЛЁН',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                letterSpacing: 1.5,
                color: AppColors.drText.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Center(
                child: Transform.rotate(
                  angle: -0.026, // ≈ -1.5°
                  child: Container(
                    width: cardWidth,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0x80000000),
                          blurRadius: 50,
                          offset: Offset(0, 20),
                        ),
                        BoxShadow(
                          color: AppColors.drAmber.withValues(alpha: 0.15),
                          blurRadius: 80,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: isLandscape ? 4 / 3 : 3 / 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: imageWidget,
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: Center(
                            child: Text(
                              _guestName ?? 'Гость',
                              style: GoogleFonts.caveat(
                                fontSize: 26,
                                color: AppColors.ink2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'Снимок не отменить, как и сам момент.',
                style: GoogleFonts.fraunces(
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                  height: 1.4,
                  color: AppColors.drText,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    child: ElevatedButton(
                      onPressed: widget.onShootMore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.drAmber,
                        foregroundColor: AppColors.dark,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.pillBR,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Новый кадр',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward, size: 22),
                        ],
                      ),
                    ),
                  ),
                  if (d.canSign) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: AppSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed:
                            (_signLoading || d.status == _UploadStatus.failed)
                                ? null
                                : _handleSign,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.drText.withValues(alpha: 0.12),
                          foregroundColor: AppColors.drText,
                          disabledBackgroundColor: AppColors.drText.withValues(alpha: 0.06),
                          disabledForegroundColor: AppColors.drText.withValues(alpha: 0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.pillBR,
                          ),
                        ),
                        child: _signLoading ||
                                d.status == _UploadStatus.pending
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.drAmber,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Кадр загружается…',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.drText.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.edit_outlined, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Подписать кадр',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (d.status == _UploadStatus.failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Кадр не загрузился — без интернета подписать нельзя',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppColors.shutter,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────
class _RotatingIcon extends StatelessWidget {
  final double turns;
  final Widget child;
  const _RotatingIcon({required this.turns, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: turns,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

class _CamBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _CamBtn({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSizes.iconBtnSize,
        height: AppSizes.iconBtnSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AppColors.drAmber.withValues(alpha: 0.22)
              : const Color(0x59000000),
          border: Border.all(
            color: active
                ? AppColors.drAmber.withValues(alpha: 0.4)
                : const Color(0x1FFFFFFF),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active
              ? AppColors.drAmber
              : AppColors.drText.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _BigCamBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _BigCamBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AppColors.drAmber.withValues(alpha: 0.22)
              : const Color(0x80000000),
          border: Border.all(
            color: active
                ? AppColors.drAmber.withValues(alpha: 0.45)
                : const Color(0x33FFFFFF),
            width: 1.2,
          ),
        ),
        child: Icon(
          icon,
          size: 24,
          color: active
              ? AppColors.drAmber
              : AppColors.drText.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _CaptureOverlay extends StatelessWidget {
  const _CaptureOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: const Color(0x99000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.drAmber,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Проявляется кадр…',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: AppColors.drText.withValues(alpha: 0.7),
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
