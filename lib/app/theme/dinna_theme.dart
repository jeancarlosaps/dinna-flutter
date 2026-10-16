import 'package:flutter/material.dart';

import 'dinna_colors.dart';

abstract final class DinnaTheme {
  static const radius = 16.0;

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
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape),
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
