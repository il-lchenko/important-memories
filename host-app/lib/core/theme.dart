import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary:   AppColors.amber,
      onPrimary: Colors.white,
      secondary: AppColors.ink,
      onSecondary: AppColors.paper,
      error:     AppColors.shutter,
      onError:   Colors.white,
      surface:   AppColors.paper,
      onSurface: AppColors.ink,
    ),
    scaffoldBackgroundColor: AppColors.paper,
  );

  return base.copyWith(
    textTheme: _buildTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
        textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600),
        elevation: 0,
        shadowColor: Colors.transparent,
      ).copyWith(
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        overlayColor: WidgetStateProperty.all(Colors.white10),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppColors.paper3;
          return AppColors.amber;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppColors.ink4;
          return Colors.white;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
        side: BorderSide(color: AppColors.line),
        textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      constraints: const BoxConstraints(minHeight: 52),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.amber, width: 1),
      ),
      hintStyle: GoogleFonts.manrope(fontSize: 16, color: AppColors.ink4),
    ),
    cardTheme: CardTheme(
      color: AppColors.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgBR,
        side: BorderSide(color: AppColors.line),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.paper,
      selectedItemColor: AppColors.amber,
      unselectedItemColor: AppColors.ink3,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
  );
}

TextTheme _buildTextTheme(TextTheme base) {
  return base.copyWith(
    // Playfair Display — заголовки
    displayLarge:  GoogleFonts.playfairDisplay(fontSize: 48, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.96, fontFeatures: [const FontFeature.liningFigures()]),
    displayMedium: GoogleFonts.playfairDisplay(fontSize: 36, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.72, fontFeatures: [const FontFeature.liningFigures()]),
    displaySmall:  GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w500, color: AppColors.ink, fontFeatures: [const FontFeature.liningFigures()]),
    headlineLarge: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.ink, fontFeatures: [const FontFeature.liningFigures()]),
    headlineMedium:GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.ink, fontFeatures: [const FontFeature.liningFigures()]),

    // Manrope — тело и UI
    titleLarge:  GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
    titleMedium: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
    titleSmall:  GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.ink),
    bodyLarge:   GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.ink),
    bodyMedium:  GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.ink2),
    bodySmall:   GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.ink3),
    labelLarge:  GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
    labelSmall:  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.ink3, letterSpacing: 0.14, fontFeatures: [const FontFeature.tabularFigures()]),
  );
}
