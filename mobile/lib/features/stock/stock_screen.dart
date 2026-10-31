import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/stock_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/user.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/stock_transfer.dart';
import 'stock_requests.dart';
import 'transfers_list.dart';

class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider).user;
    // The procurement unit buys for itself; branches ask it for stock.
    final isProcurement =
        user?.role == UserRole.storekeeper || (user?.store?.isMain ?? false);

    return DefaultTabController(
      length: isProcurement ? 2 : 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
              tabs: [
                const Tab(text: 'Balances'),
                const Tab(text: 'Incoming'),
                if (!isProcurement) const Tab(text: 'Requests'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _BalancesTab(),
                const _IncomingTransfersTab(),
                if (!isProcurement) const BranchRequestsTab(),
              ],
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
  String _query = '';
  bool _onlyReorder = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(stockRepositoryProvider).status();
  }

  void _reload() {
    setState(() => _future = ref.read(stockRepositoryProvider).status());
  }

  Future<void> _recordPurchase(StoreItemStatus item) async {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Buy stock — ${item.itemName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity bought'),
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
          .purchase(
            itemId: item.itemId,
            qty: qty,
            note: noteController.text.isEmpty ? null : noteController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Purchase recorded.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
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

  bool get _canCorrect {
    final role = ref.read(authSessionProvider).user?.role;
    return role == UserRole.admin || role == UserRole.storeManager;
  }

  Future<void> _itemActions(StoreItemStatus item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                item.itemName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text('Balance ${item.balance.toStringAsFixed(0)}'),
            ),
            ListTile(
              leading: const Icon(Icons.outbox_outlined),
              title: const Text('Log what was used (Stock Out)'),
              onTap: () => Navigator.pop(context, 'use'),
            ),
            if (item.isDrink)
              ListTile(
                leading: const Icon(Icons.add_shopping_cart),
                title: const Text('Record drinks bought'),
                onTap: () => Navigator.pop(context, 'buy'),
              ),
            if (_canCorrect)
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Correct the count'),
                subtitle: const Text(
                  'After a stock count, breakage or spoilage. Needs a reason.',
                ),
                onTap: () => Navigator.pop(context, 'correct'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'use':
        await _logConsumption(item);
      case 'buy':
        await _recordPurchase(item);
      case 'correct':
        await _correct(item);
    }
  }

  /// Stocktake: enter what is actually on the shelf; the difference is
  /// recorded as a correction with the reason, and shows in Changes.
  Future<void> _correct(StoreItemStatus item) async {
    final countController = TextEditingController();
    final reasonController = TextEditingController();
    String? error;

    final result = await showDialog<(double, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final counted = double.tryParse(countController.text);
          final diff = counted == null ? null : counted - item.balance;
          return AlertDialog(
            title: Text('Correct ${item.itemName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The app says ${item.balance.toStringAsFixed(0)}.'),
                TextField(
                  controller: countController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Actually on the shelf',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (diff != null && diff != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      diff > 0
                          ? '${diff.toStringAsFixed(diff % 1 == 0 ? 0 : 1)} more than recorded'
                          : '${(-diff).toStringAsFixed(diff % 1 == 0 ? 0 : 1)} fewer than recorded',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: diff > 0 ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ),
                TextField(
                  controller: reasonController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    helperText: 'e.g. 2 bottles broke, weekly count',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (diff == null || diff == 0) {
                    setDialogState(
                      () => error = 'Enter a count different from the app.',
                    );
                    return;
                  }
                  final reason = reasonController.text.trim();
                  if (reason.isEmpty) {
                    setDialogState(() => error = 'A reason is needed.');
                    return;
                  }
                  Navigator.pop(context, (diff, reason));
                },
                child: const Text('Save correction'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;

    try {
      await ref
          .read(stockRepositoryProvider)
          .correctStock(itemId: item.itemId, qty: result.$1, reason: result.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stock corrected.')));
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

        final query = _query.trim().toLowerCase();
        final shown = [
          for (final item in items)
            if ((query.isEmpty ||
                    item.itemName.toLowerCase().contains(query)) &&
                (!_onlyReorder || item.needsReorder))
              item,
        ];
        final reorderCount = items.where((i) => i.needsReorder).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search items',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: Text('Re-Order only ($reorderCount)'),
                  selected: _onlyReorder,
                  onSelected: (value) => setState(() => _onlyReorder = value),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: shown.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No items match.')),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final item = shown[index];
                          return Card(
                            child: ListTile(
                              title: Text(item.itemName),
                              subtitle: Text(
                                'Balance: ${item.balance.toStringAsFixed(0)} · re-order level ${item.safetyStock.toStringAsFixed(0)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.isDrink)
                                    IconButton(
                                      icon: const Icon(Icons.add_shopping_cart),
                                      tooltip: 'Buy stock',
                                      onPressed: () => _recordPurchase(item),
                                    ),
                                  Chip(
                                    label: Text(item.status),
                                    backgroundColor: item.needsReorder
                                        ? AppColors.danger
                                        : AppColors.gold,
                                    labelStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _itemActions(item),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
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
    _future = ref.read(stockRepositoryProvider).transfers();
  }

  void _reload() {
    setState(() => _future = ref.read(stockRepositoryProvider).transfers());
  }

  @override
  Widget build(BuildContext context) {
    final myStore = ref.watch(authSessionProvider).user?.storeId;
    return FutureBuilder<List<StockTransfer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final all = snapshot.data!;
        // Waiting to be counted here; everything else is history, each
        // with a receipt.
        final waiting = all
            .where((t) => t.status == 'dispatched' && t.toStoreId == myStore)
            .toList();
        final history = all.where((t) => !waiting.contains(t)).toList();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (waiting.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Nothing waiting to be received.')),
                ),
              for (final transfer in waiting)
                _TransferCard(transfer: transfer, onConfirmed: _reload),
              if (history.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    'Past transfers',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final transfer in history.take(30))
                  TransferTile(transfer: transfer),
              ],
            ],
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
                      width: 120,
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
