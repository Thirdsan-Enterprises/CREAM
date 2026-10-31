import 'package:cream_pos/shared/models/stock_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a confirmed transfer reads when people come back as plain ids', () {
    // POST /transfers/{id}/confirm returns dispatched_by / confirmed_by as
    // ids, not people. This used to throw, so the branch saw "Something
    // went wrong" although the delivery was recorded.
    final transfer = StockTransfer.fromJson({
      'id': 3,
      'from_store_id': 1,
      'to_store_id': 3,
      'status': 'confirmed',
      'dispatched_at': '2026-10-31T11:24:00Z',
      'dispatched_by': 4,
      'confirmed_by': 7,
      'confirmed_at': '2026-10-31T11:25:00Z',
      'items': [],
    });
    expect(transfer.dispatchedByName, isNull);
    expect(transfer.isReceived, isTrue);
  });
}
