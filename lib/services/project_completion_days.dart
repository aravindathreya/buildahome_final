/// Estimates construction days still pending from a known duration and progress.
/// Missing or nonpositive duration is unknown, rather than a completed project.
/// Round partial days up so unfinished work retains at least one pending day.
int? remainingProjectDays({
  required int? totalDays,
  required String? completion,
}) {
  if (totalDays == null || totalDays <= 0) return null;
  final percent = double.tryParse(completion?.replaceAll('%', '').trim() ?? '');
  if (percent == null || !percent.isFinite) return null;
  final boundedPercent = percent.clamp(0.0, 100.0);
  final remaining = (totalDays * (100.0 - boundedPercent) / 100.0).ceil();
  return remaining.clamp(0, totalDays).toInt();
}
