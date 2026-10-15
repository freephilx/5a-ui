import 'package:flutter/material.dart';

// Visual reference: FlClash dev ui/{shape,surface,typography}.dart.
// Use Flutter's own Material components with the same spacing and surface roles.
ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff8493a3),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.content,
  );
  final dark = brightness == Brightness.dark;
  final neutral = scheme.copyWith(
    // Near-neutral surface levels follow FlClash dev and the native sidebar.
    surface: dark ? const Color(0xff141516) : const Color(0xfffafafa),
    surfaceBright: dark ? const Color(0xff3a3b3d) : const Color(0xfffafafa),
    surfaceContainer: dark ? const Color(0xff202123) : const Color(0xfff0f1f3),
    surfaceContainerLow: dark
        ? const Color(0xff1c1d1f)
        : const Color(0xfff6f6f7),
    surfaceContainerHigh: dark
        ? const Color(0xff2b2c2f)
        : const Color(0xffe9eaed),
    surfaceContainerHighest: dark
        ? const Color(0xff36373a)
        : const Color(0xffe3e5e8),
    outlineVariant: dark ? const Color(0xff44474d) : const Color(0xffc5c8cd),
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
      // FlClash dev keeps inputs outlined so they read as editable controls.
      // Material supplies the hover, focus, error and disabled border states.
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(1000),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(1000),
        ),
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
