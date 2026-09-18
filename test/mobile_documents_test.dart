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

    test('role-hidden documents are not rendered', () {
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

      expect(_categoryLabels(staff.library), contains('Contracts'));
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
      expect(names['Side'], 'Missing');
      expect(names['Terrace'], 'Available');
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
          home: DocumentsV1CategoryScreen(category: category),
        ),
      );

      expect(find.text('Architectural'), findsOneWidget);
      expect(find.text('Floor Plans'), findsOneWidget);
      expect(find.text('Contracts'), findsNothing);
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

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentsV1ListScreen(
            categoryLabel: 'Architectural',
            section: g2.library.libraryCategories.single.sections.single,
          ),
        ),
      );

      expect(find.text('Second Floor Plan'), findsOneWidget);
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
}
