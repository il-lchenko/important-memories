import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/tokens.dart';
import '../events/events_provider.dart';
import '../events/widgets/public_link_sheet.dart';
import 'plus_providers.dart';

TextStyle _display(double size, {FontWeight w = FontWeight.w600}) => GoogleFonts.playfairDisplay(
      fontFeatures: [const FontFeature.liningFigures()],
      fontSize: size, fontWeight: w, color: AppColors.ink, letterSpacing: -0.4, height: 1.1,
    );

Widget _roundBtn(IconData icon, VoidCallback onTap) => InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(color: AppColors.paper2, shape: BoxShape.circle),
        child: Icon(icon, color: AppColors.ink, size: 22),
      ),
    );

Widget _img(String? url, {BoxFit fit = BoxFit.cover}) {
  if (url == null) return Container(color: AppColors.paper3);
  return CachedNetworkImage(
    imageUrl: url, cacheKey: Uri.parse(url).path, fit: fit, fadeInDuration: Duration.zero,
    errorWidget: (_, __, ___) => Container(color: AppColors.paper3),
  );
}

// ─── Полоса «Мини-альбомы» над разделом «Кадры» ──────────────────────────────

class MiniAlbumsStrip extends ConsumerWidget {
  const MiniAlbumsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionsProvider).valueOrNull;
    final list = (cols?['collections'] as List?)?.cast<Map>() ?? const [];
    return Container(
      color: AppColors.paper,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('МИНИ-АЛЬБОМЫ',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
            const Spacer(),
            InkWell(
              onTap: () => context.push('/collections/create'),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(children: [
                  const Icon(Icons.add, size: 16, color: AppColors.amber),
                  const SizedBox(width: 4),
                  Text('Подборка', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.amber)),
                ]),
              ),
            ),
          ]),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Соберите лучшие кадры из разных альбомов в одну подборку.',
                  style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3)),
            )
          else
            SizedBox(
              height: 108,
              child: ListView.separated(
                padding: const EdgeInsets.only(top: 10),
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final c = list[i];
                  final previews = (c['preview_urls'] as List?)?.cast<String>() ?? const [];
                  return InkWell(
                    onTap: () => context.push('/collections/${c['id']}'),
                    child: SizedBox(
                      width: 96,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(width: 96, height: 72, child: previews.isEmpty ? Container(color: AppColors.paper3) : _img(previews.first)),
                        ),
                        const SizedBox(height: 4),
                        Text(c['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Создание подборки ────────────────────────────────────────────────────────

class CollectionCreateScreen extends ConsumerStatefulWidget {
  const CollectionCreateScreen({super.key});

  @override
  ConsumerState<CollectionCreateScreen> createState() => _CollectionCreateScreenState();
}

class _CollectionCreateScreenState extends ConsumerState<CollectionCreateScreen> {
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final t = _title.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final resp = await ref.read(dioProvider).post('collections/', data: {'title': t});
      ref.invalidate(collectionsProvider);
      final id = (resp.data as Map)['id'] as String;
      if (!mounted) return;
      context.pushReplacement('/collections/$id/add');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(extractUserMessage(e)),
        action: SnackBarAction(label: 'Плюс', onPressed: () => context.push('/plus')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
          Row(children: [_roundBtn(Icons.chevron_left, () => context.pop())]),
          const SizedBox(height: 18),
          Text('МИНИ-АЛЬБОМ', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
          const SizedBox(height: 4),
          Text('Новая подборка', style: _display(32)),
          const SizedBox(height: 22),
          TextField(
            controller: _title, maxLength: 80, onChanged: (_) => setState(() {}),
            style: _display(22, w: FontWeight.w500),
            decoration: const InputDecoration(hintText: 'Например, Лучшее за лето', counterText: ''),
          ),
          const SizedBox(height: 16),
          Text(
            'В подборку можно собрать кадры из любых ваших альбомов и из альбомов, где вы были гостем. '
            'Файлы не копируются, поэтому подборка ничего не занимает в хранилище. Если автор удалит кадр '
            'или альбом пропадёт по сроку хранения, кадр исчезнет и из подборки.',
            style: GoogleFonts.manrope(fontSize: 13, height: 1.5, color: AppColors.ink3),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: (_title.text.trim().isEmpty || _busy) ? null : _create,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Создать и выбрать кадры'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Подборка ─────────────────────────────────────────────────────────────────

class CollectionDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const CollectionDetailScreen({super.key, required this.id});

  @override
  ConsumerState<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends ConsumerState<CollectionDetailScreen> {
  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _refresh() {
    ref.invalidate(collectionProvider(widget.id));
    ref.invalidate(collectionsProvider);
  }

  Future<void> _menu(Map<String, dynamic> col) async {
    final ctrl = TextEditingController(text: col['title'] as String? ?? '');
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(22, 16, 22, 22 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Подборка', style: _display(22)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLength: 80, decoration: const InputDecoration(counterText: '')),
          const SizedBox(height: 12),
          SizedBox(height: AppSizes.buttonHeight, child: ElevatedButton(onPressed: () => Navigator.pop(ctx, 'rename'), child: const Text('Сохранить название'))),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Удалить подборку', style: TextStyle(color: AppColors.shutter))),
        ]),
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    try {
      if (action == 'rename' && title.isNotEmpty) {
        await ref.read(dioProvider).patch('collections/${widget.id}', data: {'title': title});
        _refresh();
      } else if (action == 'delete') {
        await ref.read(dioProvider).delete('collections/${widget.id}');
        ref.invalidate(collectionsProvider);
        if (mounted) context.pop();
      }
    } catch (e) {
      _snack(extractUserMessage(e));
    }
  }

  Future<void> _remove(String frameId) async {
    try {
      await ref.read(dioProvider).delete('collections/${widget.id}/items/$frameId');
      _refresh();
    } catch (e) {
      _snack(extractUserMessage(e));
    }
  }

  void _openViewer(List<Map> items, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CollectionViewer(
        items: items, initial: index,
        onRemove: (frameId) async {
          await _remove(frameId);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collectionProvider(widget.id));
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
          error: (e, _) => Center(child: Text(extractUserMessage(e))),
          data: (col) {
            final items = (col['items'] as List).cast<Map>();
            final limit = col['frames_limit'] as int? ?? 0;
            final unavailable = col['unavailable_count'] as int? ?? 0;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Row(children: [
                  _roundBtn(Icons.chevron_left, () => context.pop()),
                  const Spacer(),
                  _roundBtn(Icons.ios_share, () => showPublicLinkSheet(context,
                      base: 'collections/${widget.id}', title: col['title'] as String? ?? 'Подборка',
                      note: 'По ссылке видны только кадры из ваших событий и снятые вами. Чужие кадры из альбомов, где вы были гостем, не показываются.')),
                  const SizedBox(width: 8),
                  _roundBtn(Icons.more_horiz, () => _menu(Map<String, dynamic>.from(col))),
                ]),
                const SizedBox(height: 18),
                Text('МИНИ-АЛЬБОМ · ${items.length} ИЗ $limit',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: AppColors.ink3)),
                const SizedBox(height: 4),
                Text(col['title'] as String? ?? '', style: _display(30, w: FontWeight.w500)),
                const SizedBox(height: 16),
                SizedBox(
                  height: AppSizes.buttonHeight,
                  child: ElevatedButton.icon(
                    onPressed: items.length >= limit ? null : () async {
                      await context.push('/collections/${widget.id}/add');
                      _refresh();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить кадры'),
                  ),
                ),
                if (unavailable > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Недоступно кадров: $unavailable. Автор удалил их или срок хранения альбома закончился.',
                        style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink3)),
                  ),
                const SizedBox(height: 14),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('Подборка пуста. Выберите кадры из ваших альбомов.',
                        textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink3))),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
                    itemCount: items.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _openViewer(items, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _img((items[i]['thumbnail_url'] ?? items[i]['preview_url'] ?? items[i]['full_url']) as String?),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CollectionViewer extends StatefulWidget {
  final List<Map> items;
  final int initial;
  final Future<void> Function(String frameId) onRemove;
  const _CollectionViewer({required this.items, required this.initial, required this.onRemove});

  @override
  State<_CollectionViewer> createState() => _CollectionViewerState();
}

class _CollectionViewerState extends State<_CollectionViewer> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  late final List<Map> _items = List<Map>.from(widget.items);
  final Set<int> _zoomed = {};

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: AppColors.drText)),
              Expanded(
                child: Text(_items.isEmpty ? '' : '${_index + 1} / ${_items.length}',
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, letterSpacing: 1.4, color: AppColors.drText)),
              ),
              IconButton(
                tooltip: 'Убрать из подборки',
                onPressed: _items.isEmpty ? null : () async {
                  final id = _items[_index]['id'] as String;
                  await widget.onRemove(id);
                  if (!mounted) return;
                  setState(() {
                    _items.removeAt(_index);
                    if (_index >= _items.length) _index = _items.length - 1;
                  });
                  if (_items.isEmpty && mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.delete_outline, color: AppColors.drText),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: _items.length,
              // Пока кадр увеличен, листание страниц отключаем: двигаем сам кадр.
              physics: _zoomed.contains(_index) ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final f = _items[i];
                final preview = (f['preview_url'] ?? f['thumbnail_url'] ?? f['full_url']) as String?;
                final full = f['full_url'] as String?;
                return _ZoomableFrame(
                  preview: preview, full: full,
                  onZoomChanged: (z) => setState(() { z ? _zoomed.add(i) : _zoomed.remove(i); }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_items.isEmpty ? '' : (_items[_index]['event_title'] as String? ?? ''),
                style: GoogleFonts.manrope(fontSize: 13, color: AppColors.drText.withValues(alpha: 0.7))),
          ),
        ]),
      ),
    );
  }
}

/// Кадр с увеличением щипком; при приближении подгружается оригинал.
class _ZoomableFrame extends StatefulWidget {
  final String? preview;
  final String? full;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomableFrame({required this.preview, required this.full, required this.onZoomChanged});

  @override
  State<_ZoomableFrame> createState() => _ZoomableFrameState();
}

class _ZoomableFrameState extends State<_ZoomableFrame> {
  final _ctrl = TransformationController();
  bool _wantFull = false;
  bool _zoomed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChange() {
    final scale = _ctrl.value.getMaxScaleOnAxis();
    final z = scale > 1.05;
    if (z != _zoomed) {
      _zoomed = z;
      widget.onZoomChanged(z);
    }
    if (z && !_wantFull) setState(() => _wantFull = true);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _ctrl,
      minScale: 1, maxScale: 8,
      onInteractionUpdate: (_) => _onChange(),
      onInteractionEnd: (_) => _onChange(),
      child: Stack(fit: StackFit.expand, children: [
        _img(widget.preview, fit: BoxFit.contain),
        if (_wantFull && widget.full != null && widget.full != widget.preview) _img(widget.full, fit: BoxFit.contain),
      ]),
    );
  }
}

// ─── Выбор кадров в подборку ──────────────────────────────────────────────────

class CollectionPickerScreen extends ConsumerStatefulWidget {
  final String id;
  const CollectionPickerScreen({super.key, required this.id});

  @override
  ConsumerState<CollectionPickerScreen> createState() => _CollectionPickerScreenState();
}

class _CollectionPickerScreenState extends ConsumerState<CollectionPickerScreen> {
  String? _source;
  final Set<String> _picked = {};
  bool _busy = false;

  List<({String id, String title})> _sources() {
    final mine = ref.watch(eventsProvider).valueOrNull ?? const [];
    final invited = ref.watch(invitedEventsProvider).valueOrNull ?? const [];
    return [
      for (final e in mine)
        if (e['status'] != 'draft' && e['status'] != 'cancelled' && (e['frames_count'] as int? ?? 0) > 0)
          (id: e['id'] as String, title: '${e['title']}${e['kind'] == 'solo' ? ' (соло)' : ''}'),
      for (final e in invited)
        if ((e['total_frames'] as int? ?? 0) > 0) (id: e['id'] as String, title: '${e['title']} · гость'),
    ];
  }

  Future<void> _add() async {
    if (_picked.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('collections/${widget.id}/items', data: {'frame_ids': _picked.toList()});
      ref.invalidate(collectionProvider(widget.id));
      ref.invalidate(collectionsProvider);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(extractUserMessage(e)),
        action: SnackBarAction(label: 'Плюс', onPressed: () => context.push('/plus')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = ref.watch(collectionProvider(widget.id)).valueOrNull;
    final sources = _sources();
    final active = _source ?? (sources.isNotEmpty ? sources.first.id : null);
    final already = <String>{for (final i in (col?['items'] as List? ?? const [])) (i as Map)['id'] as String};
    final limit = col?['frames_limit'] as int? ?? 0;
    final room = limit - already.length;
    final album = active == null ? null : ref.watch(albumFramesProvider(active));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(children: [
              _roundBtn(Icons.chevron_left, () => context.pop()),
              const SizedBox(width: 12),
              Expanded(child: Text('Выбрать кадры', style: _display(24))),
            ]),
          ),
          if (sources.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Пока нечего выбирать: когда в ваших альбомах появятся кадры, их можно будет собрать в подборку.',
                      textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 14, height: 1.5, color: AppColors.ink3)),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ChoiceChip(
                  label: Text(sources[i].title, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600,
                      color: active == sources[i].id ? AppColors.paper : AppColors.ink2)),
                  selected: active == sources[i].id,
                  showCheckmark: false,
                  selectedColor: AppColors.ink,
                  backgroundColor: AppColors.paper2,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _source = sources[i].id),
                ),
              ),
            ),
            Expanded(
              child: album == null
                  ? const SizedBox()
                  : album.when(
                      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
                      error: (e, _) => Center(child: Text(extractUserMessage(e))),
                      data: (a) {
                        final frames = (a['items'] as List).cast<Map>();
                        if (a['revealed'] == false) {
                          return Center(child: Text('Этот альбом ещё не открыт: кадры появятся после проявки.',
                              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink3)));
                        }
                        return GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
                          itemCount: frames.length,
                          itemBuilder: (_, i) {
                            final f = frames[i];
                            final id = f['id'] as String;
                            final taken = already.contains(id);
                            final on = _picked.contains(id);
                            return GestureDetector(
                              onTap: taken ? null : () => setState(() {
                                if (on) {
                                  _picked.remove(id);
                                } else if (_picked.length < room) {
                                  _picked.add(id);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('В подборке может быть до $limit кадров')));
                                }
                              }),
                              child: Stack(fit: StackFit.expand, children: [
                                Opacity(
                                  opacity: taken ? 0.4 : 1,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: _img((f['thumbnail_url'] ?? f['preview_url'] ?? f['full_url']) as String?),
                                  ),
                                ),
                                if (on)
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.amber, width: 3),
                                    ),
                                    alignment: Alignment.topRight,
                                    padding: const EdgeInsets.all(4),
                                    child: Container(
                                      width: 22, height: 22,
                                      decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                                      child: const Icon(Icons.check, size: 15, color: Colors.white),
                                    ),
                                  ),
                              ]),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: SizedBox(
              width: double.infinity, height: AppSizes.buttonHeight,
              child: ElevatedButton(
                onPressed: (_picked.isEmpty || _busy) ? null : _add,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_picked.isEmpty ? 'Выберите кадры' : 'Добавить ${_picked.length}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
