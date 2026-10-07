import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/theme_service.dart';

class AppTheme {
  // Brand tokens — between indigo and purple
  static const Color navy = Color(0xFF3B2A7D);
  static const Color navySoft = Color(0xFF523D9E);
  static const Color accentBlue = Color(0xFF7063CC);
  static const Color mutedGrey = Color(0xFFA1A1AA);
  static const Color lightBorder = Color(0xFFE4E4E7);
  static const Color softShadow = Color(0x14000000);

  // Light theme colors
  static const Color lightBackgroundPrimary = Color(0xFFF7F8FB);
  static const Color lightBackgroundSecondary = Color(0xFFFFFFFF);
  static const Color lightBackgroundPrimaryLight = Color(0xFFEEF2F7);
  static const Color lightTextPrimary = Color(0xFF1B254B);
  static const Color lightTextSecondary = Color(0xFF8A94A6);

  // Fixed dark palette (always dark — used by getDarkTheme)
  static const Color _darkBackgroundPrimary = Color(0xFF121212);
  static const Color _darkBackgroundSecondary = Color(0xFF1C1C1E);
  static const Color _darkBackgroundPrimaryLight = Color(0xFF2A2A2D);
  static const Color _darkTextPrimary = Color(0xFFF4F4F5);
  static const Color _darkTextSecondary = Color(0xFFA1A1AA);
  static const Color _darkBorder = Color(0xFF3F3F46);

  // Primary color — between indigo and purple
  static const Color primaryColorConst = navy;
  static const Color primaryColorConstDark = Color(0xFF271B54);
  static const Color primaryColorConstLight = Color(0xFF4C3894);

  // Adaptive colors follow the user's light/dark preference.
  // NOTE: Historical names like [darkBackgroundPrimary] are used across the
  // app; they now resolve to light tokens when light mode is active.
  static bool get isDark => ThemeService.instance.isDark;

  static Color get darkBackgroundPrimary =>
      isDark ? _darkBackgroundPrimary : lightBackgroundPrimary;
  static Color get darkBackgroundSecondary =>
      isDark ? _darkBackgroundSecondary : lightBackgroundSecondary;
  static Color get darkBackgroundPrimaryLight =>
      isDark ? _darkBackgroundPrimaryLight : lightBackgroundPrimaryLight;
  static Color get darkTextPrimary =>
      isDark ? _darkTextPrimary : lightTextPrimary;
  static Color get darkTextSecondary =>
      isDark ? _darkTextSecondary : lightTextSecondary;
  static Color get border => isDark ? _darkBorder : lightBorder;
  static Color get borderColor => border;

  static Color get backgroundPrimary => darkBackgroundPrimary;
  static Color get backgroundSecondary => darkBackgroundSecondary;
  static Color get backgroundPrimaryLight => darkBackgroundPrimaryLight;
  static Color get textPrimary => darkTextPrimary;
  static Color get textSecondary => darkTextSecondary;

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
      outline: lightBorder,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: lightBackgroundPrimary,
      canvasColor: lightBackgroundPrimary,
      cardColor: lightBackgroundSecondary,
      dividerColor: lightBorder,
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
        actionsIconTheme:
            const IconThemeData(color: lightTextPrimary, size: 22),
        titleTextStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
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
          side: const BorderSide(color: lightBorder),
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
            inherit: false,
            textBaseline: TextBaseline.alphabetic,
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
            inherit: false,
            textBaseline: TextBaseline.alphabetic,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'Mulish-Regular',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColorConst,
          side: const BorderSide(color: lightBorder),
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
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'Mulish-Regular',
        ),
        unselectedLabelStyle: TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
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
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFamily: 'Mulish-Regular',
        ),
        unselectedLabelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
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
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: lightTextPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        secondaryLabelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: lightBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Mulish-Regular',
        ),
        contentTextStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
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
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
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
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: primaryColorConst,
        textColor: lightTextPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBackgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColorConst, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        labelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: mutedGrey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
        hintStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: mutedGrey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
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
            color: lightTextPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(
            color: lightTextPrimary, fontSize: 15, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(
            color: lightTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        bodySmall: TextStyle(
            color: mutedGrey, fontSize: 12.5, fontWeight: FontWeight.w500),
        labelLarge: TextStyle(
            color: lightTextPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700),
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
      surface: _darkBackgroundSecondary,
      background: _darkBackgroundPrimary,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: _darkTextPrimary,
      onBackground: _darkTextPrimary,
      outline: _darkBorder,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      primaryColor: primaryColorConst,
      scaffoldBackgroundColor: _darkBackgroundPrimary,
      canvasColor: _darkBackgroundPrimary,
      cardColor: _darkBackgroundSecondary,
      dividerColor: _darkBorder,
      fontFamily: 'Mulish-Regular',
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _darkBackgroundSecondary,
        foregroundColor: _darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: _darkTextPrimary),
        titleTextStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: _darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkBackgroundSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3F3F46)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkBackgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF3F3F46)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF3F3F46)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: primaryColorConstLight, width: 1.5),
        ),
        labelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: _darkTextSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
        hintStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: _darkTextSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: ThemeData.dark()
          .textTheme
          .apply(
            fontFamily: 'Mulish-Regular',
            bodyColor: _darkTextPrimary,
            displayColor: _darkTextPrimary,
          )
          .copyWith(
            headlineLarge: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800),
            headlineMedium: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800),
            headlineSmall: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800),
            bodyLarge: const TextStyle(color: _darkTextPrimary, fontSize: 15),
            bodyMedium: const TextStyle(color: _darkTextPrimary, fontSize: 14),
            bodySmall:
                const TextStyle(color: _darkTextSecondary, fontSize: 12.5),
            titleLarge: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800),
            titleMedium: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
            titleSmall: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            labelLarge: const TextStyle(
                color: _darkTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            labelMedium:
                const TextStyle(color: _darkTextSecondary, fontSize: 12),
            labelSmall:
                const TextStyle(color: _darkTextSecondary, fontSize: 11),
          ),
      primaryTextTheme: ThemeData.dark().primaryTextTheme.apply(
            fontFamily: 'Mulish-Regular',
            bodyColor: _darkTextPrimary,
            displayColor: _darkTextPrimary,
          ),
      iconTheme: const IconThemeData(color: _darkTextPrimary),
      primaryIconTheme: const IconThemeData(color: _darkTextPrimary),
      listTileTheme: const ListTileThemeData(
        iconColor: _darkTextPrimary,
        textColor: _darkTextPrimary,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: _darkBackgroundSecondary,
        titleTextStyle: TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: _darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Mulish-Regular',
        ),
        contentTextStyle: TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: _darkTextPrimary,
          fontSize: 14,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkBackgroundSecondary,
        modalBackgroundColor: _darkBackgroundSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          textStyle: const TextStyle(
            inherit: false,
            textBaseline: TextBaseline.alphabetic,
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
            inherit: false,
            textBaseline: TextBaseline.alphabetic,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'Mulish-Regular',
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkBackgroundPrimaryLight,
        selectedColor: primaryColorConstLight.withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: _darkTextPrimary,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        secondaryLabelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: _darkBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryColorConstLight,
        contentTextStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: _darkTextSecondary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFamily: 'Mulish-Regular',
        ),
        unselectedLabelStyle: const TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _darkBackgroundSecondary,
        selectedItemColor: Colors.white,
        unselectedItemColor: _darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFamily: 'Mulish-Regular',
        ),
        unselectedLabelStyle: TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontFamily: 'Mulish-Regular',
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColorConstLight,
      ),
    );
  }

  // Legacy getter for backward compatibility
  static ThemeData get darkTheme => getDarkTheme();

  static Color getBackgroundPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _darkBackgroundPrimary
        : lightBackgroundPrimary;
  }

  static Color getBackgroundSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _darkBackgroundSecondary
        : lightBackgroundSecondary;
  }

  static Color getBackgroundPrimaryLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _darkBackgroundPrimaryLight
        : lightBackgroundPrimaryLight;
  }

  static Color getTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _darkTextPrimary
        : lightTextPrimary;
  }

  static Color getTextSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _darkTextSecondary
        : lightTextSecondary;
  }

  static Color getPrimaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  static Color getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _darkBorder
        : lightBorder;
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
        color: darkBackgroundSecondary,
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
        color: darkBackgroundPrimaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColorConstLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColorConstLight.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      );

  /// Applies [delta] logical pixels to every text size under [child]
  /// (including hardcoded [TextStyle.fontSize] values).
  static Widget withFontSizeDelta(
    BuildContext context,
    Widget child, {
    double delta = -2,
    double minFontSize = 8,
  }) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: _FontSizeDeltaTextScaler(
          parent: media.textScaler,
          delta: delta,
          minFontSize: minFontSize,
        ),
      ),
      child: child,
    );
  }
}

/// Applies an absolute font-size delta on top of the parent [TextScaler].
class _FontSizeDeltaTextScaler extends TextScaler {
  final TextScaler parent;
  final double delta;
  final double minFontSize;

  const _FontSizeDeltaTextScaler({
    required this.parent,
    required this.delta,
    required this.minFontSize,
  });

  @override
  double scale(double fontSize) {
    final next = parent.scale(fontSize) + delta;
    return next < minFontSize ? minFontSize : next;
  }

  @override
  @Deprecated(
    'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  double get textScaleFactor {
    const sample = 14.0;
    return scale(sample) / sample;
  }

  @override
  TextScaler clamp({
    double minScaleFactor = 0.0,
    double maxScaleFactor = double.infinity,
  }) {
    return _FontSizeDeltaTextScaler(
      parent: parent.clamp(
        minScaleFactor: minScaleFactor,
        maxScaleFactor: maxScaleFactor,
      ),
      delta: delta,
      minFontSize: minFontSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _FontSizeDeltaTextScaler &&
        other.parent == parent &&
        other.delta == delta &&
        other.minFontSize == minFontSize;
  }

  @override
  int get hashCode => Object.hash(parent, delta, minFontSize);
}
