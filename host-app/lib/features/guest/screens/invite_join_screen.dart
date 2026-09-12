// Экран использования персонального invite-токена гостем.
// Fetch preview → показать «Вы приглашены на X от Y» → ввод имени (если auth
// отсутствует, иначе берём display_name) → POST /guest/invites/{token}/join.
// Обходит PIN и лимит альбомов на стороне backend.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../auth/auth_provider.dart';
import '../../../utils/guest_prefs.dart';
import '../guest_provider.dart';

class InviteJoinScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteJoinScreen({super.key, required this.token});

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  bool _loadingPreview = true;
  bool _joining = false;
  Map<String, dynamic>? _preview;
  String? _previewError;
  String? _joinError;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('guest/invites/${widget.token}');
      if (!mounted) return;
      setState(() {
        _preview = Map<String, dynamic>.from(resp.data as Map);
        _loadingPreview = false;
        // Префилл имени из display_name инвайта (если гость не залогинен).
        final displayName = _preview!['display_name'] as String?;
        if (_nameCtrl.text.isEmpty && displayName != null) {
          _nameCtrl.text = displayName;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _previewError = extractUserMessage(e);
      });
    }
  }

  Future<void> _join() async {
    final name = _nameCtrl.text.trim();
    final isAuthed = ref.read(authProvider).valueOrNull ?? false;
    if (!isAuthed && name.isEmpty) {
      setState(() => _joinError = 'Введите ваше имя');
      return;
    }
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final fingerprint = await getDeviceFingerprint();
      final dio = ref.read(dioProvider);
      final resp = await dio.post(
        'guest/invites/${widget.token}/join',
        data: {
          if (name.isNotEmpty) 'name': name,
          'fingerprint': fingerprint,
        },
      );
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
        _joining = false;
        _joinError = extractUserMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: _loadingPreview
            ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
            : _previewError != null
                ? _ErrorState(
                    message: _previewError!,
                    onBack: () => context.go('/guest/entry'),
                  )
                : _buildInvite(),
      ),
    );
  }

  Widget _buildInvite() {
    final p = _preview!;
    final displayName = p['display_name'] as String? ?? '';
    final eventTitle = p['event_title'] as String? ?? '';
    final used = p['used'] as bool? ?? false;
    final expired = p['expired'] as bool? ?? false;

    if (used) {
      return _ErrorState(
        message: 'Это приглашение уже использовано. Попросите хоста создать новое.',
        onBack: () => context.go('/guest/entry'),
      );
    }
    if (expired) {
      return _ErrorState(
        message: 'Срок приглашения истёк. Попросите хоста создать новое.',
        onBack: () => context.go('/guest/entry'),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => context.go('/guest/entry'),
            icon: const Icon(Icons.arrow_back, color: AppColors.ink2),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ЛИЧНОЕ ПРИГЛАШЕНИЕ',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.amber,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Вас ждут на\n«$eventTitle»',
            style: GoogleFonts.playfairDisplay(
              fontSize: 32,
              fontWeight: FontWeight.w500,
              height: 1.05,
              letterSpacing: -0.64,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Хост создал персональную ссылку для «$displayName». '
            'Никакого PIN — сразу к камере.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: AppColors.ink3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ВАШЕ ИМЯ',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.ink3,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            maxLength: 40,
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: 'Так вас увидят в альбоме',
              counterText: '',
              filled: true,
              fillColor: AppColors.paper2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_joinError != null) ...[
            const SizedBox(height: 8),
            Text(
              _joinError!,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.shutter),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _joining ? null : _join,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _joining
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Войти в альбом',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _ErrorState({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link_off, size: 48, color: AppColors.ink3),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink2, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onBack,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Ввести код вручную',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
