import 'package:shared_preferences/shared_preferences.dart';

import 'rbac_service.dart';

/// Once-per-day daily update reminder for site roles.
class DailyUpdatePromptService {
  DailyUpdatePromptService._();

  static const String _promptedPrefix = 'daily_update_prompted_date_';
  static const String _submittedPrefix = 'daily_update_submitted_date_';

  static const Set<String> eligibleRoles = {
    'Site Engineer',
    'Super Admin',
  };

  static bool isEligibleRole(String? role) {
    final normalized = RBACService().normalizeRole(role);
    if (normalized == null || normalized.isEmpty) return false;
    if (eligibleRoles.contains(normalized)) return true;
    // Super Admin is not always present in RBAC roleMapping; match case-insensitively.
    final lower =
        normalized.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    return eligibleRoles.any((r) => r.toLowerCase() == lower);
  }

  /// IST calendar date (`yyyy-MM-dd`) so the reminder follows the work day.
  static String todayDateKey([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final ist = utc.add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<String> _userKey() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? prefs.getString('user_id');
    final id = userId?.trim() ?? '';
    return id.isEmpty ? 'anon' : id;
  }

  static Future<bool> wasPromptedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('$_promptedPrefix${await _userKey()}');
    return stored == todayDateKey();
  }

  static Future<void> markPromptedToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_promptedPrefix${await _userKey()}',
      todayDateKey(),
    );
  }

  static Future<bool> wasSubmittedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('$_submittedPrefix${await _userKey()}');
    return stored == todayDateKey();
  }

  /// Call after a daily update is saved so later launches the same day stay quiet.
  static Future<void> markSubmittedToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_submittedPrefix${await _userKey()}',
      todayDateKey(),
    );
  }

  /// True when this user already saved a daily update for the current IST day.
  static Future<bool> hasAddedToday() => wasSubmittedToday();
}
