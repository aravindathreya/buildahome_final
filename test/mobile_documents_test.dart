import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/client_portal/client_portal_document_ui.dart';
import 'package:buildAhome/client_portal/client_portal_hub.dart';
import 'package:buildAhome/documents_v1/documents_v1_home_screen.dart';
import 'package:buildAhome/models/workflow_document.dart';
import 'package:buildAhome/services/mobile_documents.dart';
import 'package:buildAhome/services/mobile_quick_actions.dart';

Map<String, dynamic> _architecturalPayload({
  required String projectId,
  required List<String> floorPlans,
  bool includeContracts = true,
  bool configured = true,
}) {
  return {
    'message': 'success',
    'configured': configured,
    'project_id': projectId,
    'user_id': 'u1',
    'extra_future_field': {'nested': true},
    'categories': [
      {
        'id': 'architectural',
        'label': 'Architectural',
        'unknown_category_flag': true,
        'types': [
          {
            'id': 'floor_plans',
            'label': 'Floor Plans',
            'documents': [
              for (var i = 0; i < floorPlans.length; i++)
                {
                  'id': 'fp_$i',
                  'document_key': floorPlans[i]
                      .toLowerCase()
                      .replaceAll(' ', '_'),
                  'name': floorPlans[i],
                  'status': 'uploaded',
                  'url': '/files/${floorPlans[i]}.pdf',
                  'mystery_column': 'ok',
                },
            ],
          },
        ],
      },
      if (includeContracts)
        {
          'id': 'contracts',
          'label': 'Contracts',
          'types': [
            {
              'id': 'agreements',
              'label': 'Agreements',
              'documents': [
                {
                  'id': 'c1',
                  'name': 'Construction Agreement',
                  'status': 'available',
                  'url': '/files/agreement.pdf',
                },
              ],
            },
          ],
        },
    ],
  };
}

List<String> _categoryLabels(WorkflowDocumentLibrary library) {
  return [for (final c in library.libraryCategories) c.label];
}

List<String> _typeLabels(WorkflowDocumentCategory category) {
  return [for (final s in category.sections) s.label];
}

List<String> _docNames(WorkflowDocumentSection section) {
  return [for (final d in section.documents) d.name];
}

WorkflowDocumentCategory _category(
  WorkflowDocumentLibrary library,
  String label,
) {
  return library.libraryCategories.firstWhere((c) => c.label == label);
}

void main() {
  group('mobileDocumentsCacheKey', () {
    test('includes user, role, and project', () {
      expect(
        mobileDocumentsCacheKey(
          userId: '1',
          role: 'Admin',
          projectId: '100',
        ),
        'mobile_documents_v1_1_Admin_100',
      );
    });

    test('isolates cache by project, user, and role', () {
      final a = mobileDocumentsCacheKey(
        userId: '1',
        role: 'Admin',
        projectId: '100',
      );
      final b = mobileDocumentsCacheKey(
        userId: '1',
        role: 'Admin',
        projectId: '200',
      );
      final c = mobileDocumentsCacheKey(
        userId: '2',
        role: 'Admin',
        projectId: '100',
      );
      final d = mobileDocumentsCacheKey(
        userId: '1',
        role: 'Client',
        projectId: '100',
      );
      expect({a, b, c, d}.length, 4);
    });

    test('Quick Action cache prefix stays distinct', () {
      final docs = mobileDocumentsCacheKey(
        userId: '1',
        role: 'Admin',
        projectId: '100',
      );
      final qa = mobileQuickActionsCacheKey(
        userId: '1',
        role: 'Admin',
        surface: MobileQuickActionSurface.staffHome,
      );
      expect(docs, isNot(qa));
      expect(docs, contains('mobile_documents_v1_'));
    });
  });

  group('parseMobileDocumentsPayload', () {
    test('renders Category → Type → Document dynamically', () {
      final snapshot = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '100',
          floorPlans: [
            'Ground Floor Plan',
            'First Floor Plan',
          ],
        ),
        expectedProjectId: '100',
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.configured, isTrue);
      expect(_categoryLabels(snapshot.library), contains('Architectural'));

      final architectural = _category(snapshot.library, 'Architectural');
      expect(_typeLabels(architectural), ['Floor Plans']);
      expect(
        _docNames(architectural.sections.first),
        ['Ground Floor Plan', 'First Floor Plan'],
      );
    });

    test('G+1 vs G+2 document lists come from the payload', () {
      final g1 = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: 'g1',
          floorPlans: ['Ground Floor Plan', 'First Floor Plan'],
          includeContracts: false,
        ),
      )!;
      final g2 = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: 'g2',
          floorPlans: [
            'Ground Floor Plan',
            'First Floor Plan',
            'Second Floor Plan',
          ],
          includeContracts: false,
        ),
      )!;

      final g1Docs = _docNames(_category(g1.library, 'Architectural').sections.first);
      final g2Docs = _docNames(_category(g2.library, 'Architectural').sections.first);
      expect(g1Docs, ['Ground Floor Plan', 'First Floor Plan']);
      expect(g2Docs, contains('Second Floor Plan'));
      expect(g1Docs, isNot(g2Docs));
    });

    test('Contracts folder is omitted from the catalog', () {
      final staff = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '100',
          floorPlans: ['Ground Floor Plan'],
          includeContracts: true,
        ),
      )!;
      final client = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '100',
          floorPlans: ['Ground Floor Plan'],
          includeContracts: false,
        ),
      )!;

      expect(_categoryLabels(staff.library), contains('Architectural'));
      expect(_categoryLabels(staff.library), isNot(contains('Contracts')));
      expect(_categoryLabels(client.library), isNot(contains('Contracts')));
    });

    test('unknown categories and fields are kept without crashing', () {
      final snapshot = parseMobileDocumentsPayload({
        'success': true,
        'configured': true,
        'project_id': '9',
        'brand_new_top_level': 123,
        'categories': [
          {
            'id': 'fire_safety',
            'label': 'Fire Safety',
            'future_icon_pack': 'lucide',
            'types': [
              {
                'id': 'sprinklers',
                'label': 'Sprinkler Layouts',
                'documents': [
                  {
                    'id': 'fs1',
                    'name': 'Ground Floor Sprinklers',
                    'status': 'queued_for_review',
                    'brand_new_status_meta': {'x': 1},
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(snapshot, isNotNull);
      expect(_categoryLabels(snapshot!.library), ['Fire Safety']);
      expect(
        snapshot.library.libraryCategories.first.sections.first.documents.first
            .name,
        'Ground Floor Sprinklers',
      );
      expect(
        snapshot.library.libraryCategories.first.sections.first.documents.first
            .displayStatus,
        'queued_for_review',
      );
    });

    test('empty configured catalog is intentional, not a parse failure', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': 'empty',
        'categories': [],
      });
      expect(snapshot, isNotNull);
      expect(shouldUseMobileDocumentsSnapshot(snapshot), isTrue);
      expect(snapshot!.isIntentionalEmpty, isTrue);
      expect(snapshot.library.libraryCategories, isEmpty);
    });

    test('inactive required documents still appear without a file url', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'label': 'Floor Plans',
                'documents': [
                  {
                    'id': 'gfp',
                    'document_key': 'ground_floor_plan',
                    'name': 'Ground Floor Plan',
                    'status': 'inactive',
                    'required': true,
                    'mandatory': true,
                  },
                ],
              },
            ],
          },
        ],
      });
      final doc = snapshot!.library.libraryCategories.first.sections.first
          .documents.single;
      expect(doc.name, 'Ground Floor Plan');
      expect(doc.hasUrl, isFalse);
      expect(doc.status, 'inactive');
      expect(doc.isLatest, isTrue);
      expect(doc.raw['mandatory'], isTrue);
    });

    test('duplicate documents are collapsed', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'label': 'Floor Plans',
                'documents': [
                  {
                    'id': 'gfp',
                    'document_key': 'ground_floor_plan',
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/files/g.pdf',
                    'revision': 1,
                  },
                  {
                    'id': 'gfp',
                    'document_key': 'ground_floor_plan',
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/files/g.pdf',
                    'revision': 1,
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(
        snapshot!.library.libraryCategories.first.sections.first.documents
            .length,
        1,
      );
    });

    test('configured false is a fallback signal', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': false,
        'project_id': '100',
        'categories': [],
      });
      expect(snapshot, isNotNull);
      expect(shouldUseMobileDocumentsSnapshot(snapshot), isFalse);
    });

    test('API failure / unauthorized payloads parse as null', () {
      expect(parseMobileDocumentsPayload(null), isNull);
      expect(parseMobileDocumentsPayload('nope'), isNull);
      expect(
        parseMobileDocumentsPayload({
          'success': false,
          'message': 'Unauthorized',
          'project_id': '100',
        }),
        isNull,
      );
      expect(
        parseMobileDocumentsPayload({
          'error': 'timeout',
        }),
        isNull,
      );
    });

    test('rejects a snapshot built for a different project', () {
      final payload = _architecturalPayload(
        projectId: '100',
        floorPlans: ['Ground Floor Plan'],
        includeContracts: false,
      );
      expect(
        parseMobileDocumentsPayload(payload, expectedProjectId: '200'),
        isNull,
      );
    });

    test('cached Project A JSON cannot hydrate Project B', () {
      final snapshot = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '100',
          floorPlans: ['Ground Floor Plan'],
          includeContracts: false,
        ),
      )!;
      final cached = snapshot.toJson();
      expect(
        MobileDocumentsSnapshot.fromJson(cached, expectedProjectId: '200'),
        isNull,
      );
      expect(
        MobileDocumentsSnapshot.fromJson(cached, expectedProjectId: '100')
            ?.projectId,
        '100',
      );
    });

    test('cached snapshot for another user is rejected', () {
      final snapshot = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '100',
          floorPlans: ['Ground Floor Plan'],
          includeContracts: false,
        ),
      )!;
      final cached = {
        ...snapshot.toJson(),
        'user_id': 'u1',
      };
      expect(
        MobileDocumentsSnapshot.fromJson(
          cached,
          expectedProjectId: '100',
          expectedUserId: 'u2',
        ),
        isNull,
      );
    });

    test('client fixed project uses the payload project_id', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': 'client-fixed-9',
        'categories': [
          {
            'id': 'landscape',
            'label': 'Landscape',
            'types': [
              {
                'id': 'planting',
                'label': 'Planting Plans',
                'documents': [
                  {'id': '1', 'name': 'Front Garden', 'status': 'pending'},
                ],
              },
            ],
          },
        ],
      });
      expect(snapshot!.projectId, 'client-fixed-9');
      expect(_categoryLabels(snapshot.library), ['Landscape']);
    });

    test('pending / missing / uploaded / available statuses survive', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'elevations',
                'label': 'Elevations',
                'documents': [
                  {'id': '1', 'name': 'Front', 'status': 'uploaded', 'url': '/a.pdf'},
                  {'id': '2', 'name': 'Rear', 'status': 'pending'},
                  {'id': '3', 'name': 'Side', 'status': 'missing'},
                  {'id': '4', 'name': 'Terrace', 'status': 'available', 'url': '/b.pdf'},
                ],
              },
            ],
          },
        ],
      });
      final names = {
        for (final doc in snapshot!
            .library.libraryCategories.first.sections.first.documents)
          doc.name: doc.displayStatus,
      };
      expect(names['Front'], 'Uploaded');
      expect(names['Rear'], 'Pending');
      expect(names['Side'], 'Pending');
      expect(names['Terrace'], 'Available');
    });

    test('Quality splits SIPR and SD into inspection report and site document',
        () {
      final category = WorkflowDocumentCategory(
        id: 'quality_test_reports',
        label: 'Quality and test report',
        sections: [
          WorkflowDocumentSection(
            id: 'soil',
            label: 'Soil test report',
            categoryId: 'quality_test_reports',
            categoryLabel: 'Quality and test report',
            documents: [
              WorkflowDocumentUpload(
                id: 's1',
                documentKey: 'soil_test_report',
                name: 'Soil test report',
                url: '/files/soil.pdf',
                status: 'uploaded',
                isLatest: true,
              ),
            ],
          ),
          WorkflowDocumentSection(
            id: 'sipr_sd',
            label: 'SIPR,SD',
            categoryId: 'quality_test_reports',
            categoryLabel: 'Quality and test report',
            documents: [
              WorkflowDocumentUpload(
                id: 'sipr1',
                documentKey: 'report_a',
                name: 'Inspection pack.pdf',
                url: '/files/sipr.pdf',
                status: 'uploaded',
                isLatest: true,
              ),
              WorkflowDocumentUpload(
                id: 'sd1',
                documentKey: 'site_document',
                name: 'Site document pack',
                url: '/files/sd.pdf',
                status: 'uploaded',
                isLatest: true,
              ),
            ],
          ),
        ],
      );

      final sections = buildChecklistTypeSectionsForCategory(category)!;
      expect(
        sections.map((s) => s.label).toList(),
        [
          'Soil test report',
          'QC Reports(NDT test reports)',
          'Site inspection report',
          'Site document',
        ],
      );
      expect(sections.any((s) => s.label == 'Other'), isFalse);
      expect(sections.any((s) => s.label == 'SIPR,SD'), isFalse);
      expect(
        sections
            .firstWhere((s) => s.label == 'Site inspection report')
            .documents
            .map((d) => d.id),
        contains('sipr1'),
      );
      expect(
        sections
            .firstWhere((s) => s.label == 'Site document')
            .documents
            .single
            .id,
        'sd1',
      );
      expect(
        sectionVisualFor(
          sections.firstWhere((s) => s.label == 'Soil test report'),
        ).subtitle,
        'Soil investigation reports',
      );
    });

    test('structural checklist folders and framing shows checked versions only',
        () {
      final category = WorkflowDocumentCategory(
        id: 'structural_civil',
        label: 'Structural & Civil',
        sections: [
          WorkflowDocumentSection(
            id: 'all',
            label: 'All',
            categoryId: 'structural_civil',
            categoryLabel: 'Structural & Civil',
            documents: [
              WorkflowDocumentUpload(
                id: 'f1',
                documentKey: 'framing_drawing',
                name: 'Sample - Framing drawing.pdf',
                url: '/files/framing_v1.pdf',
                status: 'uploaded',
                isLatest: false,
                revision: 1,
                uploadedAt: '2026-10-06',
                raw: const {'checked': true},
              ),
              WorkflowDocumentUpload(
                id: 'f2',
                documentKey: 'framing_drawing',
                name: 'framing drawing 2.jpg',
                url: '/files/framing_v2.jpg',
                status: 'uploaded',
                isLatest: true,
                revision: 2,
                uploadedAt: '2026-10-12',
                raw: const {'is_current': true},
              ),
              WorkflowDocumentUpload(
                id: 'f3',
                documentKey: 'framing_drawing',
                name: 'framing old unused.pdf',
                url: '/files/framing_v0.pdf',
                status: 'uploaded',
                isLatest: false,
                revision: 0,
                uploadedAt: '2026-10-01',
                raw: const {'checked': false},
              ),
              WorkflowDocumentUpload(
                id: 'found1',
                documentKey: 'foundation',
                name: 'Foundation upto plinth',
                url: '/files/foundation.pdf',
                status: 'uploaded',
                isLatest: true,
              ),
            ],
          ),
        ],
      );

      final sections = buildChecklistTypeSectionsForCategory(category)!;
      expect(
        sections.map((s) => s.label).toList(),
        [
          'Framing drawing',
          'Foundation upto plinth',
          'Floor wise slab drawings',
        ],
      );
      final framing =
          sections.firstWhere((s) => s.label == 'Framing drawing');
      expect(framing.documents.map((d) => d.id).toList()..sort(), ['f1', 'f2']);
      expect(framing.documents.any((d) => d.id == 'f3'), isFalse);
    });

    test('checklist folders keep multiple distinct files across all types', () {
      WorkflowDocumentUpload doc({
        required String id,
        required String key,
        required String name,
        required String url,
        Map<String, dynamic> raw = const {'checked': true},
      }) {
        return WorkflowDocumentUpload(
          id: id,
          documentKey: key,
          name: name,
          url: url,
          status: 'uploaded',
          isLatest: true,
          raw: raw,
        );
      }

      final architectural = WorkflowDocumentCategory(
        id: 'architectural',
        label: 'Architectural',
        sections: [
          WorkflowDocumentSection(
            id: 'all',
            label: 'All',
            categoryId: 'architectural',
            categoryLabel: 'Architectural',
            documents: [
              doc(
                id: 'fp1',
                key: 'ground_floor_plan',
                name: 'Ground Floor Plan',
                url: '/g.pdf',
              ),
              doc(
                id: 'fp2',
                key: 'first_floor_plan',
                name: 'First Floor Plan',
                url: '/f.pdf',
              ),
              doc(
                id: 'wd1',
                key: 'working_drawing_a',
                name: 'Working drawing A',
                url: '/wa.pdf',
              ),
              doc(
                id: 'wd2',
                key: 'working_drawing_b',
                name: 'Working drawing B',
                url: '/wb.pdf',
              ),
              doc(
                id: 'fs1',
                key: 'filler_slab_kitchen',
                name: 'Filler slab - Kitchen',
                url: '/fk.pdf',
              ),
              doc(
                id: 'fs2',
                key: 'filler_slab_toilet',
                name: 'Filler slab - Toilet',
                url: '/ft.pdf',
              ),
              doc(
                id: 'sec1',
                key: 'section_aa',
                name: 'Section AA',
                url: '/saa.pdf',
              ),
              doc(
                id: 'sec2',
                key: 'section_bb',
                name: 'Section BB',
                url: '/sbb.pdf',
              ),
              doc(
                id: 'el1',
                key: 'front_elevation',
                name: 'Front Elevation',
                url: '/fe.pdf',
              ),
              doc(
                id: 'el2',
                key: 'side_elevation',
                name: 'Side Elevation',
                url: '/se.pdf',
              ),
              doc(
                id: 'e2d1',
                key: '2d_elevation_front',
                name: '2D Elevation Front',
                url: '/2df.pdf',
              ),
              doc(
                id: 'e2d2',
                key: '2d_elevation_rear',
                name: '2D Elevation Rear',
                url: '/2dr.pdf',
              ),
              doc(
                id: 'dw1',
                key: 'door_detail',
                name: 'Door detail',
                url: '/door.pdf',
              ),
              doc(
                id: 'dw2',
                key: 'window_grill',
                name: 'Window grill',
                url: '/grill.pdf',
              ),
              doc(
                id: 'fl1',
                key: 'flooring_living',
                name: 'Flooring living',
                url: '/fl1.pdf',
              ),
              doc(
                id: 'fl2',
                key: 'flooring_bedroom',
                name: 'Flooring bedroom',
                url: '/fl2.pdf',
              ),
              doc(
                id: 'dado1',
                key: 'dado_kitchen',
                name: 'Dado Kitchen',
                url: '/dk.pdf',
              ),
              doc(
                id: 'dado2',
                key: 'dado_toilet',
                name: 'Dado Toilet',
                url: '/dt.pdf',
              ),
              doc(
                id: 'fab1',
                key: 'fabrication_a',
                name: 'Fabrication A',
                url: '/fa.pdf',
              ),
              doc(
                id: 'fab2',
                key: 'fabrication_b',
                name: 'Fabrication B',
                url: '/fb.pdf',
              ),
              doc(
                id: 'sky1',
                key: 'skylight_a',
                name: 'Skylight A',
                url: '/sa.pdf',
              ),
              doc(
                id: 'sky2',
                key: 'skylight_b',
                name: 'Skylight B',
                url: '/sb.pdf',
              ),
              doc(
                id: 'paint1',
                key: 'paint_shade_ext',
                name: 'Paint shade exterior',
                url: '/pe.pdf',
              ),
              doc(
                id: 'paint2',
                key: 'paint_shade_int',
                name: 'Paint shade interior',
                url: '/pi.pdf',
              ),
              doc(
                id: 'area1',
                key: 'area_statement_v1',
                name: 'Final Area statement A',
                url: '/aa.pdf',
              ),
              doc(
                id: 'area2',
                key: 'area_statement_v2',
                name: 'Final Area statement B',
                url: '/ab.pdf',
              ),
            ],
          ),
        ],
      );

      final archSections = buildArchitecturalTypeSections(architectural);
      void expectPair(String label, List<String> ids) {
        final section = archSections.firstWhere((s) => s.label == label);
        expect(
          section.documents.map((d) => d.id).toList()..sort(),
          ids..sort(),
          reason: label,
        );
      }

      expectPair('Final Floor plan', ['fp1', 'fp2']);
      expectPair('Working drawing', ['wd1', 'wd2']);
      expectPair('Filler slab detail (if any)', ['fs1', 'fs2']);
      expectPair('Section', ['sec1', 'sec2']);
      expectPair('Final Elevation', ['el1', 'el2']);
      expectPair('2D Elevation', ['e2d1', 'e2d2']);
      expectPair('Door/Window/ grill detail', ['dw1', 'dw2']);
      expectPair('Flooring details', ['fl1', 'fl2']);
      expectPair('Dado Detail - Kitchen/toilet', ['dado1', 'dado2']);
      expectPair('Fabrication Detail', ['fab1', 'fab2']);
      expectPair('Skylight detail', ['sky1', 'sky2']);
      expectPair('Paint shade', ['paint1', 'paint2']);
      expectPair('Final Area statement', ['area1', 'area2']);

      final structural = WorkflowDocumentCategory(
        id: 'structural_civil',
        label: 'Structural & Civil',
        sections: [
          WorkflowDocumentSection(
            id: 'all',
            label: 'All',
            categoryId: 'structural_civil',
            categoryLabel: 'Structural & Civil',
            documents: [
              doc(
                id: 'fr1',
                key: 'framing_gf',
                name: 'Framing GF',
                url: '/fr1.pdf',
              ),
              doc(
                id: 'fr2',
                key: 'framing_ff',
                name: 'Framing FF',
                url: '/fr2.pdf',
              ),
              doc(
                id: 'found1',
                key: 'foundation_a',
                name: 'Foundation A',
                url: '/fo1.pdf',
              ),
              doc(
                id: 'found2',
                key: 'foundation_b',
                name: 'Foundation B',
                url: '/fo2.pdf',
              ),
              doc(
                id: 'slab1',
                key: 'floor_wise_slab_gf',
                name: 'Floor wise slab GF',
                url: '/sl1.pdf',
              ),
              doc(
                id: 'slab2',
                key: 'floor_wise_slab_ff',
                name: 'Floor wise slab FF',
                url: '/sl2.pdf',
              ),
            ],
          ),
        ],
      );
      final structSections =
          buildChecklistTypeSectionsForCategory(structural)!;
      expect(
        structSections
            .firstWhere((s) => s.label == 'Framing drawing')
            .documents
            .map((d) => d.id)
            .toList()
          ..sort(),
        ['fr1', 'fr2'],
      );
      expect(
        structSections
            .firstWhere((s) => s.label == 'Foundation upto plinth')
            .documents
            .map((d) => d.id)
            .toList()
          ..sort(),
        ['found1', 'found2'],
      );
      expect(
        structSections
            .firstWhere((s) => s.label == 'Floor wise slab drawings')
            .documents
            .map((d) => d.id)
            .toList()
          ..sort(),
        ['slab1', 'slab2'],
      );

      final quality = WorkflowDocumentCategory(
        id: 'quality',
        label: 'Quality',
        sections: [
          WorkflowDocumentSection(
            id: 'all',
            label: 'All',
            categoryId: 'quality',
            categoryLabel: 'Quality',
            documents: [
              doc(
                id: 'soil1',
                key: 'soil_a',
                name: 'Soil test A',
                url: '/soil1.pdf',
              ),
              doc(
                id: 'soil2',
                key: 'soil_b',
                name: 'Soil test B',
                url: '/soil2.pdf',
              ),
              doc(
                id: 'qc1',
                key: 'ndt_a',
                name: 'NDT report A',
                url: '/qc1.pdf',
              ),
              doc(
                id: 'qc2',
                key: 'ndt_b',
                name: 'NDT report B',
                url: '/qc2.pdf',
              ),
            ],
          ),
        ],
      );
      final qualitySections = buildChecklistTypeSectionsForCategory(quality)!;
      expect(
        qualitySections
            .firstWhere((s) => s.label == 'Soil test report')
            .documents
            .length,
        2,
      );
      expect(
        qualitySections
            .firstWhere((s) => s.label == 'QC Reports(NDT test reports)')
            .documents
            .length,
        2,
      );

      final preConversion = WorkflowDocumentCategory(
        id: 'pre_conversion',
        label: 'Pre Conversion',
        sections: [
          WorkflowDocumentSection(
            id: 'all',
            label: 'All',
            categoryId: 'pre_conversion',
            categoryLabel: 'Pre Conversion',
            documents: [
              doc(
                id: 'prop1',
                key: 'proposal_a',
                name: 'Proposal A',
                url: '/p1.pdf',
              ),
              doc(
                id: 'prop2',
                key: 'proposal_b',
                name: 'Proposal B',
                url: '/p2.pdf',
              ),
              doc(
                id: 'book1',
                key: 'booking_a',
                name: 'Booking form A',
                url: '/b1.pdf',
              ),
              doc(
                id: 'book2',
                key: 'booking_b',
                name: 'Booking form B',
                url: '/b2.pdf',
              ),
            ],
          ),
        ],
      );
      final preSections =
          buildChecklistTypeSectionsForCategory(preConversion)!;
      expect(
        preSections.firstWhere((s) => s.label == 'Proposal').documents.length,
        2,
      );
      expect(
        preSections
            .firstWhere((s) => s.label == 'Booking form')
            .documents
            .length,
        2,
      );
    });

    test('working drawing office versions keep checked rows on mobile', () {
      final expanded = expandMobileDocumentFileMaps({
        'id': 'wd1',
        'document_key': 'working_drawing',
        'name': 'Working drawing',
        'status': 'uploaded',
        'versions': [
          {
            'id': 'v1',
            'url': '/files/working_v1.pdf',
            'revision': 1,
            'checked': false,
          },
          {
            'id': 'v2',
            'url': '/files/working_v2.pdf',
            'revision': 2,
            'checked': true,
            'is_latest': true,
          },
        ],
      });
      expect(expanded, hasLength(2));
      expect(expanded.where((m) => m['checked'] == true), hasLength(1));
      expect(
        expanded.firstWhere((m) => m['checked'] == true)['url'].toString(),
        contains('working_v2'),
      );

      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': 'wd-versions',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'drawings',
                'label': 'Drawings',
                'documents': [
                  {
                    'id': 'wd1',
                    'document_key': 'working_drawing',
                    'name': 'Working drawing',
                    'status': 'uploaded',
                    'versions': [
                      {
                        'id': 'v1',
                        'url': '/files/working_v1.pdf',
                        'checked': false,
                      },
                      {
                        'id': 'v2',
                        'url': '/files/working_v2.pdf',
                        'checked': true,
                        'is_latest': true,
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      })!;
      final category = snapshot.library.libraryCategories.single;
      final sections = buildArchitecturalTypeSections(category);
      final working =
          sections.firstWhere((s) => s.label == 'Working drawing');
      expect(working.documents, hasLength(1));
      expect(working.documents.single.url, contains('working_v2'));
      expect(
        documentVersionExplicitVisibility(working.documents.single.raw),
        isTrue,
      );
    });

    test('architectural nested upload does not duplicate the row', () {
      final expanded = expandMobileDocumentFileMaps({
        'id': 'wd1',
        'document_key': 'working_drawing',
        'name': 'Sample - Working drawing.pdf',
        'status': 'pending',
        'url': '/files/working.pdf',
        'latest_upload': {
          'id': 'up1',
          'url':
              'https://cdn.example.com/bucket/working?X-Amz-Signature=sig',
        },
        'files': [
          {
            'id': 'f1',
            'url': 'https://cdn.example.com/bucket/working?X-Amz-Signature=sig',
          },
        ],
      });
      expect(expanded, hasLength(1));
      expect(expanded.single['url'], isNotNull);
      expect(
        expanded.single['url'].toString(),
        anyOf(
          contains('/files/working.pdf'),
          contains('cdn.example.com'),
        ),
      );

      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': 'arch-dup',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'drawings',
                'label': 'Drawings',
                'documents': [
                  {
                    'id': 'wd1',
                    'document_key': 'working_drawing',
                    'name': 'Sample - Working drawing.pdf',
                    'status': 'pending',
                    'url': '/files/working.pdf',
                    'latest_upload': {
                      'url':
                          'https://cdn.example.com/bucket/working?X-Amz-Signature=sig',
                    },
                  },
                ],
              },
            ],
          },
        ],
      })!;
      final docs = snapshot.library.libraryCategories.single.sections.single
          .documents;
      expect(docs, hasLength(1));
      expect(docs.single.hasUrl, isTrue);
      expect(docs.single.displayStatus, isNot('Pending'));
    });

    test('nested / signed upload URLs are not left Pending', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': 'test-g',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'label': 'Floor Plans',
                'documents': [
                  {
                    'id': 'gfp',
                    'document_key': 'ground_floor_plan',
                    'name': 'Ground Floor Plan',
                    'status': 'pending',
                    'latest_upload': {
                      'id': 'up1',
                      'url':
                          'https://cdn.example.com/bucket/obj/abc123?X-Amz-Signature=sig',
                    },
                  },
                  {
                    'id': 'ffp',
                    'document_key': 'first_floor_plan',
                    'name': 'First Floor Plan',
                    'status': 'required',
                    'files': [
                      {
                        'file_url':
                            'https://s3.amazonaws.com/buildahome/docs/ffp',
                      },
                    ],
                  },
                  {
                    'id': 'prop',
                    'document_key': 'proposal',
                    'name': 'Proposal',
                    'status': 'pending',
                    'file': '/files/proposal_pack.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final docs = snapshot.library.libraryCategories.first.sections.first
          .documents;
      expect(docs.length, greaterThanOrEqualTo(3));
      for (final doc in docs) {
        expect(doc.hasUrl, isTrue, reason: doc.name);
        expect(doc.displayStatus, isNot('Pending'), reason: doc.name);
        expect(
          ClientPortalStatusBadge.fromStatus(
            doc.displayStatus,
            isLatest: doc.isLatest,
            hasUrl: doc.hasUrl,
          ),
          ClientPortalStatusBadgeKind.latest,
          reason: doc.name,
        );
      }
    });
  });

  group('MobileDocumentsInFlight', () {
    test('does not start a second fetch for the same project', () async {
      final inflight = MobileDocumentsInFlight();
      var calls = 0;
      Future<void> work() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }

      await Future.wait([
        inflight.run('100', work),
        inflight.run('100', work),
        inflight.run('100', work),
      ]);
      expect(calls, 1);
    });

    test('allows parallel fetches for different projects', () async {
      final inflight = MobileDocumentsInFlight();
      final started = <String>[];
      Future<void> work(String id) async {
        started.add(id);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final a = inflight.run('100', () => work('100'));
      final b = inflight.run('200', () => work('200'));
      expect(inflight.inFlightCount, 2);
      await Future.wait([a, b]);
      expect(started, containsAll(['100', '200']));
    });
  });

  group('shouldUseMobileDocumentsSnapshot', () {
    test('API failure fallback keeps legacy path', () {
      expect(shouldUseMobileDocumentsSnapshot(null), isFalse);
    });
  });

  group('catalog-driven Mobile Documents', () {
    Map<String, dynamic> professionalCatalog({
      String architecturalName = 'Architectural',
      String gfcTypeName = 'GFC Drawings',
      String workingName =
          'Working Drawings, Isometric Views & Elevations',
      bool includeLandscape = false,
    }) {
      return {
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'category_id': 12,
            'name': architecturalName,
            'dashboard_card': 'gfc',
            'types': [
              {
                'type_id': 3,
                'name': 'Floor Plans',
                'dashboard_section': 'architectural',
                'dashboard_section_label': 'GFC / Construction Drawings',
                'documents': [
                  {
                    'document_definition_id': 81,
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/files/gfp.pdf',
                    'task_id': '999',
                  },
                ],
              },
              {
                'type_id': 44,
                'name': gfcTypeName,
                'dashboard_section_label': 'GFC / Construction Drawings',
                'documents': [
                  {
                    'document_definition_id': 90,
                    'name': workingName,
                    'status': 'pending',
                    'task_id': '999',
                    'dashboard_card': 'gfc',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 13,
            'name': 'Structural & Civil',
            'dashboard_card': 'gfc',
            'document_types': [
              {
                'type_id': 51,
                'name': 'Ground Floor (GF)',
                'document_definitions': [
                  {
                    'document_definition_id': 201,
                    'name': 'GF Structural',
                    'status': 'available',
                  },
                ],
              },
              {
                'type_id': 52,
                'name': 'First Floor (FF)',
                'documents': [
                  {
                    'document_definition_id': 202,
                    'name': 'FF Structural',
                    'status': 'missing',
                  },
                ],
              },
              {
                'type_id': 53,
                'name': 'Headroom / Roof (SHR)',
                'documents': [
                  {
                    'document_definition_id': 203,
                    'name': 'SHR Structural',
                    'status': 'required',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 14,
            'name': 'Electrical',
          },
          {
            'category_id': 15,
            'name': 'NDT Tests',
            'dashboard_card': 'quality',
          },
          if (includeLandscape)
            {
              'category_id': 99,
              'name': 'Landscape',
              'types': [
                {
                  'type_id': 991,
                  'name': 'Planting',
                  'documents': [
                    {
                      'document_definition_id': 992,
                      'name': 'Front Garden Plan',
                      'status': 'pending',
                    },
                  ],
                },
              ],
            },
          {
            'category_id': 'gallery',
            'name': 'Gallery',
            'dashboard_card': 'gallery',
            'types': [
              {
                'id': 'first',
                'name': 'first',
                'dashboard_card': 'gallery',
                'documents': [
                  {'id': 'g1', 'name': 'Site photo', 'url': '/photo.jpg'},
                ],
              },
              {
                'id': 'second',
                'name': 'second',
                'dashboard_card': 'gallery',
              },
            ],
          },
        ],
      };
    }

    test('renders live catalog names, not hardcoded dashboard strings', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      final labels = _categoryLabels(snapshot.library);
      expect(labels, contains('Architectural'));
      expect(labels, contains('Structural & Civil'));
      expect(labels, contains('Electrical'));
      expect(labels, contains('NDT Tests'));
      expect(labels, isNot(contains('GFC / Construction Drawings')));
      expect(labels, isNot(contains('Quality & Test Reports')));
      expect(labels, isNot(contains('Site & Construction Records')));

      final architectural = _category(snapshot.library, 'Architectural');
      expect(architectural.id, '12');
      expect(_typeLabels(architectural), ['Floor Plans', 'GFC Drawings']);
      expect(
        _docNames(architectural.sections.firstWhere((s) => s.id == '44')),
        ['Working Drawings, Isometric Views & Elevations'],
      );

      final structural = _category(snapshot.library, 'Structural & Civil');
      expect(structural.id, '13');
      expect(
        _typeLabels(structural),
        ['Ground Floor (GF)', 'First Floor (FF)', 'Headroom / Roof (SHR)'],
      );
    });

    test('new category/type/document appears without code changes', () {
      final snapshot = parseMobileDocumentsPayload(
        professionalCatalog(includeLandscape: true),
      )!;
      expect(_categoryLabels(snapshot.library), contains('Landscape'));
      final landscape = _category(snapshot.library, 'Landscape');
      expect(landscape.id, '99');
      expect(_typeLabels(landscape), ['Planting']);
      expect(_docNames(landscape.sections.single), ['Front Garden Plan']);
    });

    test('rename of category/type/document changes Mobile labels', () {
      final renamed = parseMobileDocumentsPayload(
        professionalCatalog(
          architecturalName: 'Architecture Studio',
          gfcTypeName: 'Issued For Construction',
          workingName: 'IFC Set A',
        ),
      )!;
      final architectural = _category(renamed.library, 'Architecture Studio');
      expect(architectural.id, '12');
      expect(_typeLabels(architectural), contains('Issued For Construction'));
      expect(
        _docNames(architectural.sections.firstWhere((s) => s.id == '44')),
        ['IFC Set A'],
      );
    });

    test('visibility keys are catalog IDs, not dashboard slugs', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      final architectural = _category(snapshot.library, 'Architectural');
      expect(architectural.id, '12');
      expect(
        architectural.sections.map((s) => s.id).toList(),
        ['3', '44'],
      );
      expect(
        architectural.sections
            .expand((s) => s.documents)
            .map((d) => d.documentKey)
            .toList(),
        ['81', '90'],
      );
      expect(architectural.id, isNot('gfc'));
    });

    test('requirements resolve through document_definition_id', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      final working = snapshot.library.libraryCategories
          .expand((c) => c.sections)
          .expand((s) => s.documents)
          .firstWhere((d) => d.documentKey == '90');
      expect(working.name, 'Working Drawings, Isometric Views & Elevations');
      expect(working.raw['document_definition_id'], 90);
      expect(working.documentKey, isNot('999'));
    });

    test('dashboard_card does not determine Mobile hierarchy', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      expect(
        _categoryLabels(snapshot.library),
        isNot(contains('GFC / Construction Drawings')),
      );
      expect(_category(snapshot.library, 'NDT Tests').id, '15');
      final gfcType = _category(snapshot.library, 'Architectural')
          .sections
          .firstWhere((s) => s.id == '44');
      expect(gfcType.label, 'GFC Drawings');
      expect(gfcType.label, isNot('GFC / Construction Drawings'));
    });

    test('Gallery is not a document catalog section', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      expect(_categoryLabels(snapshot.library), isNot(contains('Gallery')));
      expect(
        snapshot.library.libraryCategories.any((c) => c.id == 'gallery'),
        isFalse,
      );
      expect(
        snapshot.library.libraryCategories.any(
          (c) => c.sections.any((s) => s.id == 'first' || s.id == 'second'),
        ),
        isFalse,
      );
    });

    test('SOP Floor Plans stay catalog rows, not GFC dashboard sections', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      final architectural = _category(snapshot.library, 'Architectural');
      final floorPlans =
          architectural.sections.firstWhere((s) => s.id == '3');
      final gfc = architectural.sections.firstWhere((s) => s.id == '44');
      expect(floorPlans.label, 'Floor Plans');
      expect(_docNames(floorPlans), ['Ground Floor Plan']);
      expect(_docNames(gfc), isNot(contains('Ground Floor Plan')));
      expect(floorPlans.id, isNot(gfc.id));
    });

    test('does not map documents by task ID', () {
      final snapshot = parseMobileDocumentsPayload(professionalCatalog())!;
      final docs = snapshot.library.libraryCategories
          .expand((c) => c.sections)
          .expand((s) => s.documents)
          .where((d) => d.taskId == '999')
          .toList();
      expect(docs.length, 2);
      expect(docs.map((d) => d.documentKey).toSet(), {'81', '90'});
    });

    test('dashboard-only rows without document_definition_id are not invented',
        () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'documents': [
          {
            'dashboard_card': 'quality',
            'dashboard_section': 'ndt',
            'dashboard_section_label': 'Quality & Test Reports',
            'filename': 'legacy.pdf',
          },
          {
            'category_id': 15,
            'category_name': 'NDT Tests',
            'type_id': 70,
            'type_name': 'Cube Tests',
            'document_definition_id': 701,
            'name': '7-day Cube Test',
            'status': 'pending',
          },
        ],
      })!;
      expect(_categoryLabels(snapshot.library), ['NDT Tests']);
      expect(
        _categoryLabels(snapshot.library),
        isNot(contains('Quality & Test Reports')),
      );
      expect(
        _docNames(snapshot.library.libraryCategories.single.sections.single),
        ['7-day Cube Test'],
      );
    });
  });

  group('Documents V1 widgets', () {
    testWidgets('renders dynamic types under a category', (tester) async {
      final snapshot = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '100',
          floorPlans: ['Ground Floor Plan', 'First Floor Plan'],
          includeContracts: false,
        ),
      )!;
      final category = snapshot.library.libraryCategories.single;

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentsV1CategoryScreen(
            category: category,
            viewerRole: 'Client',
          ),
        ),
      );

      expect(find.text('Architectural'), findsOneWidget);
      // Checklist categories list type folders; files open inside the folder.
      expect(find.text('Final Floor plan'), findsOneWidget);
      expect(find.text('Ground Floor Plan'), findsNothing);
      expect(find.text('First Floor Plan'), findsNothing);
      expect(find.text('Contracts'), findsNothing);
    });

    testWidgets(
        'Architectural opens to the 13 type sections',
        (tester) async {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'mixed',
                'label': 'Drawings',
                'documents': [
                  {
                    'id': '1',
                    'document_key': 'ground_floor_plan',
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/g.pdf',
                    'revision': 1,
                    'is_latest': false,
                  },
                  {
                    'id': '1b',
                    'document_key': 'ground_floor_plan',
                    'name': 'Ground Floor Plan rev2',
                    'status': 'uploaded',
                    'url': '/g2.pdf',
                    'revision': 2,
                    'is_latest': true,
                  },
                  {
                    'id': '1c',
                    'document_key': 'first_floor_plan',
                    'name': 'First Floor Plan',
                    'status': 'uploaded',
                    'url': '/ff.pdf',
                    'is_latest': true,
                  },
                  {
                    'id': '2',
                    'name': 'Sample - Working drawing.pdf',
                    'status': 'uploaded',
                    'url': '/w.pdf',
                  },
                  {
                    'id': '3',
                    'name': 'Front Elevation',
                    'status': 'uploaded',
                    'url': '/e.pdf',
                  },
                  {
                    'id': '4',
                    'name': 'Sample - Section.pdf',
                    'status': 'uploaded',
                    'url': '/s.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;
      final category = snapshot.library.libraryCategories.single;
      final typeSections = buildArchitecturalTypeSections(category);
      expect(typeSections.length, 13);
      expect(
        typeSections.map((s) => s.label).toList(),
        [
          'Final Floor plan',
          'Working drawing',
          'Filler slab detail (if any)',
          'Section',
          'Final Elevation',
          '2D Elevation',
          'Door/Window/ grill detail',
          'Flooring details',
          'Dado Detail - Kitchen/toilet',
          'Fabrication Detail',
          'Skylight detail',
          'Paint shade',
          'Final Area statement',
        ],
      );
      expect(
        typeSections.any((s) => s.label == 'Final Area statement'),
        isTrue,
      );
      final floorPlans =
          typeSections.firstWhere((s) => s.label == 'Final Floor plan');
      // Same key keeps current only; distinct floor plans stay separate.
      expect(
        floorPlans.documents.map((d) => d.name).toList()..sort(),
        ['First Floor Plan', 'Ground Floor Plan rev2'],
      );
      expect(
        typeSections.firstWhere((s) => s.label == 'Working drawing').documents,
        hasLength(1),
      );
      expect(
        typeSections.firstWhere((s) => s.label == 'Section').documents,
        hasLength(1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentsV1CategoryScreen(
            category: category,
            clientMode: true,
            viewerRole: 'Client',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Architectural'), findsWidgets);
      expect(find.text('Final Floor plan'), findsOneWidget);
      expect(find.text('Working drawing'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Final Elevation'), findsOneWidget);
      // Files stay inside their type folder — not dumped on the category page.
      expect(find.text('Ground Floor Plan'), findsNothing);
      expect(find.text('Sample - Working drawing.pdf'), findsNothing);
    });

    testWidgets('renders individual documents including pending rows',
        (tester) async {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'label': 'Floor Plans',
                'documents': [
                  {
                    'id': '1',
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/g.pdf',
                    'is_latest': true,
                  },
                  {
                    'id': '2',
                    'name': 'First Floor Plan',
                    'status': 'pending',
                  },
                ],
              },
            ],
          },
        ],
      })!;
      final section = snapshot.library.libraryCategories.single.sections.single;

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentsV1ListScreen(
            categoryLabel: 'Architectural',
            section: section,
            viewerRole: 'Admin',
          ),
        ),
      );

      expect(find.text('Ground Floor Plan'), findsOneWidget);
      expect(find.text('First Floor Plan'), findsOneWidget);
    });

    testWidgets('G+2 list shows the extra floor that G+1 omits', (tester) async {
      final g2 = parseMobileDocumentsPayload(
        _architecturalPayload(
          projectId: '200',
          floorPlans: [
            'Ground Floor Plan',
            'First Floor Plan',
            'Second Floor Plan',
          ],
          includeContracts: false,
        ),
      )!;
      final section = g2.library.libraryCategories.single.sections.single;
      expect(
        _docNames(section),
        ['Ground Floor Plan', 'First Floor Plan', 'Second Floor Plan'],
      );

      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentsV1ListScreen(
            categoryLabel: 'Architectural',
            section: section,
            viewerRole: 'Admin',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3 Documents'), findsOneWidget);
      expect(find.text('Second Floor Plan'), findsOneWidget);
    });
  });

  group('Contracts category', () {
    test('is dropped from Docs catalog and For me hub', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'name': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'name': 'Floor Plans',
                'documents': [
                  {
                    'id': '1',
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/g.pdf',
                  },
                ],
              },
            ],
          },
          {
            'id': 'contracts',
            'name': 'Contracts',
            'types': [
              {
                'id': 'agreements',
                'name': 'Agreements',
                'documents': [
                  {
                    'id': '9',
                    'name': 'Construction Agreement',
                    'status': 'uploaded',
                    'url': '/c.pdf',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'receipts_and_agreements',
            'name': 'Receipts and Agreements',
            'client_journey_key': 'receipts_and_agreements',
            'types': [
              {
                'type_id': 'receipts',
                'name': 'Receipts',
                'documents': [
                  {
                    'document_definition_id': 4,
                    'name': 'Payment Receipt',
                    'status': 'uploaded',
                    'url': '/r.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;

      expect(
        snapshot.library.libraryCategories.map((c) => c.label),
        containsAll(['Architectural', 'Receipts and Agreements']),
      );
      expect(
        snapshot.library.libraryCategories.map((c) => c.label),
        isNot(contains('Contracts')),
      );
      final hubTitles = buildClientPortalHubItems(
        snapshot.library,
        role: 'Client',
      ).map((item) => item.title);
      expect(hubTitles, isNot(contains('Contracts')));
      expect(hubTitles, contains('Receipts and Agreements'));
    });
  });

  group('Uncategorized category', () {
    test('is dropped from mobile catalog parse and hub', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'id': 'architectural',
            'name': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'name': 'Floor Plans',
                'documents': [
                  {
                    'id': '1',
                    'name': 'Ground Floor Plan',
                    'status': 'uploaded',
                    'url': '/g.pdf',
                  },
                ],
              },
            ],
          },
          {
            'id': 'uncategorized',
            'name': 'Uncategorized',
            'types': [
              {
                'id': 'other',
                'name': 'Other',
                'documents': [
                  {
                    'id': '9',
                    'name': 'Loose file',
                    'status': 'uploaded',
                    'url': '/x.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;

      expect(
        snapshot.library.libraryCategories.map((c) => c.label),
        ['Architectural'],
      );
      expect(
        buildClientPortalHubItems(snapshot.library).map((i) => i.title),
        isNot(contains('Uncategorized')),
      );
    });
  });

  group('Area Statement client visibility', () {
    test('detects Area Statement by name, key, and URL', () {
      expect(
        isAreaStatementDocumentRef(name: 'Area Statement'),
        isTrue,
      );
      expect(
        isAreaStatementDocumentRef(documentKey: 'area_statement'),
        isTrue,
      );
      expect(
        isAreaStatementDocumentRef(
          url: 'https://office.buildahome.in/serve_sales_sop_area_statement/3',
        ),
        isTrue,
      );
      expect(isAreaStatementDocumentRef(name: 'Floor Plan'), isFalse);
    });

    test('strips Area Statement from client categories', () {
      final category = WorkflowDocumentCategory(
        id: 'architectural',
        label: 'Architectural',
        sections: [
          WorkflowDocumentSection(
            id: 'misc',
            label: 'Misc',
            documents: [
              WorkflowDocumentUpload(
                id: '1',
                documentKey: 'area_statement',
                name: 'Area Statement',
                url: '/a.pdf',
                isLatest: true,
              ),
              WorkflowDocumentUpload(
                id: '2',
                documentKey: 'gfp',
                name: 'Ground Floor Plan',
                url: '/g.pdf',
                isLatest: true,
              ),
            ],
          ),
        ],
      );

      final filtered = withoutAreaStatementDocuments(category);
      expect(filtered.sections, hasLength(1));
      expect(
        filtered.sections.single.documents.map((d) => d.name),
        ['Ground Floor Plan'],
      );
    });
  });

  group('client portal hub', () {
    test('pins KYC, Documents, and Receipts; catalog fills the rest', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'category_id': 12,
            'name': 'Architectural',
            'types': [
              {
                'type_id': 44,
                'name': 'GFC Drawings',
                'documents': [
                  {
                    'document_definition_id': 90,
                    'name': 'Working Drawings',
                    'status': 'pending',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'office_documents',
            'name': 'Documents',
            'client_journey_key': 'office_documents',
            'types': [
              {
                'type_id': 'lib',
                'name': 'Library',
                'documents': [
                  {'document_definition_id': 1, 'name': 'Note', 'status': 'uploaded', 'url': '/n.pdf'},
                ],
              },
            ],
          },
          {
            'category_id': 'receipts_and_agreements',
            'name': 'Receipts and Agreements',
            'client_journey_key': 'receipts_and_agreements',
            'types': [
              {
                'type_id': 'agreements',
                'name': 'Agreements',
                'documents': [
                  {'document_definition_id': 2, 'name': 'Agreement', 'status': 'available'},
                ],
              },
            ],
          },
          {
            'category_id': 99,
            'name': 'Landscape',
            'types': [
              {
                'type_id': 991,
                'name': 'Planting',
                'documents': [
                  {'document_definition_id': 992, 'name': 'Garden', 'status': 'pending'},
                ],
              },
            ],
          },
        ],
      })!;

      final items = buildClientPortalHubItems(snapshot.library);
      expect(items.first.kind, ClientPortalHubKind.kyc);
      expect(items.map((i) => i.title), containsAll(['Documents', 'Receipts and Agreements', 'Architectural', 'Landscape']));
      expect(
        items.where((i) => i.kind == ClientPortalHubKind.catalog).map((i) => i.title),
        ['Architectural', 'Landscape'],
      );
      expect(
        items.where((i) => i.kind == ClientPortalHubKind.catalog).map((i) => i.title),
        isNot(contains('Documents')),
      );
      expect(
        items.where((i) => i.isPinnedSpecial).map((i) => i.title),
        containsAll(['KYC & Documents', 'Documents', 'Receipts and Agreements']),
      );
      expect(
        items.where((i) => i.isCatalog).every((i) => !i.title.startsWith(RegExp(r'\d+\. '))),
        isTrue,
      );

      final withoutKyc = buildClientPortalHubItems(
        snapshot.library,
        includeKyc: false,
      );
      expect(
        withoutKyc.map((i) => i.kind),
        isNot(contains(ClientPortalHubKind.kyc)),
      );
      expect(
        withoutKyc.map((i) => i.title),
        isNot(contains('KYC & Documents')),
      );
      expect(
        withoutKyc.map((i) => i.title),
        containsAll(['Documents', 'Receipts and Agreements']),
      );
      expect(items.map((i) => i.title), isNot(contains('Site Preparation')));
      expect(items.map((i) => i.title), isNot(contains('Demolition Details')));
      expect(items.map((i) => i.title), isNot(contains('Site Inspection')));
      expect(items.where((i) => i.isProjectStep), isEmpty);
    });

    test('staff Docs matches the client hub without KYC', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'category_id': 'structural',
            'name': 'Structural & Civil',
            'types': [
              {
                'type_id': 'framing',
                'name': 'Framing',
                'documents': [
                  {
                    'document_definition_id': 1,
                    'name': 'Framing',
                    'status': 'uploaded',
                    'url': '/f.pdf',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'site_document',
            'name': 'Site Document',
            'client_journey_key': 'site_document',
            'types': [
              {
                'type_id': 'report',
                'name': 'Site Inspection Report',
                'documents': [
                  {
                    'document_definition_id': 2,
                    'name': 'Report',
                    'status': 'uploaded',
                    'url': '/r.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final client = buildClientPortalHubItems(
        snapshot.library,
        role: 'Client',
      ).map((item) => item.title);
      final staff = buildClientPortalHubItems(
        snapshot.library,
        role: 'Site Engineer',
      ).map((item) => item.title);

      expect(client, contains('KYC & Documents'));
      expect(client, contains('Structural & Civil'));
      expect(client, contains('Site inspection report'));
      expect(staff, isNot(contains('KYC & Documents')));
      expect(staff, contains('Structural & Civil'));
      expect(staff, contains('Site inspection report'));
    });

    test('site engineer hub hides KYC, project documents, and contracts', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '100',
        'categories': [
          {
            'category_id': 'kyc',
            'name': 'KYC',
            'types': [
              {
                'type_id': 'aadhaar',
                'name': 'Aadhaar',
                'documents': [
                  {
                    'document_definition_id': 1,
                    'name': 'Aadhaar',
                    'status': 'uploaded',
                    'url': '/a.pdf',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'project_documents',
            'name': 'Project Documents',
            'types': [
              {
                'type_id': 'permit',
                'name': 'Permit',
                'documents': [
                  {
                    'document_definition_id': 2,
                    'name': 'Permit',
                    'status': 'uploaded',
                    'url': '/p.pdf',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'contracts',
            'name': 'Contracts',
            'types': [
              {
                'type_id': 'agreement',
                'name': 'Agreement',
                'documents': [
                  {
                    'document_definition_id': 3,
                    'name': 'Agreement',
                    'status': 'uploaded',
                    'url': '/c.pdf',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'office_documents',
            'name': 'Documents',
            'client_journey_key': 'office_documents',
            'types': [
              {
                'type_id': 'lib',
                'name': 'Library',
                'documents': [
                  {
                    'document_definition_id': 4,
                    'name': 'Note',
                    'status': 'uploaded',
                    'url': '/n.pdf',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'receipts_and_agreements',
            'name': 'Receipts and Agreements',
            'client_journey_key': 'receipts_and_agreements',
            'types': [
              {
                'type_id': 'agreements',
                'name': 'Agreements',
                'documents': [
                  {
                    'document_definition_id': 5,
                    'name': 'Agreement',
                    'status': 'available',
                  },
                ],
              },
            ],
          },
          {
            'category_id': 'structural',
            'name': 'Structural & Civil',
            'types': [
              {
                'type_id': 'framing',
                'name': 'Framing',
                'documents': [
                  {
                    'document_definition_id': 6,
                    'name': 'Framing',
                    'status': 'uploaded',
                    'url': '/f.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final titles = buildClientPortalHubItems(
        snapshot.library,
        role: 'Site Engineer',
      ).map((item) => item.title);

      expect(titles, contains('Structural & Civil'));
      expect(titles, isNot(contains('KYC')));
      expect(titles, isNot(contains('KYC & Documents')));
      expect(titles, isNot(contains('Project Documents')));
      expect(titles, isNot(contains('Contracts')));
      expect(titles, isNot(contains('Documents')));
      expect(titles, isNot(contains('Receipts and Agreements')));
    });

    test('KYC hub visibility is Client and Super Admin only', () {
      expect(roleCanSeeClientPortalKyc('Client'), isTrue);
      expect(roleCanSeeClientPortalKyc('Super Admin'), isTrue);
      expect(roleCanSeeClientPortalKyc('Admin'), isTrue);
      expect(roleCanSeeClientPortalKyc('Project Manager'), isFalse);
      expect(roleCanSeeClientPortalKyc('Site Engineer'), isFalse);
      expect(roleCanSeeClientPortalKyc('Sales'), isFalse);
      expect(roleCanSeeClientPortalKyc(null), isFalse);
    });

    test('new catalog categories get a colored icon, not a plain folder', () {
      final landscape = categoryVisualFor(categoryId: '99', label: 'Landscape');
      expect(landscape.icon, Icons.park_outlined);

      final unknown = hashedCatalogVisual(seed: 'brand_new_category_xyz');
      expect(unknown.icon, isNot(Icons.folder_open_outlined));
      expect(unknown.iconBg, isNot(const Color(0xFFF0F4FF)));

      final named = categoryVisualFor(
        categoryId: '120',
        label: 'Custom Pack',
        iconName: 'electrical_services',
      );
      expect(named.icon, Icons.electrical_services_outlined);
    });
  });

  group('document download access', () {
    WorkflowDocumentUpload firstDoc(MobileDocumentsSnapshot snapshot) {
      return snapshot
          .library.libraryCategories.first.sections.first.documents.first;
    }

    test('download is shown until the web restricts it', () {
      final snapshot = parseMobileDocumentsPayload(
        _architecturalPayload(projectId: '9', floorPlans: ['Plan A']),
        viewerRole: 'Client',
      )!;
      expect(snapshot.canDownload, isTrue);
      expect(firstDoc(snapshot).canDownload, isTrue);
    });

    test('can_download true shows download on every file', () {
      final payload = _architecturalPayload(
        projectId: '9',
        floorPlans: ['Plan A'],
      );
      payload['can_download'] = true;
      final snapshot = parseMobileDocumentsPayload(
        payload,
        viewerRole: 'Site Engineer',
      )!;
      expect(snapshot.canDownload, isTrue);
      expect(firstDoc(snapshot).canDownload, isTrue);
      expect(_categoryLabels(snapshot.library), isNot(contains('Contracts')));
    });

    test('download_roles decides who sees download', () {
      final payload = _architecturalPayload(
        projectId: '9',
        floorPlans: ['Plan A'],
      );
      payload['download_roles'] = ['Project Manager', 'Admin'];

      final manager = parseMobileDocumentsPayload(
        payload,
        viewerRole: 'Project Manager',
      )!;
      final engineer = parseMobileDocumentsPayload(
        payload,
        viewerRole: 'Site Engineer',
      )!;

      expect(manager.canDownload, isTrue);
      expect(firstDoc(manager).canDownload, isTrue);
      expect(engineer.canDownload, isFalse);
      expect(firstDoc(engineer).canDownload, isFalse);
    });

    test('download_access.roles and empty list are honored', () {
      final allowed = _architecturalPayload(
        projectId: '9',
        floorPlans: ['Plan A'],
      );
      allowed['download_access'] = {
        'roles': ['Client'],
      };
      expect(
        parseMobileDocumentsPayload(allowed, viewerRole: 'Client')!.canDownload,
        isTrue,
      );
      expect(
        parseMobileDocumentsPayload(allowed, viewerRole: 'client')!.canDownload,
        isTrue,
      );

      final nobody = _architecturalPayload(
        projectId: '9',
        floorPlans: ['Plan A'],
      );
      nobody['download_roles'] = <String>[];
      expect(
        parseMobileDocumentsPayload(nobody, viewerRole: 'Admin')!.canDownload,
        isFalse,
      );
    });

    test('one file can turn download off while the catalog allows it', () {
      final payload = {
        'message': 'success',
        'configured': true,
        'project_id': '9',
        'can_download': true,
        'categories': [
          {
            'id': 'architectural',
            'label': 'Architectural',
            'types': [
              {
                'id': 'floor_plans',
                'label': 'Floor Plans',
                'documents': [
                  {
                    'id': 'fp_0',
                    'name': 'Plan A',
                    'status': 'uploaded',
                    'url': '/files/a.pdf',
                  },
                  {
                    'id': 'fp_1',
                    'name': 'Plan B',
                    'status': 'uploaded',
                    'url': '/files/b.pdf',
                    'can_download': false,
                  },
                ],
              },
            ],
          },
        ],
      };
      final snapshot = parseMobileDocumentsPayload(
        payload,
        viewerRole: 'Client',
      )!;
      final parsed =
          snapshot.library.libraryCategories.first.sections.first.documents;
      expect(parsed.first.canDownload, isTrue);
      expect(parsed[1].canDownload, isFalse);
    });

    test('cached catalog keeps the web download rule', () {
      final payload = _architecturalPayload(
        projectId: '9',
        floorPlans: ['Plan A'],
      );
      payload['download_roles'] = ['Client'];
      final snapshot = parseMobileDocumentsPayload(
        payload,
        viewerRole: 'Client',
      )!;
      final restored = MobileDocumentsSnapshot.fromJson(
        snapshot.toJson(),
        expectedProjectId: '9',
        viewerRole: 'Client',
      )!;
      expect(restored.canDownload, isTrue);
      expect(firstDoc(restored).canDownload, isTrue);

      final otherRole = MobileDocumentsSnapshot.fromJson(
        snapshot.toJson(),
        expectedProjectId: '9',
        viewerRole: 'Billing',
      )!;
      expect(otherRole.canDownload, isFalse);
    });
  });

  group('multi-file soil / booking / expand', () {
    test('plumbing drawing keeps every nested upload', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '77',
        'categories': [
          {
            'id': 'mep',
            'label': 'MEP',
            'types': [
              {
                'id': 'plumbing_drawing',
                'label': 'Plumbing drawing',
                'documents': [
                  {
                    'document_key': 'plumbing_drawing',
                    'name': 'Plumbing drawing',
                    'status': 'uploaded',
                    'url': '/files/plumb_latest.pdf',
                    'files': [
                      {
                        'id': 'p1',
                        'url': '/files/plumb_a.pdf',
                        'name': 'Plumbing A',
                      },
                    ],
                    'uploads': [
                      {
                        'id': 'p2',
                        'url': '/files/plumb_b.pdf',
                        'name': 'Plumbing B',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final mep = snapshot.library.libraryCategories
          .firstWhere((c) => c.label == 'MEP');
      expect(isMultiFileDocumentCategory(mep), isTrue);
      final flat = buildFlatCategoryDocumentsSection(mep);
      expect(flat.documents.length, greaterThanOrEqualTo(2));
      final urls = flat.documents.map((d) => d.url ?? '').toList();
      expect(urls.any((u) => u.endsWith('/files/plumb_a.pdf')), isTrue);
      expect(urls.any((u) => u.endsWith('/files/plumb_b.pdf')), isTrue);
      expect(workflowDocCountForCategory(mep), flat.documents.length);
    });

    test('mirrored category sections are stripped for Quality / Pre / Structural',
        () {
      final quality = WorkflowDocumentCategory(
        id: 'quality_test_reports',
        label: 'Quality & Test Reports',
        sections: [
          WorkflowDocumentSection(
            id: 'quality_test_reports',
            label: 'Quality and test report',
            categoryId: 'quality_test_reports',
            categoryLabel: 'Quality & Test Reports',
            documents: const [],
          ),
          WorkflowDocumentSection(
            id: 'soil_test',
            label: 'Soil test report',
            categoryId: 'quality_test_reports',
            categoryLabel: 'Quality & Test Reports',
            documents: const [],
          ),
        ],
      );
      expect(
        substantiveDocumentSections(quality).map((s) => s.label).toList(),
        ['Soil test report'],
      );
      expect(catalogCategorySubtitle(quality), 'Soil test report');

      final pre = WorkflowDocumentCategory(
        id: 'pre_conversion_documents',
        label: 'Pre Conversion Documents',
        sections: [
          WorkflowDocumentSection(
            id: 'pre_conversion_documents',
            label: 'Pre Conversion Documents',
            categoryId: 'pre_conversion_documents',
            categoryLabel: 'Pre Conversion Documents',
            documents: const [],
          ),
          WorkflowDocumentSection(
            id: 'proposal',
            label: 'Proposal',
            categoryId: 'pre_conversion_documents',
            categoryLabel: 'Pre Conversion Documents',
            documents: const [],
          ),
          WorkflowDocumentSection(
            id: 'booking_form',
            label: 'Booking form',
            categoryId: 'pre_conversion_documents',
            categoryLabel: 'Pre Conversion Documents',
            documents: const [],
          ),
        ],
      );
      expect(
        substantiveDocumentSections(pre).map((s) => s.label).toList(),
        ['Proposal', 'Booking form'],
      );

      final structural = WorkflowDocumentCategory(
        id: 'structural_civil',
        label: 'Structural & Civil',
        sections: [
          WorkflowDocumentSection(
            id: 'structural_civil',
            label: 'Structural & Civil',
            categoryId: 'structural_civil',
            categoryLabel: 'Structural & Civil',
            documents: const [],
          ),
          WorkflowDocumentSection(
            id: 'gf_structural',
            label: 'GF Structural',
            categoryId: 'structural_civil',
            categoryLabel: 'Structural & Civil',
            documents: const [],
          ),
        ],
      );
      expect(
        substantiveDocumentSections(structural).map((s) => s.label).toList(),
        ['GF Structural'],
      );
    });

    test('Pre-conversion keeps Proposal and Booking form as sections', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '79',
        'categories': [
          {
            'id': 'pre_conversion_documents',
            'label': 'Pre Conversion Documents',
            'client_journey_key': 'pre_conversion_documents',
            'types': [
              {
                'id': 'proposal',
                'label': 'Proposal',
                'documents': [
                  {
                    'document_key': 'proposal',
                    'name': 'Proposal pack',
                    'status': 'uploaded',
                    'url': '/files/proposal.pdf',
                  },
                ],
              },
              {
                'id': 'booking_form',
                'label': 'Booking form',
                'documents': [
                  {
                    'document_key': 'booking_form',
                    'name': 'Booking form',
                    'status': 'uploaded',
                    'uploads': [
                      {'id': 'b1', 'url': '/files/booking_1.pdf'},
                      {'id': 'b2', 'url': '/files/booking_2.pdf'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final pre = snapshot.library.libraryCategories.firstWhere(
        (c) => c.label == 'Pre Conversion Documents',
      );
      expect(isMultiFileDocumentCategory(pre), isFalse);
      expect(pre.sections.map((s) => s.label).toList(), [
        'Proposal',
        'Booking form',
      ]);
      expect(
        pre.sections.firstWhere((s) => s.label == 'Proposal').documents.length,
        1,
      );
      expect(
        pre.sections
            .firstWhere((s) => s.label == 'Booking form')
            .documents
            .length,
        2,
      );
    });

    test('Quality is not flattened just because it contains Soil test', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '78',
        'categories': [
          {
            'id': 'quality',
            'label': 'Quality and test report',
            'types': [
              {
                'id': 'soil_test',
                'label': 'Soil test report',
                'documents': [
                  {
                    'document_key': 'soil_test_report',
                    'name': 'Soil test report',
                    'status': 'uploaded',
                    'files': [
                      {'id': 's1', 'url': '/files/soil_a.pdf'},
                      {'id': 's2', 'url': '/files/soil_b.pdf'},
                    ],
                  },
                ],
              },
              {
                'id': 'ndt',
                'label': 'NDT report',
                'documents': [
                  {
                    'document_key': 'ndt_report',
                    'name': 'NDT report',
                    'status': 'uploaded',
                    'url': '/files/ndt.pdf',
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final quality = snapshot.library.libraryCategories
          .firstWhere((c) => c.label == 'Quality and test report');
      expect(isMultiFileDocumentCategory(quality), isFalse);
      expect(quality.sections.length, 2);
      final soil =
          quality.sections.firstWhere((s) => s.label == 'Soil test report');
      expect(isMultiFileDocumentSection(soil), isTrue);
      expect(soil.documents.length, 2);
    });

    test('expand merges files from every nested list key', () {
      final expanded = expandMobileDocumentFileMaps({
        'document_key': 'soil_test_report',
        'name': 'Soil test report',
        'url': '/files/soil_cover.pdf',
        'files': [
          {'url': '/files/soil_1.pdf'},
        ],
        'uploads': [
          {'url': '/files/soil_2.pdf'},
          {'url': '/files/soil_1.pdf'},
        ],
      });
      final urls = expanded
          .map((row) => (row['url'] ?? '').toString())
          .where((url) => url.isNotEmpty)
          .toList();
      expect(urls.any((u) => u.endsWith('/files/soil_1.pdf')), isTrue);
      expect(urls.any((u) => u.endsWith('/files/soil_2.pdf')), isTrue);
      expect(urls.any((u) => u.endsWith('/files/soil_cover.pdf')), isTrue);
      expect(expanded.length, 3);
    });

    test('expand pulls a second soil PDF from activity history', () {
      final expanded = expandMobileDocumentFileMaps({
        'document_key': 'soil_test_report',
        'name': 'Soil test report',
        'url': '/files/soil_new.pdf',
        'is_latest': true,
        'activity': [
          {
            'action': 'uploaded',
            'file_url': '/files/soil_old.pdf',
          },
          {
            'action': 'uploaded',
            'url': '/files/soil_new.pdf',
          },
        ],
      });
      final urls = expanded
          .map((row) => (row['url'] ?? '').toString())
          .where((url) => url.isNotEmpty)
          .toList();
      expect(urls.any((u) => u.endsWith('/files/soil_old.pdf')), isTrue);
      expect(urls.any((u) => u.endsWith('/files/soil_new.pdf')), isTrue);
      expect(expanded.length, greaterThanOrEqualTo(2));
    });

    test('soil and booking catalog rows keep every upload', () {
      final snapshot = parseMobileDocumentsPayload({
        'message': 'success',
        'configured': true,
        'project_id': '55',
        'categories': [
          {
            'id': 'quality',
            'label': 'Quality',
            'types': [
              {
                'id': 'soil_test',
                'label': 'Soil test report',
                'documents': [
                  {
                    'document_key': 'soil_test_report',
                    'name': 'Soil test report',
                    'status': 'uploaded',
                    'files': [
                      {
                        'id': 's1',
                        'url': '/files/soil_a.pdf',
                        'name': 'Soil A',
                      },
                      {
                        'id': 's2',
                        'url': '/files/soil_b.pdf',
                        'name': 'Soil B',
                      },
                    ],
                  },
                ],
              },
            ],
          },
          {
            'id': 'booking',
            'label': 'Booking form',
            'types': [
              {
                'id': 'booking_form',
                'label': 'Booking form',
                'documents': [
                  {
                    'document_key': 'booking_form',
                    'name': 'Booking form',
                    'status': 'uploaded',
                    'uploads': [
                      {
                        'id': 'b1',
                        'url': '/files/booking_1.pdf',
                        'name': 'Form 1',
                      },
                      {
                        'id': 'b2',
                        'url': '/files/booking_2.pdf',
                        'name': 'Form 2',
                      },
                      {
                        'id': 'b3',
                        'url': '/files/booking_3.pdf',
                        'name': 'Form 3',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      })!;

      final quality = snapshot.library.libraryCategories
          .firstWhere((c) => c.label == 'Quality');
      final soil = quality.sections.firstWhere((s) => s.label == 'Soil test report');
      expect(soil.documents.length, 2);
      expect(isMultiFileDocumentSection(soil), isTrue);
      expect(
        buildFlatCategoryDocumentsSection(quality).documents.length,
        2,
      );

      final booking = snapshot.library.libraryCategories
          .firstWhere((c) => c.label == 'Booking form');
      expect(isMultiFileDocumentCategory(booking), isTrue);
      expect(workflowDocCountForCategory(booking), 3);
      expect(
        buildFlatCategoryDocumentsSection(booking).documents.length,
        3,
      );
    });
  });
}
