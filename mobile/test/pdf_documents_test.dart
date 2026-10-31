import 'dart:io';

import 'package:cream_pos/core/api/repositories/branch_reports_repository.dart';
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
}
