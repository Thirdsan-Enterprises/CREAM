import 'package:flutter/material.dart';

import 'bt_printer.dart';

/// Lists the printers paired with this phone, with the paper width, and
/// remembers the one chosen. Returns it, or null when cancelled.
Future<SavedPrinter?> choosePrinter(BuildContext context) {
  return showDialog<SavedPrinter>(
    context: context,
    builder: (_) => const _PrinterPicker(),
  );
}

class _PrinterPicker extends StatefulWidget {
  const _PrinterPicker();

  @override
  State<_PrinterPicker> createState() => _PrinterPickerState();
}

class _PrinterPickerState extends State<_PrinterPicker> {
  List<PairedPrinter>? _printers;
  String? _problem;
  int _paper = 80;

  @override
  void initState() {
    super.initState();
    BtPrinter.saved().then((p) {
      if (p != null && mounted) setState(() => _paper = p.paperMm);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _printers = null;
      _problem = null;
    });
    try {
      final printers = await BtPrinter.paired();
      if (mounted) setState(() => _printers = printers);
    } catch (e) {
      if (mounted) {
        setState(() {
          _printers = const [];
          _problem = e is PrinterProblem
              ? e.message
              : 'Could not read the Bluetooth printers.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final printers = _printers;
    return AlertDialog(
      title: const Text('Receipt printer'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Paper width'),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 80, label: Text('80 mm')),
                ButtonSegment(value: 58, label: Text('58 mm')),
              ],
              selected: {_paper},
              onSelectionChanged: (v) => setState(() => _paper = v.first),
            ),
            const SizedBox(height: 12),
            if (printers == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_problem != null)
              Text(_problem!)
            else if (printers.isEmpty)
              const Text(
                'No printer is paired with this phone. Turn the printer on, '
                'pair it in the phone\'s Bluetooth settings (the PIN is '
                'usually 0000 or 1234), then come back.',
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in printers)
                      ListTile(
                        leading: const Icon(Icons.print_outlined),
                        title: Text(p.name.isEmpty ? p.address : p.name),
                        subtitle: Text(p.address),
                        onTap: () async {
                          final chosen = SavedPrinter(
                            p.name.isEmpty ? p.address : p.name,
                            p.address,
                            _paper,
                          );
                          await BtPrinter.save(chosen);
                          if (context.mounted) Navigator.pop(context, chosen);
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _load, child: const Text('Refresh')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
