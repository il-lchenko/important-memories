import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/tokens.dart';
import '../../../widgets/f_logo_animated.dart';

// Локальный shim вместо CachedNetworkImage: принимает тот же imageUrl (для читаемости),
// но грузит соответствующий файл из assets/onboarding/. Все Unsplash-фото прибиты
// к сборке, чтобы онбординг работал офлайн и мгновенно.
class CachedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Duration? fadeInDuration;
  const CachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration,
  });

  static String _resolveAsset(String url) {
    final m = RegExp(r'photo-([a-z0-9\-]+)').firstMatch(url);
    var id = m?.group(1) ?? '';
    // Оригинал 1511285560929-fabc09f7c0d4 удалён с Unsplash → замена.
    if (id == '1511285560929-fabc09f7c0d4') id = '1533174072545-7a4b6ad7a6c3';
    return 'assets/onboarding/photo-$id.jpg';
  }

  @override
  Widget build(BuildContext context) {
    final path = _resolveAsset(imageUrl);
    return Image.asset(
      path,
      fit: fit,
      filterQuality: FilterQuality.high,
      errorBuilder: errorWidget != null
          ? (ctx, err, _) => errorWidget!(ctx, imageUrl, err)
          : null,
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  static const _lastPage = 6;

  void _next() {
    if (_page < _lastPage) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _markDone().then((_) { if (mounted) context.go('/auth/email'); });
    }
  }

  void _skip() {
    _markDone().then((_) { if (mounted) context.go('/auth/email'); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: [
          PageView(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _OnbPage1(onSkip: _skip),
              _OnbPage2(onSkip: _skip),
              _OnbPage3(onSkip: _skip),
              _OnbPage4(onSkip: _skip),
              _OnbPage5(onSkip: _skip),
              _OnbPageFrames(onSkip: _skip),
              _OnbPage6(onSkip: _skip, isActive: _page == 6),
            ],
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _OnbFooter(page: _page, onNext: _next),
          ),
        ],
      ),
    );
  }
}

// ─── Pager row ────────────────────────────────────────────────────────────────

class _OnbPager extends StatelessWidget {
  final int step;
  final VoidCallback onSkip;
  const _OnbPager({required this.step, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${step.toString().padLeft(2, '0')} / 07',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              letterSpacing: 1.54,
              color: AppColors.ink3,
            ),
          ),
          if (step < 7)
            GestureDetector(
              onTap: onSkip,
              child: const Text(
                'Пропустить',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink3,
                ),
              ),
            )
          else
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}

// ─── Copy block ───────────────────────────────────────────────────────────────

class _OnbCopy extends StatelessWidget {
  final String title;
  final String subtitle;
  const _OnbCopy({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
              fontSize: 36,
              fontWeight: FontWeight.w500,
              height: 1.05,
              letterSpacing: -0.72,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              height: 1.5,
              color: AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Footer: dots + circle button ────────────────────────────────────────────

class _OnbFooter extends StatelessWidget {
  final int page;
  final VoidCallback onNext;
  const _OnbFooter({required this.page, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final isLast = page == 6;
    return Container(
      padding: EdgeInsets.fromLTRB(28, 24, 28, math.max(36.0, safeBottom + 16)),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F6F2E8), AppColors.paper, AppColors.paper],
          stops: [0.0, 0.25, 1.0],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: List.generate(7, (i) {
              final active = i == page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: i < 6 ? const EdgeInsets.only(right: 5) : EdgeInsets.zero,
                width: active ? 16 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: active ? AppColors.ink : const Color(0x2E1A1714),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              );
            }),
          ),
          GestureDetector(
            onTap: onNext,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.amber,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Icon(
                isLast ? Icons.check : Icons.arrow_forward,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 1: film hero ────────────────────────────────────────────────────────

class _OnbPage1 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage1({required this.onSkip});

  // Обложки для двух карточек — живые яркие фото с людьми и эмоциями.
  // Оба photo-id уже прибиты в assets/onboarding/ (CachedNetworkImage shim).
  static const _cover1 =
      'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800';
  static const _cover2 =
      'https://images.unsplash.com/photo-1541532713592-79a0317b6b77?w=800';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OnbPager(step: 1, onSkip: onSkip),
            const SizedBox(height: 8),
            // Заголовок раздела «Мои альбомы» ˅ + фильтр + поиск (как в реальном экране).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Мои альбомы',
                    style: GoogleFonts.playfairDisplay(
                      fontFeatures: [const FontFeature.liningFigures()],
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.6,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 20, color: AppColors.ink),
                  const Spacer(),
                  const Icon(Icons.tune, size: 18, color: AppColors.ink3),
                  const SizedBox(width: 14),
                  const Icon(Icons.search, size: 18, color: AppColors.ink3),
                ],
              ),
            ),
            // Список карточек альбомов — уменьшенный масштаб чтобы влезли обе + подпись.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: const [
                  _OnbAlbumCard(
                    coverUrl: _cover1,
                    status: _AlbumStatus.completed,
                    title: 'Летний фестиваль',
                    guests: 18,
                    frames: 124,
                    date: '16.07.2026',
                  ),
                  SizedBox(height: 10),
                  _OnbAlbumCard(
                    coverUrl: _cover2,
                    status: _AlbumStatus.active,
                    title: 'Ночь пятницы',
                    guests: 12,
                    frames: 47,
                    date: '05.07.2026',
                  ),
                ],
              ),
            ),
            _OnbCopy(
              title: 'Создайте альбом\nмероприятия',
              subtitle: 'Выберите дату, стиль и количество кадров. Гости снимают через QR — никаких приложений и аккаунтов',
            ),
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }
}

enum _AlbumStatus { completed, active, draft }

class _OnbAlbumCard extends StatelessWidget {
  final String coverUrl;
  final _AlbumStatus status;
  final String title;
  final int guests;
  final int frames;
  final String date;

  const _OnbAlbumCard({
    required this.coverUrl,
    required this.status,
    required this.title,
    required this.guests,
    required this.frames,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final (dotColor, dotGlow, badgeLabel) = switch (status) {
      _AlbumStatus.completed => (const Color(0xFF5BAA72), true, 'ПРОЯВЛЕНО'),
      _AlbumStatus.active => (const Color(0xFFC9881E), true, 'ЗАПИСЬ'),
      _AlbumStatus.draft => (AppColors.ink3, false, 'ЧЕРНОВИК'),
    };

    return AspectRatio(
      aspectRatio: 2.0, // ~170h при ширине ~340 — обе карточки + подпись влезают
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1E1A1714)),
          boxShadow: const [
            BoxShadow(color: Color(0x0D1A1714), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                errorWidget: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4A3828), Color(0xFF2A1810), Color(0xFF100806)],
                    ),
                  ),
                ),
              ),
              // Тёмный градиент снизу.
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
              // Бейдж статуса.
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
                      Text(
                        badgeLabel,
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
              // Название + метрики.
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
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 15, color: Color(0xFFB0A080)),
                        const SizedBox(width: 4),
                        Text('$guests',
                          style: GoogleFonts.manrope(fontSize: 13, color: const Color(0xFFB0A080), fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        const Icon(Icons.camera_roll_outlined, size: 15, color: Color(0xFFC9881E)),
                        const SizedBox(width: 4),
                        Text('$frames',
                          style: GoogleFonts.manrope(fontSize: 13, color: const Color(0xFFC9881E), fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFFB0A080)),
                        const SizedBox(width: 4),
                        Text(date,
                          style: GoogleFonts.manrope(fontSize: 13, color: const Color(0xFFB0A080), fontWeight: FontWeight.w600)),
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

// ─── Page 2: QR ───────────────────────────────────────────────────────────────

class _OnbPage2 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage2({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 2, onSkip: onSkip),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.paper2,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 220, height: 220,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: 'https://impomento.pro/g/anya-misha',
                      version: QrVersions.auto,
                      backgroundColor: AppColors.paper,
                      foregroundColor: AppColors.ink,
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.ink,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.ink,
                      ),
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'impomento.pro/g/anya-misha',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      letterSpacing: 1.32,
                      color: AppColors.ink3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          _OnbCopy(
            title: 'QR-код — доступ\nко всему',
            subtitle: 'Гостям не нужно ничего скачивать — только открыть ссылку',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

// ─── Page 3: Polaroid stack ───────────────────────────────────────────────────

class _OnbPage3 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage3({required this.onSkip});

  static const _url1 = 'https://images.unsplash.com/photo-1522673607200-164d1b6ce486'
      '?w=400&auto=format&fit=crop&q=80';
  static const _url2 = 'https://images.unsplash.com/photo-1469371670807-013ccf25f16a'
      '?w=400&auto=format&fit=crop&q=80';
  static const _url3 = 'https://images.unsplash.com/photo-1511285560929-fabc09f7c0d4'
      '?w=400&auto=format&fit=crop&q=80';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 3, onSkip: onSkip),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 360,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 30, left: 20,
                    child: Transform.rotate(
                      angle: -7 * math.pi / 180,
                      child: _PolCard(
                        photoUrl: _url1,
                        colors: const [Color(0xFFF0C896), Color(0xFFC97E4A), Color(0xFF5A2A14)],
                        caption: 'Аня',
                        leakTl: true,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 70, right: 20,
                    child: Transform.rotate(
                      angle: 6 * math.pi / 180,
                      child: _PolCard(
                        photoUrl: _url2,
                        colors: const [Color(0xFFD4955F), Color(0xFF8C4A28), Color(0xFF2A1810)],
                        caption: 'первый танец',
                        leakBr: true,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 150, left: 0, right: 0,
                    child: Center(
                      child: Transform.rotate(
                        angle: -2 * math.pi / 180,
                        child: _PolCard(
                          photoUrl: _url3,
                          colors: const [Color(0xFFE8B888), Color(0xFFA06030), Color(0xFF2A1408)],
                          caption: '',
                          leakTl: true,
                          leakBr: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _OnbCopy(
            title: 'Плёнки проявятся\nодновременно',
            subtitle: 'Альбом станет доступен всем одновременно — в выбранное вами время. Вспоминайте праздник вместе!',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

// ─── Polaroid card ────────────────────────────────────────────────────────────

class _PolCard extends StatelessWidget {
  final String? photoUrl;
  final List<Color> colors;
  final String caption;
  final bool leakTl;
  final bool leakBr;

  const _PolCard({
    required this.colors,
    required this.caption,
    this.photoUrl,
    this.leakTl = false,
    this.leakBr = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x338A6914),
            blurRadius: 20,
            offset: Offset(0, 8),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Color(0x1A1A1714),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (photoUrl != null)
                          CachedNetworkImage(
                            imageUrl: photoUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, -0.2),
                                  radius: 1.2,
                                  colors: colors,
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, -0.2),
                                  radius: 1.2,
                                  colors: colors,
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -0.2),
                                radius: 1.2,
                                colors: colors,
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
          Positioned(
            bottom: 8, left: 0, right: 0,
            child: Center(
              child: Text(
                caption,
                style: const TextStyle(
                  fontFamily: 'Caveat',
                  fontSize: 18,
                  color: AppColors.ink2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 4: Album modes (fan of cards) ──────────────────────────────────────

class _OnbPage4 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage4({required this.onSkip});

  // Verified Unsplash photos reused throughout for journal/retro grids
  static const _p1 = 'https://images.unsplash.com/photo-1519741497674-611481863552?w=300&auto=format&fit=crop&q=80';
  static const _p2 = 'https://images.unsplash.com/photo-1522673607200-164d1b6ce486?w=300&auto=format&fit=crop&q=80';
  static const _p3 = 'https://images.unsplash.com/photo-1469371670807-013ccf25f16a?w=300&auto=format&fit=crop&q=80';
  static const _p4 = 'https://images.unsplash.com/photo-1511285560929-fabc09f7c0d4?w=300&auto=format&fit=crop&q=80';
  static const _p5 = 'https://images.unsplash.com/photo-1464207687429-7505649dae38?w=300&auto=format&fit=crop&q=80';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 4, onSkip: onSkip),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 360,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Журнал card — light, back-left
                  Positioned(
                    top: 20, left: 0, right: 30,
                    child: Transform.rotate(
                      angle: -6 * math.pi / 180,
                      child: _AlbumCard(
                        label: 'ЖУРНАЛ',
                        dark: false,
                        child: _JournalPreview(
                          urls: [_p2, _p3, _p4, _p1, _p5, _p2],
                        ),
                      ),
                    ),
                  ),
                  // Ретро card — dark, back-right
                  Positioned(
                    top: 55, left: 30, right: 0,
                    child: Transform.rotate(
                      angle: 5 * math.pi / 180,
                      child: _AlbumCard(
                        label: 'РЕТРО',
                        dark: true,
                        child: _RetroPreview(
                          urls: [_p1, _p5, _p3, _p4],
                        ),
                      ),
                    ),
                  ),
                  // ПОЛАРОИД — 3 больших полароида без карточки-контейнера,
                  // прямо на фоне страницы (чтобы не было «пустого квадрата» сзади).
                  Positioned(
                    top: 100, left: 0, right: 0,
                    child: SizedBox(
                      height: 220,
                      child: _PolaroidPreview(
                        urlAnya: _p2,
                        urlToast: _p4,
                        urlMisha: _p5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _OnbCopy(
            title: 'Несколько режимов\nпросмотра',
            subtitle: 'Ретро-стиль, журнал или легендарный Polaroid — выбирайте под настроение',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final String label;
  final bool dark;
  final bool polaroid;
  final Widget child;
  const _AlbumCard({
    required this.label,
    required this.child,
    this.dark = false,
    this.polaroid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1510) : (polaroid ? const Color(0xFFEDE8DF) : AppColors.paper2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -6),
          BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              bottom: 12, left: 16,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  letterSpacing: 1.6,
                  color: dark ? const Color(0x99FFD2AA) : AppColors.ink3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalPreview extends StatelessWidget {
  final List<String> urls;
  const _JournalPreview({required this.urls});

  static const _fallback = [
    [Color(0xFFF3CDA0), Color(0xFFB07840)],
    [Color(0xFFD4955F), Color(0xFF6A3A20)],
    [Color(0xFFE8B888), Color(0xFF8A5030)],
    [Color(0xFFC97E4A), Color(0xFF4A2010)],
    [Color(0xFFF0C896), Color(0xFF9A5A28)],
    [Color(0xFFD4A870), Color(0xFF5A2818)],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 36),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: false,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 3 / 4,
        ),
        itemCount: 6,
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: CachedNetworkImage(
            imageUrl: urls[i],
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            placeholder: (_, __) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _fallback[i],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _fallback[i],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetroPreview extends StatelessWidget {
  final List<String> urls;
  const _RetroPreview({required this.urls});

  static const _fallback = [
    [Color(0xFFC97E4A), Color(0xFF3A1208)],
    [Color(0xFFF0C896), Color(0xFF8A4428)],
    [Color(0xFFE8B888), Color(0xFF4A2010)],
    [Color(0xFF805030), Color(0xFF1A0A04)],
  ];

  @override
  Widget build(BuildContext context) {
    Widget cell(int i) => Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: urls[i],
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              placeholder: (_, __) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _fallback[i],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _fallback[i],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 36),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [cell(0), const SizedBox(width: 4), cell(1)],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [cell(2), const SizedBox(width: 4), cell(3)],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolaroidPreview extends StatelessWidget {
  final String urlAnya;
  final String urlToast;
  final String urlMisha;
  const _PolaroidPreview({
    required this.urlAnya,
    required this.urlToast,
    required this.urlMisha,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -7 * math.pi / 180,
            child: _MiniPolCard(
              photoUrl: urlAnya,
              fallbackColors: const [Color(0xFFF3CDA0), Color(0xFF6A3520)],
              caption: 'Аня',
              offsetX: -60,
            ),
          ),
          Transform.rotate(
            angle: 5 * math.pi / 180,
            child: _MiniPolCard(
              photoUrl: urlMisha,
              fallbackColors: const [Color(0xFFD4955F), Color(0xFF3A1810)],
              caption: 'Миша',
              offsetX: 60,
            ),
          ),
          Transform.rotate(
            angle: -1 * math.pi / 180,
            child: _MiniPolCard(
              photoUrl: urlToast,
              fallbackColors: const [Color(0xFFE8B888), Color(0xFF5A2810)],
              caption: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPolCard extends StatelessWidget {
  final String? photoUrl;
  final List<Color> fallbackColors;
  final String caption;
  final double offsetX;
  const _MiniPolCard({
    required this.fallbackColors,
    required this.caption,
    this.photoUrl,
    this.offsetX = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(offsetX, 0),
      child: Container(
        width: 90,
        padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.all(Radius.circular(2)),
          boxShadow: [
            BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: photoUrl!,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        placeholder: (_, __) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: fallbackColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: fallbackColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: fallbackColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
              ),
            ),
            SizedBox(
              height: 22,
              child: Center(
                child: Text(
                  caption,
                  style: GoogleFonts.caveat(fontSize: 14, color: AppColors.ink2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page 5: Film styles ──────────────────────────────────────────────────────

class _OnbPage5 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage5({required this.onSkip});

  static const _heroUrl =
      'https://images.unsplash.com/photo-1464207687429-7505649dae38'
      '?w=800&auto=format&fit=crop&q=80';

  // Same base photo for all swatches — тот же кадр что и в hero, чтобы фильтр
  // сразу читался. Фото 173KB (не пережато агрессивно) → нет JPEG-блоков.
  static const _swatchBase =
      'https://images.unsplash.com/photo-1464207687429-7505649dae38'
      '?w=600&auto=format&fit=crop&q=85';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 5, onSkip: onSkip),
          const SizedBox(height: 16),
          // Main hero: real film photo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: _heroUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (_, __) => Container(color: const Color(0xFFE5D8C0)),
                      errorWidget: (_, __, ___) => Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Color(0xFFF8ECD0), Color(0xFFC98A5A)],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x55000000)],
                          stops: [0.55, 1.0],
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 14, left: 16,
                      child: Text(
                        'KODAK PORTRA 400',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          letterSpacing: 1.4,
                          color: Color(0xCCFFD2AA),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Row of 4 film swatches with real photos + colour matrix
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _FilmSwatch(
                  label: 'Оригинал',
                  photoUrl: _swatchBase,
                  fallbackTop: const Color(0xFFF8F5F0),
                  fallbackBot: const Color(0xFF8A7D6A),
                  matrix: _FilmSwatch.identity,
                )),
                const SizedBox(width: 8),
                Expanded(child: _FilmSwatch(
                  label: 'Fuji',
                  photoUrl: _swatchBase,
                  fallbackTop: const Color(0xFFC8E0C0),
                  fallbackBot: const Color(0xFF1A3020),
                  matrix: _FilmSwatch.fuji400h,
                )),
                const SizedBox(width: 8),
                Expanded(child: _FilmSwatch(
                  label: 'Cinestill',
                  photoUrl: _swatchBase,
                  fallbackTop: const Color(0xFF301020),
                  fallbackBot: const Color(0xFFF04060),
                  matrix: _FilmSwatch.cinestill800,
                  dark: true,
                )),
                const SizedBox(width: 8),
                Expanded(child: _FilmSwatch(
                  label: 'Ilford',
                  photoUrl: _swatchBase,
                  fallbackTop: const Color(0xFFB0A8A0),
                  fallbackBot: const Color(0xFF101010),
                  matrix: _FilmSwatch.ilfordHp5,
                )),
              ],
            ),
          ),
          _OnbCopy(
            title: 'Разные виды\nплёнок',
            subtitle: 'Portra, Fuji, Cinestill или ч/б — один фильтр для всех снимков',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

class _FilmSwatch extends StatelessWidget {
  final String label;
  final String? photoUrl;
  final Color fallbackTop;
  final Color fallbackBot;
  final List<double> matrix;
  final bool dark;

  const _FilmSwatch({
    required this.label,
    required this.fallbackTop,
    required this.fallbackBot,
    required this.matrix,
    this.photoUrl,
    this.dark = false,
  });

  // Identity — no change
  static const identity = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // Fuji 400H — прохладнее, чуть менее насыщенно (без агрессивных offset,
  // которые давали заметный узор «крапинок» на JPEG-исходнике)
  static const fuji400h = <double>[
    0.92, 0.02, 0.02, 0, 0,
    0.02, 0.95, 0.03, 0, 0,
    0.03, 0.03, 1.05, 0, 4,
    0, 0, 0, 1, 0,
  ];

  // Cinestill 800T — тёплый оранжевый оттенок, но мягкий (без -15 в синем,
  // которое давало разрывы уровней в тенях и «пятна»)
  static const cinestill800 = <double>[
    1.12, 0.05, 0.0, 0, 4,
    0.0, 0.9, 0.02, 0, 0,
    0.0, 0.0, 0.82, 0, -4,
    0, 0, 0, 1, 0,
  ];

  // Ilford HP5+ — плавный grayscale через 50% mix (чистая luminance даёт
  // JPEG-блоки крупными пятнами на маленьком swatch)
  static const ilfordHp5 = <double>[
    0.65, 0.25, 0.10, 0, 0,
    0.25, 0.65, 0.10, 0, 0,
    0.25, 0.25, 0.50, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 80,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base: gradient fallback always shown under photo
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fallbackTop, fallbackBot],
                ),
              ),
            ),
            // Real photo with colour matrix filter
            if (photoUrl != null)
              ColorFiltered(
                colorFilter: ColorFilter.matrix(matrix),
                child: CachedNetworkImage(
                  imageUrl: photoUrl!,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  placeholder: (_, __) => const SizedBox.shrink(),
                ),
              ),
            // Film label
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 8,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: dark ? const Color(0xCCFFD2AA) : const Color(0xCCFFFFFF),
                  shadows: const [
                    Shadow(color: Color(0x80000000), blurRadius: 4),
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

// ─── Page 6: Все альбомы в разделе «Кадры» ───────────────────────────────────

class _OnbPageFrames extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPageFrames({required this.onSkip});

  // Свадьба «Аня и Миша» — 3 фото для _CollageA (1 big + 2 small).
  static const _wed1 = 'https://images.unsplash.com/photo-1519741497674-611481863552?w=600';
  static const _wed2 = 'https://images.unsplash.com/photo-1465495976277-4387d4b0b4c6?w=400';
  static const _wed3 = 'https://images.unsplash.com/photo-1525258946800-98cfd641d0de?w=400';

  // Концерт «Летний фест» — 4 фото для _TiltedStrip.
  static const _concert1 = 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=300';
  static const _concert2 = 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=300';
  static const _concert3 = 'https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=300';
  static const _concert4 = 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.paper2,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OnbPager(step: 6, onSkip: onSkip),
            const SizedBox(height: 8),
            // Шапка «Кадры» — реплика шапки MemoriesScreen 1:1
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Кадры',
                      style: GoogleFonts.playfairDisplay(
                        fontFeatures: [const FontFeature.liningFigures()],
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                        letterSpacing: -0.7,
                        height: 1.05,
                      ),
                    ),
                  ),
                  // Иконка фильтра (декоративная в онбординге, не кликается)
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    child: const Icon(Icons.tune, size: 22, color: AppColors.ink2),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    child: const Icon(Icons.search, size: 24, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            // Скролл со списком блоков
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Блок 1 — collage_a (свадьба: 1 big + 2 small)
                    const _OnbMemoryBlock(
                      eventType: 'СВАДЬБА',
                      title: 'Аня и Миша',
                      date: '25 июня',
                      child: _OnbCollageA(
                        big: _wed1,
                        small1: _wed2,
                        small2: _wed3,
                      ),
                    ),
                    // Блок 2 — tilted (концерт: 4 полароидные наклонённые)
                    const _OnbMemoryBlock(
                      eventType: 'КОНЦЕРТ',
                      title: 'Летний фест',
                      date: '12 июля',
                      child: _OnbTiltedStrip(
                        photos: [_concert1, _concert2, _concert3, _concert4],
                      ),
                    ),
                    _OnbCopy(
                      title: 'Раздел «Кадры»\nвсегда под рукой',
                      subtitle: 'Все ваши альбомы — в одном месте. Поиск, фильтры, продление хранения',
                    ),
                    const SizedBox(height: 130),
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

/// Обёртка секции — воспроизводит `MemoryBlockWidget` из memory_blocks.dart:
/// padding 18/18/18/22, header (eventType амбер + title серифом + date справа), gap 12, потом блок.
class _OnbMemoryBlock extends StatelessWidget {
  final String eventType;
  final String title;
  final String date;
  final Widget child;

  const _OnbMemoryBlock({
    required this.eventType,
    required this.title,
    required this.date,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (matches _MemoryHeader из memory_blocks.dart)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              eventType,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.amber,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    fontFeatures: [const FontFeature.liningFigures()],
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    letterSpacing: -0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                date,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Воспроизводит `_CollageA`: Row([big flex2, gap4, Column([small1, gap4, small2]) flex1]).
class _OnbCollageA extends StatelessWidget {
  final String big;
  final String small1;
  final String small2;

  const _OnbCollageA({required this.big, required this.small1, required this.small2});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(flex: 2, child: _tile(big)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _tile(small1)),
                    const SizedBox(height: 4),
                    Expanded(child: _tile(small2)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Дот-пагинация (первая точка активна) — как в реальных карусельных блоках.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dot(true),
            const SizedBox(width: 6),
            _dot(false),
            const SizedBox(width: 6),
            _dot(false),
          ],
        ),
      ],
    );
  }

  Widget _tile(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  Widget _dot(bool active) {
    return Container(
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? AppColors.amber : AppColors.ink4.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Воспроизводит `_TiltedStrip`: горизонтальная лента полароидных карточек
/// 92×116 с наклонами `[-3, 1.4, -1, 2.6]°` и y-offset `[-2, 3, -3, 2]`, overlap -8px.
class _OnbTiltedStrip extends StatelessWidget {
  final List<String> photos;
  const _OnbTiltedStrip({required this.photos});

  static const _rotations = [-3.0, 1.4, -1.0, 2.6];
  static const _yOffsets = [-2.0, 3.0, -3.0, 2.0];
  static const _cardWidth = 92.0;
  static const _cardHeight = 116.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: photos.length,
        itemBuilder: (ctx, i) {
          return Transform.translate(
            offset: Offset(i == 0 ? 0 : -8.0, _yOffsets[i % 4]),
            child: Transform.rotate(
              angle: _rotations[i % 4] * math.pi / 180,
              child: Container(
                width: _cardWidth,
                height: _cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.5),
                ),
                clipBehavior: Clip.hardEdge,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: photos[i],
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 200),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


// ─── Page 7: F-логотип с реальной анимацией из logo-anim-F.html ──────────────

class _OnbPage6 extends StatefulWidget {
  final VoidCallback onSkip;
  final bool isActive;
  const _OnbPage6({required this.onSkip, required this.isActive});

  @override
  State<_OnbPage6> createState() => _OnbPage6State();
}

class _OnbPage6State extends State<_OnbPage6> {
  // Пересборка FLogoAnimated по этому ключу перезапускает анимацию с 0
  // каждый раз, когда пользователь долистывает до 7-го экрана.
  Key _logoKey = UniqueKey();
  bool _hasBeenActive = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _hasBeenActive = true;
    }
  }

  @override
  void didUpdateWidget(covariant _OnbPage6 old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      // Дошли до 7 экрана — стартуем анимацию с самого начала.
      setState(() {
        _hasBeenActive = true;
        _logoKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 7, onSkip: widget.onSkip),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 340,
              child: Center(
                // FLogoAnimated монтируется только когда страница фактически видима
                // (иначе PageView pre-cache запустил бы анимацию заранее, и
                // пользователь увидел бы её с середины).
                child: _hasBeenActive
                    ? FLogoAnimated(key: _logoKey, size: 240, isDark: false, loop: false)
                    : const SizedBox(width: 240, height: 240),
              ),
            ),
          ),
          _OnbCopy(
            title: 'Готовы\nначать?',
            subtitle: 'Одна камера · один альбом · много воспоминаний. Пора запечатлеть свой момент',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

// ─── Film grain overlay ───────────────────────────────────────────────────────

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x5AB08040)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 220; i++) {
      final x = (math.sin(i * 2.731 + 0.3) * 0.5 + 0.5) * size.width;
      final y = (math.cos(i * 1.913 + 1.1) * 0.5 + 0.5) * size.height;
      final r = (math.sin(i * 5.137) * 0.5 + 0.5) * 1.6 + 0.2;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Decorative QR ────────────────────────────────────────────────────────────

class _QrPainter extends CustomPainter {
  const _QrPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final inkP = Paint()..color = AppColors.ink;
    final paperP = Paint()..color = AppColors.paper;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), inkP);

    final cell = w / 21;
    const dataZone = [
      [0,1,0,1,1,0,1,0,0,1,0,1,0,0,1,0,1,1,0,1,0],
      [1,0,1,0,0,1,0,1,0,0,1,0,1,0,0,1,0,0,1,0,1],
      [0,1,0,1,0,1,1,0,1,0,1,1,0,1,0,1,0,1,0,1,0],
      [1,0,1,0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,1,0,1],
      [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      [1,0,1,1,0,1,0,1,0,0,1,0,1,1,0,1,0,1,1,0,1],
      [0,1,0,0,1,0,1,0,1,0,0,1,0,0,1,0,1,0,0,1,0],
      [1,0,1,0,0,1,0,0,1,0,1,0,0,1,0,1,0,0,1,0,1],
      [0,1,0,1,0,0,1,0,0,1,0,0,1,0,1,0,1,0,0,1,0],
      [1,0,0,1,1,0,0,1,0,1,0,1,0,0,0,1,0,1,0,0,1],
      [0,1,0,0,0,1,0,0,1,0,1,0,0,1,0,0,1,0,1,0,0],
      [1,0,1,0,1,0,1,0,0,0,1,0,1,0,0,1,0,1,0,1,0],
      [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
      [0,1,0,1,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1],
      [1,0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0],
    ];
    for (int row = 0; row < dataZone.length; row++) {
      for (int col = 0; col < dataZone[row].length; col++) {
        if (dataZone[row][col] == 0) {
          canvas.drawRect(
            Rect.fromLTWH(col * cell, row * cell, cell, cell),
            paperP,
          );
        }
      }
    }

    _finder(canvas, 0, 0, cell, inkP, paperP);
    _finder(canvas, (21 - 7) * cell, 0, cell, inkP, paperP);
    _finder(canvas, 0, (21 - 7) * cell, cell, inkP, paperP);

    final cx = w / 2;
    final cy = h / 2;
    canvas.drawCircle(Offset(cx, cy), cell * 2.0, paperP);
    canvas.drawCircle(Offset(cx, cy), cell * 1.3, inkP);
    canvas.drawCircle(Offset(cx, cy), cell * 0.5, Paint()..color = AppColors.amber);
  }

  void _finder(Canvas canvas, double x, double y, double c, Paint ink, Paint paper) {
    canvas.drawRect(Rect.fromLTWH(x, y, 7 * c, 7 * c), ink);
    canvas.drawRect(Rect.fromLTWH(x + c, y + c, 5 * c, 5 * c), paper);
    canvas.drawRect(Rect.fromLTWH(x + 2 * c, y + 2 * c, 3 * c, 3 * c), ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
