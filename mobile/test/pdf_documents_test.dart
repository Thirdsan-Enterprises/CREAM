import 'dart:io';

import 'package:cream_pos/core/api/repositories/branch_reports_repository.dart';
import 'package:cream_pos/core/api/repositories/operations_repository.dart';
import 'package:cream_pos/shared/models/stock_transfer.dart';
import 'package:cream_pos/shared/pdf/cream_documents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a transfer receipt shows sent, received and the difference', () async {
    final transfer = StockTransfer.fromJson({
      'id': 42,
      'from_store_id': 1,
      'from_store': {'name': 'Kira'},
      'to_store_id': 3,
      'to_store': {'name': 'Town'},
      'status': 'discrepancy',
      'dispatched_at': '2026-10-30T07:15:00Z',
      'confirmed_at': '2026-10-30T09:40:00Z',
      'dispatched_by': {'name': 'Procurement'},
      'confirmed_by': {'name': 'Grace (Town)'},
      'items': [
        {
          'id': 1,
          'item_id': 1,
          'item': {'name': 'Rice', 'unit': 'kg'},
          'qty_dispatched': '20.00',
          'qty_received': '20.00',
        },
        {
          'id': 2,
          'item_id': 2,
          'item': {'name': 'Cooking oil', 'unit': 'litre'},
          'qty_dispatched': '5.00',
          'qty_received': '4.00',
        },
      ],
    });
    final bytes = await transferReceiptPdf(transfer, printedBy: 'Owner');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File('$out/transfer.pdf').writeAsBytesSync(bytes);
  });

  test('a branch report renders', () async {
    final data = BranchDetail.fromJson({
      'store': {'name': 'Town', 'is_main': false},
      'period': {'days': 7},
      'totals': {
        'revenue': 1850000,
        'previous_revenue': 1600000,
        'change_pct': 15.6,
        'sales_count': 92,
        'average_sale': 20108,
        'plates_sold': 98,
        'plate_revenue': 1470000,
        'drinks_sold': 120,
        'drink_revenue': 330000,
        'items_sold': 40,
        'item_revenue': 50000,
      },
      'daily': [
        for (var d = 24; d <= 30; d++)
          {
            'date': '2026-10-$d',
            'revenue': 200000 + d * 3000,
            'sales_count': 13,
          },
      ],
      'hourly': [
        for (var h = 0; h < 24; h++)
          {'hour': h, 'revenue': 0, 'sales_count': 0},
      ],
      'by_payment_method': [
        {'method': 'cash', 'revenue': 1200000, 'sales_count': 60},
        {'method': 'momo', 'revenue': 500000, 'sales_count': 25},
        {'method': 'account', 'revenue': 150000, 'sales_count': 7},
      ],
      'by_cashier': [
        {
          'name': 'Grace',
          'revenue': 1100000,
          'sales_count': 55,
          'plates_sold': 60,
        },
        {
          'name': 'Owner',
          'revenue': 750000,
          'sales_count': 37,
          'plates_sold': 38,
        },
      ],
      'drinks': [],
      'menu_items': [
        {'name': 'Soda', 'category': 'Drinks', 'qty': 80, 'revenue': 160000},
        {
          'name': 'Passion Juice',
          'category': 'Drinks',
          'qty': 34,
          'revenue': 170000,
        },
        {'name': 'Tea', 'category': 'Breakfast', 'qty': 30, 'revenue': 30000},
        {'name': 'Egg', 'category': 'Breakfast', 'qty': 10, 'revenue': 20000},
      ],
      'stock_used': [
        {'name': 'Rice', 'unit': 'kg', 'is_drink': false, 'qty': 42},
      ],
      'stock': {
        'reorder_count': 2,
        'sufficient_count': 14,
        'reorder_items': [
          {'item_name': 'Cooking oil', 'balance': 2, 'safety_stock': 5},
          {'item_name': 'Soda', 'balance': 6, 'safety_stock': 10},
        ],
      },
      'transfers': {
        'received': 3,
        'with_discrepancy': 1,
        'awaiting_confirmation': 0,
      },
      'recent_sales': [],
    });
    final bytes = await branchReportPdf(
      data,
      range: ReportRange.last7Days,
      printedBy: 'Owner',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File('$out/branch.pdf').writeAsBytesSync(bytes);
  });

  test('a cashier day report renders', () async {
    final day = DayReport.fromJson({
      'date': '2026-11-05',
      'scope': 'person',
      'person': {'id': 7, 'name': 'Joy Akello', 'role': 'cashier'},
      'store': {'id': 3, 'name': 'Town'},
      'sales_count': 31,
      'gross': 392000,
      'discounts': 2000,
      'total': 390000,
      'plates': 28,
      'by_payment': [
        {'method': 'cash', 'count': 22, 'total': 270000},
        {'method': 'momo', 'count': 9, 'total': 120000},
      ],
      'items': [
        {'name': 'Beef', 'category': 'Lunch', 'qty': 14, 'revenue': 140000},
        {'name': 'Fish', 'category': 'Lunch', 'qty': 8, 'revenue': 96000},
        {'name': 'Peas', 'category': 'Lunch', 'qty': 6, 'revenue': 54000},
        {
          'name': 'Milk Tea',
          'category': 'Breakfast',
          'qty': 12,
          'revenue': 36000,
        },
        {
          'name': 'Chapati',
          'category': 'Breakfast',
          'qty': 20,
          'revenue': 30000,
        },
        {'name': 'Soda', 'category': 'Drinks', 'qty': 24, 'revenue': 36000},
      ],
      'discounted_sales': [
        {
          'id': 4,
          'discount': 2000,
          'note': 'Regular customer',
          'sold_at': '2026-11-05T10:00:00Z',
        },
      ],
      'cancelled_sales': [
        {
          'id': 9,
          'total': 10000,
          'reason': 'Rang twice',
          'sold_at': '2026-11-05T11:00:00Z',
        },
      ],
      'expenses': [
        {
          'id': 1,
          'amount': 5000,
          'category': 'Transport',
          'note': 'Boda to market',
          'paid_from': 'cash',
          'spent_at': '2026-11-05T08:00:00Z',
          'recorded_by': 'Joy Akello',
        },
        {
          'id': 2,
          'amount': 3000,
          'category': 'Small purchases',
          'note': 'Matches',
          'paid_from': 'cash',
          'spent_at': '2026-11-05T09:00:00Z',
          'recorded_by': 'Joy Akello',
        },
      ],
      'expenses_total': 8000,
      'cash_sales': 270000,
      'cash_expenses': 8000,
      'cash_to_hand_over': 262000,
    });
    final bytes = await dayReportPdf(day, printedBy: 'Joy Akello');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File('$out/day.pdf').writeAsBytesSync(bytes);
  });
}
