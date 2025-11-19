import 'package:flutter/material.dart';

class AppTheme {
  // Dark grey and primaryColorConst color scheme
  static const Color backgroundPrimary = Color.fromARGB(255, 234, 234, 234); // Primary dark grey
  static const Color backgroundSecondary = Color.fromARGB(255, 211, 211, 211); // Secondary dark grey
  static const Color backgroundPrimaryLight = Color.fromARGB(255, 229, 229, 229); // Lighter dark grey
  static const Color primaryColorConst = Color(0xFF001489); // Primary primaryColorConst
  static const Color primaryColorConstDark = Color(0xFF08254f); // Darker primaryColorConst#001489
  static const Color primaryColorConstLight = Color(0xFF08254f); // Lighter primaryColorConst#08254f
  static const Color textPrimary = Color.fromARGB(255, 27, 27, 27); // Light text for dark background
  static const Color textSecondary = Color.fromARGB(255, 40, 40, 40); // Secondary text
  static const Color onPrimaryColorConst = Color.fromARGB(255, 120, 120, 120); // Tertiary text
  static const Color onSecondaryColorConst = Color.fromARGB(255, 120, 120, 120); // Tertiary text
  static const Color onSurfaceColorConst = Color.fromARGB(255, 120, 120, 120); // Tertiary text
  static const Color onBackgroundColorConst = Color.fromARGB(255, 120, 120, 120); // Tertiary text
  
  static ThemeData get darkTheme {
    return ThemeData(
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: backgroundPrimary,
      fontFamily: 'Mulish-Regular',
      
      colorScheme: ColorScheme.dark(
        primary: primaryColorConst,
        secondary: primaryColorConstDark,
        surface: backgroundSecondary,
        background: backgroundPrimary,
        onPrimary: onPrimaryColorConst,
        onSecondary: onSecondaryColorConst,
        onSurface: onSurfaceColorConst,
        onBackground: onBackgroundColorConst,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: backgroundSecondary,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
      ),

      cardTheme: CardThemeData(
        color: backgroundSecondary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColorConst,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColorConst.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColorConst.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColorConst, width: 2),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
      ),

      iconTheme: IconThemeData(
        color: textPrimary,
      ),

      dividerColor: primaryColorConst.withOpacity(0.3),
    );
  }

  // Grid card decoration
  static BoxDecoration get gridCardDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        backgroundSecondary,
        backgroundPrimaryLight,
      ],
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: primaryColorConst.withOpacity(0.3),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 8,
        offset: Offset(0, 4),
      ),
    ],
  );

  // Grid card decoration with hover effect
  static BoxDecoration get gridCardDecorationPressed => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        backgroundPrimaryLight,
        primaryColorConst.withOpacity(0.1),
      ],
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: primaryColorConst,
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: primaryColorConst.withOpacity(0.3),
        blurRadius: 12,
        offset: Offset(0, 6),
      ),
    ],
  );
}

