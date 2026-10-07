import 'package:buildAhome/models/sales_sop_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('morning and evening slots keep their clock time', () {
    final morning = SalesSopSlotOption.fromJson({
      'index': 1,
      'display': 'Fri, 13 September 2030 · Morning',
      'time_label': 'Morning',
      'datetime': '2030-09-13T10:00:00',
    }, 1);
    final evening = SalesSopSlotOption.fromJson({
      'index': 2,
      'time_label': 'Evening',
      'time': '4:00 PM',
      'date': '2030-09-14',
    }, 2);

    expect(morning.clockLabel, '10:00 AM');
    expect(morning.periodLabel, 'Morning');
    expect(evening.clockLabel, '4:00 PM');
    expect(evening.periodLabel, 'Evening');
  });

  test('given slots without an index still load for visit details', () {
    final slot = SalesSopSlot.fromJson({
      'title': 'Site Inspection',
      'status': 'submitted',
      'preferred_slots': [
        {
          'date': '2030-09-13',
          'time_label': 'Morning',
          'datetime': '2030-09-13T10:00:00',
        },
        {
          'date': '2030-09-14',
          'time_label': 'Evening',
          'datetime': '2030-09-14T16:00:00',
        },
      ],
    });

    expect(slot.options, hasLength(2));
    expect(slot.options.first.clockLabel, '10:00 AM');
    expect(slot.options.last.clockLabel, '4:00 PM');
    expect(slot.options.last.periodLabel, 'Evening');
  });
}
