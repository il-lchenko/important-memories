import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

const _guestBase = String.fromEnvironment('GUEST_PWA_URL', defaultValue: 'https://impomento.pro');

/// Открытая ссылка на альбом, соло-альбом или подборку: включить, отправить, копировать, обновить, отключить.
/// [base] — путь API без префикса: `events/<id>` или `collections/<id>`.
Future<void> showPublicLinkSheet(
  BuildContext context, {
  required String base,
  required String title,
  String? note,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _PublicLinkSheet(base: base, title: title, note: note),
  );
}

class _PublicLinkSheet extends ConsumerStatefulWidget {
  final String base;
  final String title;
  final String? note;
  const _PublicLinkSheet({required this.base, required this.title, this.note});

  @override
  ConsumerState<_PublicLinkSheet> createState() => _PublicLinkSheetState();
}

class _PublicLinkSheetState extends ConsumerState<_PublicLinkSheet> {
  String? _token;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(dioProvider).get('${widget.base}/public-share');
      if (!mounted) return;
      setState(() {
        _token = (r.data as Map)['public_share_token'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = extractUserMessage(e); _loading = false; });
    }
  }

  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioProvider);
      if (action == 'delete') {
        await dio.delete('${widget.base}/public-share');
        _token = null;
      } else {
        final r = await dio.post('${widget.base}/public-share/$action');
        _token = (r.data as Map)['public_share_token'] as String?;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(extractUserMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _url => _token == null ? null : '$_guestBase/a/$_token';

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.paper3, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('Поделиться ссылкой', style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.amber)))
          else if (_error != null)
            Text(_error!, style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink3))
          else if (url != null) ...[
            SelectableText(url, style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink, fontFeatures: [const FontFeature.tabularFigures()])),
            const SizedBox(height: 10),
            Text(widget.note ?? 'Любой, у кого есть ссылка, увидит кадры. Вы отвечаете за её распространение.',
                style: GoogleFonts.manrope(fontSize: 13, height: 1.45, color: AppColors.ink3)),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Share.share('${widget.title}\n$url', subject: widget.title),
                icon: const Icon(Icons.ios_share, size: 20),
                label: const Text('Отправить'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
                },
                icon: const Icon(Icons.copy_outlined, size: 20),
                label: const Text('Копировать'),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              TextButton(onPressed: _busy ? null : () => _act('regenerate'), child: const Text('Обновить ссылку')),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : () => _act('delete'),
                child: const Text('Отключить', style: TextStyle(color: AppColors.shutter)),
              ),
            ]),
          ] else ...[
            Text(
              'Ссылка выключена. Включив её, вы разрешаете просмотр всем, у кого она будет, и берёте на себя ответственность за её распространение.',
              style: GoogleFonts.manrope(fontSize: 13.5, height: 1.45, color: AppColors.ink3),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : () => _act('enable'),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Включить ссылку'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
