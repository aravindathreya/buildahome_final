import 'package:flutter/material.dart';

class AppTheme {
  // Light theme colors
  static const Color lightBackgroundPrimary = Color.fromARGB(255, 234, 234, 234);
  static const Color lightBackgroundSecondary = Color.fromARGB(255, 211, 211, 211);
  static const Color lightBackgroundPrimaryLight = Color.fromARGB(255, 229, 229, 229);
  static const Color lightTextPrimary = Color.fromARGB(255, 27, 27, 27);
  static const Color lightTextSecondary = Color.fromARGB(255, 40, 40, 40);
  
  // Dark theme colors
  static const Color darkBackgroundPrimary = Color.fromARGB(255, 18, 18, 18);
  static const Color darkBackgroundSecondary = Color.fromARGB(255, 30, 30, 30);
  static const Color darkBackgroundPrimaryLight = Color.fromARGB(255, 40, 40, 40);
  static const Color darkTextPrimary = Color.fromARGB(255, 255, 255, 255);
  static const Color darkTextSecondary = Color.fromARGB(255, 200, 200, 200);
  
  // Primary color - dark indigo that works well in both light and dark modes
  static const Color primaryColorConst = Color.fromARGB(255, 46, 60, 135); // Dark indigo (#3F51B5)
  static const Color primaryColorConstDark = Color.fromARGB(255, 44, 54, 119); // Darker indigo for dark mode
  static const Color primaryColorConstLight = Color.fromARGB(255, 92, 107, 192); // Lighter indigo for light mode
  
  // Legacy colors for backward compatibility (will use theme-aware versions)
  static Color get backgroundPrimary => lightBackgroundPrimary;
  static Color get backgroundSecondary => lightBackgroundSecondary;
  static Color get backgroundPrimaryLight => lightBackgroundPrimaryLight;
  static Color get textPrimary => lightTextPrimary;
  static Color get textSecondary => lightTextSecondary;
  
  static ThemeData getLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: lightBackgroundPrimary,
      fontFamily: 'Mulish-Regular',
      
      colorScheme: ColorScheme.light(
        primary: primaryColorConst,
        secondary: primaryColorConstLight,
        surface: lightBackgroundSecondary,
        background: lightBackgroundPrimary,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
        onBackground: lightTextPrimary,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: lightBackgroundSecondary,
        elevation: 0,
        iconTheme: IconThemeData(color: lightTextPrimary),
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
      ),

      cardTheme: CardThemeData(
        color: lightBackgroundSecondary,
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
        fillColor: lightBackgroundPrimaryLight,
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
        labelStyle: TextStyle(color: lightTextSecondary),
        hintStyle: TextStyle(color: lightTextSecondary),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(color: lightTextPrimary, fontSize: 28, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: lightTextPrimary, fontSize: 24, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: lightTextPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: lightTextPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: lightTextPrimary, fontSize: 14),
        bodySmall: TextStyle(color: lightTextSecondary, fontSize: 12),
      ),

      iconTheme: IconThemeData(
        color: lightTextPrimary,
      ),

      dividerColor: primaryColorConst.withOpacity(0.3),
    );
  }
  
  static ThemeData getDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: darkBackgroundPrimary,
      fontFamily: 'Mulish-Regular',
      
      colorScheme: ColorScheme.dark(
        primary: primaryColorConst,
        secondary: primaryColorConstLight,
        surface: darkBackgroundSecondary,
        background: darkBackgroundPrimary,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onBackground: darkTextPrimary,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: darkBackgroundSecondary,
        elevation: 0,
        iconTheme: IconThemeData(color: darkTextPrimary),
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
      ),

      cardTheme: CardThemeData(
        color: darkBackgroundSecondary,
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
        fillColor: darkBackgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColorConst.withOpacity(0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColorConst.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColorConst, width: 2),
        ),
        labelStyle: TextStyle(color: darkTextSecondary),
        hintStyle: TextStyle(color: darkTextSecondary),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(color: darkTextPrimary, fontSize: 28, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: darkTextPrimary, fontSize: 24, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: darkTextPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: darkTextPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: darkTextPrimary, fontSize: 14),
        bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12),
      ),

      iconTheme: IconThemeData(
        color: darkTextPrimary,
      ),

      dividerColor: primaryColorConst.withOpacity(0.5),
    );
  }
  
  // Legacy getter for backward compatibility
  static ThemeData get darkTheme => getLightTheme();
  
  // Helper methods to get theme-aware colors from context
  static Color getBackgroundPrimary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkBackgroundPrimary : lightBackgroundPrimary;
  }
  
  static Color getBackgroundSecondary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkBackgroundSecondary : lightBackgroundSecondary;
  }
  
  static Color getBackgroundPrimaryLight(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkBackgroundPrimaryLight : lightBackgroundPrimaryLight;
  }
  
  static Color getTextPrimary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkTextPrimary : lightTextPrimary;
  }
  
  static Color getTextSecondary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkTextSecondary : lightTextSecondary;
  }
  
  static Color getPrimaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
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

