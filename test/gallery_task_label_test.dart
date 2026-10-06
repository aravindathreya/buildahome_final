import 'package:buildAhome/Gallery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the parent task name when the photo clears task_name', () {
    final merged = mergeGalleryImageContext(
      {
        'task_name': 'Footing excavation',
        's_note': 'Footing excavation',
        'task_id': '88',
      },
      {
        'url': 'https://office.buildahome.in/files/migrated/site.jpg',
        'filename': 'site.jpg',
        'task_name': null,
        'note': null,
        'document_name': null,
      },
    );

    expect(galleryImageTaskLabel(merged), 'Footing excavation');
    expect(
      galleryImageCaption(taskName: galleryImageTaskLabel(merged)),
      'Footing excavation',
    );
  });

  test('uses s_note when task_name is only the file name', () {
    final merged = mergeGalleryImageContext(
      {
        's_note': 'Slab casting',
        'dashboard_card': 'gallery',
      },
      {
        'url': 'https://office.buildahome.in/files/a.jpg',
        'filename': 'a.jpg',
        'task_name': 'a.jpg',
        'name': 'a',
      },
    );

    expect(galleryImageTaskLabel(merged), 'Slab casting');
  });

  test('reads a nested task object', () {
    expect(
      galleryImageTaskLabel({
        'url': 'https://office.buildahome.in/files/b.jpg',
        'filename': 'b.jpg',
        'task': {'task_name': 'Column reinforcement'},
      }),
      'Column reinforcement',
    );
  });

  test('keeps the upload clock time from the parent response', () {
    final merged = mergeGalleryImageContext(
      {
        'task_name': 'Slab casting',
        'submitted_at': '2026-10-05 14:32:00',
      },
      {
        'url': 'https://office.buildahome.in/files/a.jpg',
        'filename': 'a.jpg',
        'uploaded_at': null,
        'date': '05 Oct 2026',
      },
    );

    expect(
      galleryUploadedAtLabel(merged),
      '05 Oct 2026, 02:32 PM',
    );
  });

  test('does not invent a clock time for a date-only value', () {
    expect(galleryFormatUploadedAt('05 Oct 2026'), '05 Oct 2026');
    expect(
      galleryFormatUploadedAt('2026-10-05T09:05:00'),
      '05 Oct 2026, 09:05 AM',
    );
  });

  test('prefers the parent workflow name over a photo caption', () {
    final merged = mergeGalleryImageContext(
      {
        'workflow_item_name': 'Mark centre line of the building',
        'task_id': '77',
      },
      {
        'url': 'https://office.buildahome.in/files/c.jpg',
        'filename': 'c.jpg',
        'task_name': 'Photo upload',
        'note': 'Looks good',
        'name': 'c',
      },
    );

    expect(
      galleryImageTaskLabel(merged),
      'Mark centre line of the building',
    );
  });

  test('does not treat a file name as the caption', () {
    expect(
      galleryImageCaption(taskName: 'photo.jpg', title: 'photo.jpg'),
      'Workflow upload',
    );
    expect(
      galleryImageCaption(taskName: 'Plinth beam', title: 'photo.jpg'),
      'Plinth beam',
    );
  });
}
