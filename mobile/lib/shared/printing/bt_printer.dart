import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/repositories/operations_repository.dart';

import 'bt_printer_stub.dart' if (dart.library.io) 'bt_printer_io.dart' as impl;

/// A printer paired with this phone in its Bluetooth settings.
class PairedPrinter {
  const PairedPrinter(this.name, this.address);

  final String name;
  final String address;
}

/// The printer receipts go to, remembered on this phone.
class SavedPrinter {
  const SavedPrinter(this.name, this.address, this.paperMm);

  final String name;
  final String address;

  /// 58 or 80.
  final int paperMm;
}

/// Something went wrong printing; [message] is for the cashier.
class PrinterProblem implements Exception {
  const PrinterProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Direct Bluetooth printing to an ESC/POS thermal printer. Android only:
/// a browser or an iPhone cannot reach these printers, so there the
/// receipt is shared or printed as a PDF instead.
class BtPrinter {
  BtPrinter._();

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _name = 'printer.name';
  static const _address = 'printer.address';
  static const _paper = 'printer.paper';

  static Future<SavedPrinter?> saved() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_address);
    if (address == null) return null;
    return SavedPrinter(
      prefs.getString(_name) ?? address,
      address,
      prefs.getInt(_paper) ?? 80,
    );
  }

  static Future<void> save(SavedPrinter printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_name, printer.name);
    await prefs.setString(_address, printer.address);
    await prefs.setInt(_paper, printer.paperMm);
  }

  /// Printers paired with the phone. Throws [PrinterProblem] when
  /// Bluetooth is off or not allowed.
  static Future<List<PairedPrinter>> paired() => impl.pairedPrinters();

  /// Prints a receipt; throws [PrinterProblem] with what to do.
  static Future<void> printReceipt(
    SavedPrinter printer,
    Receipt receipt, {
    double? cashReceived,
  }) => impl.printReceipt(printer, receipt, cashReceived: cashReceived);
}
