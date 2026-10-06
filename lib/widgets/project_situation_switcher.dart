import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/data_provider.dart';

enum ProjectSituationTab { focus, status, timeline, schedule }

bool isClientSituationRole(String? role) {
  return (role ?? '').trim().toLowerCase() == 'client';
}

/// Clients see Focus + Timeline. Staff also get Status.
/// Schedule is not shown for non-clients.
List<ProjectSituationTab> projectSituationTabsForRole(String? role) {
  final client = isClientSituationRole(role);
  return [
    ProjectSituationTab.focus,
    if (!client) ProjectSituationTab.status,
    ProjectSituationTab.timeline,
  ];
}

/// Compact Focus / Status / Timeline / Schedule switcher shared by situation screens.
class ProjectSituationSwitcher extends StatelessWidget
    implements PreferredSizeWidget {
  final ProjectSituationTab selected;
  final ValueChanged<ProjectSituationTab> onChanged;
  final bool? showStatus;
  final bool? showSchedule;

  const ProjectSituationSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showStatus,
    this.showSchedule,
  });

  List<ProjectSituationTab> get _tabs {
    final role = DataProvider().currentRole;
    return [
      ProjectSituationTab.focus,
      if (showStatus ?? !isClientSituationRole(role))
        ProjectSituationTab.status,
      ProjectSituationTab.timeline,
      if (showSchedule == true) ProjectSituationTab.schedule,
    ];
  }

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    const labels = {
      ProjectSituationTab.focus: 'Focus',
      ProjectSituationTab.status: 'Status',
      ProjectSituationTab.timeline: 'Timeline',
      ProjectSituationTab.schedule: 'Schedule',
    };
    final tabs = [
      for (final tab in _tabs) MapEntry(tab, labels[tab]!),
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

bool isMainCriticalTimelineTask(Map<String, dynamic> task) {
  if (timelineTaskTruthy(task['is_main_critical'])) return true;
  for (final nestKey in const [
    'main_critical',
    'meta',
    'context',
    'context_json',
  ]) {
    final nest = task[nestKey];
    if (nest is Map && timelineTaskTruthy(nest['is_main_critical'])) {
      return true;
    }
  }
  return false;
}

/// Timeline shows only Main Critical tasks for every role.
List<Map<String, dynamic>> visibleTimelineTasksForRole({
  required String? role,
  required List<Map<String, dynamic>> tasks,
  required bool criticalOnly,
}) {
  if (criticalOnly) {
    return tasks.where(isMainCriticalTimelineTask).toList();
  }
  return List<Map<String, dynamic>>.from(tasks);
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
