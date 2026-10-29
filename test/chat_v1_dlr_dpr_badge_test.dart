import 'package:buildAhome/chat_v1/chat_v1_dlr_dpr_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 29, 18);
  final rows = [
    {'id': 223228, 'date': 'Thursday October 29 2026'},
    {'id': 223227, 'date': 'Thursday October 29 2026'},
    {'id': 222793, 'date': 'Tuesday October 27 2026'},
    {'id': 'x', 'date': 'garbage'},
  ];

  test('counts only today and above seen id', () {
    expect(unseenTodayDlrDprCount(rows, now, 0), 2);
    expect(unseenTodayDlrDprCount(rows, now, 223227), 1);
    expect(unseenTodayDlrDprCount(rows, now, 223228), 0);
    expect(latestTodayDlrDprId(rows, now), 223228);
  });

  test('new update later same day shows again', () {
    final more = [
      {'id': 223300, 'date': 'Thursday October 29 2026'},
      ...rows,
    ];
    expect(unseenTodayDlrDprCount(more, now, 223228), 1);
  });

  test('no updates today and label cap', () {
    expect(unseenTodayDlrDprCount(rows, DateTime(2026, 10, 30), 0), 0);
    expect(dlrDprBadgeLabel(1), '1');
    expect(dlrDprBadgeLabel(12), '9+');
  });
}