import '../models/approved_po.dart';

/// Public helper: resolve workflow item-run id the same way My Tasks does.
String resolvedWorkflowItemRunIdFromTask(Map<String, dynamic> task) {
  final directId = task['workflow_item_run_id']?.toString().trim() ?? '';
  if (directId.isNotEmpty) return directId;

  final taskId = int.tryParse(task['id']?.toString() ?? '');
  if (taskId != null && taskId < 0) return taskId.abs().toString();

  return '';
}

/// Flow decision from approved PO (or equivalent) fields.
///
/// Single path when `site_proof_flow == "single"` OR `material_count <= 1`.
/// Multi path when `site_proof_flow == "multi"` OR `material_count > 1`.
bool shouldUseMultiMaterialSiteProof({
  String? siteProofFlow,
  int? materialCount,
  int materialsLength = 0,
}) {
  final flow = (siteProofFlow ?? '').trim().toLowerCase();
  final count = (materialCount != null && materialCount > 0)
      ? materialCount
      : materialsLength;
  if (flow == 'single' || count <= 1) return false;
  if (flow == 'multi' || count > 1) return true;
  return false;
}

bool approvedPoUsesMultiMaterialSiteProof(ApprovedPo po) =>
    po.usesMultiMaterialSiteProof;
