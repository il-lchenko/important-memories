import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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

enum _RecordState { idle, recording, uploading }

class _VoiceRecordScreenState extends ConsumerState<VoiceRecordScreen> {
  final _recorder = AudioRecorder();
  _RecordState _state = _RecordState.idle;
  final List<double> _peaks = [];
  int _elapsedMs = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  String _eventId = '';

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
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted || !mounted) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _peaks.clear();
    _elapsedMs = 0;

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      if (!mounted) return;
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      setState(() => _peaks.add(normalized));
    });

    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _elapsedMs += 200);
      if (_elapsedMs >= _maxMs) _stopAndUpload();
    });

    setState(() => _state = _RecordState.recording);
  }

  Future<void> _stopAndUpload() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;

    final path = await _recorder.stop();
    if (!mounted) return;

    if (path == null || path.isEmpty) {
      setState(() => _state = _RecordState.idle);
      return;
    }

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
      context.go('/guest/camera/$_eventId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _RecordState.idle);
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
    final isBusy = isRecording || isUploading;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  _RoundIconBtn(
                    icon: Icons.arrow_back,
                    onTap: isBusy ? null : () => context.pop(),
                  ),
                  const Spacer(),
                  Text(
                    'ГОЛОС К КАДРУ ${frameNum.toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      letterSpacing: 1.4,
                      color: AppColors.ink3,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34),
                ],
              ),
            ),

            // Polaroid (larger when idle, smaller when recording)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.only(top: isRecording ? 12 : 24),
              child: Center(
                child: _SmallPolaroid(
                  photoBytes: photoBytes,
                  ratio: ratio,
                  guestName: guestName,
                  width: isRecording ? 130 : 160,
                ),
              ),
            ),

            const Spacer(),

            if (!isBusy) ...[
              // Idle — big mic button
              GestureDetector(
                onTap: _startRecording,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.paper2,
                    border: Border.all(color: AppColors.paper3, width: 1.5),
                  ),
                  child: const Icon(Icons.mic_outlined, size: 40, color: AppColors.amber),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Расскажи о моменте',
                style: GoogleFonts.fraunces(
                  fontStyle: FontStyle.italic,
                  fontSize: 15,
                  color: AppColors.ink2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ДО 20 СЕКУНД',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: const Color(0xFF9C9082),
                ),
              ),
            ] else ...[
              // Recording / uploading — waveform capsule
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _WaveformCapsule(
                      peaks: _peaks,
                      elapsedMs: _elapsedMs,
                      isUploading: isUploading,
                      onStop: _stopAndUpload,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isUploading
                          ? 'ЗАГРУЖАЕМ...'
                          : 'ИДЁТ ЗАПИСЬ — НАЖМИ ◼ ЧТОБЫ ОСТАНОВИТЬ',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        letterSpacing: 1.0,
                        color: const Color(0xFF9C9082),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            // Skip button
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, botPad + 16),
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: OutlinedButton(
                  onPressed: isBusy ? null : () => context.go('/guest/camera/$_eventId'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink3,
                    disabledForegroundColor: AppColors.ink4,
                    side: const BorderSide(color: AppColors.paper3),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                  ),
                  child: const Text('Пропустить', style: TextStyle(fontFamily: 'Inter', fontSize: 15)),
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

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  const _WaveformPainter({required this.peaks});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 18;
    const barW = 3.0;
    const gap = 2.0;
    final totalW = barCount * barW + (barCount - 1) * gap;
    final startX = (size.width - totalW) / 2;

    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (barW + gap);
      final hasData = i < peaks.length;
      final h = hasData ? math.max(peaks[i] * size.height, 3.0) : size.height * 0.3;
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
  bool shouldRepaint(_WaveformPainter old) => old.peaks.length != peaks.length;
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

class _SmallPolaroid extends StatelessWidget {
  final Uint8List? photoBytes;
  final double ratio;
  final String guestName;
  final double width;

  const _SmallPolaroid({
    required this.photoBytes,
    required this.ratio,
    required this.guestName,
    this.width = 130,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.026,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: width,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: ratio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: photoBytes != null
                    ? Image.memory(
                        photoBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFD4A574), Color(0xFF5A3E2E)],
                          ),
                        ),
                      ),
              ),
            ),
            SizedBox(
              height: width * 0.18,
              child: Center(
                child: Text(
                  guestName,
                  style: GoogleFonts.caveat(
                    fontSize: width * 0.13,
                    color: AppColors.ink2,
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
