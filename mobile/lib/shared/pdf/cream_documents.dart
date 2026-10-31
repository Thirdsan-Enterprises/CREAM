import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/api/repositories/branch_reports_repository.dart';
import '../models/stock_transfer.dart';

/// Text is kept to plain Latin characters: the built-in PDF font has no
/// arrows or long dashes.
///
/// Printable, shareable documents in Cream's brand: a transfer receipt and
/// a branch performance report. Built on the phone, so they work the same
/// on every device and need nothing extra on the server.

const _charcoal = PdfColor.fromInt(0xFF1A1A1A);
const _gold = PdfColor.fromInt(0xFFC9A15C);
const _cream = PdfColor.fromInt(0xFFF7F3EC);
const _muted = PdfColor.fromInt(0xFF6B6459);
const _red = PdfColor.fromInt(0xFFB3261E);
const _green = PdfColor.fromInt(0xFF2E7D32);

final _money = NumberFormat.decimalPattern('en_US');
final _dateTime = DateFormat('d MMM yyyy, h:mm a');
final _date = DateFormat('d MMM yyyy');

String ugx(num value) => 'UGX ${_money.format(value.round())}';
String _qty(num value) =>
    value == value.roundToDouble() ? _money.format(value) : '$value';

Future<pw.MemoryImage?> _logo() async {
  try {
    final data = await rootBundle.load('assets/branding/app_icon_master.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null; // A document without the mark is still a document.
  }
}

pw.Widget _header(pw.MemoryImage? logo, String title, String subtitle) {
  return pw.Container(
    color: _charcoal,
    padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 20),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null)
          pw.Container(width: 46, height: 46, child: pw.Image(logo)),
        if (logo != null) pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'CREAM RESTAURANT & CATERING SERVICES',
                style: pw.TextStyle(
                  color: _gold,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              pw.Text(
                'we serve beyond your desire',
                style: pw.TextStyle(
                  color: _cream,
                  fontSize: 8,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                color: _cream,
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(subtitle, style: const pw.TextStyle(color: _gold)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _footer(pw.Context context, String generatedBy) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(28, 8, 28, 12),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Printed ${_dateTime.format(DateTime.now())} by $generatedBy',
          style: const pw.TextStyle(color: _muted, fontSize: 8),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(color: _muted, fontSize: 8),
        ),
      ],
    ),
  );
}

pw.Widget _label(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
  child: pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      color: _gold,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 1.2,
    ),
  ),
);

pw.Widget _fact(String label, String value) => pw.Expanded(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 8)),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);

pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  Map<int, pw.Alignment> align = const {},
  Map<int, PdfColor> Function(int row)? colors,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    border: null,
    headerStyle: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: _charcoal,
    ),
    headerDecoration: const pw.BoxDecoration(color: _cream),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignment: pw.Alignment.centerLeft,
    cellAlignments: align,
    headerAlignment: pw.Alignment.centerLeft,
    headerAlignments: align,
    rowDecoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE6DED0), width: .5),
      ),
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    textStyleBuilder: colors == null
        ? null
        : (index, data, rowNum) {
            final color = colors(rowNum)[index];
            return color == null
                ? null
                : pw.TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: pw.FontWeight.bold,
                  );
          },
  );
}

pw.Widget _signature(String role, String? name) => pw.Expanded(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 28),
      pw.Container(height: .7, color: _charcoal),
      pw.SizedBox(height: 4),
      pw.Text(role, style: const pw.TextStyle(fontSize: 8, color: _muted)),
      if (name != null)
        pw.Text(
          name,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
    ],
  ),
);

/// Transfer receipt: what left the procurement unit, what arrived, the
/// difference, who sent and who received, with signature lines.
Future<Uint8List> transferReceiptPdf(
  StockTransfer transfer, {
  required String printedBy,
}) async {
  final logo = await _logo();
  final doc = pw.Document(
    title: 'Transfer receipt #${transfer.id}',
    author: 'Cream Restaurant & Catering Services',
  );

  final received = transfer.isReceived;
  final rows = <List<String>>[];
  final rowColors = <int, Map<int, PdfColor>>{};
  var short = 0;
  for (final line in transfer.items) {
    final diff = (line.qtyReceived ?? line.qtyDispatched) - line.qtyDispatched;
    if (received && diff != 0) {
      short++;
      rowColors[rows.length] = {4: diff < 0 ? _red : _green};
    }
    rows.add([
      line.itemName,
      line.unit,
      _qty(line.qtyDispatched),
      received ? _qty(line.qtyReceived ?? 0) : '-',
      received ? (diff == 0 ? 'OK' : (diff > 0 ? '+' : '') + _qty(diff)) : '-',
    ]);
  }

  final status = switch (transfer.status) {
    'dispatched' => 'On the way: not yet confirmed by ${transfer.toStoreName}',
    'confirmed' => 'Received in full',
    'discrepancy' => 'Received with $short difference${short == 1 ? '' : 's'}',
    _ => transfer.status,
  };

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      header: (_) => _header(logo, 'Transfer receipt', '#${transfer.id}'),
      footer: (context) => _footer(context, printedBy),
      build: (context) => [
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  _fact('From', transfer.fromStoreName),
                  _fact('To', transfer.toStoreName),
                  _fact(
                    'Sent',
                    _dateTime.format(transfer.dispatchedAt.toLocal()),
                  ),
                  _fact(
                    'Received',
                    transfer.confirmedAt == null
                        ? 'Not yet'
                        : _dateTime.format(transfer.confirmedAt!.toLocal()),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: transfer.status == 'discrepancy'
                      ? const PdfColor.fromInt(0xFFFBE9E7)
                      : _cream,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  status,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: transfer.status == 'discrepancy' ? _red : _charcoal,
                  ),
                ),
              ),
              _label('Items'),
              _table(
                ['Item', 'Unit', 'Sent', 'Received', 'Difference'],
                rows,
                align: const {
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                },
                colors: (row) => rowColors[row - 1] ?? const {},
              ),
              pw.SizedBox(height: 30),
              pw.Row(
                children: [
                  _signature(
                    'Sent by (${transfer.fromStoreName})',
                    transfer.dispatchedByName,
                  ),
                  pw.SizedBox(width: 40),
                  _signature(
                    'Received by (${transfer.toStoreName})',
                    transfer.confirmedByName,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Branch performance report for a period: the same figures as the
/// Branch screen, laid out for printing or sending.
Future<Uint8List> branchReportPdf(
  BranchDetail data, {
  required ReportRange range,
  required String printedBy,
}) async {
  final logo = await _logo();
  final period = range.resolve();
  final periodLabel = period.from == period.to
      ? _date.format(period.from)
      : '${_date.format(period.from)} to ${_date.format(period.to)}';
  final t = data.totals;
  final doc = pw.Document(
    title: '${data.storeName} performance, $periodLabel',
    author: 'Cream Restaurant & Catering Services',
  );

  final change = t.changePct == null
      ? 'No sales to compare'
      : '${t.changePct! >= 0 ? 'Up' : 'Down'} ${t.changePct!.abs().toStringAsFixed(1)}% ${range.comparisonLabel}';

  String pct(double part) =>
      t.revenue > 0 ? '${(part / t.revenue * 100).toStringAsFixed(0)}%' : '-';

  const payLabels = {
    'cash': 'Cash',
    'momo': 'MoMo',
    'airtel': 'Airtel',
    'account': 'Account',
    'lpo': 'LPO',
  };

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      header: (_) => _header(logo, data.storeName, periodLabel),
      footer: (context) => _footer(context, printedBy),
      build: (context) => [
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(28, 18, 28, 0),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                ugx(t.revenue),
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: _charcoal,
                ),
              ),
              pw.Text(
                change,
                style: pw.TextStyle(
                  color: (t.changePct ?? 0) < 0 ? _red : _green,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  _fact('Sales', '${t.salesCount}'),
                  _fact('Average sale', ugx(t.averageSale)),
                  _fact(
                    'Plates',
                    '${_qty(t.platesSold)} · ${ugx(t.plateRevenue)}',
                  ),
                  _fact(
                    'Drinks',
                    '${_qty(t.drinksSold)} · ${ugx(t.drinkRevenue)}',
                  ),
                ],
              ),
              if (t.itemsSold > 0) ...[
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    _fact(
                      'Breakfast & other items',
                      '${_qty(t.itemsSold)} · ${ugx(t.itemRevenue)}',
                    ),
                    pw.Expanded(flex: 3, child: pw.SizedBox()),
                  ],
                ),
              ],
              if (data.days > 1) ...[
                _label('Sales by day'),
                _table(
                  ['Day', 'Sales', 'Revenue'],
                  [
                    for (final day in data.daily)
                      [
                        DateFormat('EEE d MMM').format(DateTime.parse(day.key)),
                        '${day.salesCount}',
                        ugx(day.revenue),
                      ],
                  ],
                  align: const {
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                  },
                ),
              ],
              _label('How customers paid'),
              data.paymentMethods.isEmpty
                  ? pw.Text('No sales.')
                  : _table(
                      ['Method', 'Sales', 'Amount', 'Share'],
                      [
                        for (final m in data.paymentMethods)
                          [
                            payLabels[m.name] ?? m.name,
                            _qty(m.count),
                            ugx(m.revenue),
                            pct(m.revenue),
                          ],
                      ],
                      align: const {
                        1: pw.Alignment.centerRight,
                        2: pw.Alignment.centerRight,
                        3: pw.Alignment.centerRight,
                      },
                    ),
              _label('Sales by staff'),
              data.cashiers.isEmpty
                  ? pw.Text('No sales.')
                  : _table(
                      ['Name', 'Sales', 'Plates', 'Amount'],
                      [
                        for (final c in data.cashiers)
                          [
                            c.name,
                            _qty(c.count),
                            _qty(c.extra),
                            ugx(c.revenue),
                          ],
                      ],
                      align: const {
                        1: pw.Alignment.centerRight,
                        2: pw.Alignment.centerRight,
                        3: pw.Alignment.centerRight,
                      },
                    ),
              _label('Drinks & menu items'),
              data.drinks.isEmpty
                  ? pw.Text('Nothing sold besides plates.')
                  : _table(
                      ['Item', 'Heading', 'Qty', 'Amount'],
                      [
                        for (final d in data.drinks)
                          [
                            d.name,
                            d.category ?? 'Drinks',
                            _qty(d.count),
                            ugx(d.revenue),
                          ],
                      ],
                      align: const {
                        2: pw.Alignment.centerRight,
                        3: pw.Alignment.centerRight,
                      },
                    ),
              _label('Stock'),
              pw.Row(
                children: [
                  _fact('To re-order', '${data.reorderCount}'),
                  _fact('Sufficient', '${data.sufficientCount}'),
                  _fact('Transfers received', '${data.transfersReceived}'),
                  _fact('With differences', '${data.transfersWithDiscrepancy}'),
                ],
              ),
              if (data.reorderItems.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                _table(
                  ['Item to re-order', 'In stock', 'Re-order level'],
                  [
                    for (final r in data.reorderItems)
                      [r.name, _qty(r.balance), _qty(r.safetyStock)],
                  ],
                  align: const {
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                  },
                ),
              ],
              if (data.stockUsed.isNotEmpty) ...[
                _label('Stock used'),
                _table(
                  ['Item', 'Unit', 'Used'],
                  [
                    for (final s in data.stockUsed)
                      [s.name, s.unit, _qty(s.qty)],
                  ],
                  align: const {2: pw.Alignment.centerRight},
                ),
              ],
              pw.SizedBox(height: 16),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
