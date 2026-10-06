import 'package:buildAhome/services/project_completion_days.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remainingProjectDays', () {
    test('missing or nonpositive duration has no completion estimate', () {
      for (final totalDays in <int?>[null, 0, -1]) {
        expect(
          remainingProjectDays(totalDays: totalDays, completion: '0'),
          isNull,
        );
        expect(
          remainingProjectDays(totalDays: totalDays, completion: '100'),
          isNull,
        );
      }
    });

    test('unstarted project retains the full known duration', () {
      expect(
        remainingProjectDays(totalDays: 364, completion: '0'),
        364,
      );
    });

    test('almost complete project still has a pending day', () {
      expect(
        remainingProjectDays(totalDays: 364, completion: '99.9'),
        1,
      );
    });

    test('partial work on a one-day project remains pending', () {
      expect(
        remainingProjectDays(totalDays: 1, completion: '50'),
        1,
      );
    });

    test('whole remaining days are not rounded up unnecessarily', () {
      expect(
        remainingProjectDays(totalDays: 364, completion: '50'),
        182,
      );
    });

    test('completed project has zero pending days', () {
      expect(
        remainingProjectDays(totalDays: 364, completion: '100'),
        0,
      );
    });

    test('missing, invalid and nonfinite progress stays unknown', () {
      for (final completion in <String?>[
        null,
        '',
        '   ',
        '%',
        'unknown',
        'NaN',
        'Infinity',
        '-Infinity',
      ]) {
        expect(
          remainingProjectDays(totalDays: 364, completion: completion),
          isNull,
          reason: 'Invalid progress: $completion',
        );
      }
    });

    test('percent format and surrounding whitespace are accepted', () {
      expect(
        remainingProjectDays(totalDays: 364, completion: ' 50% '),
        182,
      );
      expect(
        remainingProjectDays(totalDays: 364, completion: ' 99.9 % '),
        1,
      );
    });

    test('progress outside the allowed range is clamped', () {
      expect(
        remainingProjectDays(totalDays: 364, completion: '-5%'),
        364,
      );
      expect(
        remainingProjectDays(totalDays: 364, completion: '150%'),
        0,
      );
    });
  });
}
