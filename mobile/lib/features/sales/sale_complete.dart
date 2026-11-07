import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/operations_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/pdf/cream_documents.dart';
import '../../shared/pdf/share_pdf.dart';
import '../../shared/printing/bt_printer.dart';
import '../../shared/printing/printer_picker.dart';

/// After a sale: the amount, the change to give, any account warning, and
/// the receipt to print or send. One tap starts the next sale.
Future<void> showSaleComplete(
  BuildContext context, {
  required int? saleId,
  required double total,
  double? cashReceived,
  String? warning,
  bool blocked = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Consumer(
          builder: (context, ref, _) {
            final change = cashReceived == null ? null : cashReceived - total;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 56,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sale complete',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  CurrencyFormatter.format(total),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (change != null && change >= 0)
                  Text(
                    'Change: ${CurrencyFormatter.format(change)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (warning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          (blocked ? AppColors.danger : const Color(0xFFB7791F))
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          blocked ? Icons.block : Icons.warning_amber,
                          color: blocked
                              ? AppColors.danger
                              : const Color(0xFFB7791F),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(warning)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (saleId != null)
                  OutlinedButton.icon(
                    onPressed: () => offerReceipt(
                      context,
                      ref,
                      saleId,
                      cashReceived: cashReceived,
                    ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Receipt'),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'New sale',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Print or send (WhatsApp...) a sale's receipt. On an Android phone the
/// receipt goes straight to the Bluetooth thermal printer; elsewhere (and
/// on request) it is a PDF to share or print.
Future<void> offerReceipt(
  BuildContext context,
  WidgetRef ref,
  int saleId, {
  double? cashReceived,
}) async {
  Future<void> asPdf() => offerPdf(
    context,
    title: 'Receipt #$saleId',
    filename: 'cream-receipt-$saleId.pdf',
    build: () async {
      final receipt = await ref
          .read(operationsRepositoryProvider)
          .receipt(saleId);
      return receiptPdf(receipt, cashReceived: cashReceived);
    },
  );

  if (!BtPrinter.supported) return asPdf();

  final printer = await BtPrinter.saved();
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text(
              'Receipt #$saleId',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (printer != null)
            ListTile(
              leading: const Icon(Icons.print, color: AppColors.success),
              title: Text('Print on ${printer.name}'),
              subtitle: Text('Bluetooth · ${printer.paperMm} mm paper'),
              onTap: () => Navigator.pop(context, 'print'),
            ),
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: Text(
              printer == null ? 'Choose Bluetooth printer' : 'Change printer',
            ),
            onTap: () => Navigator.pop(context, 'choose'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Share or print as PDF'),
            subtitle: const Text('WhatsApp, email, other printers...'),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'pdf':
      return asPdf();
    case 'choose':
      final chosen = await choosePrinter(context);
      if (chosen != null && context.mounted) {
        await _printOn(context, ref, saleId, chosen, cashReceived);
      }
    case 'print':
      await _printOn(context, ref, saleId, printer!, cashReceived);
  }
}

Future<void> _printOn(
  BuildContext context,
  WidgetRef ref,
  int saleId,
  SavedPrinter printer,
  double? cashReceived,
) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  String message;
  try {
    final receipt = await ref
        .read(operationsRepositoryProvider)
        .receipt(saleId);
    await BtPrinter.printReceipt(printer, receipt, cashReceived: cashReceived);
    message = 'Receipt printed on ${printer.name}.';
  } catch (e) {
    message = e is PrinterProblem ? e.message : 'Could not print: $e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
