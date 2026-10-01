import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buildAhome/services/daily_update_prompt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyUpdatePromptService.isEligibleRole', () {
    test('includes coordinator, assistant coordinator, and site engineer', () {
      expect(
        DailyUpdatePromptService.isEligibleRole('Project Coordinator'),
        isTrue,
      );
      expect(
        DailyUpdatePromptService.isEligibleRole('Project Co-ordinator'),
        isTrue,
      );
      expect(
        DailyUpdatePromptService.isEligibleRole('Assistant Project Coordinator'),
        isTrue,
      );
      expect(DailyUpdatePromptService.isEligibleRole('APCC'), isTrue);
      expect(DailyUpdatePromptService.isEligibleRole('Site Engineer'), isTrue);
      expect(DailyUpdatePromptService.isEligibleRole('site engineer'), isTrue);
    });

    test('excludes other roles', () {
      expect(DailyUpdatePromptService.isEligibleRole('Admin'), isFalse);
      expect(DailyUpdatePromptService.isEligibleRole('Project Manager'), isFalse);
      expect(DailyUpdatePromptService.isEligibleRole('Client'), isFalse);
      expect(DailyUpdatePromptService.isEligibleRole(null), isFalse);
    });
  });

  group('DailyUpdatePromptService.todayDateKey', () {
    test('uses the IST calendar day', () {
      expect(
        DailyUpdatePromptService.todayDateKey(DateTime.utc(2026, 10, 1, 18, 29)),
        '2026-10-01',
      );
      expect(
        DailyUpdatePromptService.todayDateKey(DateTime.utc(2026, 10, 1, 18, 30)),
        '2026-10-02',
      );
    });
  });

  group('once per day prefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'userId': '42',
      });
    });

    test('prompt and submit flags are scoped to today and this user', () async {
      expect(await DailyUpdatePromptService.wasPromptedToday(), isFalse);
      expect(await DailyUpdatePromptService.wasSubmittedToday(), isFalse);

      await DailyUpdatePromptService.markPromptedToday();
      expect(await DailyUpdatePromptService.wasPromptedToday(), isTrue);
      expect(await DailyUpdatePromptService.wasSubmittedToday(), isFalse);

      await DailyUpdatePromptService.markSubmittedToday();
      expect(await DailyUpdatePromptService.wasSubmittedToday(), isTrue);
      expect(await DailyUpdatePromptService.hasAddedToday(), isTrue);
    });
  });
}
