// Helpers for Sales SOP "Upcoming" rows returned by get_projects_for_user
// when the app sends include_upcoming_sops=1 (Architect roles only).
// These rows have no ERP project id: {id: null, sales_sop_id, is_upcoming: true}.

bool isUpcomingSopRow(dynamic p) {
  if (p is! Map) return false;
  final flag = p['is_upcoming'];
  final upcoming = flag == true || flag == 1 || flag?.toString() == 'true';
  final sop = p['sales_sop_id']?.toString().trim() ?? '';
  return upcoming && sop.isNotEmpty && sop != 'null';
}

class UpcomingSopSplit {
  final List<dynamic> projects;
  final List<dynamic> upcoming;
  const UpcomingSopSplit(this.projects, this.upcoming);
}

/// Splits an API list into ERP project rows and upcoming SOP rows.
/// ERP rows keep their original order/shape so existing consumers are unaffected.
UpcomingSopSplit splitUpcomingSopRows(List<dynamic> rows) {
  final projects = <dynamic>[];
  final upcoming = <dynamic>[];
  for (final r in rows) {
    (isUpcomingSopRow(r) ? upcoming : projects).add(r);
  }
  return UpcomingSopSplit(projects, upcoming);
}