import 'package:buildAhome/Payments.dart';
import 'package:buildAhome/models/payment_proof_item.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentProofItem _proof({
  required String status,
  String stageName = '',
  int? stageTaskId,
  bool isBill = true,
  String rejectionCode = '',
}) {
  return PaymentProofItem.fromJson({
    'url': 'https://office.buildahome.in/proof.jpg',
    'filename': 'proof.jpg',
    'is_bill': isBill,
    'status': status,
    'stage_name': stageName,
    if (stageTaskId != null) 'stage_task_id': stageTaskId,
    if (rejectionCode.isNotEmpty) 'rejection_code': rejectionCode,
  });
}

void main() {
  test('screenshot waiting on finance shows as in review', () {
    final status = displayedPaymentStatus(
      paidStatus: 'pending',
      name: 'Completion of Footing',
      isTender: true,
      proofs: [_proof(status: 'pending', stageName: 'Footing')],
    );
    expect(isPaymentStatusInReview(status), isTrue);
  });

  test('finance-approved screenshot stays on the payment status', () {
    final status = displayedPaymentStatus(
      paidStatus: 'pending',
      name: 'Completion of Footing',
      isTender: true,
      proofs: [_proof(status: 'approved', stageName: 'Footing')],
    );
    expect(status, 'pending');
  });

  test('paid stays paid even when a screenshot is still open', () {
    final status = displayedPaymentStatus(
      paidStatus: 'paid',
      name: 'Footing',
      isTender: true,
      proofs: [_proof(status: 'pending', stageName: 'Footing')],
    );
    expect(isPaymentStatusPaid(status), isTrue);
  });

  test('a screenshot for another stage does not mark this payment', () {
    final status = displayedPaymentStatus(
      paidStatus: 'due',
      name: 'Plinth Beam',
      isTender: true,
      proofs: [_proof(status: 'pending', stageName: 'Footing')],
    );
    expect(status, 'due');
    expect(isPaymentStatusScheduled(status), isFalse);
  });

  test('not due with no screenshot stays scheduled so the list can hide it', () {
    final status = displayedPaymentStatus(
      paidStatus: 'not due',
      name: 'Roof',
      isTender: true,
      proofs: const [],
    );
    expect(isPaymentStatusScheduled(status), isTrue);
  });

  test('not a bill does not put the payment in review', () {
    final status = displayedPaymentStatus(
      paidStatus: 'due',
      name: 'Footing',
      isTender: true,
      taskId: '42',
      proofs: [
        _proof(
          status: 'pending',
          stageTaskId: 42,
          isBill: false,
          rejectionCode: 'not_a_bill',
        ),
      ],
    );
    expect(status, 'due');
  });
}
