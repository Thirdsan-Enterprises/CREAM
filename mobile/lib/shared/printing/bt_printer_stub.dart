import '../../core/api/repositories/operations_repository.dart';
import 'bt_printer.dart';

/// The browser version: no Bluetooth printing (receipts go out as PDF).
Future<List<PairedPrinter>> pairedPrinters() async =>
    throw const PrinterProblem('Bluetooth printing works in the Android app.');

Future<void> printReceipt(
  SavedPrinter printer,
  Receipt receipt, {
  double? cashReceived,
}) async =>
    throw const PrinterProblem('Bluetooth printing works in the Android app.');
