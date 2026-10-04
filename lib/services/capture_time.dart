import 'package:intl/intl.dart';

/// Device-local capture clock helpers (Asia/Calcutta wall time on IST phones).
///
/// Never stamp filenames or `captured_at` from UTC components — that produces
/// `live_YYYYMMDD_HHMMSS` labels that look 5h30m early when the phone is on IST.
class CaptureTime {
  CaptureTime._();

  /// Local wall-clock now with `isUtc == false` (safe for DateFormat stamps).
  static DateTime nowLocal() {
    final now = DateTime.now();
    if (!now.isUtc) return now;
    final local = now.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  /// `live_yyyyMMdd_HHmmss.jpg` / `video_yyyyMMdd_HHmmss.mp4` using local time.
  static String stampFilename({
    required bool isVideo,
    DateTime? at,
    String imageExt = 'jpg',
    String videoExt = 'mp4',
  }) {
    final local = _asLocal(at ?? nowLocal());
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(local);
    if (isVideo) return 'video_$stamp.$videoExt';
    return 'live_$stamp.$imageExt';
  }

  /// ISO-8601 with numeric offset (e.g. 2026-09-28T08:04:47+05:30), never bare UTC-Z.
  static String toOffsetIso(DateTime at) {
    final local = _asLocal(at);
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final mins = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final base = DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(local);
    return '$base$sign$hours:$mins';
  }

  static DateTime _asLocal(DateTime at) {
    if (!at.isUtc) return at;
    final local = at.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }
}
