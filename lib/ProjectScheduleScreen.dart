import 'package:flutter/material.dart';

import 'ProjectSituationShell.dart';

/// Full project schedule (critical + non-critical). Staff / non-clients only.
class ProjectScheduleScreen extends StatelessWidget {
  const ProjectScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProjectSituationShell.schedule();
  }
}
