import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/items_repository.dart';
import '../../core/api/repositories/stock_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/store.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/models/item.dart';

class StockingScreen extends StatelessWidget {
  const StockingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(
              tabs: [
                Tab(text: 'Purchase'),
                Tab(text: 'Transfer'),
                Tab(text: 'History'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_PurchaseTab(), _TransferTab(), _HistoryTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseTab extends ConsumerStatefulWidget {
  const _PurchaseTab();

  @override
  ConsumerState<_PurchaseTab> createState() => _PurchaseTabState();
}

class _PurchaseTabState extends ConsumerState<_PurchaseTab> {
  late Future<(List<Item>, Store)> _future;
  Item? _selectedItem;
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Item>, Store)> _load() async {
    final items = await ref.read(itemsRepositoryProvider).items();
    final stores = await ref.read(storesRepositoryProvider).all();
    final main = stores.firstWhere((s) => s.isMain);
    return (items, main);
  }

  Future<void> _submit(Store mainStore) async {
    if (_selectedItem == null) return;
    final qty = double.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(stockRepositoryProvider)
          .purchase(
            itemId: _selectedItem!.id,
            storeId: mainStore.id,
            qty: qty,
            note: _noteController.text.isEmpty ? null : _noteController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Purchase recorded.')));
      setState(() {
        _qtyController.clear();
        _noteController.clear();
        _selectedItem = null;
      });
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
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Item>, Store)>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final (items, mainStore) = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock In at ${mainStore.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Item>(
                initialValue: _selectedItem,
                decoration: const InputDecoration(labelText: 'Item'),
                items: [
                  for (final item in items)
                    DropdownMenuItem(value: item, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() => _selectedItem = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity purchased',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(mainStore),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record purchase'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TransferLine {
  Item? item;
  final TextEditingController qty = TextEditingController();
}

class _TransferTab extends ConsumerStatefulWidget {
  const _TransferTab();

  @override
  ConsumerState<_TransferTab> createState() => _TransferTabState();
}

class _TransferTabState extends ConsumerState<_TransferTab> {
  late Future<(List<Item>, List<Store>)> _future;
  Store? _toStore;
  final List<_TransferLine> _lines = [_TransferLine()];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Item>, List<Store>)> _load() async {
    final items = await ref.read(itemsRepositoryProvider).items();
    final stores = await ref.read(storesRepositoryProvider).all();
    return (items, stores.where((s) => !s.isMain).toList());
  }

  Future<void> _submit() async {
    if (_toStore == null) return;
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final qty = double.tryParse(line.qty.text);
      if (line.item != null && qty != null && qty > 0) {
        items.add({'item_id': line.item!.id, 'qty': qty});
      }
    }
    if (items.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(stockRepositoryProvider)
          .dispatchTransfer(toStoreId: _toStore!.id, items: items);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transfer dispatched.')));
      setState(() {
        _lines
          ..clear()
          ..add(_TransferLine());
      });
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
    return FutureBuilder<(List<Item>, List<Store>)>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final (items, outlets) = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dispatch from Kira',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Store>(
                initialValue: _toStore,
                decoration: const InputDecoration(labelText: 'To store'),
                items: [
                  for (final store in outlets)
                    DropdownMenuItem(value: store, child: Text(store.name)),
                ],
                onChanged: (value) => setState(() => _toStore = value),
              ),
              const SizedBox(height: 16),
              for (final line in _lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<Item>(
                          initialValue: line.item,
                          decoration: const InputDecoration(labelText: 'Item'),
                          items: [
                            for (final item in items)
                              DropdownMenuItem(
                                value: item,
                                child: Text(item.name),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => line.item = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: line.qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Qty'),
                        ),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _lines.add(_TransferLine())),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Dispatch transfer'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  late Future<List<StockMovementRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(stockRepositoryProvider).movements();
  }

  void _reload() =>
      setState(() => _future = ref.read(stockRepositoryProvider).movements());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StockMovementRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final movements = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: movements.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No movements yet.'),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: movements.length,
                  itemBuilder: (context, index) {
                    final m = movements[index];
                    return ListTile(
                      title: Text('${m.itemName} — ${m.type}'),
                      subtitle: Text(
                        '${m.storeName} — ${DateFormatter.dateTime(m.occurredAt)}',
                      ),
                      trailing: Text(
                        m.qty > 0
                            ? '+${m.qty.toStringAsFixed(0)}'
                            : m.qty.toStringAsFixed(0),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
