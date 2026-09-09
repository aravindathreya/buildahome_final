import 'package:flutter/material.dart';

import 'mobile_live_test_task_body.dart';
import 'services/mobile_live_test_controller.dart';
import 'services/mobile_live_test_service.dart';
import 'widgets/modern_task_card.dart';
import 'widgets/themed_scaffold.dart';

/// Full-screen wrapper for a single live-test task.
class MobileLiveTestTaskScreen extends StatelessWidget {
  final int itemRunId;
  final MobileLiveTestService? service;
  final MobileLiveTestController? listController;

  const MobileLiveTestTaskScreen({
    super.key,
    required this.itemRunId,
    this.service,
    this.listController,
  });

  MobileLiveTestService get _service => service ?? MobileLiveTestService.instance;

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'My tasks',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          MobileLiveTestTaskBody(
            itemRunId: itemRunId,
            service: _service,
            listController: listController,
            showTestBadge: true,
            onUnavailable: () => Navigator.of(context).pop(true),
            onCompleted: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop(true);
              }
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Test execution: logged in as Super Admin; backend acts as the mapped test user.',
            style: TextStyle(
              color: kTaskMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
