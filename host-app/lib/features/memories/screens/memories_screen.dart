import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/tokens.dart';
import '../memories_provider.dart';
import '../widgets/memory_blocks.dart';

/// Раздел «Кадры» — авто-подборки из альбомов юзера.
/// Поддерживает поиск по названию + фильтр по типу события.
class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  bool _searching = false;
  String _query = '';
  String _typeFilter = 'all'; // all, wedding, birthday, corporate, ...
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _typeLabels = <String, String>{
    'all': 'Все типы',
    'Свадьба': 'Свадьбы',
    'День рождения': 'Дни рождения',
    'Корпоратив': 'Корпоративы',
    'Вечеринка': 'Вечеринки',
    'Выпускной': 'Выпускные',
    'Путешествие': 'Путешествия',
    'Отпуск': 'Отпуска',
    'Концерт': 'Концерты',
  };

  bool _matchesFilters(Map<String, dynamic> block) {
    if (_query.isNotEmpty) {
      final title = ((block['title'] as String?) ?? '').toLowerCase();
      if (!title.contains(_query.toLowerCase())) return false;
    }
    if (_typeFilter != 'all') {
      final eventType = (block['event_type'] as String?) ?? '';
      // for collection blocks event_type пустой — фильтруем по title
      if (eventType.isNotEmpty) {
        if (eventType != _typeFilter) return false;
      } else {
        final title = ((block['title'] as String?) ?? '');
        if (!title.contains(_typeLabels[_typeFilter] ?? '')) return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final blocksAsync = ref.watch(memoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.paper2,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(18, 14, 12, _searching ? 14 : 16),
              decoration: BoxDecoration(
                color: AppColors.paper,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, 3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: _searching
                  ? _MemoriesSearchBar(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      onClose: () => setState(() {
                        _searching = false;
                        _query = '';
                        _searchCtrl.clear();
                      }),
                      typeFilter: _typeFilter,
                      onTypeSelect: (v) => setState(() => _typeFilter = v),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Кадры',
                            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                              fontSize: 32,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                              letterSpacing: -0.7,
                              height: 1.05,
                            ),
                          ),
                        ),
                        _TypeFilterButton(
                          selected: _typeFilter,
                          labels: _typeLabels,
                          onSelect: (v) => setState(() => _typeFilter = v),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _searching = true),
                          icon: const Icon(Icons.search, size: 24, color: AppColors.ink2),
                          tooltip: 'Поиск',
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: blocksAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.amber, strokeWidth: 2),
                ),
                error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(memoriesProvider)),
                data: (blocks) {
                  if (blocks.isEmpty) return const _EmptyState();
                  final filtered = blocks.where(_matchesFilters).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _query.isNotEmpty
                              ? 'Ничего не найдено по «$_query»'
                              : 'Нет подборок этого типа',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink3),
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.amber,
                    backgroundColor: AppColors.paper,
                    onRefresh: () async {
                      ref.invalidate(memoriesProvider);
                      await ref.read(memoriesProvider.future);
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => MemoryBlockWidget(block: filtered[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search bar в шапке Кадры (аналог dashboard) ────────────────────────────

class _MemoriesSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final String typeFilter;
  final ValueChanged<String> onTypeSelect;

  const _MemoriesSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    required this.typeFilter,
    required this.onTypeSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back, size: 22, color: AppColors.ink2),
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
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
                        hintText: 'Название события…',
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
      ],
    );
  }
}

// ─── Type filter dropdown (лупа: тип события) ───────────────────────────────

class _TypeFilterButton extends StatelessWidget {
  final String selected;
  final Map<String, String> labels;
  final ValueChanged<String> onSelect;

  const _TypeFilterButton({required this.selected, required this.labels, required this.onSelect});

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx - 150,
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
      items: labels.entries.map((entry) {
        final active = entry.key == selected;
        return PopupMenuItem<String>(
          value: entry.key,
          height: 44,
          child: Row(
            children: [
              Icon(
                active ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: active ? AppColors.amber : AppColors.ink3,
              ),
              const SizedBox(width: 12),
              Text(
                entry.value,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.amber : AppColors.ink,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
    if (result != null && result != selected) onSelect(result);
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = selected != 'all';
    return Builder(builder: (btnCtx) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: () => _open(btnCtx),
            icon: const Icon(Icons.filter_alt_outlined, size: 24, color: AppColors.ink2),
            tooltip: 'Тип события',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (hasActive)
            Positioned(
              right: 6, top: 6,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: AppColors.amber,
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

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 40, color: AppColors.ink4),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить',
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: const BoxDecoration(
                color: AppColors.paper2,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_outlined, size: 40, color: AppColors.ink3),
            ),
            const SizedBox(height: 20),
            Text(
              'Скоро здесь появятся кадры',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Автоматические подборки из ваших альбомов — свадьбы, дни рождения, вечеринки. Как только появятся альбомы с фотографиями, здесь соберётся живая лента',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.ink3,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => GoRouter.of(context).go('/dashboard'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'К альбомам',
                style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
