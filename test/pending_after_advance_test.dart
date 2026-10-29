import 'package:buildAhome/Payments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pendingAfterAdvance', () {
    test('subtracts the advance', () {
      expect(pendingAfterAdvance(89334, 42095), 47239);
    });
    test('advance above due clamps to 0', () {
      expect(pendingAfterAdvance(1000, 5000), 0);
    });
    test('zero or negative advance leaves due unchanged', () {
      expect(pendingAfterAdvance(89334, 0), 89334);
      expect(pendingAfterAdvance(89334, -10), 89334);
    });
  });

  group('extraPaidAfterAdvance', () {
    test('advance above due shows the extra', () {
      expect(extraPaidAfterAdvance(10, 100), 90);
    });
    test('partial deduction or no advance shows nothing', () {
      expect(extraPaidAfterAdvance(89334, 42095), 0);
      expect(extraPaidAfterAdvance(100, 100), 0);
      expect(extraPaidAfterAdvance(100, 0), 0);
      expect(extraPaidAfterAdvance(100, -50), 0);
    });
  });

  group('parsePaymentAdvance', () {
    test('reads numbers and text, absent or bad is 0', () {
      expect(parsePaymentAdvance(42095), 42095);
      expect(parsePaymentAdvance('42,095'), 42095);
      expect(parsePaymentAdvance(null), 0);
      expect(parsePaymentAdvance('abc'), 0);
      expect(parsePaymentAdvance(-5), 0);
    });
  });
}
