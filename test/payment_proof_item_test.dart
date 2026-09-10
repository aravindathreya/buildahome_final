import 'package:flutter_test/flutter_test.dart';

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
      expect(item.canRemove, isTrue);
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
      expect(items[0].canRemove, isTrue);
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
      expect(items.first.canRemove, isTrue);
      expect(items.first.status, 'pending');
      final notABill = items.firstWhere((e) => e.isNotABill);
      expect(notABill.note, 'Not a bill');
      expect(notABill.canRemove, isTrue);
      expect(notABill.displayAmount, '—');
    });
  });
}
