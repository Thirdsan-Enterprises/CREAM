import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../../core/api/repositories/operations_repository.dart';

final _money = NumberFormat('#,##0', 'en_US');
final _when = DateFormat('d MMM yyyy, h:mm a');

const _payLabels = {
  'cash': 'Cash',
  'momo': 'MTN MoMo',
  'airtel': 'Airtel Money',
  'account': 'Customer account',
  'lpo': 'LPO',
};

/// Thermal printers print plain ASCII: anything else becomes a close
/// match or is dropped, so a name never prints as garbage.
String asciiOnly(String s) => s
    .replaceAll('×', 'x')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp(r'[^\x20-\x7E]'), '');

String _qty(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// The customer receipt as ESC/POS commands for a Bluetooth thermal
/// printer (58 or 80 mm), laid out like the PDF receipt.
List<int> receiptEscPos(Receipt r, Generator g, {double? cashReceived}) {
  final out = <int>[];
  void line(String text, {PosStyles styles = const PosStyles()}) =>
      out.addAll(g.text(asciiOnly(text), styles: styles));
  void pair(String left, String right, {bool bold = false}) => out.addAll(
    g.row([
      PosColumn(
        text: asciiOnly(left),
        width: 7,
        styles: PosStyles(bold: bold),
      ),
      PosColumn(
        text: asciiOnly(right),
        width: 5,
        styles: PosStyles(align: PosAlign.right, bold: bold),
      ),
    ]),
  );

  const center = PosStyles(align: PosAlign.center);
  out.addAll(g.reset());
  line(
    'CREAM',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ),
  );
  line('Restaurant & Catering Services', styles: center);
  line('we serve beyond your desire', styles: center);
  line(
    r.storeName,
    styles: const PosStyles(align: PosAlign.center, bold: true),
  );
  if (r.storeAddress != null && r.storeAddress!.isNotEmpty) {
    line(r.storeAddress!, styles: center);
  }
  if (r.storePhone != null && r.storePhone!.isNotEmpty) {
    line('Tel ${r.storePhone}', styles: center);
  }
  out.addAll(g.hr());
  pair('Receipt #${r.number}', '');
  line(_when.format(r.soldAt.toLocal()));
  if (r.cashier != null) line('Served by ${r.cashier}');
  if (r.voided) {
    line(
      'CANCELLED',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
  }
  out.addAll(g.hr());
  for (final (name, qty, price, total) in r.lines) {
    line(name, styles: const PosStyles(bold: true));
    pair('  ${_qty(qty)} x ${_money.format(price)}', _money.format(total));
  }
  out.addAll(g.hr());
  if (r.discount > 0) {
    pair('Subtotal', _money.format(r.subtotal));
    pair('Discount', '-${_money.format(r.discount)}');
    if (r.discountNote != null && r.discountNote!.isNotEmpty) {
      line('  (${r.discountNote})');
    }
  }
  out.addAll(
    g.row([
      PosColumn(
        text: 'TOTAL',
        width: 5,
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
      PosColumn(
        text: 'UGX ${_money.format(r.total)}',
        width: 7,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    ]),
  );
  pair('Paid by', _payLabels[r.paymentMethod] ?? r.paymentMethod);
  if (cashReceived != null && cashReceived >= r.total) {
    pair('Cash received', _money.format(cashReceived));
    pair('Change', _money.format(cashReceived - r.total), bold: true);
  }
  if (r.customerName != null) {
    line('Account: ${r.customerName}');
    if (r.customerBalance != null) {
      pair(
        r.customerBalance! < 0 ? 'Balance owed' : 'Balance left',
        'UGX ${_money.format(r.customerBalance!.abs())}',
      );
    }
  }
  out.addAll(g.hr());
  line(
    'Thank you for dining with us!',
    styles: const PosStyles(align: PosAlign.center, bold: true),
  );
  line('Customer receipt.', styles: center);
  line('Not a URA EFRIS fiscal receipt.', styles: center);
  out.addAll(g.feed(3));
  out.addAll(g.cut());
  return out;
}
