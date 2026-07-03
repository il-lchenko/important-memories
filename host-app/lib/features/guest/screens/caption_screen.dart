import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../utils/guest_prefs.dart';

class CaptionScreen extends ConsumerStatefulWidget {
  final String frameId;
  const CaptionScreen({super.key, required this.frameId});

  @override
  ConsumerState<CaptionScreen> createState() => _CaptionScreenState();
}

class _CaptionScreenState extends ConsumerState<CaptionScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _isSaving = false;
  String _eventId = '';
  String? _savedText;
  String? _errorText;

  static const _maxLen = 120;

  @override
  void initState() {
    super.initState();
    GuestPrefs.currentEventId().then((id) {
      if (mounted) setState(() => _eventId = id ?? '');
    });
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasUnsaved =>
      _controller.text.trim().isNotEmpty && _savedText == null;

  Future<bool> _confirmLeave() async {
    if (!_hasUnsaved) return true;
    final result = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Подпись не сохранена',
                style: GoogleFonts.fraunces(
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Если вернуться сейчас, то текст не попадёт в альбом. Сохранить подпись или продолжить без неё?',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.ink3,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'leave'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink3,
                        side: const BorderSide(color: AppColors.paper3),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Без подписи',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, 'save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Сохранить',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == 'save') {
      await _save();
      return false;
    }
    return result == 'leave';
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      final token =
          _eventId.isEmpty ? '' : await GuestPrefs.tokenFor(_eventId);
      final dio = ref.read(dioProvider);
      await dio.patch(
        'guest/frames/${widget.frameId}',
        data: {'caption': text},
        options: Options(headers: {'X-Guest-Token': token}),
      );
      // Запомнить, чтобы camera screen показала «Подпись сохранена» toast.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_sign_toast', 'Подпись сохранена');
      if (!mounted) return;
      setState(() {
        _savedText = text;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Не удалось сохранить. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    final extra = state.extra is Map ? state.extra as Map : const {};
    final photoBytes = extra['photoBytes'] as Uint8List?;
    final ratio = (extra['ratio'] as num?)?.toDouble() ?? 3 / 4;
    final frameNum = extra['frameNum'] as int? ?? 0;
    final guestName = extra['guestName'] as String? ?? 'Гость';

    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    if (_savedText != null) {
      return _DisplayMode(
        photoBytes: photoBytes,
        ratio: ratio,
        guestName: guestName,
        savedText: _savedText!,
        eventId: _eventId,
        topPad: topPad,
        botPad: botPad,
      );
    }

    final charCount = _controller.text.length;

    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave() && mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        resizeToAvoidBottomInset: true,
        body: Padding(
          padding: EdgeInsets.only(top: topPad),
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                  children: [
                    _RoundIconBtn(
                      icon: Icons.arrow_back,
                      onTap: () async {
                        if (await _confirmLeave() && mounted) context.pop();
                      },
                    ),
                    const Spacer(),
                    Text(
                      'ПОДПИСЬ К КАДРУ ${frameNum.toString().padLeft(2, '0')}',
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

              // Big polaroid — на всю ширину
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _BigPhoto(
                  photoBytes: photoBytes,
                  ratio: ratio,
                  guestName: guestName,
                ),
              ),

              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Оставьте комментарий к снимку',
                        style: GoogleFonts.fraunces(
                          fontWeight: FontWeight.w500,
                          fontSize: 26,
                          height: 1.15,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Несколько слов о запечатлённом моменте. Подпись сохранится в альбоме.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.ink3,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _controller,
                        focusNode: _focus,
                        maxLength: _maxLen,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Закат, который мы так ждали…',
                          hintStyle: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.ink4,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: const Color(0x0A000000),
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.amber),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$charCount / $_maxLen',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            letterSpacing: 1.0,
                            color: charCount >= _maxLen
                                ? AppColors.shutter
                                : AppColors.ink4,
                          ),
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorText!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.shutter,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Buttons
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, botPad + 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: AppSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: (charCount > 0 && !_isSaving) ? _save : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.amber,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.paper3,
                          disabledForegroundColor: AppColors.ink4,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Сохранить подпись',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: AppSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (await _confirmLeave() && mounted) {
                            context.go('/guest/camera/$_eventId');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.paper3,
                          foregroundColor: AppColors.ink2,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Пропустить',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Display mode — after save
// ─────────────────────────────────────────────────────────────────────────────
class _DisplayMode extends StatelessWidget {
  final Uint8List? photoBytes;
  final double ratio;
  final String guestName;
  final String savedText;
  final String eventId;
  final double topPad;
  final double botPad;

  const _DisplayMode({
    required this.photoBytes,
    required this.ratio,
    required this.guestName,
    required this.savedText,
    required this.eventId,
    required this.topPad,
    required this.botPad,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Padding(
        padding: EdgeInsets.only(top: topPad, bottom: botPad),
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  _RoundIconBtn(
                    icon: Icons.arrow_back,
                    onTap: () => context.go('/guest/camera/$eventId'),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check, size: 11, color: AppColors.amber),
                        const SizedBox(width: 4),
                        Text(
                          'ПОДПИСАНО',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            color: AppColors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34),
                ],
              ),
            ),

            // Big polaroid — full width
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _BigPhoto(
                photoBytes: photoBytes,
                ratio: ratio,
                guestName: guestName,
              ),
            ),

            const SizedBox(height: 26),

            // Caption text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                savedText,
                textAlign: TextAlign.center,
                style: GoogleFonts.caveat(
                  fontStyle: FontStyle.italic,
                  fontSize: 26,
                  height: 1.2,
                  color: AppColors.ink2,
                ),
              ),
            ),

            const Spacer(),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    child: ElevatedButton(
                      onPressed: () => context.go('/guest/camera/$eventId'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Вернуться к съёмке',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    child: OutlinedButton(
                      onPressed: () => context.go('/events/$eventId/album'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink3,
                        side: const BorderSide(color: AppColors.paper3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'К альбому',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
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
// Shared widgets (mirror sign_choice_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────
class _BigPhoto extends StatelessWidget {
  final Uint8List? photoBytes;
  final double ratio;
  final String guestName;

  const _BigPhoto({
    required this.photoBytes,
    required this.ratio,
    required this.guestName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Transform.rotate(
        angle: -0.014,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 10),
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
                height: width * 0.11,
                child: Center(
                  child: Text(
                    guestName,
                    style: GoogleFonts.caveat(
                      fontSize: width * 0.085,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
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
        child: Icon(icon, size: 16, color: AppColors.ink2),
      ),
    );
  }
}
