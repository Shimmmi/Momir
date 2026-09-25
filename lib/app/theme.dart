import 'package:flutter/material.dart';

const momirInk = Color(0xFF16130F);
const momirPaper = Color(0xFFF3EEE4);
const momirField = Color(0xFF1C1915);
const momirLine = Color(0xFF3A342C);
const momirGold = Color(0xFFE4C56A);

ThemeData buildMomirTheme() {
  const scheme = ColorScheme.dark(
    surface: momirField,
    primary: momirPaper,
    onPrimary: momirInk,
    secondary: momirGold,
    onSecondary: momirInk,
    onSurface: momirPaper,
    error: Color(0xFFFFB4A9),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: momirField,
    useMaterial3: true,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: momirField,
      foregroundColor: momirPaper,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: momirPaper,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: momirPaper,
        foregroundColor: momirInk,
        disabledBackgroundColor: const Color(0xFF3A342C),
        disabledForegroundColor: const Color(0xFF8A8175),
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: momirPaper,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: momirLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: momirGold),
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1,
        color: momirPaper,
      ),
      titleLarge: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: momirInk,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: momirPaper,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: momirPaper,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.4,
        color: momirPaper,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: Color(0xFFC8BBA6),
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: Color(0xFF8A8175),
      ),
      labelLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: momirInk,
      ),
    ),
  );
}
