import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/widgets/project_situation_switcher.dart';

void main() {
  group('projectSituationTabsForRole', () {
    test('client only sees Focus and Timeline', () {
      expect(
        projectSituationTabsForRole('Client'),
        [
          ProjectSituationTab.focus,
          ProjectSituationTab.timeline,
        ],
      );
    });

    test('staff sees Focus, Status, and Timeline', () {
      expect(
        projectSituationTabsForRole('Admin'),
        [
          ProjectSituationTab.focus,
          ProjectSituationTab.status,
          ProjectSituationTab.timeline,
        ],
      );
      expect(
        projectSituationTabsForRole('Site Engineer'),
        isNot(contains(ProjectSituationTab.schedule)),
      );
    });
  });

  group('visibleTimelineTasksForRole', () {
    final tasks = [
      {'task_name': 'Main slab', 'is_main_critical': true},
      {'task_name': 'Side plaster', 'is_main_critical': false},
      {
        'task_name': 'Nested main',
        'main_critical': {'is_main_critical': 'yes'},
      },
    ];

    test('client timeline keeps only main critical tasks', () {
      final visible = visibleTimelineTasksForRole(
        role: 'Client',
        tasks: tasks,
        criticalOnly: true,
      );
      expect(
        visible.map((t) => t['task_name']),
        ['Main slab', 'Nested main'],
      );
    });

    test('staff timeline keeps only main critical tasks', () {
      final visible = visibleTimelineTasksForRole(
        role: 'Admin',
        tasks: tasks,
        criticalOnly: true,
      );
      expect(
        visible.map((t) => t['task_name']),
        ['Main slab', 'Nested main'],
      );
    });
  });
}
