import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/models/work_order.dart';

void main() {
  group('formatIndianRupees', () {
    test('uses Indian grouping', () {
      expect(formatIndianRupees(120000), '₹1,20,000');
      expect(formatIndianRupees(250000), '₹2,50,000');
      expect(formatIndianRupees(1000), '₹1,000');
      expect(formatIndianRupees(100), '₹100');
      expect(formatIndianRupees(0), '₹0');
    });

    test('keeps minus for negative balance', () {
      expect(formatIndianRupees(-15000), '-₹15,000');
    });
  });

  group('WorkOrder.fromJson list item', () {
    test('parses the list payload example', () {
      final item = WorkOrder.fromJson({
        'work_order_id': 44,
        'trade': 'Civil',
        'wo_number': 'WO-44',
        'value': 250000,
        'status': 'approved',
        'status_label': 'Approved',
        'contractor': {
          'name': 'ABC Contractors',
          'code': 'C1',
          'pan': 'ABCDE1234F',
        },
        'has_pdf': true,
        'pdf_document': {
          'url': 'https://office.buildahome.in/files/work_order_44.pdf',
          'path': '/files/work_order_44.pdf',
        },
      });

      expect(item.workOrderId, 44);
      expect(item.trade, 'Civil');
      expect(item.displayWoNumber(prefixWoHash: true), 'WO #WO-44');
      expect(item.value, 250000);
      expect(item.statusKind, WorkOrderStatusKind.approved);
      expect(item.displayStatusLabel, 'Approved');
      expect(item.contractor.name, 'ABC Contractors');
      expect(item.canOpenPdf, isTrue);
      expect(
        item.pdfDocument!.resolvedUrl,
        'https://office.buildahome.in/files/work_order_44.pdf',
      );
    });

    test('falls back to work_order_id for WO number', () {
      final item = WorkOrder.fromJson({'work_order_id': 9, 'status': 'unsigned'});
      expect(item.displayWoNumber(prefixWoHash: true), 'WO #9');
      expect(item.displayWorkOrderNo(), '#9');
      expect(item.statusKind, WorkOrderStatusKind.unsigned);
      expect(item.displayStatusLabel, 'Unsigned');
    });

    test('maps unapproved to awaiting approval', () {
      final item = WorkOrder.fromJson({'status': 'unapproved'});
      expect(item.statusKind, WorkOrderStatusKind.unapproved);
      expect(item.displayStatusLabel, 'Awaiting approval');
    });
  });

  group('WorkOrderListResult', () {
    test('parses summary and project fields', () {
      final result = WorkOrderListResult.fromJson({
        'success': true,
        'project_id': 958,
        'sales_sop_id': 214,
        'project_name': 'Site A',
        'project_number': 'P-12',
        'status': 'all',
        'summary': {
          'total': 4,
          'approved': 2,
          'unsigned': 1,
          'unapproved': 1,
        },
        'items': [
          {
            'work_order_id': 44,
            'trade': 'Civil',
            'value': 250000,
            'status': 'approved',
          },
        ],
        'has_more': false,
      });

      expect(result.projectId, 958);
      expect(result.salesSopId, 214);
      expect(result.projectSubtitle, 'Site A · P-12');
      expect(result.summary.total, 4);
      expect(result.summary.approved, 2);
      expect(result.items, hasLength(1));
      expect(result.hasMore, isFalse);
    });
  });

  group('WorkOrder detail extras', () {
    test('parses totals, milestones, notes, locked, and documents', () {
      final item = WorkOrder.fromJson({
        'work_order_id': 44,
        'trade': 'Civil',
        'wo_number': 'WO-44',
        'status': 'approved',
        'locked': 1,
        'created_at': '12 Jan 2026',
        'comments': 'Site extras',
        'contractor': {
          'name': 'ABC Contractors',
          'code': 'C1',
          'pan': 'ABCDE1234F',
        },
        'has_pdf': true,
        'pdf_document': {'url': 'https://example.com/wo.pdf'},
        'has_difference_of_cost': true,
        'difference_of_cost_document': {
          'path': '/files/doc_44.pdf',
        },
        'totals': {
          'wo_value': 250000,
          'total_billed': 100000,
          'total_paid': 80000,
          'balance': -5000,
        },
        'milestones': [
          {
            'stage': 'Foundation',
            'percentage': 20,
            'billed': 50000,
            'paid': 40000,
            'approved_on': '1 Feb 2026',
          },
          {
            'stage': 'Hold',
            'is_debit_note': true,
            'notes': 'Material return',
            'billed': 0,
            'paid': 0,
          },
          {
            'stage': 'Clearing',
            'percentage': '',
            'is_clearing_balance': 1,
            'billed': 1000,
            'paid': 1000,
          },
        ],
        'notes': [
          {
            'text': 'Signed copy uploaded',
            'posted_by': 'Priya',
            'posted_at': '2 Feb 2026',
          },
        ],
      });

      expect(item.locked, isTrue);
      expect(item.totals.woValue, 250000);
      expect(item.totals.balance, -5000);
      expect(item.canOpenPdf, isTrue);
      expect(item.canOpenDifferenceOfCost, isTrue);
      expect(
        item.differenceOfCostDocument!.resolvedUrl,
        'https://office.buildahome.in/files/doc_44.pdf',
      );

      expect(item.milestones, hasLength(3));
      expect(item.milestones[0].hasPercentage, isTrue);
      expect(item.milestones[0].percentage, '20');
      expect(item.milestones[1].displayStage, 'Debit note · Hold');
      expect(item.milestones[1].notes, 'Material return');
      expect(item.milestones[2].hasPercentage, isFalse);
      expect(item.milestones[2].isClearingBalance, isTrue);

      expect(item.notes, hasLength(1));
      expect(item.notes.first.postedBy, 'Priya');
    });
  });

  group('groupWorkOrdersForDisplay', () {
    test('stays flat when fewer than 4 items', () {
      final items = [
        WorkOrder.fromJson({'trade': 'Civil', 'work_order_id': 1}),
        WorkOrder.fromJson({'trade': 'Electrical', 'work_order_id': 2}),
      ];
      final sections = groupWorkOrdersForDisplay(items);
      expect(sections, hasLength(1));
      expect(sections.first.trade, isEmpty);
      expect(sections.first.items, hasLength(2));
    });

    test('groups by trade when there are 4 or more items', () {
      final items = [
        WorkOrder.fromJson({'trade': 'Civil', 'work_order_id': 1}),
        WorkOrder.fromJson({'trade': 'Civil', 'work_order_id': 2}),
        WorkOrder.fromJson({'trade': 'Electrical', 'work_order_id': 3}),
        WorkOrder.fromJson({'trade': 'Plumbing', 'work_order_id': 4}),
      ];
      final sections = groupWorkOrdersForDisplay(items);
      expect(sections.map((s) => s.trade).toList(), [
        'Civil',
        'Electrical',
        'Plumbing',
      ]);
      expect(sections.first.items, hasLength(2));
    });
  });
}
