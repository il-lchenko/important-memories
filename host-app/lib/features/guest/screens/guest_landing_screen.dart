import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../utils/guest_prefs.dart';
import '../guest_provider.dart';

class GuestLandingScreen extends ConsumerStatefulWidget {
  final String code;
  const GuestLandingScreen({super.key, required this.code});

  @override
  ConsumerState<GuestLandingScreen> createState() => _GuestLandingScreenState();
}

class _GuestLandingScreenState extends ConsumerState<GuestLandingScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final name = _nameCtrl.text.trim();
    final isAuthed = ref.read(authProvider).valueOrNull ?? false;

    if (!isAuthed && name.isEmpty) {
      setState(() => _error = 'Введите ваше имя');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fingerprint = await getDeviceFingerprint();
      final dio = ref.read(dioProvider);

      final resp = await dio.post('guest/sessions', data: {
        'short_code': widget.code,
        if (name.isNotEmpty) 'name': name,
        'fingerprint': fingerprint,
      });

      final data = Map<String, dynamic>.from(resp.data as Map);
      final guestToken = data['guest_token'] as String;
      final guestName = data['name'] as String? ?? '';
      final event = data['event'] as Map;
      final eventId = event['id'] as String;
      final framesRemaining = data['frames_remaining'] as int? ?? 10;
      final settings = event['settings'] as Map? ?? {};
      final lutPreset = settings['lut_preset'] as String? ?? 'original';

      await GuestPrefs.saveSession(
        eventId: eventId,
        token: guestToken,
        framesRemaining: framesRemaining,
        lutPreset: lutPreset,
      );
      if (guestName.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('guest_name', guestName);
      }

      if (!mounted) return;
      context.go('/guest/camera/$eventId');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = extractUserMessage(e);
        _loading = false;
      });
    }
  }

  void _showRenameSheet(String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.lg),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Изменить имя',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Только для этого события',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.ink3,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 40,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'Ваше имя',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.paper2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  final newName = ctrl.text.trim();
                  if (newName.isNotEmpty) {
                    _nameCtrl.text = newName;
                    setState(() {});
                  }
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  height: AppSizes.buttonHeight,
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: AppRadius.mdBR,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Сохранить',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(guestEventPreviewProvider(widget.code));
    final authAsync = ref.watch(authProvider);
    final isAuthed = authAsync.valueOrNull ?? false;
    final userAsync = isAuthed ? ref.watch(currentUserProvider) : null;
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: previewAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.amber),
        ),
        error: (e, _) => _EventNotFound(onBack: () => context.go('/guest/entry')),
        data: (event) {
          // Pre-fill name from user profile (if authenticated and name not already set)
          if (isAuthed && _nameCtrl.text.isEmpty) {
            userAsync?.whenData((user) {
              final dn = user['display_name'] as String? ?? '';
              if (_nameCtrl.text.isEmpty && dn.isNotEmpty) {
                _nameCtrl.text = dn;
              }
            });
          }

          final title = event['title'] as String? ?? '';
          final coverUrl = event['cover_url'] as String?;
          final status = event['status'] as String? ?? '';
          final revealAt = event['reveal_at'] as String?;
          final startAt = event['start_at'] as String?;
          final framesPerGuest = event['frames_per_guest'] as int? ?? 0;
          final lut = (event['lut_preset'] as String? ?? 'original')
              .replaceAll('_', ' ')
              .toUpperCase();

          final dateStr = _formatDate(startAt ?? revealAt);

          return Column(
            children: [
              // Cover + top bar
              SizedBox(
                height: 260 + top,
                child: Stack(
                  children: [
                    // Cover or gradient placeholder
                    Positioned.fill(
                      child: coverUrl != null
                          ? Image.network(coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _GradientCover())
                          : _GradientCover(),
                    ),
                    // Scrim
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x80000000), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    // Top bar
                    Positioned(
                      top: top + 8, left: 8, right: 8,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _LightIconBtn(
                            icon: Icons.arrow_back,
                            onTap: () => context.pop(),
                          ),
                          Text(
                            'КОД ${widget.code}',
                            style: const TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 10,
                              letterSpacing: 1.4,
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                          const SizedBox(width: AppSizes.iconBtnSize),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Info block
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dateStr != null)
                        Text(
                          '${_eventTypeLabel(status)} · $dateStr',
                          style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: AppColors.amber,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                          letterSpacing: -0.56,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$framesPerGuest кадров · $lut',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Name banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.08),
                          border: Border.all(
                            color: AppColors.amber.withValues(alpha: 0.2),
                          ),
                          borderRadius: AppRadius.mdBR,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_outline,
                                    size: 16, color: AppColors.amber),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _nameCtrl.text.isEmpty
                                        ? 'Введите имя'
                                        : 'Подписываться как ${_nameCtrl.text}',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!isAuthed) ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: _nameCtrl,
                                maxLength: 40,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: AppColors.ink,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Ваше имя в альбоме',
                                  counterText: '',
                                  filled: true,
                                  fillColor: AppColors.paper,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                            GestureDetector(
                              onTap: () =>
                                  _showRenameSheet(_nameCtrl.text),
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(top: 6),
                                child: const Text(
                                  'Изменить имя для этого события →',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: AppColors.amber,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.shutter,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom button
              Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + bottom),
                child: GestureDetector(
                  onTap: _loading ? null : _join,
                  child: Container(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: AppRadius.mdBR,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _loading
                        ? const Center(
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_outlined,
                                  size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Войти и начать снимать',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _formatDate(String? isoStr) {
    if (isoStr == null) return null;
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      const months = [
        'янв', 'фев', 'мар', 'апр', 'май', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
      ];
      return '${dt.day} ${months[dt.month - 1]}';
    } catch (_) {
      return null;
    }
  }

  String _eventTypeLabel(String status) {
    switch (status) {
      case 'active': return 'ИДЁТ';
      case 'revealed': return 'ПРОЯВЛЕНО';
      case 'completed': return 'ЗАВЕРШЕНО';
      default: return 'СОБЫТИЕ';
    }
  }
}

class _LightIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _LightIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSizes.iconBtnSize,
        height: AppSizes.iconBtnSize,
        decoration: BoxDecoration(
          color: const Color(0x33000000),
          borderRadius: AppRadius.smBR,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _GradientCover extends StatelessWidget {
  const _GradientCover();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.2,
          colors: [
            Color(0xFFD4A574),
            Color(0xFF8A5030),
            Color(0xFF3A2010),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
    );
  }
}

class _EventNotFound extends StatelessWidget {
  final VoidCallback onBack;
  const _EventNotFound({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.arrow_back, size: 18, color: AppColors.amber),
              ),
            ),
            const Spacer(),
            // Film roll icon
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.paper2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: const Icon(Icons.camera_roll_outlined, size: 36, color: AppColors.ink3),
            ),
            const SizedBox(height: 24),
            const Text(
              'Событие\nне найдено',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 32,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Проверьте код и попробуйте снова. Возможно, событие завершено или ссылка устарела.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                height: 1.5,
                color: AppColors.ink3,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: AppRadius.mdBR,
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Попробовать снова',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(height: bottom + 16),
          ],
        ),
      ),
    );
  }
}
