import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/data_provider.dart';

enum ProjectSituationTab { focus, status, timeline, schedule }

/// Compact Focus / Status / Timeline / Schedule switcher shared by situation screens.
class ProjectSituationSwitcher extends StatelessWidget
    implements PreferredSizeWidget {
  final ProjectSituationTab selected;
  final ValueChanged<ProjectSituationTab> onChanged;
  final bool? showSchedule;

  const ProjectSituationSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showSchedule,
  });

  bool get _showSchedule {
    if (showSchedule != null) return showSchedule!;
    final role = (DataProvider().currentRole ?? '').trim().toLowerCase();
    return role.isNotEmpty && role != 'client';
  }

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final tabs = <MapEntry<ProjectSituationTab, String>>[
      const MapEntry(ProjectSituationTab.focus, 'Focus'),
      const MapEntry(ProjectSituationTab.status, 'Status'),
      const MapEntry(ProjectSituationTab.timeline, 'Timeline'),
      if (_showSchedule)
        const MapEntry(ProjectSituationTab.schedule, 'Schedule'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTheme.darkBackgroundPrimaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final tab in tabs)
              _TabChip(
                label: tab.value,
                selected: selected == tab.key,
                onTap: () => onChanged(tab.key),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppTheme.navy : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected
                    ? Colors.white
                    : AppTheme.darkTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared helpers for timeline / schedule task lists.
bool timelineTaskTruthy(dynamic value) {
  if (value == true || value == 1) return true;
  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

bool isOngoingTimelineTask(Map<String, dynamic> task) {
  return timelineTaskTruthy(task['is_pending']) &&
      !timelineTaskTruthy(task['is_completed']) &&
      !timelineTaskTruthy(task['is_cancelled']) &&
      !timelineTaskTruthy(task['is_upcoming']) &&
      !timelineTaskTruthy(task['is_not_started']);
}

int? indexOfOngoingTimelineTask(List<Map<String, dynamic>> tasks) {
  for (var i = 0; i < tasks.length; i++) {
    if (isOngoingTimelineTask(tasks[i])) return i;
  }
  // Fallback: first incomplete non-cancelled task.
  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    if (!timelineTaskTruthy(task['is_completed']) &&
        !timelineTaskTruthy(task['is_cancelled'])) {
      return i;
    }
  }
  return null;
}
