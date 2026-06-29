import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';
import '../events_provider.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _tab = 0; // 0 = мои, 1 = приглашённые
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line, width: 1)),
              ),
              child: Text('Альбомы', style: Theme.of(context).textTheme.displayMedium),
            ),

            // Segment control: МОИ / ПРИГЛАШЕНИЯ
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: _TabSwitcher(
                tab: _tab,
                onChanged: (t) => setState(() { _tab = t; _selectedFilter = 'all'; }),
              ),
            ),

            if (_tab == 1) ...[
              // ─── Другие события ────────────────────────────────
              Expanded(child: _InvitedSection()),
            ] else ...[
            // ─── Мои альбомы ────────────────────────────────────
            const SizedBox(height: 14),
            // Фильтр-чипы
            eventsAsync.maybeWhen(
              data: (events) {
                final visible = events.where((e) => (e['status'] as String?) != 'cancelled').toList();
                final activeCount = visible.where((e) => (e['status'] as String?) == 'active').length;
                final completedCount = visible.where((e) => (e['status'] as String?) == 'completed').length;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
                  child: Row(children: [
                    _FilterChip(
                      label: 'Все',
                      count: visible.length,
                      accent: AppColors.amber,
                      active: _selectedFilter == 'all',
                      onTap: () => setState(() => _selectedFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Записываются',
                      count: activeCount,
                      accent: AppColors.shutter,
                      active: _selectedFilter == 'active',
                      onTap: () => setState(() => _selectedFilter = 'active'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Проявлены',
                      count: completedCount,
                      accent: AppColors.success,
                      active: _selectedFilter == 'completed',
                      onTap: () => setState(() => _selectedFilter = 'completed'),
                    ),
                  ]),
                );
              },
              orElse: () => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
                child: Row(children: [
                  _FilterChip(label: 'Все', accent: AppColors.amber, active: true, onTap: () {}),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Записываются', accent: AppColors.shutter, onTap: () {}),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Проявлены', accent: AppColors.success, onTap: () {}),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // Список ивентов
            Expanded(
              child: eventsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
                error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(eventsProvider)),
                data: (events) {
                  final visible = events.where((e) => (e['status'] as String?) != 'cancelled').toList();
                  final filtered = _selectedFilter == 'all'
                      ? visible
                      : visible.where((e) => (e['status'] as String?) == _selectedFilter).toList();
                  return RefreshIndicator(
                    color: AppColors.amber,
                    backgroundColor: AppColors.paper,
                    onRefresh: () async {
                      ref.invalidate(eventsProvider);
                      await ref.read(eventsProvider.future);
                    },
                    child: visible.isEmpty
                        ? LayoutBuilder(
                            builder: (ctx, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: SizedBox(
                                height: constraints.maxHeight,
                                child: _EmptyState(onTap: () => context.push('/events/create')),
                              ),
                            ),
                          )
                        : filtered.isEmpty
                            ? LayoutBuilder(
                                builder: (ctx, constraints) => SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: SizedBox(
                                    height: constraints.maxHeight,
                                    child: Center(
                                      child: Text(
                                        'Нет альбомов в этом разделе',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink3),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 11,
                                    child: _EventCard(event: filtered[i]),
                                  ),
                                ),
                              ),
                  );
                },
              ),
            ),
            ], // end else (tab == 0)
          ],
        ),
      ),
      floatingActionButton: _tab == 0 ? eventsAsync.maybeWhen(
        data: (events) => events.isEmpty
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/events/create'),
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add, size: 28),
              ),
        orElse: () => null,
      ) : null,
      bottomNavigationBar: _BottomNav(),
    );
  }
}

// ─── Tab switcher ─────────────────────────────────────────────────────────────

class _TabSwitcher extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChanged;
  const _TabSwitcher({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: AppRadius.lgBR,
      ),
      child: Row(
        children: [
          _TabBtn(label: 'МОИ АЛЬБОМЫ', active: tab == 0, onTap: () => onChanged(0)),
          const SizedBox(width: 2),
          _TabBtn(label: 'ДРУГИЕ СОБЫТИЯ', active: tab == 1, onTap: () => onChanged(1)),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          decoration: BoxDecoration(
            color: active ? AppColors.paper : Colors.transparent,
            borderRadius: AppRadius.mdBR,
            boxShadow: active
                ? const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? AppColors.amber : AppColors.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Invited events section ───────────────────────────────────────────────────

class _InvitedSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitedAsync = ref.watch(invitedEventsProvider);

    return invitedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 40, color: AppColors.ink4),
              const SizedBox(height: 16),
              Text(
                'Не удалось загрузить события',
                style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink3),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(invitedEventsProvider),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
      data: (events) {
        if (events.isEmpty) {
          return _InvitedEmpty();
        }
        return RefreshIndicator(
          color: AppColors.amber,
          backgroundColor: AppColors.paper,
          onRefresh: () async {
            ref.invalidate(invitedEventsProvider);
            await ref.read(invitedEventsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              for (final e in events) ...[
                _InvitedEventCard(event: e),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/guest/entry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink3,
                  side: const BorderSide(color: AppColors.paper3),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.qr_code_outlined, size: 18),
                label: const Text('Подключиться к новому', style: TextStyle(fontFamily: 'Inter', fontSize: 14)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InvitedEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.paper2, shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_outlined, size: 32, color: AppColors.ink3),
            ),
            const SizedBox(height: 20),
            Text(
              'Нет других событий',
              style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink2),
            ),
            const SizedBox(height: 8),
            Text(
              'Когда вас пригласят на событие,\nоно появится здесь',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3, height: 1.5),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.push('/guest/entry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.amber,
                side: const BorderSide(color: AppColors.amber),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.qr_code_outlined, size: 18),
              label: const Text('Подключиться к событию', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitedEventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const _InvitedEventCard({required this.event});

  String _dateStr() {
    final raw = (event['start_at'] ?? event['end_at']) as String?;
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('dd.MM', 'ru').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = event['title'] as String? ?? 'Событие';
    final myFrames = event['my_frames_count'] as int? ?? 0;
    final totalFrames = event['total_frames'] as int? ?? 0;
    final coverUrl = event['cover_url'] as String?;
    final dateStr = _dateStr();

    return GestureDetector(
      onTap: () => context.push('/events/${event['id']}/album'),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: AppRadius.mdBR,
          border: Border.all(color: AppColors.paper3),
        ),
        child: Row(
          children: [
            // Cover thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: AppRadius.md),
              child: SizedBox(
                width: 80, height: 80,
                child: coverUrl != null
                    ? Image.network(coverUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _InvitedCoverPlaceholder())
                    : _InvitedCoverPlaceholder(),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (dateStr.isNotEmpty) dateStr,
                      '$myFrames ВАШИХ · $totalFrames ВСЕГО',
                    ].join(' · '),
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono', fontSize: 9,
                      letterSpacing: 0.8, color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            // Guest badge
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.1),
                  borderRadius: AppRadius.pillBR,
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'ГОСТЬ',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono', fontSize: 9,
                    color: AppColors.amber, fontWeight: FontWeight.w700,
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

class _InvitedCoverPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A6F5A), Color(0xFF2A1E15)],
        ),
      ),
    );
  }
}

// ─── Filter chip (existing) ────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.count,
    this.active = false,
    this.accent = AppColors.amber,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppSizes.chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: AppRadius.pillBR,
          border: Border.all(
            color: active ? accent : AppColors.line,
            width: active ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color dot — always visible, hints the accent
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? accent : AppColors.ink2,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: active ? accent : AppColors.ink4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ─── Карточка события ─────────────────────────────────────────────────────────
class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventCard({required this.event});

  String _dateStr() {
    final raw = (event['start_at'] ?? event['created_at']) as String?;
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = event['status'] as String? ?? 'draft';
    final title = (event['title'] ?? event['name'] ?? 'Ивент') as String;
    final guestsCount = event['guests_count'] as int? ?? 0;
    final framesCount = event['frames_count'] as int? ?? 0;
    final coverUrl = event['cover_url'] as String?;

    final dotColor = status == 'active'
        ? const Color(0xFFC9881E)
        : status == 'completed'
            ? const Color(0xFF5BAA72)
            : AppColors.ink3;
    final dotGlow = status == 'active' || status == 'completed';
    final badgeLabel = status == 'active' ? 'ЗАПИСЬ'
        : status == 'completed' ? 'ПРОЯВЛЕНО'
        : status == 'draft' ? 'ЧЕРНОВИК'
        : status.toUpperCase();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1E1A1714)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D1A1714), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(11.5),
      child: GestureDetector(
      onTap: () => context.push('/events/${event['id']}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
            // Обложка
            if (coverUrl != null)
              Image.network(coverUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _CoverPlaceholder())
            else
              const _CoverPlaceholder(),
            // Экспоненциальный затемняющий градиент снизу — без blur
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 100,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.25, 0.55, 0.80, 1.0],
                    colors: [
                      Color(0x000A0603),
                      Color(0x100A0603),
                      Color(0x3C0A0603),
                      Color(0x780A0603),
                      Color(0xB20A0603),
                    ],
                  ),
                ),
              ),
            ),
            // Статус бейдж
            Positioned(
              top: 10, left: 10,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        boxShadow: dotGlow
                            ? [BoxShadow(color: dotColor.withValues(alpha: 0.8), blurRadius: 6)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(badgeLabel,
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono', fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.12, color: dotColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Название + мета
            Positioned(
              bottom: 10, left: 12, right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.ptSerif(
                      fontSize: 22, fontWeight: FontWeight.w700,
                      color: const Color(0xFFF0E8D8), height: 1.2,
                      shadows: const [
                        Shadow(color: Color(0xCC000000), blurRadius: 0, offset: Offset(0, 1)),
                        Shadow(color: Color(0x88000000), blurRadius: 6),
                        Shadow(color: Color(0x44000000), blurRadius: 16),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 13, color: Color(0xFFB0A080)),
                      const SizedBox(width: 3),
                      Text('$guestsCount',
                        style: GoogleFonts.manrope(fontSize: 12, color: const Color(0xFFB0A080), fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      const Icon(Icons.camera_roll_outlined, size: 13, color: Color(0xFFC9881E)),
                      const SizedBox(width: 3),
                      Text('$framesCount',
                        style: GoogleFonts.manrope(fontSize: 12, color: const Color(0xFFC9881E), fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFFB0A080)),
                      const SizedBox(width: 3),
                      Text(_dateStr(),
                        style: GoogleFonts.manrope(fontSize: 12, color: const Color(0xFFB0A080), fontWeight: FontWeight.w500)),
                    ],
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

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A3828), Color(0xFF2A1810), Color(0xFF100806)],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Film strip icon
                  const SizedBox(
                    width: 130,
                    height: 90,
                    child: Center(
                      child: SizedBox(
                        width: 112,
                        height: 80,
                        child: CustomPaint(painter: _AlbumPainter()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Создайте первый\nальбом',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      letterSpacing: -0.01 * 24,
                      height: 1.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Свадьба, день рождения, выпускной или вечеринка — запечатлевайте каждое событие с разных ракурсов!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Начните с названия и даты события',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      color: AppColors.ink3,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: AppSizes.buttonHeight,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                    spreadRadius: -4,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'Создать альбом',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomNav extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    void onQrTap() {
      final events = ref.read(eventsProvider).valueOrNull ?? [];
      final active = events.where((e) => (e['status'] as String?) == 'active').toList();
      final target = active.isNotEmpty ? active.first : (events.isNotEmpty ? events.first : null);
      if (target != null) {
        context.push('/events/${target['id']}/qr');
      } else {
        context.push('/events/create');
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottomInset),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavItem(icon: Icons.photo_library_outlined, label: 'Альбомы', active: true),
          _NavItem(icon: Icons.qr_code_outlined, label: 'QR', onTap: onQrTap),
          _NavItem(icon: Icons.person_outline, label: 'Профиль', onTap: () => context.push('/profile')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.ink4),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Нет подключения',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              'Не удалось загрузить альбомы.\nПроверьте соединение.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s3),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Попробовать снова'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _NavItem({required this.icon, required this.label, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.amber : Colors.transparent,
            ),
          ),
          const SizedBox(height: 5),
          Icon(icon, color: active ? AppColors.ink : AppColors.ink4, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: active ? AppColors.ink : AppColors.ink4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Album painter (open album with photo frames) ─────────────────────────────

class _AlbumPainter extends CustomPainter {
  const _AlbumPainter();

  static const _page   = Color(0xFFF6F2E8);
  static const _page2  = Color(0xFFEDE8DF);
  static const _spine  = Color(0xFFD4C8B0);
  static const _photo  = Color(0xFFD4A373);
  static const _photo2 = Color(0xFF8A5828);
  static const _amber  = Color(0xFFFFB347);
  static const _line   = Color(0xFFD8CFBF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const r = Radius.circular(6.0);
    const spineW = 8.0;
    final midX = w / 2;

    // Shadow under album
    final shadowP = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, 6, w - 8, h - 6), r),
      shadowP,
    );

    // Left page
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, midX - spineW / 2, h),
        topLeft: r, bottomLeft: r,
      ),
      Paint()..color = _page,
    );
    // Right page
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(midX + spineW / 2, 0, midX - spineW / 2, h),
        topRight: r, bottomRight: r,
      ),
      Paint()..color = _page2,
    );
    // Spine
    canvas.drawRect(
      Rect.fromLTWH(midX - spineW / 2, 0, spineW, h),
      Paint()..color = _spine,
    );

    final framePaint = Paint()
      ..color = _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Left page: two small portrait frames
    final lp = midX - spineW / 2;
    final lPad = lp * 0.12;
    final lFrameW = (lp - lPad * 3) / 2;
    final lFrameH = lFrameW * 1.3;
    final lTop = (h - lFrameH) / 2;

    for (int i = 0; i < 2; i++) {
      final fx = lPad + i * (lFrameW + lPad);
      final fillP = Paint()
        ..shader = LinearGradient(
          colors: i == 0 ? [_photo, _photo2] : [const Color(0xFFF0D4A0), const Color(0xFF6A3520)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(fx, lTop, lFrameW, lFrameH));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(fx, lTop, lFrameW, lFrameH), const Radius.circular(2)),
        fillP,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(fx, lTop, lFrameW, lFrameH), const Radius.circular(2)),
        framePaint,
      );
    }

    // Right page: one larger landscape frame + amber accent line
    final rX = midX + spineW / 2;
    final rW = midX - spineW / 2;
    final rPad = rW * 0.12;
    final rFrameW = rW - rPad * 2;
    final rFrameH = rFrameW * 0.65;
    final rTop = (h - rFrameH) / 2 - 4;

    final rFillP = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE8B888), Color(0xFF5A2A0A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(rX + rPad, rTop, rFrameW, rFrameH));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rX + rPad, rTop, rFrameW, rFrameH), const Radius.circular(2)),
      rFillP,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rX + rPad, rTop, rFrameW, rFrameH), const Radius.circular(2)),
      framePaint,
    );

    // Amber dot accent bottom-right of right page
    canvas.drawCircle(
      Offset(rX + rW - rPad, h - rPad * 0.8),
      2.0,
      Paint()..color = _amber,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
