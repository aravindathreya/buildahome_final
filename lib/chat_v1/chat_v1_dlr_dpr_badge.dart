// DLR / DPR unread badge for the Internal chat pill.
// Rows come from /API/view_all_dpr: {id, date: "Thursday October 29 2026", ...}.
import 'package:intl/intl.dart';

DateTime? parseDlrDprDate(dynamic raw) {
  final s = (raw ?? '').toString().trim();
  if (s.isEmpty) return null;
  try {
    return DateFormat('EEEE MMMM d yyyy').parseLoose(s);
  } catch (_) {}
  return DateTime.tryParse(s);
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _rowId(dynamic row) => int.tryParse('${row['id'] ?? ''}') ?? 0;

/// Ids of today's updates (local date).
List<int> todayDlrDprIds(List rows, DateTime now) {
  final out = <int>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final d = parseDlrDprDate(row['date']);
    if (d == null || !_isSameDay(d, now)) continue;
    final id = _rowId(row);
    if (id > 0) out.add(id);
  }
  return out;
}

/// Today's updates with id above the last seen id.
int unseenTodayDlrDprCount(List rows, DateTime now, int seenMaxId) =>
    todayDlrDprIds(rows, now).where((id) => id > seenMaxId).length;

/// Highest id among today's updates (0 when none).
int latestTodayDlrDprId(List rows, DateTime now) {
  var max = 0;
  for (final id in todayDlrDprIds(rows, now)) {
    if (id > max) max = id;
  }
  return max;
}

String dlrDprBadgeLabel(int count) => count > 9 ? '9+' : '$count';

String dlrDprSeenKey(String projectId) => 'dlr_dpr_seen_$projectId';
