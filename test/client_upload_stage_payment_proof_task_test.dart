import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/MyTasksScreen.dart';

void main() {
  group('isClientUploadStagePaymentProofTask', () {
    test('matches task_category client_upload_stage_payment_proof', () {
      expect(
        isClientUploadStagePaymentProofTask({
          'task_category': 'client_upload_stage_payment_proof',
        }),
        isTrue,
      );
    });

    test('matches category aliases with spaces or hyphens', () {
      expect(
        isClientUploadStagePaymentProofTask({
          'category': 'Client Upload Stage Payment Proof',
        }),
        isTrue,
      );
      expect(
        isClientUploadStagePaymentProofTask({
          'erp_category': 'client-upload-stage-payment-proof',
        }),
        isTrue,
      );
    });

    test('ignores unrelated categories', () {
      expect(
        isClientUploadStagePaymentProofTask({
          'task_category': 'check_approve_indent',
        }),
        isFalse,
      );
      expect(isClientUploadStagePaymentProofTask({}), isFalse);
      expect(
        isClientUploadStagePaymentProofTask({
          'task_category': 'payment_pending',
        }),
        isFalse,
      );
    });
  });

  group('stage name and IST created time', () {
    const note = 'Sales SOP Project ID: 2553\n'
        'Project ID: 3326906\n'
        'Client: Test (a@b.c)\n'
        '\n'
        'Stage: Completion of Footing\n'
        'Upload payment proof for raised bill';

    test('reads the Stage line as the bill name', () {
      expect(stageNameFromClientProofTaskNote(note), 'Completion of Footing');
      expect(
        clientUploadStagePaymentProofCardTitle({
          'note': note,
          'task_category': 'client_upload_stage_payment_proof',
        }),
        'Completion of Footing',
      );
    });

    test('falls back to the note title when Stage is missing', () {
      expect(
        clientUploadStagePaymentProofCardTitle({
          'note': 'Sales SOP Project ID: 2553',
        }),
        'Sales SOP Project ID: 2553',
      );
    });

    test('naive UTC from get_erp_tasks becomes IST +5:30', () {
      expect(
        formatErpCreatedAtIst('2026-10-03T09:03:00'),
        '03 Oct 2026, 02:33 PM',
      );
      expect(
        formatErpCreatedAtIst('2026-10-03 09:03:00'),
        '03 Oct 2026, 02:33 PM',
      );
    });

    test('explicit offset or Z is not shifted a second time', () {
      expect(
        formatErpCreatedAtIst('2026-10-03T14:33:00+05:30'),
        '03 Oct 2026, 02:33 PM',
      );
      expect(
        formatErpCreatedAtIst('2026-10-03T09:03:00Z'),
        '03 Oct 2026, 02:33 PM',
      );
    });

    test('UTC late evening rolls the IST calendar date', () {
      expect(
        formatErpCreatedAtIst('2026-10-03T20:00:00'),
        '04 Oct 2026, 01:30 AM',
      );
    });
  });
}
