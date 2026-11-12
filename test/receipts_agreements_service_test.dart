import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/services/receipts_agreements_service.dart';

void main() {
  test('receipts payload parses groups and hides empty tabs', () {
    final result = parseReceiptsAgreementsPayload({
      'success': true,
      'project_id': 1289,
      'can_view': true,
      'groups': [
        {
          'id': 'receipts',
          'label': 'Receipts',
          'documents': [
            {'doc_id': 2, 'name': 'b.pdf', 'url': 'https://x/files/b.pdf'},
            {'doc_id': 1, 'name': 'a.pdf', 'url': 'https://x/files/a.pdf'},
          ],
        },
        {'id': 'agreements', 'label': 'Agreements', 'documents': []},
      ],
    }, projectId: '1289');
    expect(result.total, 2);
    expect(result.nonEmptyGroups.map((g) => g.id), ['receipts']);
    expect(result.groups.first.documents.first.name, 'b.pdf');
  });
}