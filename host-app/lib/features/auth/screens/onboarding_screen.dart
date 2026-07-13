import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/tokens.dart';

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
              _OnbPage6(onSkip: _skip),
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
              fontFamily: 'JetBrains Mono',
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

  // Яркое событие с людьми, дневной свет — вместо тёмной ночной сцены.
  static const _photoUrlBright =
      'https://images.unsplash.com/photo-1519671482749-fd09be7ccebf'
      '?w=800&auto=format&fit=crop&q=80';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 1, onSkip: onSkip),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: _photoUrlBright,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (_, __) => Container(color: const Color(0xFFE5D8C0)),
                      errorWidget: (_, __, ___) => Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Color(0xFFF8ECD0), Color(0xFFD4A860)],
                          ),
                        ),
                      ),
                    ),
                    // Простой градиент снизу для читаемости названия/даты. Без плёночных эффектов.
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x66000000)],
                          stops: [0.55, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14, left: 14,
                      child: Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.shutter,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'ИДЁТ',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 14, left: 16,
                      child: Text(
                        'Свадьба Ани и Миши',
                        style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()], 
                          fontSize: 22,
                          color: AppColors.paper,
                          shadows: const [
                            Shadow(color: Color(0x80000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 14, right: 14,
                      child: Text(
                        '·12·07·26',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          letterSpacing: 1.0,
                          color: Color(0xD9FFD2AA),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _OnbCopy(
            title: 'Создайте альбом\nмероприятия',
            subtitle: 'Выберите дату, стиль и количество кадров. Гости снимают через QR — никаких приложений и аккаунтов',
          ),
          const SizedBox(height: 140),
        ],
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
                    child: const CustomPaint(painter: _QrPainter()),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'impomento.pro/g/qb47d7rt',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
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
                          caption: 'тост',
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
                  // Полароид card — front-center
                  Positioned(
                    top: 100, left: 8, right: 8,
                    child: Transform.rotate(
                      angle: -2 * math.pi / 180,
                      child: _AlbumCard(
                        label: 'ПОЛАРОИД',
                        dark: false,
                        polaroid: true,
                        child: _PolaroidPreview(
                          urlAnya: _p2,
                          urlToast: _p4,
                          urlMisha: _p5,
                        ),
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
                  fontFamily: 'JetBrains Mono',
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
              offsetX: -20,
            ),
          ),
          Transform.rotate(
            angle: 5 * math.pi / 180,
            child: _MiniPolCard(
              photoUrl: urlMisha,
              fallbackColors: const [Color(0xFFD4955F), Color(0xFF3A1810)],
              caption: 'Миша',
              offsetX: 20,
            ),
          ),
          Transform.rotate(
            angle: -1 * math.pi / 180,
            child: _MiniPolCard(
              photoUrl: urlToast,
              fallbackColors: const [Color(0xFFE8B888), Color(0xFF5A2810)],
              caption: 'тост',
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

  // Same base photo for all swatches — color matrix shows film difference
  static const _swatchBase =
      'https://images.unsplash.com/photo-1519741497674-611481863552'
      '?w=300&auto=format&fit=crop&q=80';

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
                          fontFamily: 'JetBrains Mono',
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

  // Fuji 400H — cool, desaturated, slight green-cyan push
  static const fuji400h = <double>[
    0.82, 0.02, 0.02, 0, 3,
    0.04, 0.88, 0.06, 0, 6,
    0.04, 0.04, 1.10, 0, 12,
    0, 0, 0, 1, 0,
  ];

  // Cinestill 800T — warm orange push, deep shadows, red halation
  static const cinestill800 = <double>[
    1.25, 0.08, 0.0, 0, 10,
    0.0, 0.82, 0.0, 0, 0,
    0.0, 0.0, 0.68, 0, -15,
    0, 0, 0, 1, 0,
  ];

  // Ilford HP5+ — classic luminance grayscale
  static const ilfordHp5 = <double>[
    0.299, 0.587, 0.114, 0, 0,
    0.299, 0.587, 0.114, 0, 0,
    0.299, 0.587, 0.114, 0, 0,
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
            // Grain texture
            CustomPaint(painter: _GrainPainter()),
            // Film label
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
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

  static const _p1 = 'https://images.unsplash.com/photo-1522673607200-164d1b6ce486?w=300&auto=format&fit=crop&q=80';
  static const _p2 = 'https://images.unsplash.com/photo-1469371670807-013ccf25f16a?w=300&auto=format&fit=crop&q=80';
  static const _p3 = 'https://images.unsplash.com/photo-1511285560929-fabc09f7c0d4?w=300&auto=format&fit=crop&q=80';
  static const _p4 = 'https://images.unsplash.com/photo-1519671482749-fd09be7ccebf?w=300&auto=format&fit=crop&q=80';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 6, onSkip: onSkip),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 340,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.paper2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top bar mock
                      Row(
                        children: [
                          const Text(
                            'КАДРЫ',
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono', fontSize: 11,
                              letterSpacing: 1.7, color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '4 альбома',
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono', fontSize: 10,
                                letterSpacing: 0.6, color: AppColors.amber,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Search bar mock
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.search, size: 16, color: AppColors.ink3),
                            SizedBox(width: 8),
                            Text(
                              'Найти альбом',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.ink4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Album mini-cards
                      _AlbumFrameRow(title: 'Свадьба Ани и Миши', meta: '2 дня назад · 82 кадра', photoUrl: _p1, status: 'ПРОЯВЛЕНО', statusColor: const Color(0xFF6A9269)),
                      const SizedBox(height: 8),
                      _AlbumFrameRow(title: 'Юбилей 30 лет', meta: 'сейчас · 24/45', photoUrl: _p2, status: 'ИДЁТ', statusColor: AppColors.shutter),
                      const SizedBox(height: 8),
                      _AlbumFrameRow(title: 'Корпоратив весной', meta: '15 марта · 156 кадров', photoUrl: _p3, status: 'ПРОЯВЛЕНО', statusColor: const Color(0xFF6A9269)),
                      const SizedBox(height: 8),
                      _AlbumFrameRow(title: 'День рождения Кати', meta: '18 июля · 0 гостей', photoUrl: _p4, status: 'ЧЕРНОВИК', statusColor: AppColors.ink3),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _OnbCopy(
            title: 'Раздел «Кадры»\nвсегда под рукой',
            subtitle: 'Все ваши альбомы — в одном месте. Поиск, фильтры, продление хранения',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

class _AlbumFrameRow extends StatelessWidget {
  final String title;
  final String meta;
  final String photoUrl;
  final String status;
  final Color statusColor;
  const _AlbumFrameRow({
    required this.title, required this.meta, required this.photoUrl,
    required this.status, required this.statusColor,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44, height: 44,
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => Container(color: const Color(0xFFE5D8C0)),
                errorWidget: (_, __, ___) => Container(color: const Color(0xFFD4A860)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(meta,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(status,
              style: TextStyle(
                fontFamily: 'JetBrains Mono', fontSize: 9,
                letterSpacing: 1.0, color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 7: Save memories (last slide) ──────────────────────────────────────

class _OnbPage6 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage6({required this.onSkip});

  static const _bgUrl =
      'https://images.unsplash.com/photo-1527529482837-4698179dc6ce'
      '?w=800&auto=format&fit=crop&q=80';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnbPager(step: 7, onSkip: onSkip),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Real photo background
                    CachedNetworkImage(
                      imageUrl: _bgUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0, 0.1),
                            radius: 1.1,
                            colors: [
                              Color(0xFFF5E4C4),
                              Color(0xFFD4A860),
                              Color(0xFF8A5828),
                              Color(0xFF3A2010),
                            ],
                            stops: [0.0, 0.4, 0.75, 1.0],
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0, 0.1),
                            radius: 1.1,
                            colors: [
                              Color(0xFFF5E4C4),
                              Color(0xFFD4A860),
                              Color(0xFF8A5828),
                              Color(0xFF3A2010),
                            ],
                            stops: [0.0, 0.4, 0.75, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Простой градиент снизу — только для читаемости copy.
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x55000000)],
                          stops: [0.6, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _OnbCopy(
            title: 'Важные\nвоспоминания',
            subtitle: 'Ваши гости снимают, вы получаете альбом. Просто, как одноразовая камера',
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
