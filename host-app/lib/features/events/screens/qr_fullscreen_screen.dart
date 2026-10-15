import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../album/album_provider.dart';
import '../qr_style.dart';

class QrFullscreenScreen extends ConsumerStatefulWidget {
  final String eventId;
  const QrFullscreenScreen({super.key, required this.eventId});

  @override
  ConsumerState<QrFullscreenScreen> createState() => _QrFullscreenScreenState();
}

class _QrFullscreenScreenState extends ConsumerState<QrFullscreenScreen> {
  QrPreset _preset = QrPreset.classic;

  @override
  void initState() {
    super.initState();
    _loadPreset();
  }

  Future<void> _loadPreset() async {
    final dio = ref.read(dioProvider);
    String? server;
    try {
      final e = await ref.read(eventDetailProvider(widget.eventId).future);
      server = (e['settings'] as Map?)?['qr_style'] as String?;
    } catch (_) {}
    final p = await loadQrPreset(dio, widget.eventId, serverValue: server);
    if (mounted) setState(() => _preset = p);
  }

  Future<void> _pickStyle() async {
    final selected = await showModalBottomSheet<QrPreset>(
      context: context,
      backgroundColor: AppColors.dark2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _StylePickerSheet(current: _preset),
    );
    if (selected != null && selected != _preset) {
      final previous = _preset;
      setState(() => _preset = selected);
      try {
        await saveQrPreset(ref.read(dioProvider), widget.eventId, selected);
        ref.invalidate(eventDetailProvider(widget.eventId));
      } catch (_) {
        if (!mounted) return;
        setState(() => _preset = previous);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось сохранить стиль QR'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));
    final title = eventAsync.maybeWhen(
      data: (e) => (e['title'] ?? e['name'] ?? 'Событие') as String,
      orElse: () => '',
    );
    final shortCode = eventAsync.maybeWhen(
      data: (e) => e['short_code'] as String? ?? widget.eventId,
      orElse: () => widget.eventId,
    );
    const guestBase = String.fromEnvironment(
      'GUEST_PWA_URL',
      defaultValue: 'https://impomento.pro',
    );
    final joinUrlFull = '$guestBase/g/$shortCode';
    final joinUrl = joinUrlFull.replaceFirst(RegExp(r'https?://'), '');
    final style = kQrPresets[_preset]!;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(
          children: [
            // Top nav
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.close, color: AppColors.drText, size: 24),
                  ),
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      letterSpacing: 0.16,
                      color: AppColors.drAmber,
                    ),
                  ),
                  GestureDetector(
                    onTap: _pickStyle,
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.palette_outlined, color: AppColors.drAmber, size: 22),
                  ),
                ],
              ),
            ),

            // Core content
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()],
                      fontWeight: FontWeight.w500,
                      fontSize: 28,
                      letterSpacing: -0.01 * 28,
                      height: 1.1,
                      color: AppColors.drText,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR code
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 280,
                    height: 280,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: style.container,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: style.glow,
                          blurRadius: 60,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: joinUrlFull,
                      version: QrVersions.auto,
                      backgroundColor: style.canvas,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: style.modules,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: style.modules,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // URL pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x14FFB347),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x33FFB347)),
                    ),
                    child: Text(
                      joinUrl,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        letterSpacing: 0.04,
                        color: AppColors.drAmber,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Hint
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Отправьте QR-код или ссылку гостям.\nОткрыв страницу, они смогут сразу начать съёмку',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Color(0x8CF0E6D2),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              child: Row(
                children: [
                  Expanded(
                    child: _DarkButton(
                      icon: Icons.copy_outlined,
                      label: 'Скопировать',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: 'https://$joinUrl'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ссылка скопирована')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DarkButton(
                      icon: Icons.share_outlined,
                      label: 'Поделиться',
                      onTap: () => Share.share(
                        'Присоединяйся к «$title»!\n$joinUrlFull',
                        subject: title,
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

class _DarkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DarkButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0x14FFB347),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x33FFB347)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.drAmber, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.drAmber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StylePickerSheet extends StatelessWidget {
  final QrPreset current;
  const _StylePickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Стиль QR',
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                  color: AppColors.drText,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, size: 22, color: AppColors.drAmber),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: QrPreset.values.map((preset) {
              final style = kQrPresets[preset]!;
              final isSelected = preset == current;
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: style.container,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.drAmber : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: style.glow, blurRadius: 24, spreadRadius: -8)]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Мини-QR превью (упрощённый плашка-паттерн)
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: CustomPaint(
                            painter: _MiniQrPainter(
                              bg: style.canvas,
                              fg: style.modules,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        style.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: style.subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _MiniQrPainter extends CustomPainter {
  final Color bg;
  final Color fg;
  _MiniQrPainter({required this.bg, required this.fg});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = bg;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      paint,
    );

    final fgPaint = Paint()..color = fg;
    final cell = size.width / 11;
    // 3 угловых глаза (кроме правого-нижнего)
    void eye(double cx, double cy) {
      final outer = Rect.fromLTWH(cx * cell, cy * cell, 3 * cell, 3 * cell);
      canvas.drawRRect(
        RRect.fromRectAndRadius(outer, const Radius.circular(2)),
        fgPaint,
      );
      final inner = Rect.fromLTWH(
        (cx + 0.6) * cell, (cy + 0.6) * cell, 1.8 * cell, 1.8 * cell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.6)),
        Paint()..color = bg,
      );
      final dot = Rect.fromLTWH(
        (cx + 1) * cell, (cy + 1) * cell, cell, cell,
      );
      canvas.drawRect(dot, fgPaint);
    }
    eye(0.5, 0.5);
    eye(7.5, 0.5);
    eye(0.5, 7.5);

    // Псевдо-модули в центре (seed-независимый паттерн для визуального ощущения)
    const pattern = [
      [0, 1, 1, 0, 1],
      [1, 0, 1, 1, 0],
      [0, 1, 0, 1, 1],
      [1, 1, 1, 0, 1],
      [0, 1, 0, 1, 0],
    ];
    for (int y = 0; y < 5; y++) {
      for (int x = 0; x < 5; x++) {
        if (pattern[y][x] == 1) {
          canvas.drawRect(
            Rect.fromLTWH((3 + x) * cell, (3 + y) * cell, cell, cell),
            fgPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MiniQrPainter old) => old.bg != bg || old.fg != fg;
}
