import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';

class LiveProgressScreen extends ConsumerStatefulWidget {
  final String eventId;
  const LiveProgressScreen({super.key, required this.eventId});

  @override
  ConsumerState<LiveProgressScreen> createState() => _LiveProgressScreenState();
}

class _LiveProgressScreenState extends ConsumerState<LiveProgressScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _liveDot;

  @override
  void initState() {
    super.initState();
    _liveDot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _liveDot.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(eventDetailProvider(widget.eventId));
    ref.invalidate(eventProgressProvider(widget.eventId));
    await Future.wait([
      ref.read(eventDetailProvider(widget.eventId).future),
      ref.read(eventProgressProvider(widget.eventId).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));
    final progressAsync = ref.watch(eventProgressProvider(widget.eventId));

    final eventTitle = eventAsync.maybeWhen(
      data: (e) => e['title'] as String? ?? '',
      orElse: () => '',
    );

    final settings = eventAsync.maybeWhen(
      data: (e) => (e['settings'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      orElse: () => <String, dynamic>{},
    );
    final framesPerGuest = settings['frames_per_guest'] as int? ?? 24;
    final maxGuests = settings['max_guests'] as int? ?? 0;
    final revealAt = settings['reveal_at'] as String?;

    final totalFrames = progressAsync.maybeWhen(
      data: (p) => p['total_frames'] as int? ?? 0,
      orElse: () => 0,
    );
    final maxFrames = maxGuests * framesPerGuest;

    final items = progressAsync.maybeWhen(
      data: (p) => List<Map<String, dynamic>>.from((p['items'] as List?) ?? []),
      orElse: () => <Map<String, dynamic>>[],
    );

    // Group frames by guest, track count and last activity
    final guestMap = <String, _GuestInfo>{};
    for (final frame in items) {
      final guestId = frame['guest_id'] as String? ?? '';
      final guestName = frame['guest_name'] as String? ?? '?';
      final capturedAt = DateTime.tryParse(frame['captured_at'] as String? ?? '');
      guestMap.putIfAbsent(guestId, () => _GuestInfo(name: guestName, id: guestId));
      guestMap[guestId]!.frames++;
      if (capturedAt != null) {
        final last = guestMap[guestId]!.lastAt;
        if (last == null || capturedAt.isAfter(last)) {
          guestMap[guestId]!.lastAt = capturedAt;
        }
      }
    }
    final guests = guestMap.values.toList()
      ..sort((a, b) => (b.lastAt ?? DateTime(0)).compareTo(a.lastAt ?? DateTime(0)));

    // Remaining until reveal
    Duration? remaining;
    if (revealAt != null) {
      final revealDt = DateTime.tryParse(revealAt)?.toLocal();
      if (revealDt != null) {
        final diff = revealDt.difference(DateTime.now());
        remaining = diff.isNegative ? Duration.zero : diff;
      }
    }

    final isLoading = progressAsync.isLoading && items.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  _IcBtn(icon: Icons.chevron_left, onTap: () => context.pop()),
                  Expanded(
                    child: eventTitle.isEmpty
                        ? const SizedBox.shrink()
                        : Text(
                            eventTitle,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.17,
                              color: AppColors.ink,
                            ),
                          ),
                  ),
                  _IcBtn(icon: Icons.refresh, onTap: _refresh),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
                  : RefreshIndicator(
                      color: AppColors.amber,
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                        children: [
                          // Live big card
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.paper2,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedBuilder(
                                  animation: _liveDot,
                                  builder: (_, __) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.shutter.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppColors.shutter.withValues(
                                              alpha: _liveDot.value * 0.5 + 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'LIVE',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.2,
                                            color: AppColors.shutter,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontFamily: 'JetBrains Mono',
                                      fontSize: 88,
                                      fontWeight: FontWeight.w500,
                                      height: 1,
                                      letterSpacing: -3.52,
                                      color: AppColors.ink,
                                    ),
                                    children: [
                                      TextSpan(text: '$totalFrames'),
                                      if (maxFrames > 0)
                                        TextSpan(
                                          text: ' / $maxFrames',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            color: AppColors.ink3,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  guests.isEmpty
                                      ? 'Кадров пока нет · потяните для обновления'
                                      : 'Кадров отснято · ${guests.length} ${_guestWord(guests.length)}',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: AppColors.ink3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (guests.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            const Text(
                              'ПОСЛЕДНИЕ',
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 10,
                                letterSpacing: 1.4,
                                color: AppColors.ink3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...List.generate(guests.length, (i) => _GuestRow(
                              data: guests[i],
                              framesPerGuest: framesPerGuest,
                              isLast: i == guests.length - 1,
                            )),
                          ],
                          if (remaining != null) ...[
                            const SizedBox(height: 14),
                            _RevealCard(remaining: remaining),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _guestWord(int n) {
  if (n % 100 >= 11 && n % 100 <= 19) return 'гостей';
  switch (n % 10) {
    case 1: return 'гость';
    case 2:
    case 3:
    case 4: return 'гостя';
    default: return 'гостей';
  }
}

// ─── data model ──────────────────────────────────────────────────────────────

class _GuestInfo {
  final String name;
  final String id;
  int frames = 0;
  DateTime? lastAt;
  _GuestInfo({required this.name, required this.id});
}

// ─── widgets ─────────────────────────────────────────────────────────────────

class _IcBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IcBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: AppColors.ink2, size: 20),
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  final _GuestInfo data;
  final int framesPerGuest;
  final bool isLast;
  const _GuestRow({required this.data, required this.framesPerGuest, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final grad = _gradientForId(data.id);
    final initial = data.name.isNotEmpty ? data.name[0].toUpperCase() : '?';
    final agoStr = _timeAgo(data.lastAt);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast
          ? null
          : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: grad,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              data.name,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${data.frames} / $framesPerGuest',
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 14,
              color: AppColors.ink3,
            ),
          ),
          if (agoStr.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              agoStr,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                letterSpacing: 0.4,
                color: AppColors.ink4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RevealCard extends StatelessWidget {
  final Duration remaining;
  const _RevealCard({required this.remaining});

  String _fmt(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    final done = remaining.inSeconds == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1, 1),
                  radius: 1.0,
                  colors: [Color(0x2FFFB347), Colors.transparent],
                ),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.drAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.timer_outlined, color: AppColors.drAmber, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? 'ГОТОВО К ПРОЯВКЕ' : 'ПРОЯВКА ЧЕРЕЗ',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        letterSpacing: 1.54,
                        color: Color(0x99F0E6D2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      done ? '—' : '${_fmt(h)} : ${_fmt(m)} : ${_fmt(s)}',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 24,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w500,
                        color: AppColors.drAmber,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.drAmber, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

String _timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '·ТОЛЬКО ЧТО';
  if (diff.inHours < 1) return '·${diff.inMinutes} МИН';
  if (diff.inDays < 1) return '·${diff.inHours} ЧАС';
  return '·${diff.inDays} ДН';
}

List<Color> _gradientForId(String id) {
  final palettes = [
    [const Color(0xFFD4A373), const Color(0xFFA6701A)],
    [const Color(0xFFC97E4A), const Color(0xFF6A3520)],
    [const Color(0xFF6B8E6F), const Color(0xFF2C4A3A)],
    [const Color(0xFFD54B3D), const Color(0xFF4A1818)],
    [const Color(0xFF5B7BA8), const Color(0xFF1E3A5F)],
    [const Color(0xFF8B6BA8), const Color(0xFF3D2060)],
  ];
  final idx = id.codeUnits.fold(0, (a, b) => a + b) % palettes.length;
  return palettes[idx];
}
