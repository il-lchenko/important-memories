import 'package:flutter/material.dart';

abstract final class AppColors {
  // Paper Light (основная тема)
  static const paper  = Color(0xFFF6F2E8);
  static const paper2 = Color(0xFFEFE8D8);
  static const paper3 = Color(0xFFE5DCC7);
  static const ink    = Color(0xFF1A1714);
  static const ink2   = Color(0xFF3A322B);
  static const ink3   = Color(0xFF6B6258);
  static const ink4   = Color(0xFF9C9082);
  static const line   = Color(0x141A1714); // rgba(26,23,20,0.08)

  // Акценты
  static const amber   = Color(0xFFC9881E);
  static const amber2  = Color(0xFFA6701A);
  static const shutter = Color(0xFFD54B3D);
  static const success = Color(0xFF6A9269);

  // Darkroom (только camera + reveal + frame fullscreen)
  static const dark    = Color(0xFF16100C);
  static const dark2   = Color(0xFF1F1812);
  static const dark3   = Color(0xFF2A211A);
  static const drText  = Color(0xFFF0E6D2);
  static const drAmber = Color(0xFFFFB347);
}

abstract final class AppRadius {
  static const sm   = Radius.circular(8);
  static const md   = Radius.circular(16);
  static const lg   = Radius.circular(24);
  static const xl   = Radius.circular(36);
  static const pill = Radius.circular(999);

  static const smBR  = BorderRadius.all(sm);
  static const mdBR  = BorderRadius.all(md);
  static const lgBR  = BorderRadius.all(lg);
  static const xlBR  = BorderRadius.all(xl);
  static const pillBR = BorderRadius.all(pill);
}

abstract final class AppSpacing {
  static const s1 = 8.0;
  static const s2 = 16.0;
  static const s3 = 24.0;
  static const s4 = 32.0;
  static const s5 = 40.0;
  static const s6 = 48.0;
  static const s7 = 56.0;
  static const s8 = 64.0;
}

abstract final class AppSizes {
  static const chipHeight   = 32.0;
  static const buttonHeight = 56.0;
  static const iconBtnSize  = 36.0;
  static const shutterSize  = 68.0;
  static const tabBarHeight = 80.0;
}
