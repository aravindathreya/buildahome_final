import 'package:flutter/widgets.dart';

import '../site_proof_multi/multi_material_site_proof_screen.dart';
import 'camera_capture_recovery.dart';

/// Screens the dashboard can reopen directly after Android killed the app
/// while the camera was open. Other screens get their recovered file back
/// through [CameraCaptureRecovery.takeRecovered] when they are opened again.
void registerCameraCaptureResumers() {
  CameraCaptureRecovery.registerResumer(
    CameraCaptureScreens.multiMaterialSiteProof,
    MultiMaterialSiteProofScreen.resumeAfterCameraRestart,
  );
}

/// Called by the dashboards on start, next to the daily update recovery.
Future<void> resumePendingCameraCapture(BuildContext context) async {
  registerCameraCaptureResumers();
  if (!context.mounted) return;
  await CameraCaptureRecovery.resumeIfPending(context);
}
