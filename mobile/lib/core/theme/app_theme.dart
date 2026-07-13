import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Brand theming for Cream POS.
///
/// Brand fonts (serif-adjacent headings, sans body) are supplied by Thirdsan
/// separately and land in assets/branding/ before final UI polish; until then
/// headings are differentiated with weight/letter-spacing on the platform
/// default so the layout doesn't depend on a font that isn't in the repo yet.
class AppTheme {
  AppTheme._();

  static const _headingLetterSpacing = 0.2;

  static TextTheme _textTheme(Color onSurface) {
    final base = ThemeData.light().textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: _headingLetterSpacing,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: _headingLetterSpacing,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: _headingLetterSpacing,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: _headingLetterSpacing,
      ),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  /// Dark, brand-forward theme: login screen and Back Office (used
  /// deliberately, not under lunch-rush time pressure).
  static ThemeData backOffice() {
    final colorScheme = const ColorScheme.dark().copyWith(
      primary: AppColors.gold,
      onPrimary: AppColors.charcoal,
      secondary: AppColors.goldLight,
      secondaryContainer: AppColors.gold,
      onSecondaryContainer: AppColors.charcoal,
      surface: AppColors.charcoal,
      onSurface: AppColors.cream,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.charcoal,
      textTheme: _textTheme(AppColors.cream),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.charcoal,
        foregroundColor: AppColors.cream,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.charcoal,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: AppColors.creamDark),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.04),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Light, cream-surfaced theme: the Outlet Terminal sell screen, used
  /// under lunch-rush pressure — minimal chrome, large legible numerals.
  static ThemeData outletTerminal() {
    final colorScheme = const ColorScheme.light().copyWith(
      primary: AppColors.gold,
      onPrimary: AppColors.charcoal,
      secondary: AppColors.charcoal,
      secondaryContainer: AppColors.creamDark,
      onSecondaryContainer: AppColors.charcoal,
      surface: AppColors.cream,
      onSurface: AppColors.charcoal,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.cream,
      textTheme: _textTheme(AppColors.charcoal),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.charcoal,
          foregroundColor: AppColors.cream,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.creamDark),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.creamDark),
        ),
      ),
    );
  }
}
