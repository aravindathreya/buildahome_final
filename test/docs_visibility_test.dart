import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/documents_v1/document_visibility.dart';
import 'package:buildAhome/models/workflow_document.dart';

WorkflowDocumentUpload _doc(String id, {String? url}) => WorkflowDocumentUpload(
      id: id,
      documentKey: id,
      name: id,
      url: url,
    );

void main() {
  test('empty sections and the bare "Section" row are hidden', () {
    final category = WorkflowDocumentCategory(
      id: 'architectural',
      label: 'Architectural',
      sections: [
        WorkflowDocumentSection(id: 'section', label: 'Section'),
        WorkflowDocumentSection(
          id: 'working_drawing',
          label: 'Working drawing',
          documents: [_doc('wd', url: '/files/wd.pdf')],
        ),
        WorkflowDocumentSection(
          id: 'paint_shade',
          label: 'Paint shade',
          documents: [_doc('pending')],
        ),
      ],
    );
    final visible = visibleDocsCategory(category)!;
    expect(visible.sections.map((s) => s.id), ['working_drawing']);
  });

  test('"Section" with files keeps its files under Section drawings', () {
    final section = WorkflowDocumentSection(
      id: 'section',
      label: 'section',
      documents: [_doc('s1', url: '/files/s1.pdf')],
    );
    final visible = visibleDocsSection(section)!;
    expect(visible.label, 'Section drawings');
    expect(visible.documents.length, 1);
  });

  test('category with no files is hidden', () {
    final category = WorkflowDocumentCategory(
      id: 'electrical',
      label: 'Electrical',
      sections: [WorkflowDocumentSection(id: 'e', label: 'Electrical point')],
    );
    expect(visibleDocsCategory(category), isNull);
  });

  test('visibleDocsSections drops empty rows and renames "Section"', () {
    final sections = visibleDocsSections([
      WorkflowDocumentSection(id: 'empty', label: 'Plinth beam'),
      WorkflowDocumentSection(
        id: 'section',
        label: 'Section',
        documents: [_doc('s1', url: '/files/s1.pdf')],
      ),
    ]);
    expect(sections.map((s) => s.label), ['Section drawings']);
  });
}
