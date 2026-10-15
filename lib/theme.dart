import 'package:flutter/material.dart';

// Visual reference: FlClash dev ui/{shape,surface,typography}.dart.
// Use Flutter's own Material components with the same spacing and surface roles.
ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xffd8c0c3),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.content,
  );
  final dark = brightness == Brightness.dark;
  final neutral = scheme.copyWith(
    // The fixed seed's surface tones, capped at chroma 3 (paper at 1.5),
    // following FlClash dev's neutral surface palette.
    surface: dark ? const Color(0xff151313) : const Color(0xfffef8f7),
    surfaceBright: dark ? const Color(0xff3b3839) : const Color(0xfffef8f7),
    surfaceContainer: dark ? const Color(0xff211f1f) : const Color(0xfff3ecec),
    surfaceContainerLow: dark
        ? const Color(0xff1d1b1b)
        : const Color(0xfff9f2f2),
    surfaceContainerHigh: dark
        ? const Color(0xff2c2929)
        : const Color(0xffede7e6),
    surfaceContainerHighest: dark
        ? const Color(0xff373434)
        : const Color(0xffe7e1e1),
    outlineVariant: dark ? const Color(0xff4d4546) : const Color(0xffcfc4c4),
  );
  return _theme(neutral, brightness);
}

ThemeData _theme(ColorScheme scheme, Brightness brightness) {
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
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? scheme.surfaceContainer : scheme.surfaceBright,
      elevation: 0,
      indicatorColor: scheme.secondaryContainer,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? scheme.surfaceContainer : scheme.surfaceBright,
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge!.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium!.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge!.copyWith(
        fontSize: 20,
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
