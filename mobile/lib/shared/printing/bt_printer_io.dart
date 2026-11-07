import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/api/repositories/operations_repository.dart';
import 'bt_printer.dart';
import 'receipt_escpos.dart';

String? _connectedTo;

Future<void> _ready() async {
  if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
    throw const PrinterProblem(
      'Allow Cream to use "Nearby devices" (Bluetooth) when the phone asks, '
      'or in Settings > Apps > Cream > Permissions.',
    );
  }
  if (!await PrintBluetoothThermal.bluetoothEnabled) {
    throw const PrinterProblem('Turn on Bluetooth, then try again.');
  }
}

Future<List<PairedPrinter>> pairedPrinters() async {
  await _ready();
  final devices = await PrintBluetoothThermal.pairedBluetooths;
  return [for (final d in devices) PairedPrinter(d.name, d.macAdress)];
}

Future<void> printReceipt(
  SavedPrinter printer,
  Receipt receipt, {
  double? cashReceived,
}) async {
  await _ready();
  final connected = await PrintBluetoothThermal.connectionStatus;
  if (!connected || _connectedTo != printer.address) {
    if (connected) await PrintBluetoothThermal.disconnect;
    final ok = await PrintBluetoothThermal.connect(
      macPrinterAddress: printer.address,
    );
    if (!ok) {
      _connectedTo = null;
      throw PrinterProblem(
        'Could not reach ${printer.name}. Check it is on, has paper and is '
        'near the phone, then try again.',
      );
    }
    _connectedTo = printer.address;
  }
  final profile = await CapabilityProfile.load();
  final generator = Generator(
    printer.paperMm == 58 ? PaperSize.mm58 : PaperSize.mm80,
    profile,
  );
  final sent = await PrintBluetoothThermal.writeBytes(
    receiptEscPos(receipt, generator, cashReceived: cashReceived),
  );
  if (!sent) {
    _connectedTo = null;
    throw PrinterProblem(
      'The receipt did not reach ${printer.name}. Try again.',
    );
  }
}
