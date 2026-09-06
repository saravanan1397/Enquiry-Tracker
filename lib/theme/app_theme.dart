import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF496673);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFDDE8EC);
  static const onPrimaryContainer = Color(0xFF263E48);
  static const secondary = Color(0xFF6C7F78);
  static const secondaryContainer = Color(0xFFE0E9E5);
  static const onSecondaryContainer = Color(0xFF344941);
  static const background = Color(0xFFF4F7F8);
  static const surface = Color(0xFFFBFCFC);
  static const surfaceMuted = Color(0xFFEEF3F4);
  static const text = Color(0xFF202C31);
  static const textMuted = Color(0xFF65757C);
  static const outline = Color(0xFF9DABB0);
  static const outlineSoft = Color(0xFFD8E1E4);
  static const success = Color(0xFF4E7669);
  static const successSurface = Color(0xFFE5EFEB);
  static const warning = Color(0xFF8A6B38);
  static const warningSurface = Color(0xFFF4EDDF);
  static const error = Color(0xFFA85651);
  static const errorSurface = Color(0xFFF6E7E5);
}

class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      errorContainer: AppColors.errorSurface,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineSoft,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.outlineSoft),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outlineSoft),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(AppColors.surfaceMuted),
        headingTextStyle: TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: TextStyle(color: AppColors.text),
        dividerThickness: 0.8,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.text,
        contentTextStyle: TextStyle(color: AppColors.onPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
