import 'package:flutter/material.dart';

import 'dinna_colors.dart';

abstract final class DinnaTheme {
  static const radius = 12.0;

  static const fontFamily = 'Inter';
  static const serifFamily = 'Source Serif 4';

  static const taglineStyle = TextStyle(
    fontFamily: serifFamily,
    fontStyle: FontStyle.italic,
    fontSize: 22,
    height: 1.4,
  );

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: DinnaColors.terracotta,
          surface: DinnaColors.cream,
        ).copyWith(
          primary: DinnaColors.terracotta,
          onPrimary: DinnaColors.white,
          primaryContainer: DinnaColors.terracottaSoft,
          onPrimaryContainer: DinnaColors.brown,
          secondary: DinnaColors.sage,
          onSecondary: DinnaColors.white,
          secondaryContainer: DinnaColors.sageSoft,
          onSecondaryContainer: DinnaColors.brown,
          tertiary: DinnaColors.amber,
          onTertiary: DinnaColors.white,
          tertiaryContainer: DinnaColors.amberSoft,
          onTertiaryContainer: DinnaColors.brown,
          error: DinnaColors.error,
          onError: DinnaColors.white,
          surface: DinnaColors.cream,
          onSurface: DinnaColors.brown,
          onSurfaceVariant: DinnaColors.muted,
          surfaceContainerLowest: DinnaColors.white,
          outline: DinnaColors.muted,
          outlineVariant: DinnaColors.line,
        );

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      textTheme: const TextTheme(
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4),
        bodySmall: TextStyle(fontSize: 13, height: 1.4),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.4),
      ),
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        elevation: 0,
        shape: shape.copyWith(side: BorderSide(color: colorScheme.outlineVariant)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: shape,
          backgroundColor: colorScheme.surfaceContainerLowest,
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: colorScheme.outlineVariant)),
      ),
    );
  }
}
