import '../models/approved_po.dart';

/// Public helper: resolve workflow item-run id the same way My Tasks does.
String resolvedWorkflowItemRunIdFromTask(Map<String, dynamic> task) {
  final directId = task['workflow_item_run_id']?.toString().trim() ?? '';
  if (directId.isNotEmpty) return directId;

  final taskId = int.tryParse(task['id']?.toString() ?? '');
  if (taskId != null && taskId < 0) return taskId.abs().toString();

  return '';
}

/// Flow decision for Approved PO / site-proof tasks.
///
/// Backend treats **all** Approved POs as the new partial flow
/// (`site_proof_flow: "multi"`), including 1-material indents.
/// Only an explicit `"single"` keeps the legacy screens.
bool shouldUseMultiMaterialSiteProof({
  String? siteProofFlow,
  int? materialCount,
  int materialsLength = 0,
}) {
  final flow = (siteProofFlow ?? '').trim().toLowerCase();
  if (flow == 'single') return false;
  return true;
}

bool approvedPoUsesMultiMaterialSiteProof(ApprovedPo po) =>
    po.usesMultiMaterialSiteProof;
