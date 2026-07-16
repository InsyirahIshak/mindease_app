import 'package:flutter/material.dart';

class AppTheme {
  // Core colours
  static const Color primary = Color(0xFF5B9BD5);
  static const Color secondary = Color(0xFF3DBCB8);
  static const Color background = Color(0xFFF4F6F9);
  static const Color white = Colors.white;

  // Soft/light versions
  static const Color primarySoft = Color(0xFFE8F2FB);
  static const Color secondarySoft = Color(0xFFE0F7F6);

  // Text
  static const Color textDark = Color(0xFF2D3748);
  static const Color textGrey = Color(0xFF718096);

  // Gradients
  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF5B9BD5), Color(0xFF3DBCB8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: [Color(0xFF5B9BD5), Color(0xFF3DBCB8)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ThemeData for MaterialApp
  static ThemeData get themeData => ThemeData(
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      background: background,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: white,
      selectedItemColor: primary,
      unselectedItemColor: Color(0xFFB0BEC5),
      type: BottomNavigationBarType.fixed,
      elevation: 10,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
  );
}