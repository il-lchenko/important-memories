import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  int _tab = 0; // 0 = мои, 1 = приглашённые
  String _selectedFilter = 'all';
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  bool _isSearching = false;
  bool _chipsCollapsed = false;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  // Периодическая инвалидация — статусы событий могут меняться на бэкенде
  // (auto_complete по end_at), а провайдер keepAlive: true — сам не обновится.
  Timer? _refreshTimer;

  static const _collapseThreshold = 16.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    // При каждом открытии dashboard — тянем свежие статусы.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(eventsProvider);
    });
    // И далее — раз в минуту, пока пользователь на dashboard.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) ref.invalidate(eventsProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Приложение вернулось из фона → бекенд мог уже закрыть событие.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(eventsProvider);
    }
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > _collapseThreshold;
    if (collapsed != _chipsCollapsed) {
      setState(() => _chipsCollapsed = collapsed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _tabLabel => switch (_tab) {
        1 => 'Другие события',
        2 => 'Все альбомы',
        _ => 'Мои альбомы',
      };

  final GlobalKey _titleKey = GlobalKey();

  Future<void> _openTabPicker() async {
    final ctx = _titleKey.currentContext ?? context;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height + 6,
      overlay.size.width - origin.dx - box.size.width,
      0,
    );
    final result = await showMenu<int>(
      context: ctx,
      position: position,
      color: AppColors.paper,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        _tabMenuItem(value: 0, label: 'Мои альбомы', icon: Icons.collections_bookmark_outlined),
        _tabMenuItem(value: 1, label: 'Другие события', icon: Icons.groups_outlined),
        _tabMenuItem(value: 2, label: 'Все альбомы', icon: Icons.dashboard_customize_outlined),
      ],
    );
    if (result != null && result != _tab) {
      setState(() {
        _tab = result;
        _selectedFilter = 'all';
        _searchQuery = '';
        _searchController.clear();
        _dateRange = null;
        _isSearching = false;
      });
    }
  }

  PopupMenuItem<int> _tabMenuItem({required int value, required String label, required IconData icon}) {
    final active = value == _tab;
    return PopupMenuItem<int>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 20, color: active ? AppColors.amber : AppColors.ink2),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? AppColors.amber : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.paper3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Фильтры',
                  style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 20),
                Text(
                  'Диапазон дат',
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink3, letterSpacing: 0.3),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pickDateRange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: _dateRange != null
                          ? AppColors.amber.withValues(alpha: 0.10)
                          : AppColors.paper2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _dateRange != null ? AppColors.amber : AppColors.paper3,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: _dateRange != null ? AppColors.amber : AppColors.ink2,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _dateRange == null
                                ? 'За всё время'
                                : '${DateFormat('dd.MM.yyyy', 'ru').format(_dateRange!.start)} — ${DateFormat('dd.MM.yyyy', 'ru').format(_dateRange!.end)}',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: _dateRange != null ? AppColors.amber : AppColors.ink,
                            ),
                          ),
                        ),
                        if (_dateRange != null)
                          GestureDetector(
                            onTap: () {
                              setState(() => _dateRange = null);
                              Navigator.of(ctx).pop();
                            },
                            child: const Icon(Icons.close, size: 18, color: AppColors.amber),
                          )
                        else
                          const Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.paper,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Готово',
                      style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      helpText: 'Диапазон дат',
      cancelText: 'Отмена',
      confirmText: 'Применить',
      saveText: 'Применить',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.amber,
            onPrimary: Colors.white,
            surface: AppColors.paper,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (result != null) {
      setState(() => _dateRange = result);
    }
  }

  bool _matchesFilters(Map<String, dynamic> e) {
    // status filter
    if (_selectedFilter != 'all' && (e['status'] as String?) != _selectedFilter) {
      return false;
    }
    // search
    if (_searchQuery.trim().isNotEmpty) {
      final title = ((e['title'] as String?) ?? '').toLowerCase();
      if (!title.contains(_searchQuery.trim().toLowerCase())) return false;
    }
    // date range (by start_at)
    if (_dateRange != null) {
      final raw = (e['start_at'] as String?) ?? (e['end_at'] as String?);
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw);
      if (dt == null) return false;
      final localDt = dt.toLocal();
      final rangeEnd = _dateRange!.end.add(const Duration(days: 1));
      if (localDt.isBefore(_dateRange!.start) || localDt.isAfter(rangeEnd)) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: soft cream (paper) + subtle shadow below to separate from content.
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 14, 12, _isSearching ? 14 : 16),
              decoration: BoxDecoration(
                color: AppColors.paper,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, 3),
                    blurRadius: 6,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: _isSearching
                  ? _SearchBar(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      onClose: () => setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      }),
                      onFilters: _openFiltersSheet,
                      hasActiveFilter: _dateRange != null,
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            key: _titleKey,
                            onTap: _openTabPicker,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _tabLabel,
                                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()],
                                      fontSize: 32,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.ink,
                                      letterSpacing: -0.9,
                                      height: 1.05,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.arrow_drop_down, size: 24, color: AppColors.ink2),
                              ],
                            ),
                          ),
                        ),
                        _StatusFilterButton(
                          selected: _selectedFilter,
                          onSelect: (v) => setState(() => _selectedFilter = v),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _isSearching = true),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            child: Icon(Icons.search, size: 24, color: AppColors.ink2),
                          ),
                        ),
                      ],
                    ),
            ),

            if (_tab == 1) ...[
              // ─── Другие события ────────────────────────────────
              Expanded(child: _InvitedSection(filter: _selectedFilter)),
            ] else ...[
            // ─── Мои альбомы ────────────────────────────────────
            const SizedBox(height: 8),
            // Список ивентов
            Expanded(
              child: Builder(builder: (_) {
                final events = eventsAsync.valueOrNull;
                if (events == null) {
                  if (eventsAsync.hasError) return _ErrorState(onRetry: () => ref.invalidate(eventsProvider));
                  return const Center(child: CircularProgressIndicator(color: AppColors.amber));
                }
                final visible = events.where((e) => (e['status'] as String?) != 'cancelled').toList();
                  final filtered = visible.where(_matchesFilters).toList();
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
                                controller: _scrollController,
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
              }),
            ),
            ], // end else (tab == 0)
          ],
        ),
      ),
      floatingActionButton: _tab != 1 ? eventsAsync.valueOrNull?.isNotEmpty == true ? const _CreateAlbumFab() : null : null,
      floatingActionButtonLocation: const _CreateAlbumFabLocation(),
      // bottomNavigationBar is provided by MainShell (StatefulShellRoute).
    );
  }
}

// ─── Search bar (inline in header) ─────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final VoidCallback onFilters;
  final bool hasActiveFilter;
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    required this.onFilters,
    required this.hasActiveFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.paper3, width: 1),
            ),
            child: Center(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      autofocus: true,
                      textAlignVertical: TextAlignVertical.center,
                      cursorColor: AppColors.amber,
                      cursorHeight: 18,
                      style: GoogleFonts.manrope(fontSize: 15, color: AppColors.ink),
                      decoration: InputDecoration(
                        hintText: 'Название альбома…',
                        hintStyle: GoogleFonts.manrope(fontSize: 15, color: AppColors.ink3),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        controller.clear();
                        onChanged('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6, right: 4),
                        child: Icon(Icons.cancel, size: 18, color: AppColors.ink3),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.search, size: 20, color: AppColors.ink3),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onFilters,
              icon: const Icon(Icons.tune, size: 22, color: AppColors.ink2),
              tooltip: 'Фильтры',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            if (hasActiveFilter)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 22, color: AppColors.ink2),
          tooltip: 'Закрыть поиск',
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
      ],
    );
  }
}

// ─── Invited events section ───────────────────────────────────────────────────

class _InvitedSection extends ConsumerWidget {
  final String filter;
  const _InvitedSection({this.filter = 'all'});

  bool _matchStatus(Map<String, dynamic> e) {
    if (filter == 'all') return true;
    return (e['status'] as String? ?? '') == filter;
  }

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
        final filtered = events.where(_matchStatus).toList();
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
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'Нет событий в этом разделе',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3),
                    ),
                  ),
                ),
              for (final e in filtered) ...[
                AspectRatio(aspectRatio: 3 / 2, child: _InvitedEventCard(event: e)),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => context.push('/guest/entry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.qr_code_outlined, size: 18),
                label: Text(
                  'Подключиться к новому',
                  style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
                ),
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
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink2),
            ),
            const SizedBox(height: 8),
            Text(
              'Когда вас пригласят на событие,\nоно появится здесь',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/guest/entry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.qr_code_outlined, size: 18),
              label: Text(
                'Подключиться к событию',
                style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
              ),
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
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
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
    final status = event['status'] as String? ?? 'active';

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
          onTap: () => context.push('/events/${event['id']}/album'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null)
                CachedNetworkImage(imageUrl: coverUrl, cacheKey: Uri.parse(coverUrl).path, fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => _InvitedCoverPlaceholder())
              else
                _InvitedCoverPlaceholder(),
              // Dark gradient below
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
              // Status badge — top-left
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
                          fontFamily: 'Inter', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.12, color: dotColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // GUEST badge — bottom-right (diagonal from status)
              Positioned(
                bottom: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: const Text(
                    'ГОСТЬ',
                    style: TextStyle(
                      fontFamily: 'Inter', fontSize: 10,
                      color: Colors.white, fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              // Title + meta
              Positioned(
                bottom: 10, left: 12, right: 90, // leave room for GUEST badge
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
                        const Icon(Icons.camera_roll_outlined, size: 16, color: Color(0xFFC9881E)),
                        const SizedBox(width: 4),
                        Text('$myFrames',
                          style: GoogleFonts.manrope(fontSize: 14, color: const Color(0xFFC9881E), fontWeight: FontWeight.w700)),
                        Text(' / $totalFrames',
                          style: GoogleFonts.manrope(fontSize: 14, color: const Color(0xFFB0A080), fontWeight: FontWeight.w600)),
                        if (_dateStr().isNotEmpty) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFFB0A080)),
                          const SizedBox(width: 4),
                          Text(_dateStr(),
                            style: GoogleFonts.manrope(fontSize: 14, color: const Color(0xFFB0A080), fontWeight: FontWeight.w600)),
                        ],
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
              CachedNetworkImage(imageUrl: coverUrl, cacheKey: Uri.parse(coverUrl).path, fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => const _CoverPlaceholder())
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
                        fontFamily: 'Inter', fontSize: 10,
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
                      const Icon(Icons.person_outline, size: 16, color: Color(0xFFB0A080)),
                      const SizedBox(width: 4),
                      Text('$guestsCount',
                        style: GoogleFonts.manrope(fontSize: 14, color: const Color(0xFFB0A080), fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      const Icon(Icons.camera_roll_outlined, size: 16, color: Color(0xFFC9881E)),
                      const SizedBox(width: 4),
                      Text('$framesCount',
                        style: GoogleFonts.manrope(fontSize: 14, color: const Color(0xFFC9881E), fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFFB0A080)),
                      const SizedBox(width: 4),
                      Text(_dateStr(),
                        style: GoogleFonts.manrope(fontSize: 14, color: const Color(0xFFB0A080), fontWeight: FontWeight.w600)),
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
                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
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

// ─── FAB: создать альбом ──────────────────────────────────────────────────────

class _CreateAlbumFab extends StatelessWidget {
  const _CreateAlbumFab();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/events/create'),
      child: Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: AppColors.amber,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.amber.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: -3,
              offset: const Offset(0, 4),
            ),
            const BoxShadow(
              color: Color(0x29000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.add_photo_alternate_outlined, size: 28, color: Colors.white),
      ),
    );
  }
}

// ─── Status filter dropdown in header (replaces chip row) ───────────────────

class _StatusFilterButton extends StatelessWidget {
  final String selected; // 'all' | 'active' | 'completed'
  final ValueChanged<String> onSelect;

  const _StatusFilterButton({required this.selected, required this.onSelect});

  Color? get _dotColor {
    switch (selected) {
      case 'active':
        return AppColors.shutter;
      case 'completed':
        return AppColors.success;
      default:
        return null;
    }
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx - 120,
      origin.dy + box.size.height + 4,
      overlay.size.width - origin.dx - box.size.width,
      0,
    );
    final result = await showMenu<String>(
      context: context,
      position: position,
      color: AppColors.paper,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        _item('all', 'Все', AppColors.amber, Icons.dashboard_customize_outlined),
        _item('active', 'Записываются', AppColors.shutter, Icons.fiber_manual_record),
        _item('completed', 'Проявлены', AppColors.success, Icons.check_circle_outline),
      ],
    );
    if (result != null && result != selected) onSelect(result);
  }

  PopupMenuItem<String> _item(String value, String label, Color accent, IconData icon) {
    final active = value == selected;
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 18, color: active ? accent : AppColors.ink2),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? accent : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dot = _dotColor;
    return Builder(builder: (btnCtx) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(btnCtx),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Icon(Icons.filter_alt_outlined, size: 24, color: AppColors.ink2),
            ),
          ),
          if (dot != null)
            Positioned(
              right: 4, top: 6,
              child: Container(
                width: 9, height: 9,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.paper, width: 1.5),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Custom FAB location — pushed further from the right edge (default 16 → 28)
/// and slightly higher to avoid overlapping the bottom nav shadow.
class _CreateAlbumFabLocation extends FloatingActionButtonLocation {
  const _CreateAlbumFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double fabX = scaffoldGeometry.scaffoldSize.width -
        scaffoldGeometry.floatingActionButtonSize.width - 20;
    final double contentBottom = scaffoldGeometry.contentBottom;
    final double bottomInset = scaffoldGeometry.minInsets.bottom;
    final double fabY = contentBottom - scaffoldGeometry.floatingActionButtonSize.height - 16 - bottomInset;
    return Offset(fabX, fabY);
  }
}
