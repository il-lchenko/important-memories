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

  void _next() {
    if (_page < 5) {
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
            '${step.toString().padLeft(2, '0')} / 06',
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              letterSpacing: 1.54,
              color: AppColors.ink3,
            ),
          ),
          if (step < 6)
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
            style: GoogleFonts.playfairDisplay(
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
    final isLast = page == 5;
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
          // Left: dots + label
          Row(
            children: List.generate(6, (i) {
              final active = i == page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: i < 5 ? const EdgeInsets.only(right: 5) : EdgeInsets.zero,
                width: active ? 16 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: active ? AppColors.ink : const Color(0x2E1A1714),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              );
            }),
          ),
          // Right: circle arrow button
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

  static const _photoUrl =
      'https://images.unsplash.com/photo-1519741497674-611481863552'
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
                    // Real photo
                    CachedNetworkImage(
                      imageUrl: _photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF4A2A14),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            colors: [Color(0xFFF3CDA0), Color(0xFF6A3520)],
                          ),
                        ),
                      ),
                    ),
                    // Portra warm colour grade
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x33F0A040), Colors.transparent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    // Film leak TL (amber)
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-1.4, -1.4),
                          radius: 1.2,
                          colors: [Color(0x55FFB347), Colors.transparent],
                          stops: [0.0, 0.55],
                        ),
                      ),
                    ),
                    // Vignette
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.1,
                          colors: [Colors.transparent, Color(0xA0000000)],
                          stops: [0.4, 1.0],
                        ),
                      ),
                    ),
                    // Film grain
                    const _GrainOverlay(),
                    // "ИДЁТ" badge top-left
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
                    // Event name stamp bottom-left
                    Positioned(
                      bottom: 14, left: 16,
                      child: Text(
                        'Свадьба Ани и Миши',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          color: AppColors.paper,
                          shadows: const [
                            Shadow(color: Color(0x80000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ),
                    // Date stamp bottom-right
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
            subtitle: 'Выберите дату, стиль и количество кадров. Гости снимают через QR — никаких приложений и аккаунтов.',
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
          // QR card: paper-2 bg, radius 24, padding 20
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
                  // QR box: paper bg, radius 16, padding 14
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
                    'im.app/g/qb47d7rt',
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
            subtitle: 'Гостям не нужно ничего скачивать — только открыть ссылку.',
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
                        // Real photo or gradient fallback
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
                        if (leakTl)
                          Container(
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(-1.4, -1.4),
                                radius: 1.2,
                                colors: [Color(0x55FFB347), Colors.transparent],
                                stops: [0.0, 0.55],
                              ),
                            ),
                          ),
                        if (leakBr)
                          Container(
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(1.4, 1.4),
                                radius: 1.2,
                                colors: [Color(0x55D54B3D), Colors.transparent],
                                stops: [0.0, 0.52],
                              ),
                            ),
                          ),
                        // Warm tone grade
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0x22F0A040), Colors.transparent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        // Vignette
                        Container(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              radius: 1.0,
                              colors: [Colors.transparent, Color(0x66000000)],
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
                        child: _JournalPreview(),
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
                        child: _RetroPreview(),
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
                        child: _PolaroidPreview(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _OnbCopy(
            title: 'Несколько режимов\nпросмотра',
            subtitle: 'Ретро-стиль, журнал или легендарный Polaroid — выбирайте под настроение.',
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
            if (dark) CustomPaint(painter: _GrainPainter()),
            Positioned(
              bottom: 12, left: 16,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  letterSpacing: 1.6,
                  color: dark ? AppColors.ink3 : AppColors.ink3,
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
  const _JournalPreview();

  @override
  Widget build(BuildContext context) {
    const scenes = [
      [Color(0xFFF3CDA0), Color(0xFFB07840)],
      [Color(0xFFD4955F), Color(0xFF6A3A20)],
      [Color(0xFFE8B888), Color(0xFF8A5030)],
      [Color(0xFFC97E4A), Color(0xFF4A2010)],
      [Color(0xFFF0C896), Color(0xFF9A5A28)],
      [Color(0xFFD4A870), Color(0xFF5A2818)],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: false,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 5,
          mainAxisSpacing: 5,
          childAspectRatio: 3 / 4,
        ),
        itemCount: 6,
        itemBuilder: (_, i) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: scenes[i],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
    );
  }
}

class _RetroPreview extends StatelessWidget {
  const _RetroPreview();

  @override
  Widget build(BuildContext context) {
    const scenes = [
      [Color(0xFFC97E4A), Color(0xFF3A1208)],
      [Color(0xFFF0C896), Color(0xFF8A4428)],
      [Color(0xFFE8B888), Color(0xFF4A2010)],
      [Color(0xFF805030), Color(0xFF1A0A04)],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                for (int i = 0; i < 2; i++) ...[
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: scenes[i],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  if (i == 0) const SizedBox(width: 5),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              children: [
                for (int i = 2; i < 4; i++) ...[
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: scenes[i],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  if (i == 2) const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolaroidPreview extends StatelessWidget {
  const _PolaroidPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -7 * math.pi / 180,
            child: _MiniPolCard(
              colors: const [Color(0xFFF3CDA0), Color(0xFF6A3520)],
              caption: 'Аня',
              offsetX: -20,
            ),
          ),
          Transform.rotate(
            angle: 5 * math.pi / 180,
            child: _MiniPolCard(
              colors: const [Color(0xFFD4955F), Color(0xFF3A1810)],
              caption: 'тост',
              offsetX: 20,
            ),
          ),
          Transform.rotate(
            angle: -1 * math.pi / 180,
            child: _MiniPolCard(
              colors: const [Color(0xFFE8B888), Color(0xFF5A2810)],
              caption: 'Миша',
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPolCard extends StatelessWidget {
  final List<Color> colors;
  final String caption;
  final double offsetX;
  const _MiniPolCard({required this.colors, required this.caption, this.offsetX = 0});

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
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
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

  static const _films = [
    {'label': 'Без фильтра',    'top': Color(0xFFF8F5F0), 'bot': Color(0xFF8A7D6A)},
    {'label': 'Kodak Portra',  'top': Color(0xFFF0D4A0), 'bot': Color(0xFF5A2A0A)},
    {'label': 'Fuji 400H',     'top': Color(0xFFC8E0C0), 'bot': Color(0xFF1A3020)},
    {'label': 'Cinestill 800', 'top': Color(0xFF301020), 'bot': Color(0xFFF04060)},
    {'label': 'Ilford HP5+',   'top': Color(0xFFB0A8A0), 'bot': Color(0xFF101010)},
  ];

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
                      placeholder: (_, __) => Container(color: const Color(0xFF2A1408)),
                      errorWidget: (_, __, ___) => Container(
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            colors: [Color(0xFFF3CDA0), Color(0xFF1F1208)],
                          ),
                        ),
                      ),
                    ),
                    // Portra warm grade
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x33F0A840), Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    const _GrainOverlay(),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-1.4, -1.4), radius: 1.2,
                          colors: [Color(0x55FFB347), Colors.transparent],
                          stops: [0.0, 0.55],
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.1,
                          colors: [Colors.transparent, Color(0x8C000000)],
                          stops: [0.4, 1.0],
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
          // Row of 4 other film swatches
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (int i = 0; i < _films.length; i++) ...[
                  if (i != 1) ...[
                    Expanded(
                      child: _FilmSwatch(
                        label: (_films[i]['label'] as String).split(' ').first,
                        top: _films[i]['top'] as Color,
                        bot: _films[i]['bot'] as Color,
                        dark: i == 3,
                      ),
                    ),
                    if (i < _films.length - 1 && !(i == 1)) const SizedBox(width: 8),
                  ],
                ],
              ],
            ),
          ),
          _OnbCopy(
            title: 'Разные виды\nплёнок',
            subtitle: 'Portra, Fuji, Cinestill или ч/б — один фильтр для всех снимков.',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

class _FilmSwatch extends StatelessWidget {
  final String label;
  final Color top;
  final Color bot;
  final bool dark;
  const _FilmSwatch({required this.label, required this.top, required this.bot, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bot],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GrainPainter()),
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 8,
                  letterSpacing: 0.8,
                  color: dark ? const Color(0xCCFFD2AA) : AppColors.ink3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page 6: Save memories (last slide) ──────────────────────────────────────

class _OnbPage6 extends StatelessWidget {
  final VoidCallback onSkip;
  const _OnbPage6({required this.onSkip});

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
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
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
                    const _GrainOverlay(),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.0,
                          colors: [Colors.transparent, Color(0x661A1008)],
                          stops: [0.5, 1.0],
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72, height: 72,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.ink,
                            ),
                            child: Center(
                              child: Container(
                                width: 14, height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.amber,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.amber.withValues(alpha: 0.6),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Important\nMemories',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.48,
                              height: 1.1,
                              color: AppColors.paper,
                              shadows: const [
                                Shadow(
                                  color: Color(0x80000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'DISPOSABLE · 2026',
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 9,
                              letterSpacing: 2.0,
                              color: Color(0xCCFFD2AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _OnbCopy(
            title: 'Важные\nвоспоминания',
            subtitle: 'Ваши гости снимают, вы получаете альбом. Просто, как одноразовая камера.',
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

// ─── Film grain overlay ───────────────────────────────────────────────────────

class _GrainOverlay extends StatelessWidget {
  const _GrainOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GrainPainter());
  }
}

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

    // Fill background ink
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), inkP);

    // Noise pattern in center area (rough QR data modules)
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

    // 3 finder patterns
    _finder(canvas, 0, 0, cell, inkP, paperP);
    _finder(canvas, (21 - 7) * cell, 0, cell, inkP, paperP);
    _finder(canvas, 0, (21 - 7) * cell, cell, inkP, paperP);

    // Center logo
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
