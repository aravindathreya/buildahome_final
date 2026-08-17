import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ChatV1 design system — enterprise messenger (WhatsApp polish + ERP).
/// Isolated from production ChatBox / AppTheme widgets.
class ChatV1Theme {
  ChatV1Theme._();

  // Dark
  static const Color darkBg = Color(0xFF111315);
  static const Color darkSecondary = Color(0xFF1A1D22);
  static const Color darkCard = Color(0xFF22262C);
  static const Color darkBorder = Color(0xFF2C3138);
  static const Color darkChatBg = Color(0xFF0E1012);
  static const Color darkBubbleMe = Color(0xFF1E6B45);
  static const Color darkBubbleOther = Color(0xFF2A2F36);
  static const Color darkText = Color(0xFFF2F4F7);
  static const Color darkTextSecondary = Color(0xFF9AA3AF);
  static const Color darkTextMuted = Color(0xFF6B7280);

  // Light
  static const Color lightBg = Color(0xFFF5F7FA);
  static const Color lightSecondary = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightChatBg = Color(0xFFEEF1F5);
  static const Color lightBubbleMe = Color(0xFFD1F5E0);
  static const Color lightBubbleOther = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightTextMuted = Color(0xFF9CA3AF);

  // Accents
  static const Color accent = Color(0xFF2ECC71);
  static const Color accentSoft = Color(0x1A2ECC71);
  static const Color unread = Color(0xFF22C55E);
  static const Color pending = Color(0xFFF59E0B);
  static const Color completed = Color(0xFF22C55E);
  static const Color rejected = Color(0xFFEF4444);
  static const Color mention = Color(0xFF3B82F6);
  static const Color readTick = Color(0xFF53BDEB);

  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 22;

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color bg(BuildContext c) => isDark(c) ? darkBg : lightBg;
  static Color secondary(BuildContext c) =>
      isDark(c) ? darkSecondary : lightSecondary;
  static Color card(BuildContext c) => isDark(c) ? darkCard : lightCard;
  static Color border(BuildContext c) => isDark(c) ? darkBorder : lightBorder;
  static Color chatBg(BuildContext c) => isDark(c) ? darkChatBg : lightChatBg;
  static Color bubbleMe(BuildContext c) =>
      isDark(c) ? darkBubbleMe : lightBubbleMe;
  static Color bubbleOther(BuildContext c) =>
      isDark(c) ? darkBubbleOther : lightBubbleOther;
  static Color text(BuildContext c) => isDark(c) ? darkText : lightText;
  static Color textSecondary(BuildContext c) =>
      isDark(c) ? darkTextSecondary : lightTextSecondary;
  static Color textMuted(BuildContext c) =>
      isDark(c) ? darkTextMuted : lightTextMuted;
  static Color header(BuildContext c) =>
      isDark(c) ? darkSecondary : lightSecondary;
  static Color headerFg(BuildContext c) => text(c);

  static List<BoxShadow> shadow(BuildContext c) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark(c) ? 0.35 : 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static ThemeData data({required bool dark}) {
    final base = dark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: dark ? darkBg : lightBg,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        error: rejected,
        onError: Colors.white,
        surface: dark ? darkSecondary : lightSecondary,
        onSurface: dark ? darkText : lightText,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? darkSecondary : lightSecondary,
        foregroundColor: dark ? darkText : lightText,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: dark ? darkText : lightText,
          letterSpacing: -0.2,
        ),
      ),
      dividerColor: dark ? darkBorder : lightBorder,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      splashFactory: InkRipple.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: dark ? darkText : lightText,
        displayColor: dark ? darkText : lightText,
      ),
    );
  }
}
