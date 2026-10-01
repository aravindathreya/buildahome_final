import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../services/daily_update_prompt_service.dart';

bool _dailyUpdatePromptInFlight = false;

/// Once per IST day, asks Project Coordinators, Assistant Project
/// Coordinators, and Site Engineers to add today's daily update.
///
/// Returns true when the user chooses Add now.
Future<bool> maybePromptForDailyUpdate(BuildContext context) async {
  if (_dailyUpdatePromptInFlight) return false;
  _dailyUpdatePromptInFlight = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    if (!DailyUpdatePromptService.isEligibleRole(role)) {
      debugPrint('[DailyUpdate] skip — role $role');
      return false;
    }
    if (await DailyUpdatePromptService.wasPromptedToday()) {
      debugPrint('[DailyUpdate] skip — already prompted today');
      return false;
    }
    if (await DailyUpdatePromptService.hasAddedToday()) {
      debugPrint('[DailyUpdate] skip — daily update already added today');
      await DailyUpdatePromptService.markPromptedToday();
      return false;
    }
    if (!context.mounted) return false;

    debugPrint('[DailyUpdate] showing add-daily-update prompt');
    await DailyUpdatePromptService.markPromptedToday();
    final addNow = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => const _DailyUpdatePromptDialog(),
    );
    return addNow == true;
  } catch (e) {
    debugPrint('[DailyUpdate] prompt failed: $e');
    return false;
  } finally {
    _dailyUpdatePromptInFlight = false;
  }
}

class _DailyUpdatePromptDialog extends StatelessWidget {
  const _DailyUpdatePromptDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.darkBackgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: const Text(
        'Add today’s daily update',
        style: TextStyle(
          color: AppTheme.darkTextPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      content: const Text(
        'You have not added a daily update for today. Add one now so the site record stays up to date.',
        style: TextStyle(
          color: AppTheme.mutedGrey,
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Skip',
            style: TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.navy,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text(
            'Add now',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
