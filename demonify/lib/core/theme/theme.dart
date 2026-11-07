import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildDemonifyTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: DColors.primary,
    onPrimary: Colors.white,
    secondary: DColors.secondary,
    onSecondary: const Color(0xFF04140A),
    surface: DColors.surface1,
    onSurface: DColors.text,
    surfaceContainerLowest: DColors.background,
    surfaceContainerLow: DColors.surface1,
    surfaceContainer: DColors.surface2,
    surfaceContainerHigh: DColors.surface3,
    surfaceContainerHighest: DColors.surfaceHover,
    onSurfaceVariant: DColors.textMuted,
    outline: DColors.border,
    outlineVariant: DColors.border,
    error: DColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  final text = base.textTheme.apply(bodyColor: DColors.text, displayColor: DColors.text);
  return base.copyWith(
    scaffoldBackgroundColor: DColors.background,
    canvasColor: DColors.background,
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: DColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black,
      indicatorColor: DColors.primary.withValues(alpha: 0.22),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? DColors.primaryHover : DColors.textMuted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? DColors.text : DColors.textMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.black,
      indicatorColor: DColors.primary.withValues(alpha: 0.22),
      selectedIconTheme: const IconThemeData(color: DColors.primaryHover),
      unselectedIconTheme: const IconThemeData(color: DColors.textMuted),
      selectedLabelTextStyle: const TextStyle(color: DColors.text, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: const TextStyle(color: DColors.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, kMinTouchTarget),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DColors.text,
        minimumSize: const Size(64, kMinTouchTarget),
        side: const BorderSide(color: DColors.border),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: DColors.primaryHover, minimumSize: const Size(48, kMinTouchTarget)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DColors.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(DRadius.m), borderSide: const BorderSide(color: DColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(DRadius.m), borderSide: const BorderSide(color: DColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(DRadius.m), borderSide: const BorderSide(color: DColors.primary, width: 2)),
      labelStyle: const TextStyle(color: DColors.textMuted),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: DColors.primary,
      thumbColor: Colors.white,
      inactiveTrackColor: DColors.surface3,
      overlayColor: Color(0x339146FF),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : DColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? DColors.primary : DColors.surface3),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DColors.surface2,
      selectedColor: DColors.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      side: const BorderSide(color: DColors.border),
      shape: const StadiumBorder(),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: DColors.surface1, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: DColors.surface1, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: DColors.surface3, contentTextStyle: TextStyle(color: DColors.text)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: DColors.primary),
    dividerTheme: const DividerThemeData(color: DColors.border, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: DColors.textMuted, minVerticalPadding: 8),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
