import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';

class VoiceRecordScreen extends ConsumerStatefulWidget {
  final String frameId;
  const VoiceRecordScreen({super.key, required this.frameId});

  @override
  ConsumerState<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

enum _RecordState { idle, recording, recorded, uploading }

class _VoiceRecordScreenState extends ConsumerState<VoiceRecordScreen> {
  AudioRecorder _recorder = AudioRecorder();
  _RecordState _state = _RecordState.idle;
  final List<double> _peaks = [];
  int _elapsedMs = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription? _playerSub;
  String _eventId = '';
  String? _recordedPath;
  AudioPlayer? _player;
  bool _isPlaying = false;

  static const _maxMs = 20000;

  @override
  void initState() {
    super.initState();
    GuestPrefs.currentEventId().then((id) {
      if (mounted) setState(() => _eventId = id ?? '');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _playerSub?.cancel();
    _recorder.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted || !mounted) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Не удалось начать запись: $e'),
        backgroundColor: AppColors.shutter,
      ));
      return;
    }

    _peaks.clear();
    _elapsedMs = 0;

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
      if (!mounted) return;
      // amp.current в dBFS: -40..0 → 0..1. Ниже -40 = очень тихо.
      final normalized = ((amp.current + 40) / 40).clamp(0.0, 1.0);
      setState(() => _peaks.add(normalized));
    });

    _timer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _elapsedMs = math.min(_elapsedMs + 120, _maxMs));
      if (_elapsedMs >= _maxMs) _stopRecording();
    });

    setState(() => _state = _RecordState.recording);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;

    final path = await _recorder.stop();
    if (!mounted) return;

    if (path == null || path.isEmpty) {
      setState(() => _state = _RecordState.idle);
      return;
    }

    // Пре-загружаем плеер, чтобы юзер мог тут же прослушать запись.
    _playerSub?.cancel();
    _player?.dispose();
    _player = AudioPlayer();
    try {
      await _player!.setFilePath(path);
      _playerSub = _player!.playerStateStream.listen((s) {
        if (!mounted) return;
        final playing = s.playing && s.processingState != ProcessingState.completed;
        if (playing != _isPlaying) setState(() => _isPlaying = playing);
        if (s.processingState == ProcessingState.completed) {
          _player?.seek(Duration.zero);
          _player?.pause();
        }
      });
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _recordedPath = path;
      _state = _RecordState.recorded;
    });
  }

  Future<void> _togglePlayback() async {
    if (_player == null) return;
    if (_isPlaying) {
      await _player!.pause();
    } else {
      await _player!.seek(Duration.zero);
      await _player!.play();
    }
  }

  Future<void> _retryRecording() async {
    await _player?.pause();
    _playerSub?.cancel();
    _playerSub = null;
    // Пересоздать recorder — некоторые Android MediaRecorder не переиспользуются
    await _recorder.dispose();
    _recorder = AudioRecorder();
    setState(() {
      _peaks.clear();
      _elapsedMs = 0;
      _recordedPath = null;
      _isPlaying = false;
      _state = _RecordState.idle;
    });
  }

  Future<void> _uploadAndFinish() async {
    final path = _recordedPath;
    if (path == null) return;
    setState(() => _state = _RecordState.uploading);

    try {
      final bytes = await File(path).readAsBytes();
      final durationMs = _elapsedMs;
      final peaks = _resamplePeaks(_peaks, 40);

      final token = _eventId.isEmpty ? '' : await GuestPrefs.tokenFor(_eventId);
      final guestOpts = Options(headers: {'X-Guest-Token': token});
      final dio = ref.read(dioProvider);

      // 1. Presign
      final presignResp = await dio.post(
        'guest/frames/${widget.frameId}/voice-presign',
        data: {
          'content_type': 'audio/mp4',
          'size_bytes': bytes.length,
        },
        options: guestOpts,
      );
      final voiceS3Key = presignResp.data['voice_s3_key'] as String;
      final uploadUrl = presignResp.data['upload_url'] as String;

      // 2. PUT to S3 (separate Dio, no auth headers)
      final s3Dio = Dio();
      await s3Dio.put(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            'Content-Type': 'audio/mp4',
            'Content-Length': bytes.length.toString(),
          },
          validateStatus: (s) => s != null && s < 300,
        ),
      );

      // 3. PATCH frame with voice metadata
      await dio.patch(
        'guest/frames/${widget.frameId}',
        data: {
          'voice_s3_key': voiceS3Key,
          'voice_duration_ms': durationMs,
          'voice_peaks': peaks,
        },
        options: guestOpts,
      );

      // Запомнить для toast на camera screen.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_sign_toast', 'Голос записан');

      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _RecordState.recorded);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractUserMessage(e)),
          backgroundColor: AppColors.shutter,
        ),
      );
    }
  }

  List<double> _resamplePeaks(List<double> src, int count) {
    if (src.isEmpty) return List.filled(count, 0.1);
    if (src.length <= count) {
      return [...src, ...List.filled(count - src.length, 0.1)];
    }
    final result = <double>[];
    final step = src.length / count;
    for (int i = 0; i < count; i++) {
      result.add(src[(i * step).floor().clamp(0, src.length - 1)]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    final extra = state.extra is Map ? state.extra as Map : const {};
    final photoBytes = extra['photoBytes'] as Uint8List?;
    final ratio = (extra['ratio'] as num?)?.toDouble() ?? 3 / 4;
    final frameNum = extra['frameNum'] as int? ?? 0;
    final guestName = extra['guestName'] as String? ?? 'Гость';

    final botPad = MediaQuery.of(context).padding.bottom;
    final isRecording = _state == _RecordState.recording;
    final isUploading = _state == _RecordState.uploading;
    final isRecorded = _state == _RecordState.recorded;
    final isBusy = isRecording || isUploading;

    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    // Photo shrinks when recording/uploading to give room for waveform
    final photoSectionH = (isRecording || isUploading)
        ? (screenH * 0.28).clamp(120.0, 220.0)
        : (screenH * 0.38).clamp(160.0, 360.0);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  _RoundIconBtn(icon: Icons.arrow_back, onTap: isBusy ? null : () => context.pop()),
                  const Spacer(),
                  Text(
                    'ГОЛОС К КАДРУ ${frameNum.toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, letterSpacing: 1.4, color: AppColors.ink3),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── Photo — анимированно уменьшается (tween чтобы maxHeight тоже анимировался) ─
            TweenAnimationBuilder<double>(
              tween: Tween(end: photoSectionH),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (context, h, _) => SizedBox(
                height: h,
                width: double.infinity,
                child: Center(
                  child: _Polaroid(
                    photoBytes: photoBytes, ratio: ratio, guestName: guestName,
                    maxHeight: h, maxWidth: screenW - 48,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── State-dependent controls ───────────────────────────────
            if (_state == _RecordState.idle) ...[
              GestureDetector(
                onTap: _startRecording,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.paper2,
                    border: Border.all(color: AppColors.paper3, width: 1.5),
                  ),
                  child: const Icon(Icons.mic_outlined, size: 36, color: AppColors.amber),
                ),
              ),
              const SizedBox(height: 12),
              Text('Расскажи о моменте',
                  style: GoogleFonts.fraunces(fontStyle: FontStyle.italic, fontSize: 16, color: AppColors.ink2)),
              const SizedBox(height: 4),
              Text('ДО 20 СЕКУНД',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, letterSpacing: 1.4, color: const Color(0xFF9C9082))),
            ] else if (isRecording || isUploading) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _WaveformCapsule(
                      peaks: _peaks, elapsedMs: _elapsedMs,
                      isUploading: isUploading, onStop: _stopRecording,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isUploading ? 'ЗАГРУЖАЕМ...' : 'ИДЁТ ЗАПИСЬ — НАЖМИ ◼ ЧТОБЫ ОСТАНОВИТЬ',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, letterSpacing: 1.0, color: const Color(0xFF9C9082)),
                    ),
                  ],
                ),
              ),
            ] else if (isRecorded) ...[
              _PlaybackCapsule(
                peaks: _peaks, durationMs: _elapsedMs,
                isPlaying: _isPlaying, onTogglePlay: _togglePlayback,
              ),
              const SizedBox(height: 10),
              Text(
                'ГОЛОСОВАЯ ЗАМЕТКА ГОТОВА',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, letterSpacing: 1.4, color: AppColors.amber, fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Bottom buttons ─────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, botPad + 14),
              child: isRecorded
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: AppSizes.buttonHeight,
                          child: ElevatedButton(
                            onPressed: _uploadAndFinish,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.amber, foregroundColor: Colors.white,
                              elevation: 0, shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('К следующему кадру',
                                    style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: AppSizes.buttonHeight,
                          child: ElevatedButton(
                            onPressed: _retryRecording,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.paper3, foregroundColor: AppColors.ink2,
                              elevation: 0, shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh, size: 18),
                                SizedBox(width: 6),
                                Text('Записать заново',
                                    style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: AppSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: isBusy ? null : () => context.pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.paper3, foregroundColor: AppColors.ink2,
                          disabledBackgroundColor: AppColors.paper3.withValues(alpha: 0.5),
                          disabledForegroundColor: AppColors.ink4,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                        ),
                        child: const Text('Пропустить',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformCapsule extends StatelessWidget {
  final List<double> peaks;
  final int elapsedMs;
  final bool isUploading;
  final VoidCallback onStop;
  const _WaveformCapsule({
    required this.peaks,
    required this.elapsedMs,
    required this.isUploading,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0x14D54B3D),
        border: Border.all(color: const Color(0x33D54B3D)),
        borderRadius: AppRadius.pillBR,
      ),
      child: Row(
        children: [
          // Stop / uploading button
          GestureDetector(
            onTap: isUploading ? null : onStop,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.shutter,
              ),
              child: isUploading
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.stop, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          // Waveform
          Expanded(
            child: SizedBox(
              height: 24,
              child: CustomPaint(painter: _WaveformPainter(peaks: peaks)),
            ),
          ),
          const SizedBox(width: 8),
          // Timer
          Text(
            '● ${_fmt(elapsedMs)}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.shutter,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _PlaybackCapsule extends StatelessWidget {
  final List<double> peaks;
  final int durationMs;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  const _PlaybackCapsule({
    required this.peaks,
    required this.durationMs,
    required this.isPlaying,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.25)),
          borderRadius: AppRadius.pillBR,
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onTogglePlay,
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.amber,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 30,
                child: CustomPaint(painter: _WaveformPainter(peaks: peaks)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _fmt(durationMs),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  const _WaveformPainter({required this.peaks});

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.0;
    const gap = 2.0;
    // Кол-во баров зависит от доступной ширины — заполняем целиком.
    final barCount = ((size.width + gap) / (barW + gap)).floor();
    if (barCount <= 0) return;
    final totalW = barCount * barW + (barCount - 1) * gap;
    final startX = (size.width - totalW) / 2;

    // Показываем ПОСЛЕДНИЕ `barCount` пиков (rolling window). Свежий peak = справа.
    final start = peaks.length > barCount ? peaks.length - barCount : 0;
    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (barW + gap);
      final peakIdx = start + i;
      final hasData = peakIdx < peaks.length;
      final val = hasData ? peaks[peakIdx] : 0.0;
      // Чуть подтянуть низкое значение чтобы не было "плоско" — минимум 3px, максимум size.height
      final h = hasData ? math.max(val * size.height, 3.0) : size.height * 0.15;
      final paint = Paint()
        ..color = hasData ? AppColors.shutter : const Color(0x55A09684);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, barW, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true; // перерисовываем на каждый peak
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x0F000000),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.ink2 : AppColors.ink4,
        ),
      ),
    );
  }
}

class _Polaroid extends StatelessWidget {
  final Uint8List? photoBytes;
  final double ratio;
  final String guestName;
  final double maxHeight;
  final double maxWidth;

  const _Polaroid({
    required this.photoBytes, required this.ratio,
    required this.guestName, required this.maxHeight, required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    const hPad = 10.0;
    const vPad = 10.0;
    const nameH = 28.0;
    const botPad = 4.0;

    double imgH = (maxHeight - vPad - nameH - botPad).clamp(1.0, double.infinity);
    double imgW = imgH * ratio;
    final maxImgW = maxWidth - hPad * 2;
    if (imgW > maxImgW) {
      imgW = maxImgW;
      imgH = (imgW / ratio).clamp(1.0, double.infinity);
    }

    return Container(
      width: imgW + hPad * 2,
      padding: const EdgeInsets.fromLTRB(hPad, vPad, hPad, botPad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: imgW,
            height: imgH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: photoBytes != null
                  ? Image.memory(photoBytes!, fit: BoxFit.cover)
                  : Container(decoration: const BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFFD4A574), Color(0xFF5A3E2E)]))),
            ),
          ),
          SizedBox(
            height: nameH,
            child: Center(
              child: Text(guestName, style: GoogleFonts.caveat(fontSize: 16, color: AppColors.ink2)),
            ),
          ),
        ],
      ),
    );
  }
}
