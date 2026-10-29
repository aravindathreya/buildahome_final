import 'package:buildAhome/Dpr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses App_updates date', () {
    final d = parseDprDate('Thursday October 29 2026');
    expect(d, DateTime(2026, 10, 29));
  });

  test('parses tradesmen map string', () {
    final t = parseDprTradesmen('{Carpenter: 3, Mason: 2, Helper: 0}');
    expect(t.map((e) => '${e.key}: ${e.value}').toList(),
        ['Carpenter: 3', 'Mason: 2']);
    expect(parseDprTradesmen(null), isEmpty);
  });

  test('groups updates by day with photos', () {
    final groups = buildDprDayGroups([
      {'date': 'Thursday October 29 2026', 'update_title': 'Slab', 'id': 1},
      {'date': 'Thursday October 29 2026', 'update_title': 'Slab', 'id': 2},
      {'date': 'Wednesday October 28 2026', 'update_title': 'Brick', 'id': 3},
    ], {
      'Thursday October 29 2026': ['a.jpg', 'b.jpg'],
    });
    expect(groups.length, 2);
    expect(groups.first.updates.length, 1);
    expect((groups.first.updates.first['ids'] as List).length, 2);
    expect(groups.first.images.length, 2);
    expect(groups.last.images, isEmpty);
  });

  test('reads server tradesmenMap JSON and updated_at', () {
    expect(
        parseDprTradesmen('{"Carpenter": "3"}')
            .map((e) => '${e.key}: ${e.value}')
            .toList(),
        ['Carpenter: 3']);
    expect(
        parseDprTradesmen('[{"Mason": 2}]')
            .map((e) => '${e.key}: ${e.value}')
            .toList(),
        ['Mason: 2']);
    final groups = buildDprDayGroups([
      {
        'date': 'Thursday October 29 2026',
        'update_title': 'Footing',
        'id': 9,
        'tradesmenMap': '{"Carpenter": "3"}',
        'updated_at': '2026-10-29T03:35:00',
      },
    ], const {});
    expect(groups.single.submittedAt, DateTime(2026, 10, 29, 3, 35));
    expect(groups.single.updates.single['updatedAt'],
        DateTime(2026, 10, 29, 3, 35));
    expect((groups.single.updates.single['tradesmen'] as List).length, 1);
  });
}