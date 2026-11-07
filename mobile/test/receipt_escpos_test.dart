import 'package:cream_pos/core/api/repositories/operations_repository.dart';
import 'package:cream_pos/shared/printing/receipt_escpos.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _receipt() => Receipt.fromJson({
  'number': 1042,
  'sold_at': '2026-11-05T10:15:00Z',
  'store': {'name': 'Town', 'address': 'Kampala Road', 'phone': '0700000000'},
  'cashier': 'Joy Akello',
  'lines': [
    {'name': 'Beef', 'qty': 2, 'unit_price': 10000, 'total': 20000},
    {'name': 'Silver plate', 'qty': 2, 'unit_price': 500, 'total': 1000},
    {'name': 'Chapati – large', 'qty': 1, 'unit_price': 1500, 'total': 1500},
  ],
  'subtotal': 22500,
  'discount': 500,
  'discount_note': 'Regular',
  'total': 22000,
  'payment_method': 'cash',
  'customer': null,
  'voided': false,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final paper in [PaperSize.mm80, PaperSize.mm58]) {
    test('a receipt prints as text on a ${paper.value == 1 ? 58 : 80} mm '
        'thermal printer', () async {
      final g = Generator(paper, await CapabilityProfile.load());
      final bytes = receiptEscPos(_receipt(), g, cashReceived: 30000);
      final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

      for (final expected in [
        'CREAM',
        'Town',
        'Receipt #1042',
        'Served by Joy Akello',
        'Beef',
        '2 x 10,000',
        '20,000',
        'Silver plate',
        'Chapati - large',
        'Discount',
        'UGX 22,000',
        'Cash',
        '30,000',
        '8,000',
        'Not a URA EFRIS fiscal receipt.',
      ]) {
        expect(text, contains(expected));
      }
      // Ends by cutting the paper.
      expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x30]);
    });
  }

  test('anything a printer cannot print is replaced or dropped', () {
    expect(asciiOnly('2 × Chapati — “big”'), '2 x Chapati - "big"');
    expect(asciiOnly('Café 🍛'), 'Caf ');
  });
}
