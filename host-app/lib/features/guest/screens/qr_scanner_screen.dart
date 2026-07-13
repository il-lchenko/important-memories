import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/tokens.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final _ctrl = MobileScannerController();
  bool _scanned = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      setState(() => _permissionDenied = true);
    } else if (status.isGranted) {
      setState(() {});
      await _ctrl.start();
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    final code = _extractCode(rawValue);
    if (code == null) return;

    _scanned = true;
    _ctrl.stop();
    if (mounted) context.go('/guest/landing/$code');
  }

  String? _extractCode(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final segs = uri.pathSegments;
      if (segs.length >= 2 && segs[segs.length - 2] == 'g') {
        return segs.last;
      }
    }
    if (RegExp(r'^[A-Za-z0-9]{4,16}$').hasMatch(value)) {
      return value;
    }
    return null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Stack(
        children: [
          if (_permissionDenied)
            _NoCameraView(onSettings: openAppSettings)
          else
            MobileScanner(controller: _ctrl, onDetect: _onDetect),

          // Top bar
          Positioned(
            top: top + 8, left: 8, right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DarkBtn(
                  icon: Icons.close,
                  onTap: () => context.pop(),
                ),
                const Text(
                  'СКАНИРУЙТЕ QR',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    letterSpacing: 2.0,
                    color: Color(0x99F0E6D2),
                  ),
                ),
                _DarkBtn(
                  icon: Icons.flash_on_outlined,
                  onTap: () => _ctrl.toggleTorch(),
                ),
              ],
            ),
          ),

          // Viewfinder
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _QRViewfinder(),
                const SizedBox(height: 24),
                Text(
                  'Наведите камеру на QR-код',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: AppColors.drText.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          // Bottom: manual code button
          Positioned(
            bottom: bottom + 24, left: 20, right: 20,
            child: GestureDetector(
              onTap: () => context.push('/guest/code'),
              child: Container(
                height: AppSizes.buttonHeight,
                decoration: BoxDecoration(
                  color: const Color(0x08FFB347),
                  border: Border.all(color: const Color(0x33FFB347), width: 1.5),
                  borderRadius: AppRadius.mdBR,
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Ввести код вручную',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.drText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _DarkBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSizes.iconBtnSize,
        height: AppSizes.iconBtnSize,
        decoration: BoxDecoration(
          color: const Color(0x33FFB347),
          borderRadius: AppRadius.smBR,
        ),
        child: Icon(icon, size: 18, color: AppColors.drText),
      ),
    );
  }
}

class _QRViewfinder extends StatelessWidget {
  const _QRViewfinder();

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    const cornerLen = 28.0;
    const cornerWidth = 3.0;
    const cornerColor = AppColors.drAmber;
    const r = Radius.circular(4);

    return SizedBox(
      width: size, height: size,
      child: CustomPaint(
        painter: _ViewfinderPainter(
          cornerLen: cornerLen,
          cornerWidth: cornerWidth,
          color: cornerColor,
          radius: r,
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final double cornerLen;
  final double cornerWidth;
  final Color color;
  final Radius radius;

  const _ViewfinderPainter({
    required this.cornerLen,
    required this.cornerWidth,
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cl = cornerLen;

    // Top-left
    canvas.drawPath(Path()
      ..moveTo(0, cl)
      ..lineTo(0, radius.x)
      ..arcToPoint(Offset(radius.x, 0), radius: radius)
      ..lineTo(cl, 0), paint);
    // Top-right
    canvas.drawPath(Path()
      ..moveTo(w - cl, 0)
      ..lineTo(w - radius.x, 0)
      ..arcToPoint(Offset(w, radius.x), radius: radius, clockwise: false)
      ..lineTo(w, cl), paint);
    // Bottom-left
    canvas.drawPath(Path()
      ..moveTo(0, h - cl)
      ..lineTo(0, h - radius.x)
      ..arcToPoint(Offset(radius.x, h), radius: radius, clockwise: false)
      ..lineTo(cl, h), paint);
    // Bottom-right
    canvas.drawPath(Path()
      ..moveTo(w - cl, h)
      ..lineTo(w - radius.x, h)
      ..arcToPoint(Offset(w, h - radius.x), radius: radius)
      ..lineTo(w, h - cl), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _NoCameraView extends StatelessWidget {
  final VoidCallback onSettings;
  const _NoCameraView({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 48, color: AppColors.ink4),
            const SizedBox(height: 16),
            const Text(
              'Нет доступа к камере',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.drText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Разрешите доступ в настройках телефона',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.ink3,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onSettings,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: AppRadius.mdBR,
                ),
                child: const Text(
                  'Открыть настройки',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
