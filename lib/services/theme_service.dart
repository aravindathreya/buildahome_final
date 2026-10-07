import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide light/dark preference, persisted across launches.
class ThemeService {
  ThemeService._();

  static final ThemeService instance = ThemeService._();

  static const String _prefsKey = 'theme_mode';

  /// Defaults to dark to match the existing product look.
  final ValueNotifier<ThemeMode> modeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Bumped on every user change so a slow [load] cannot undo it.
  int _epoch = 0;

  bool get isDark => modeNotifier.value != ThemeMode.light;

  Future<void> load() async {
    final epoch = _epoch;
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _epoch) return;
    final stored = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();
    if (stored == 'light') {
      modeNotifier.value = ThemeMode.light;
    } else if (stored == 'dark') {
      modeNotifier.value = ThemeMode.dark;
    }
  }

  Future<void> setDark(bool dark) async {
    final next = dark ? ThemeMode.dark : ThemeMode.light;
    if (modeNotifier.value == next) return;
    _epoch++;
    modeNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, dark ? 'dark' : 'light');
  }

  Future<void> toggle() => setDark(!isDark);
}
