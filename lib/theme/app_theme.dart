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

  static const darkBackground = Color(0xFF0F1517);
  static const darkSurface = Color(0xFF151C1F);
  static const darkSurfaceMuted = Color(0xFF1D272A);
  static const darkPrimarySurface = Color(0xFF283B43);
  static const darkSuccess = Color(0xFFA9CDBF);
  static const darkSuccessSurface = Color(0xFF223730);
  static const darkWarning = Color(0xFFE0C38B);
  static const darkWarningSurface = Color(0xFF392F21);
  static const darkError = Color(0xFFF0B1AC);
  static const darkErrorSurface = Color(0xFF402827);

  static Color successFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSuccess : success;

  static Color warningFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkWarning : warning;
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
      onSurfaceVariant: AppColors.textMuted,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      errorContainer: AppColors.errorSurface,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineSoft,
    );
    return _build(
      colorScheme: colorScheme,
      scaffoldBackground: AppColors.background,
      mutedSurface: AppColors.surfaceMuted,
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: Color(0xFFAFC8D2),
      onPrimary: Color(0xFF19333E),
      primaryContainer: Color(0xFF314A54),
      onPrimaryContainer: Color(0xFFDCEAF0),
      secondary: Color(0xFFB7CBC4),
      onSecondary: Color(0xFF223A33),
      secondaryContainer: Color(0xFF344A43),
      onSecondaryContainer: Color(0xFFD9E8E2),
      surface: AppColors.darkSurface,
      onSurface: Color(0xFFE3E9EB),
      onSurfaceVariant: Color(0xFFB9C5C9),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF713330),
      outline: Color(0xFF89979C),
      outlineVariant: Color(0xFF3E4B50),
    );
    return _build(
      colorScheme: colorScheme,
      scaffoldBackground: AppColors.darkBackground,
      mutedSurface: AppColors.darkSurfaceMuted,
    );
  }

  static ThemeData _build({
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required Color mutedSurface,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(mutedSurface),
        headingTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: TextStyle(color: colorScheme.onSurface),
        dividerThickness: 0.8,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
