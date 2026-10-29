import 'package:buildAhome/services/upcoming_sop_projects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects upcoming SOP rows only', () {
    expect(isUpcomingSopRow({'id': null, 'sales_sop_id': 5, 'is_upcoming': true}), isTrue);
    expect(isUpcomingSopRow({'id': 3, 'name': 'A'}), isFalse);
    expect(isUpcomingSopRow({'id': null, 'is_upcoming': true}), isFalse);
    expect(isUpcomingSopRow('x'), isFalse);
  });

  test('split keeps ERP rows untouched and in order', () {
    final erpA = {'id': 1, 'name': 'A'};
    final erpB = {'id': 2, 'name': 'B'};
    final up = {'id': null, 'sales_sop_id': 9, 'is_upcoming': true, 'name': 'C'};
    final r = splitUpcomingSopRows([erpA, up, erpB]);
    expect(r.projects, [erpA, erpB]);
    expect(r.upcoming, [up]);
  });
}