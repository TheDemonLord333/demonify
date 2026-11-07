import 'package:flutter/material.dart';

/// Demonify Design-Tokens – identisch zur Verwaltungswebseite (admin-web/src/styles.css).
abstract final class DColors {
  static const background = Color(0xFF050507);
  static const surface1 = Color(0xFF0F0F14);
  static const surface2 = Color(0xFF17171F);
  static const surface3 = Color(0xFF22222C);
  static const surfaceHover = Color(0xFF2A2A36);
  static const border = Color(0xFF2E2E3A);
  static const text = Color(0xFFF4F3F8);
  static const textMuted = Color(0xFFA7A5B5);
  static const textDim = Color(0xFF6E6C7D);

  /// Hauptfarbe Lila: primäre Aktionen, aktive Navigation, Auswahl
  static const primary = Color(0xFF9146FF);
  static const primaryHover = Color(0xFFA466FF);

  /// Sekundärfarbe Grün: ergänzende Akzente und Statusanzeigen
  static const secondary = Color(0xFF1ED760);
  static const danger = Color(0xFFFF5470);
  static const warning = Color(0xFFFFB547);
}

abstract final class DSpacing {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class DRadius {
  static const s = 6.0;
  static const m = 10.0;
  static const l = 16.0;
}

/// Breakpoints für responsive Layouts
abstract final class DBreakpoints {
  /// Ab dieser Breite: Seitenleiste statt unterer Navigation
  static const wide = 840.0;
  static const extraWide = 1200.0;
}

/// Mindestgröße für Touchflächen (Material/Apple-Empfehlung)
const double kMinTouchTarget = 48;
