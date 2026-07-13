import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/stock_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/stock_transfer.dart';

class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(
              tabs: [
                Tab(text: 'Balances'),
                Tab(text: 'Incoming Transfers'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_BalancesTab(), _IncomingTransfersTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancesTab extends ConsumerStatefulWidget {
  const _BalancesTab();

  @override
  ConsumerState<_BalancesTab> createState() => _BalancesTabState();
}

class _BalancesTabState extends ConsumerState<_BalancesTab> {
  late Future<List<StoreItemStatus>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(stockRepositoryProvider).status();
  }

  void _reload() {
    setState(() => _future = ref.read(stockRepositoryProvider).status());
  }

  Future<void> _logConsumption(StoreItemStatus item) async {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log consumption — ${item.itemName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity used'),
              autofocus: true,
            ),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) return;

    try {
      await ref
          .read(stockRepositoryProvider)
          .recordConsumption(
            itemId: item.itemId,
            qty: qty,
            note: noteController.text.isEmpty ? null : noteController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Consumption logged.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoreItemStatus>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text('No items configured for this store yet.'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  title: Text(item.itemName),
                  subtitle: Text(
                    'Balance: ${item.balance.toStringAsFixed(0)} (safety: ${item.safetyStock.toStringAsFixed(0)})',
                  ),
                  trailing: Chip(
                    label: Text(item.status),
                    backgroundColor: item.needsReorder
                        ? AppColors.danger
                        : AppColors.gold,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _logConsumption(item),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _IncomingTransfersTab extends ConsumerStatefulWidget {
  const _IncomingTransfersTab();

  @override
  ConsumerState<_IncomingTransfersTab> createState() =>
      _IncomingTransfersTabState();
}

class _IncomingTransfersTabState extends ConsumerState<_IncomingTransfersTab> {
  late Future<List<StockTransfer>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(stockRepositoryProvider).incomingTransfers();
  }

  void _reload() {
    setState(
      () => _future = ref.read(stockRepositoryProvider).incomingTransfers(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StockTransfer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final transfers = snapshot.data!;
        if (transfers.isEmpty) {
          return const Center(child: Text('No incoming transfers to confirm.'));
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: transfers.length,
            itemBuilder: (context, index) =>
                _TransferCard(transfer: transfers[index], onConfirmed: _reload),
          ),
        );
      },
    );
  }
}

class _TransferCard extends ConsumerStatefulWidget {
  const _TransferCard({required this.transfer, required this.onConfirmed});

  final StockTransfer transfer;
  final VoidCallback onConfirmed;

  @override
  ConsumerState<_TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends ConsumerState<_TransferCard> {
  late final Map<int, TextEditingController> _controllers = {
    for (final item in widget.transfer.items)
      item.id: TextEditingController(
        text: item.qtyDispatched.toStringAsFixed(0),
      ),
  };
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    try {
      final items = widget.transfer.items.map((item) {
        final qty =
            double.tryParse(_controllers[item.id]!.text) ?? item.qtyDispatched;
        return {'stock_transfer_item_id': item.id, 'qty_received': qty};
      }).toList();

      await ref
          .read(stockRepositoryProvider)
          .confirmTransfer(transferId: widget.transfer.id, items: items);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transfer confirmed.')));
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From ${widget.transfer.fromStoreName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final item in widget.transfer.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.itemName} (dispatched ${item.qtyDispatched.toStringAsFixed(0)})',
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _controllers[item.id],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Received',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _confirm,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm receipt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
