import 'package:buildAhome/client_portal/client_portal_hub.dart';
import 'package:buildAhome/models/workflow_document.dart';
import 'package:buildAhome/services/receipts_agreements_service.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptsAgreementsResult _result({bool canView = true, int docs = 2}) {
  return ReceiptsAgreementsResult(
    canView: canView,
    projectId: '1662',
    groups: [
      ReceiptsAgreementsGroup(
        id: 'receipts',
        label: 'Receipts',
        documents: List.generate(
          docs,
          (i) => WorkflowDocumentUpload(
            id: 'receipt_$i',
            documentKey: 'receipt:$i',
            name: 'r$i.pdf',
            url: 'https://example.com/r$i.pdf',
            sectionId: 'receipts',
            sectionLabel: 'Receipts',
            categoryId: 'receipts_and_agreements',
            categoryLabel: 'Receipts and Agreements',
          ),
        ),
      ),
    ],
  );
}

void main() {
  test('ERP receipts row shows when canView and total > 0', () {
    final items = buildClientPortalHubItems(
      null,
      includeKyc: false,
      role: 'Admin',
      erpReceipts: _result(),
    );
    final receipts =
        items.where((i) => i.kind == ClientPortalHubKind.receipts).toList();
    expect(receipts, hasLength(1));
    expect(receipts.single.isErpReceipts, isTrue);
    expect(receipts.single.badgeCount, 2);
    expect(receipts.single.subtitle, 'Receipts');
  });

  test('ERP receipts row hidden when empty or not allowed', () {
    for (final r in [_result(docs: 0), _result(canView: false)]) {
      final items = buildClientPortalHubItems(
        null,
        includeKyc: false,
        role: 'Admin',
        erpReceipts: r,
      );
      expect(items.where((i) => i.kind == ClientPortalHubKind.receipts),
          isEmpty);
    }
  });

  test('no ERP result keeps library behaviour (no receipts without library)',
      () {
    final items =
        buildClientPortalHubItems(null, includeKyc: false, role: 'Admin');
    expect(
        items.where((i) => i.kind == ClientPortalHubKind.receipts), isEmpty);
  });
}

