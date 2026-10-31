import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Offers a document as a PDF: share or save it (WhatsApp, email, Files,
/// Drive) or print it. [build] runs once, while a spinner shows.
Future<void> offerPdf(
  BuildContext context, {
  required String title,
  required String filename,
  required Future<Uint8List> Function() build,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(filename),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share or save'),
            subtitle: const Text('WhatsApp, email, Files, Drive...'),
            onTap: () => Navigator.pop(context, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Print or preview'),
            onTap: () => Navigator.pop(context, 'print'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  Uint8List bytes;
  try {
    bytes = await build();
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not make the PDF. Try again.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (choice == 'share') {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  } else {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
  }
}
