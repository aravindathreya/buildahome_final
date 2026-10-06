import 'package:buildAhome/models/workflow_document.dart';
import 'package:buildAhome/services/document_role_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('document_role_access', () {
    test('KYC is Client and Super Admin only', () {
      expect(roleCanSeeForMeKyc('Client'), isTrue);
      expect(roleCanSeeForMeKyc('Admin'), isTrue);
      expect(roleCanSeeForMeKyc('Super Admin'), isTrue);
      expect(roleCanSeeForMeKyc('Project Manager'), isFalse);
      expect(roleCanSeeForMeKyc('Site Engineer'), isFalse);
      expect(roleCanSeeForMeKyc('Billing'), isFalse);

      expect(
        documentAccessForRole(role: 'Client', kind: ForMeDocKind.kyc).upload,
        isTrue,
      );
      expect(
        documentAccessForRole(role: 'Billing', kind: ForMeDocKind.kyc).view,
        isFalse,
      );
    });

    test('Architect can edit floor plans; Site Engineer view only', () {
      final arch = documentAccessForRole(
        role: 'Sr. Arch',
        kind: ForMeDocKind.architecturalFloorPlan,
      );
      expect(arch.view, isTrue);
      expect(arch.edit, isTrue);
      expect(arch.upload, isTrue);
      expect(arch.delete, isTrue);

      final se = documentAccessForRole(
        role: 'Site Engineer',
        kind: ForMeDocKind.architecturalFloorPlan,
      );
      expect(se.view, isTrue);
      expect(se.edit, isFalse);
      expect(se.upload, isFalse);
    });

    test('Structural and MEP designer edit their own drawings', () {
      final structural = documentAccessForRole(
        role: 'Structural Engineer',
        kind: ForMeDocKind.structuralFraming,
      );
      expect(structural.edit, isTrue);
      expect(structural.upload, isTrue);

      final mep = documentAccessForRole(
        role: 'MEP Designer',
        kind: ForMeDocKind.electrical,
      );
      expect(mep.edit, isTrue);

      final mepEng = documentAccessForRole(
        role: 'MEP engineer',
        kind: ForMeDocKind.electrical,
      );
      expect(mepEng.view, isTrue);
      expect(mepEng.edit, isFalse);
    });

    test('QC can edit QC reports; Finance can edit agreements', () {
      final qc = documentAccessForRole(
        role: 'QA/QC',
        kind: ForMeDocKind.qualityQcReports,
      );
      expect(qc.view, isTrue);
      expect(qc.edit, isTrue);
      expect(qc.upload, isTrue);

      final finance = documentAccessForRole(
        role: 'Billing',
        kind: ForMeDocKind.contractsAgreement,
      );
      expect(finance.view, isTrue);
      expect(finance.edit, isTrue);
      expect(finance.upload, isTrue);

      final seAgreement = documentAccessForRole(
        role: 'Site Engineer',
        kind: ForMeDocKind.contractsAgreement,
      );
      expect(seAgreement.view, isFalse);
    });

    test('Client cannot see Final Area Statement', () {
      final client = documentAccessForRole(
        role: 'Client',
        kind: ForMeDocKind.architecturalFinalAreaStatement,
      );
      expect(client.view, isFalse);

      final pm = documentAccessForRole(
        role: 'Project Manager',
        kind: ForMeDocKind.architecturalFinalAreaStatement,
      );
      expect(pm.view, isTrue);
    });

    test('Site Document and Planning & Commercial are staff-only view', () {
      expect(
        documentAccessForRole(
          role: 'Site Engineer',
          kind: ForMeDocKind.siteDocument,
        ).view,
        isTrue,
      );
      expect(
        documentAccessForRole(
          role: 'Client',
          kind: ForMeDocKind.siteDocument,
        ).view,
        isFalse,
      );
      expect(
        documentAccessForRole(
          role: 'Project Manager',
          kind: ForMeDocKind.planningCommercial,
        ).view,
        isTrue,
      );
      expect(
        documentAccessForRole(
          role: 'Client',
          kind: ForMeDocKind.planningCommercial,
        ).view,
        isFalse,
      );
      expect(
        classifyForMeDocument(sectionLabel: 'Final Cost Sheet'),
        ForMeDocKind.planningCommercial,
      );
      expect(
        classifyForMeDocument(categoryLabel: 'Site Document'),
        ForMeDocKind.siteDocument,
      );
    });

    test('non-clients see the client catalog without KYC', () {
      WorkflowDocumentUpload doc(String id, String name) {
        return WorkflowDocumentUpload(
          id: id,
          documentKey: id,
          name: name,
          isLatest: true,
        );
      }

      final categories = [
        WorkflowDocumentCategory(
          id: 'kyc',
          label: 'KYC & Documents',
          sections: [
            WorkflowDocumentSection(
              id: 'kyc',
              label: 'KYC',
              documents: [doc('1', 'Aadhaar')],
            ),
          ],
        ),
        WorkflowDocumentCategory(
          id: 'structural',
          label: 'Structural & Civil',
          sections: [
            WorkflowDocumentSection(
              id: 'framing',
              label: 'Framing',
              documents: [doc('2', 'Framing drawing')],
            ),
          ],
        ),
        WorkflowDocumentCategory(
          id: 'design',
          label: 'Designs and details',
          sections: [
            WorkflowDocumentSection(
              id: 'door',
              label: 'Door window grill',
              documents: [doc('3', 'Door detail')],
            ),
          ],
        ),
        WorkflowDocumentCategory(
          id: 'site_document',
          label: 'Site Document',
          sections: [
            WorkflowDocumentSection(
              id: 'report',
              label: 'Site Inspection Report',
              documents: [doc('4', 'Report')],
            ),
          ],
        ),
      ];

      final client = filterDocumentCategoriesForRole(categories, 'Client')
          .map((category) => category.label)
          .toList();
      final staff = filterDocumentCategoriesForRole(categories, 'Site Engineer')
          .map((category) => category.label)
          .toList();

      expect(client, contains('KYC & Documents'));
      expect(client, containsAll(['Structural & Civil', 'Designs and details']));
      expect(client, isNot(contains('Site Document')));

      expect(staff, isNot(contains('KYC & Documents')));
      expect(
        staff,
        client.where((label) => label != 'KYC & Documents').toList(),
      );
    });

    test('project coordinator uses the For me matrix, not the client catalog', () {
      WorkflowDocumentUpload doc(String id, String name) {
        return WorkflowDocumentUpload(
          id: id,
          documentKey: id,
          name: name,
          isLatest: true,
        );
      }

      WorkflowDocumentCategory category(String id, String label) {
        return WorkflowDocumentCategory(
          id: id,
          label: label,
          sections: [
            WorkflowDocumentSection(
              id: id,
              label: label,
              documents: [doc(id, label)],
            ),
          ],
        );
      }

      final labels = filterDocumentCategoriesForRole(
        [
          category('kyc', 'KYC & Documents'),
          category('booking', 'Booking form'),
          category('receipts', 'Payment receipts'),
          category('structural', 'Structural & Civil'),
          category('electrical', 'Electrical'),
          category('site_document', 'Site Document'),
        ],
        'Project Coordinator',
      ).map((category) => category.label).toList();

      expect(labels, isNot(contains('KYC & Documents')));
      expect(labels, isNot(contains('Booking form')));
      expect(labels, isNot(contains('Payment receipts')));
      expect(labels, containsAll(['Structural & Civil', 'Electrical', 'Site Document']));
    });

    test('classifier maps common labels', () {
      expect(
        classifyForMeDocument(sectionLabel: 'Floor plan'),
        ForMeDocKind.architecturalFloorPlan,
      );
      expect(
        classifyForMeDocument(categoryLabel: 'KYC & Documents'),
        ForMeDocKind.kyc,
      );
      expect(
        classifyForMeDocument(journeyKey: 'office_documents'),
        ForMeDocKind.officeDocuments,
      );
      expect(
        classifyForMeDocument(sectionLabel: 'Agreement'),
        ForMeDocKind.contractsAgreement,
      );
    });
  });
}
