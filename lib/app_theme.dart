import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Brand / light theme tokens (matches redesigned dashboards)
  static const Color navy = Color(0xFF1B254B);
  static const Color navySoft = Color(0xFF243463);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color mutedGrey = Color(0xFF8A94A6);
  static const Color border = Color(0xFFE8ECF1);
  static const Color softShadow = Color(0x14000000);

  // Light theme colors
  static const Color lightBackgroundPrimary = Color(0xFFF7F8FB);
  static const Color lightBackgroundSecondary = Color(0xFFFFFFFF);
  static const Color lightBackgroundPrimaryLight = Color(0xFFEEF2F7);
  static const Color lightTextPrimary = Color(0xFF1B254B);
  static const Color lightTextSecondary = Color(0xFF8A94A6);

  // Dark theme colors
  static const Color darkBackgroundPrimary = Color(0xFF0F1424);
  static const Color darkBackgroundSecondary = Color(0xFF1A2238);
  static const Color darkBackgroundPrimaryLight = Color(0xFF243049);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFA8B3C7);

  // Primary color
  static const Color primaryColorConst = navy;
  static const Color primaryColorConstDark = Color(0xFF151D3A);
  static const Color primaryColorConstLight = Color(0xFF3B4A7A);

  // Legacy colors for backward compatibility
  static Color get backgroundPrimary => lightBackgroundPrimary;
  static Color get backgroundSecondary => lightBackgroundSecondary;
  static Color get backgroundPrimaryLight => lightBackgroundPrimaryLight;
  static Color get textPrimary => lightTextPrimary;
  static Color get textSecondary => lightTextSecondary;

  static ThemeData getLightTheme() {
    final colorScheme = ColorScheme.light(
      primary: primaryColorConst,
      secondary: accentBlue,
      surface: lightBackgroundSecondary,
      background: lightBackgroundPrimary,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightTextPrimary,
      onBackground: lightTextPrimary,
      outline: border,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: lightBackgroundPrimary,
      canvasColor: lightBackgroundPrimary,
      cardColor: lightBackgroundSecondary,
      dividerColor: border,
      fontFamily: 'Mulish-Regular',
      colorScheme: colorScheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: lightBackgroundSecondary,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: lightTextPrimary, size: 22),
        actionsIconTheme: const IconThemeData(color: lightTextPrimary, size: 22),
        titleTextStyle: const TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Mulish-Regular',
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightBackgroundSecondary,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        shadowColor: softShadow,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColorConst,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'Mulish-Regular',
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlue,
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'Mulish-Regular',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColorConst,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColorConst,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColorConst,
        unselectedItemColor: mutedGrey,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'Mulish-Regular',
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: mutedGrey,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFamily: 'Mulish-Regular',
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        indicator: BoxDecoration(
          color: primaryColorConst,
          borderRadius: BorderRadius.circular(11),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightBackgroundPrimaryLight,
        selectedColor: primaryColorConst.withValues(alpha: 0.12),
        labelStyle: const TextStyle(
          color: lightTextPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: const TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Mulish-Regular',
        ),
        contentTextStyle: const TextStyle(
          color: mutedGrey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryColorConst,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColorConst,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: primaryColorConst,
        textColor: lightTextPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBackgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColorConst, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        labelStyle: const TextStyle(color: mutedGrey, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: mutedGrey, fontWeight: FontWeight.w500),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: lightTextPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3),
        headlineMedium: TextStyle(
            color: lightTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2),
        headlineSmall: TextStyle(
            color: lightTextPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(
            color: lightTextPrimary, fontSize: 17, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(
            color: lightTextPrimary, fontSize: 15, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(
            color: lightTextPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(
            color: lightTextPrimary, fontSize: 15, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(
            color: lightTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        bodySmall: TextStyle(
            color: mutedGrey, fontSize: 12.5, fontWeight: FontWeight.w500),
        labelLarge: TextStyle(
            color: lightTextPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      iconTheme: const IconThemeData(color: lightTextPrimary),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  static ThemeData getDarkTheme() {
    final colorScheme = ColorScheme.dark(
      primary: primaryColorConstLight,
      secondary: accentBlue,
      surface: darkBackgroundSecondary,
      background: darkBackgroundPrimary,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: darkTextPrimary,
      onBackground: darkTextPrimary,
      outline: const Color(0xFF334155),
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: darkBackgroundPrimary,
      canvasColor: darkBackgroundPrimary,
      cardColor: darkBackgroundSecondary,
      dividerColor: const Color(0xFF334155),
      fontFamily: 'Mulish-Regular',
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackgroundSecondary,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: darkTextPrimary),
        titleTextStyle: const TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      cardTheme: CardThemeData(
        color: darkBackgroundSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColorConstLight,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkBackgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColorConstLight, width: 1.5),
        ),
        labelStyle: const TextStyle(color: darkTextSecondary),
        hintStyle: const TextStyle(color: darkTextSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: darkTextPrimary, fontSize: 26, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(
            color: darkTextPrimary, fontSize: 22, fontWeight: FontWeight.w800),
        headlineSmall: TextStyle(
            color: darkTextPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        bodyLarge: TextStyle(color: darkTextPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: darkTextPrimary, fontSize: 14),
        bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12.5),
      ),
      iconTheme: const IconThemeData(color: darkTextPrimary),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkBackgroundSecondary,
        selectedItemColor: Colors.white,
        unselectedItemColor: darkTextSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColorConstLight,
      ),
    );
  }

  // Legacy getter for backward compatibility
  static ThemeData get darkTheme => getLightTheme();

  static Color getBackgroundPrimary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkBackgroundPrimary
        : lightBackgroundPrimary;
  }

  static Color getBackgroundSecondary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkBackgroundSecondary
        : lightBackgroundSecondary;
  }

  static Color getBackgroundPrimaryLight(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkBackgroundPrimaryLight
        : lightBackgroundPrimaryLight;
  }

  static Color getTextPrimary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkTextPrimary : lightTextPrimary;
  }

  static Color getTextSecondary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  static Color getPrimaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  static Color getBorderColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? const Color(0xFF334155)
        : border;
  }

  // Shared surface card decoration for list/grid items
  static BoxDecoration cardDecoration(BuildContext context) {
    return BoxDecoration(
      color: getBackgroundSecondary(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: getBorderColor(context)),
      boxShadow: const [
        BoxShadow(
          color: softShadow,
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  // Grid card decoration
  static BoxDecoration get gridCardDecoration => BoxDecoration(
        color: lightBackgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
            color: softShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration get gridCardDecorationPressed => BoxDecoration(
        color: lightBackgroundPrimaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColorConst, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColorConst.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      );
}
