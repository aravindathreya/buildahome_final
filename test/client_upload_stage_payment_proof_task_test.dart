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
}
