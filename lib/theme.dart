import 'package:flutter/material.dart';

// Visual reference: FlClash dev ui/{shape,surface,typography}.dart.
// Use Flutter's own Material components with the same spacing and surface roles.
ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xffd8c0c3),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.content,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  return base.copyWith(
    scaffoldBackgroundColor: dark ? scheme.surface : scheme.surfaceContainer,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? scheme.surface : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surfaceContainer : scheme.surfaceBright,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge!.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium!.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge!.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: base.textTheme.titleMedium!.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge!.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );
}
