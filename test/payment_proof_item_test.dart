import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/Payments.dart';
import 'package:buildAhome/models/payment_proof_item.dart';

void main() {
  group('PaymentProofItem.resolveDisplayNote', () {
    test('uses backend note as the only string under the image', () {
      expect(
        PaymentProofItem.resolveDisplayNote({
          'note': 'Please upload UTR screenshot',
          'is_bill': false,
          'rejection_label': 'Not a bill',
          'reject_reason': 'ignored when note is present',
          'status': 'rejected',
        }),
        'Please upload UTR screenshot',
      );
    });

    test('hides the note when backend sends an empty note and no fallback', () {
      expect(
        PaymentProofItem.resolveDisplayNote({
          'note': '',
          'status': 'pending',
          'is_bill': true,
        }),
        '',
      );
    });

    test('old payload: finance reject_reason when status is rejected', () {
      expect(
        PaymentProofItem.resolveDisplayNote({
          'status': 'rejected',
          'reject_reason': 'Wrong screenshot, please upload UPI payment',
        }),
        'Wrong screenshot, please upload UPI payment',
      );
    });

    test('old payload: Not a bill when is_bill is false', () {
      expect(
        PaymentProofItem.resolveDisplayNote({
          'is_bill': false,
          'rejection_code': 'not_a_bill',
          'rejection_label': 'Not a bill',
        }),
        'Not a bill',
      );
    });

    test('old payload: default Not a bill when label is missing', () {
      expect(
        PaymentProofItem.resolveDisplayNote({
          'is_bill': false,
          'rejection_code': 'not_a_bill',
        }),
        'Not a bill',
      );
    });

    test('finance typed reason wins over not-a-bill on old payload', () {
      expect(
        PaymentProofItem.resolveDisplayNote({
          'status': 'rejected',
          'reject_reason': 'Please upload UTR screenshot',
          'is_bill': false,
          'rejection_code': 'not_a_bill',
          'rejection_label': 'Not a bill',
        }),
        'Please upload UTR screenshot',
      );
    });
  });

  group('PaymentProofItem display', () {
    test('selfie / not-a-bill shows dash amount, badge, and note', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'selfie.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/1?index=1',
        'is_bill': false,
        'rejection_code': 'not_a_bill',
        'rejection_label': 'Not a bill',
        'receipt_total': null,
        'status': 'rejected',
        'reject_reason': '',
        'note': 'Not a bill',
      });

      expect(item.note, 'Not a bill');
      expect(item.displayAmount, '—');
      expect(item.showNotABillBadge, isTrue);
      expect(item.isRejected, isTrue);
      expect(item.countsTowardPaymentTotal, isFalse);
    });

    test('finance reject of a real bill shows typed note and amount', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'upi.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/1?index=2',
        'is_bill': true,
        'rejection_code': '',
        'rejection_label': '',
        'receipt_total': 15000,
        'status': 'rejected',
        'reject_reason': 'Please upload UTR screenshot',
        'note': 'Please upload UTR screenshot',
      });

      expect(item.note, 'Please upload UTR screenshot');
      expect(item.showNotABillBadge, isFalse);
      expect(item.isRejected, isTrue);
      expect(item.displayAmount, isNot('—'));
      expect(item.countsTowardPaymentTotal, isFalse);
      expect(item.isCorrectBill, isFalse);
      expect(item.canRemove, isTrue);
    });

    test('valid pending bill with no reject hides the note row', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'bill.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/1?index=3',
        'is_bill': true,
        'receipt_total': 2500,
        'status': 'pending',
        'note': '',
      });

      expect(item.note, isEmpty);
      expect(item.isRejected, isFalse);
      expect(item.showNotABillBadge, isFalse);
      expect(item.countsTowardPaymentTotal, isTrue);
      expect(item.displayAmount, isNot('—'));
      expect(item.isCorrectBill, isTrue);
      expect(item.canRemove, isFalse);
    });

    test('approved proofs cannot be removed', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'IMG_1234.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/123?index=2',
        'index': 2,
        'is_bill': true,
        'receipt_total': 15000,
        'amount': 15000,
        'parsed_amount': 15000,
        'status': 'approved',
        'note': '',
      });

      expect(item.displayAmount, isNot('—'));
      expect(item.receiptTotal, 15000);
      expect(item.canRemove, isFalse);
      expect(item.isApproved, isTrue);
    });

    test('shows parsed amount from amount / parsed_amount aliases', () {
      final fromAmount = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/bill.jpg',
        'is_bill': true,
        'status': 'pending',
        'amount': 12500,
      });
      final fromParsed = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/bill.jpg',
        'is_bill': true,
        'openai': {'parsed_amount': 980, 'is_bill': true},
      });

      expect(fromAmount.displayAmount, isNot('—'));
      expect(fromParsed.receiptTotal, 980);
      expect(fromParsed.displayAmount, isNot('—'));
    });

    test('rejected bill can be removed and shows the reject reason', () {
      final item = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/x.jpg?index=4',
        'is_bill': false,
        'note': 'Not a bill',
        'status': 'rejected',
      });
      expect(item.canRemove, isTrue);
      expect(item.rejectionDisplayText, 'Not a bill');
      expect(item.index, 4);
    });
  });

  group('PaymentProofItem.listFromPayload', () {
    test('reads GET snapshot payment_proof_items so reopen keeps the note', () {
      final items = PaymentProofItem.listFromPayload({
        'section': {
          'payment_proof_items': [
            {
              'filename': 'IMG_1234.jpg',
              'url': '/serve_sales_sop_payment/123?index=2',
              'is_bill': false,
              'rejection_code': 'not_a_bill',
              'rejection_label': 'Not a bill',
              'receipt_total': null,
              'status': 'rejected',
              'reject_reason':
                  'Wrong screenshot, please upload UPI payment',
              'note': 'Wrong screenshot, please upload UPI payment',
            },
          ],
        },
      }, resolveUrl: (url) {
        if (url.startsWith('http')) return url;
        return 'https://office.buildahome.in$url';
      });

      expect(items, hasLength(1));
      expect(
        items.single.note,
        'Wrong screenshot, please upload UPI payment',
      );
      expect(items.single.showNotABillBadge, isTrue);
      expect(
        items.single.url,
        'https://office.buildahome.in/serve_sales_sop_payment/123?index=2',
      );
    });

    test('prefers classified upload files over url-only section lists', () {
      final items = PaymentProofItem.listFromPayload({
        'section': {
          'payment_screenshot_urls': [
            'https://office.buildahome.in/serve_sales_sop_payment/1?index=1',
          ],
        },
        'files': [
          {
            'filename': 'selfie.jpg',
            'url':
                'https://office.buildahome.in/serve_sales_sop_payment/1?index=1',
            'is_bill': false,
            'rejection_label': 'Not a bill',
            'note': 'Not a bill',
            'status': 'rejected',
          },
        ],
      });

      expect(items.single.note, 'Not a bill');
      expect(items.single.isNotABill, isTrue);
    });

    test('merges OpenAI classification onto the full snapshot list', () {
      final items = PaymentProofItem.listFromPayload({
        'section': {
          'payment_proof_items': [
            {
              'filename': 'old.jpg',
              'url': 'https://office.buildahome.in/p/old.jpg',
            },
            {
              'filename': 'selfie.jpg',
              'url': 'https://office.buildahome.in/p/selfie.jpg',
            },
          ],
        },
        'files': [
          {
            'filename': 'selfie.jpg',
            'url': 'https://office.buildahome.in/p/selfie.jpg',
            'is_bill': false,
            'rejection_label': 'Not a bill',
            'note': 'Not a bill',
            'status': 'rejected',
          },
        ],
      });

      expect(items, hasLength(2));
      expect(items[0].note, isEmpty);
      expect(items[1].note, 'Not a bill');
      expect(items[1].showNotABillBadge, isTrue);
    });

    test('does not add rejected or not-a-bill amounts into the total', () {
      final items = PaymentProofItem.listFromPayload({
        'payment_proof_items': [
          {
            'url': 'https://a.example/1.jpg',
            'is_bill': true,
            'status': 'pending',
            'receipt_total': 1000,
            'note': '',
          },
          {
            'url': 'https://a.example/2.jpg',
            'is_bill': false,
            'status': 'rejected',
            'receipt_total': 999,
            'note': 'Not a bill',
          },
          {
            'url': 'https://a.example/3.jpg',
            'is_bill': true,
            'status': 'rejected',
            'receipt_total': 500,
            'note': 'Please upload UTR screenshot',
          },
        ],
      });

      expect(PaymentProofItem.billableTotal(items), 1000);
    });

    test('reads amount and reject note from payment_screenshot_urls maps', () {
      final items = PaymentProofItem.listFromPayload({
        'section': {
          'payment_screenshot_urls': [
            {
              'url': 'https://office.buildahome.in/p/1.jpg',
              'is_bill': true,
              'parsed_amount': 15000,
              'status': 'pending',
            },
            {
              'url': 'https://office.buildahome.in/p/2.jpg',
              'is_bill': false,
              'rejection_label': 'Not a bill',
              'note': 'Not a bill',
              'status': 'rejected',
            },
          ],
        },
      });

      expect(items, hasLength(2));
      expect(items[0].displayAmount, isNot('—'));
      expect(items[0].receiptTotal, 15000);
      expect(items[0].canRemove, isFalse);
      expect(items[1].rejectionDisplayText, 'Not a bill');
      expect(items[1].isRejected, isTrue);
      expect(items[1].canRemove, isTrue);
    });

    test('reads pending bill amount and not-a-bill from top-level files', () {
      final items = PaymentProofItem.listFromPayload({
        'files': [
          {
            'filename': 'IMG_1234.jpg',
            'url':
                'https://office.buildahome.in/serve_sales_sop_payment/123?index=2',
            'index': 2,
            'is_bill': true,
            'receipt_total': 15000,
            'amount': 15000,
            'parsed_amount': 15000,
            'status': 'pending',
            'note': '',
          },
          {
            'filename': 'selfie.jpg',
            'url':
                'https://office.buildahome.in/serve_sales_sop_payment/123?index=3',
            'index': 3,
            'is_bill': false,
            'rejection_code': 'not_a_bill',
            'rejection_label': 'Not a bill',
            'receipt_total': null,
            'status': 'rejected',
            'reject_reason': 'Not a bill',
            'note': 'Not a bill',
          },
        ],
        'payment_screenshot_urls': [
          {
            'filename': 'IMG_1234.jpg',
            'url':
                'https://office.buildahome.in/serve_sales_sop_payment/123?index=2',
            'index': 2,
            'is_bill': true,
            'receipt_total': 15000,
            'amount': 15000,
            'parsed_amount': 15000,
            'status': 'pending',
            'note': '',
          },
        ],
        'payment_proof_items': [
          {
            'filename': 'IMG_1234.jpg',
            'url':
                'https://office.buildahome.in/serve_sales_sop_payment/123?index=2',
            'index': 2,
            'is_bill': true,
            'receipt_total': 15000,
            'status': 'pending',
            'note': '',
          },
        ],
        'section': {
          'files': [
            {
              'filename': 'IMG_1234.jpg',
              'url':
                  'https://office.buildahome.in/serve_sales_sop_payment/123?index=2',
              'index': 2,
              'is_bill': true,
              'receipt_total': 15000,
              'status': 'pending',
              'note': '',
            },
          ],
        },
      });

      expect(items.first.receiptTotal, 15000);
      expect(items.first.displayAmount, contains('15,000'));
      expect(items.first.canRemove, isFalse);
      expect(items.first.status, 'pending');
      final notABill = items.firstWhere((e) => e.isNotABill);
      expect(notABill.note, 'Not a bill');
      expect(notABill.canRemove, isTrue);
      expect(notABill.displayAmount, '—');
    });
  });

  group('PaymentProofItem cleared bills under the screenshot', () {
    test('shows NT and staged lines from the API text', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'upi.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/1?index=0',
        'is_bill': true,
        'receipt_total': 35000,
        'status': 'approved',
        'note': '',
        'cleared_bills_text':
            'NT bill #12 Extra civil — ₹15,000.00\nStaged bill #8 Foundation — ₹20,000.00',
      });
      expect(item.clearedBillsText, contains('NT bill #12'));
      expect(item.clearedBillsText, contains('Staged bill #8'));
      expect(item.isApproved, isTrue);
    });

    test('builds only the staged line when NT was not applied', () {
      final text = PaymentProofItem.resolveClearedBillsText({
        'finance_applied_bills': [
          {
            'id': 3,
            'name': 'Slab',
            'kind': 'raised',
            'amount': 500.5,
            'partial': true,
          },
        ],
      });
      expect(text, contains('Non-NT: Slab'));
      expect(text, contains('(partial)'));
      expect(text.startsWith('NT:'), isFalse);
      expect(text.contains('\nNT:'), isFalse);
    });

    test('prefers summary_text and parses nt_bills / non_nt_bills', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'upi.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/1?index=0',
        'amount': 25000,
        'finance_status': 'approved',
        'status': 'approved',
        'allocation_state': 'applied',
        'heading': 'Deducted from these bills',
        'summary_text':
            'NT: Extra civil — ₹15,000.00\nNon-NT: Foundation ST-8 — ₹10,000.00 (partial)',
        'nt_bills': [
          {
            'id': 12,
            'stage_name': 'Extra civil',
            'kind': 'nt',
            'amount': 15000,
            'amount_display': '₹15,000.00',
            'partial': false,
          },
        ],
        'non_nt_bills': [
          {
            'id': 8,
            'stage_name': 'Foundation',
            'kind': 'non_nt',
            'amount': 10000,
            'amount_display': '₹10,000.00',
            'partial': true,
            'bill_amount': 20000,
            'bill_number': 'ST-8',
          },
        ],
      });

      expect(item.allocationHeading, 'Deducted from these bills');
      expect(item.allocationState, 'applied');
      expect(item.clearedBillsText, contains('NT: Extra civil'));
      expect(item.clearedBillsText, contains('Foundation ST-8'));
      expect(item.billStages, hasLength(2));
      expect(item.billStages.first.isNt, isTrue);
      expect(item.billStages.last.partial, isTrue);
      expect(item.appliedStageLabels, ['Extra civil', 'Foundation']);
    });

    test('groups proofs by NT stages first then non-NT then awaiting', () {
      final allocated = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/a.jpg',
        'index': 0,
        'amount': 25000,
        'status': 'approved',
        'nt_bills': [
          {'id': 12, 'stage_name': 'Extra civil', 'kind': 'nt', 'amount': 15000},
        ],
        'non_nt_bills': [
          {
            'id': 8,
            'stage_name': 'Foundation',
            'kind': 'non_nt',
            'amount': 10000,
            'bill_number': 'ST-8',
          },
        ],
      });
      final pending = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/b.jpg',
        'index': 1,
        'amount': 5000,
        'status': 'pending',
      });

      final sections =
          PaymentProofItem.groupByBillStage([allocated, pending]);
      expect(sections, hasLength(3));
      expect(sections[0].isNt, isTrue);
      expect(sections[0].label, 'Extra civil');
      expect(sections[0].items, hasLength(1));
      expect(sections[1].kind, 'non_nt');
      expect(sections[1].label, contains('Foundation'));
      expect(sections[1].items.single.url, allocated.url);
      expect(sections[2].isAwaiting, isTrue);
      expect(sections[2].items.single.url, pending.url);
    });

    test('builds gallery sections from pending_stage_proof_tasks', () {
      final unassigned = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/u.jpg',
        'index': 0,
        'amount': 1000,
        'status': 'pending',
      });
      final linked = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/l.jpg',
        'index': 1,
        'amount': 2000,
        'status': 'pending',
        'stage_task_id': 36940,
        'stage_name': 'Completion of Footing',
      });
      final sections = PaymentProofItem.buildGallerySections(
        items: [unassigned, linked],
        pendingTasks: const [
          PaymentProofPendingTask(
            id: 36940,
            stageName: 'Completion of Footing',
            label: 'Upload payment proof for Completion of Footing',
          ),
          PaymentProofPendingTask(
            id: 36941,
            stageName: 'Completion of Plinth Beam',
            label: 'Upload payment proof for Completion of Plinth Beam',
          ),
        ],
      );

      expect(sections, hasLength(3));
      expect(sections[0].isTask, isTrue);
      expect(sections[0].label, 'Completion of Footing');
      expect(sections[0].items.single.url, linked.url);
      expect(sections[1].label, 'Completion of Plinth Beam');
      expect(sections[1].items, isEmpty);
      expect(sections[2].isAwaiting, isTrue);
      expect(sections[2].label, 'Other uploads');
      expect(sections[2].items.single.url, unassigned.url);
    });

    test('walks a receipt across stages when the proof has no stage name', () {
      final proof = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/a.jpg',
        'is_bill': true,
        'receipt_total': 1300000,
        'index': 1,
      });
      final stages = previousPaymentStagesByUrl(
        proofs: [proof],
        bills: const [
          PaymentBillRef(
            taskId: '1',
            name: 'Completion of Footing',
            description: '',
            isTender: true,
            status: 'paid',
            amount: 700000,
          ),
          PaymentBillRef(
            taskId: '2',
            name: 'Completion of Concrete',
            description: '',
            isTender: true,
            status: 'pending',
            amount: 700000,
          ),
        ],
      );
      expect(stages[proof.url], [
        'Completion of Footing',
        'Completion of Concrete',
      ]);
    });

    test('NT accordion uses the creation description and non-NT uses the stage', () {
      final item = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/a.jpg',
        'is_bill': true,
        'amount': 1000,
        'nt_bills': [
          {
            'stage_name': 'Extra',
            'description': 'Granite for kitchen counter',
            'kind': 'nt',
          },
        ],
        'non_nt_bills': [
          {
            'stage_name': 'Completion of Footing',
            'kind': 'non_nt',
            'description': 'ignored for staged bills',
          },
        ],
      });
      expect(item.appliedStageLabels, [
        'Granite for kitchen counter',
        'Completion of Footing',
      ]);
    });

    test('hides the line when the proof has no linked bill', () {
      final item = PaymentProofItem.fromJson({
        'filename': 'upi.jpg',
        'url': 'https://office.buildahome.in/serve_sales_sop_payment/1?index=0',
        'is_bill': true,
        'receipt_total': 1000,
        'status': 'pending',
        'note': '',
      });
      expect(item.clearedBillsText, isEmpty);
    });
  });

  group('allocateFinanceApprovedPayments', () {
    PendingPaymentRow row(String name, double amount, {bool tender = true}) {
      return PendingPaymentRow(
        name: name,
        amount: amount,
        isTender: tender,
        status: 'due',
      );
    }

    test('leaves pending amounts until finance approves the proof', () {
      final pending = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/a.jpg',
        'is_bill': true,
        'receipt_total': 1300000,
        'status': 'pending',
      });
      final result = allocateFinanceApprovedPayments(
        rows: [
          row('Completion of Footing', 700000),
          row('Completion of Concrete', 700000),
        ],
        proofs: [pending],
      );
      expect(result.rows, hasLength(2));
      expect(result.rows[0].amount, 700000);
      expect(result.rows[1].amount, 700000);
      expect(result.total, 1400000);
      expect(pending.isFinanceSettled, isFalse);
    });

    test('clears the first stage and leaves the remainder on the next', () {
      final approved = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/a.jpg',
        'is_bill': true,
        'receipt_total': 1300000,
        'status': 'pending',
        'finance_status': 'approved',
      });
      final result = allocateFinanceApprovedPayments(
        rows: [
          row('Completion of Footing', 700000),
          row('Completion of Concrete', 700000),
          row('Extra work', 50000, tender: false),
        ],
        proofs: [approved],
      );
      expect(approved.isFinanceSettled, isTrue);
      expect(result.rows.map((e) => e.name), [
        'Completion of Concrete',
        'Extra work',
      ]);
      expect(result.rows[0].amount, 100000);
      expect(result.rows[1].amount, 50000);
      expect(result.total, 150000);
      expect(
        paymentStageNameIsCleared(
          'Completion of Footing',
          result.clearedNameKeys,
        ),
        isTrue,
      );
      expect(
        paymentStageNameIsCleared('Completion of Concrete', result.clearedNameKeys),
        isFalse,
      );
    });

    test('continues the same balance across non-tender rows', () {
      final approved = PaymentProofItem.fromJson({
        'url': 'https://office.buildahome.in/p/a.jpg',
        'is_bill': true,
        'receipt_total': 800,
        'status': 'approved',
      });
      final result = allocateFinanceApprovedPayments(
        rows: [
          row('Completion of Footing', 500),
          row('768', 500, tender: false),
        ],
        proofs: [approved],
      );
      expect(result.rows, hasLength(1));
      expect(result.rows.single.name, '768');
      expect(result.rows.single.isTender, isFalse);
      expect(result.rows.single.amount, 200);
      expect(result.total, 200);
    });
  });
}
