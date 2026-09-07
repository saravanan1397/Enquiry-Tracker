import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF3F6877);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFD8EAF0);
  static const onPrimaryContainer = Color(0xFF263E48);
  static const secondary = Color(0xFF5F7D70);
  static const secondaryContainer = Color(0xFFDDEBE4);
  static const onSecondaryContainer = Color(0xFF344941);
  static const background = Color(0xFFEDF3F5);
  static const surface = Color(0xFFFCFEFE);
  static const surfaceMuted = Color(0xFFE6EFF2);
  static const text = Color(0xFF202C31);
  static const textMuted = Color(0xFF65757C);
  static const outline = Color(0xFF9DABB0);
  static const outlineSoft = Color(0xFFCDDCE1);
  static const success = Color(0xFF4E7669);
  static const successSurface = Color(0xFFE5EFEB);
  static const warning = Color(0xFF8A6B38);
  static const warningSurface = Color(0xFFF4EDDF);
  static const error = Color(0xFFA85651);
  static const errorSurface = Color(0xFFF6E7E5);

  static const darkBackground = Color(0xFF0A1215);
  static const darkSurface = Color(0xFF142126);
  static const darkSurfaceMuted = Color(0xFF1C3036);
  static const darkPrimarySurface = Color(0xFF243D47);
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
      tertiary: Color(0xFF8A6A48),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFF1E3D2),
      onTertiaryContainer: Color(0xFF4A3521),
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
      tertiary: Color(0xFFDFC19A),
      onTertiary: Color(0xFF442F18),
      tertiaryContainer: Color(0xFF58442D),
      onTertiaryContainer: Color(0xFFF5DFC2),
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
    final isDark = colorScheme.brightness == Brightness.dark;
    final appBarSurface = Color.alphaBlend(
      colorScheme.primary.withAlpha(isDark ? 18 : 10),
      colorScheme.surface,
    );
    final navigationSurface = Color.alphaBlend(
      colorScheme.secondary.withAlpha(isDark ? 22 : 12),
      colorScheme.surface,
    );
    final inputSurface = Color.alphaBlend(
      colorScheme.primary.withAlpha(isDark ? 10 : 4),
      colorScheme.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarSurface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationSurface,
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
            )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputSurface,
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
        elevation: isDark ? 0 : 0.5,
        shadowColor: colorScheme.primary.withAlpha(24),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      chipTheme: ChipThemeData(
        backgroundColor: navigationSurface,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: mutedSurface,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(color: colorScheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.primary,
        textColor: colorScheme.onSurface,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(mutedSurface),
        dataRowColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) ? navigationSurface : null),
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
