import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/items_repository.dart';
import '../../core/api/repositories/stock_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/store.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/models/item.dart';
import '../sales/todays_plates.dart';
import 'kitchen_items.dart';
import 'purchases_ledger.dart';
import 'stock_requests.dart';
import 'transfers_list.dart';

/// What the item picker gave back: an item, or a request to add a new one
/// (with what was typed and the heading being looked at).
class _Pick {
  const _Pick.item(Item this.item) : newName = null, newCategory = null;
  const _Pick.addNew(this.newName, this.newCategory) : item = null;

  final Item? item;
  final String? newName;
  final String? newCategory;
}

String _headingOf(Item item) =>
    item.category ?? (item.isDrink ? 'Drinks' : 'Other');

/// Search-as-you-type item chooser, grouped under procurement's headings
/// (Food, Spices, Packaging...) with a chip per heading, so "Rice" is two
/// taps away and new items land under the right heading.
Future<_Pick?> _chooseItem(
  BuildContext context,
  List<Item> items, {
  bool allowNew = true,
  String Function(Item)? describe,
}) {
  return showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _ItemPickerSheet(items: items, allowNew: allowNew, describe: describe),
  );
}

class _ItemPickerSheet extends StatefulWidget {
  const _ItemPickerSheet({
    required this.items,
    this.allowNew = true,
    this.describe,
  });

  final List<Item> items;
  final bool allowNew;
  final String Function(Item)? describe;

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _query = '';
  String? _heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final counts = <String, int>{};
    for (final item in widget.items) {
      counts.update(_headingOf(item), (n) => n + 1, ifAbsent: () => 1);
    }
    final headings = [
      for (final c in kitchenCategories)
        if (counts.containsKey(c)) c,
      ...counts.keys.where((c) => !kitchenCategories.contains(c)),
    ];

    final groups = <String, List<Item>>{};
    for (final item in widget.items) {
      final heading = _headingOf(item);
      if (_heading != null && heading != _heading) continue;
      if (query.isNotEmpty && !item.name.toLowerCase().contains(query)) {
        continue;
      }
      groups.putIfAbsent(heading, () => []).add(item);
    }
    for (final list in groups.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final rows = <Object>[
      for (final h in headings)
        if (groups.containsKey(h)) ...[h, ...groups[h]!],
    ];
    final typed = _query.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search items',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final h in [null, ...headings])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(
                          h == null
                              ? 'All (${widget.items.length})'
                              : '$h (${counts[h]})',
                        ),
                        selected: _heading == h,
                        onSelected: (_) => setState(() => _heading = h),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.allowNew)
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(
                  typed.isEmpty
                      ? 'Add a new item'
                      : 'Add "$typed" as a new item',
                ),
                subtitle: _heading == null ? null : Text('Under $_heading'),
                onTap: () => Navigator.of(
                  context,
                ).pop(_Pick.addNew(typed.isEmpty ? null : typed, _heading)),
              ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No item with that name.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is String) {
                          return Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                            child: Text(
                              '$row (${groups[row]!.length})',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }
                        final item = row as Item;
                        return ListTile(
                          dense: true,
                          title: Text(item.name),
                          subtitle: Text(
                            widget.describe?.call(item) ??
                                (item.isDrink
                                    ? 'Drink · ${item.unit}'
                                    : item.unit),
                          ),
                          onTap: () =>
                              Navigator.of(context).pop(_Pick.item(item)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a stock movement is called on screen. The codes are for the server.
String _movementLabel(String type) => switch (type) {
  'purchase' => 'Bought',
  'transfer_out' => 'Sent to a branch',
  'transfer_in' => 'Received from procurement',
  'consumption' => 'Used / sold',
  'adjustment' => 'Corrected',
  _ => type,
};

class StockingScreen extends StatelessWidget {
  const StockingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 9,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: "Today's plates"),
                Tab(text: 'Requests'),
                Tab(text: 'Purchase'),
                Tab(text: 'Purchases ledger'),
                Tab(text: 'Send to branch'),
                Tab(text: 'Transfers'),
                Tab(text: 'Branch stock'),
                Tab(text: 'Items'),
                Tab(text: 'History'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _PlatesTab(),
                ProcurementRequestsTab(),
                _PurchaseTab(),
                PurchasesLedgerTab(),
                _TransferTab(),
                TransfersListTab(),
                BranchStockTab(),
                KitchenItemsTab(),
                _HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Each morning procurement (or the owner) sets how many lunch plates each
/// branch has today; branches sell them down from there.
class _PlatesTab extends ConsumerStatefulWidget {
  const _PlatesTab();

  @override
  ConsumerState<_PlatesTab> createState() => _PlatesTabState();
}

class _PlatesTabState extends ConsumerState<_PlatesTab> {
  List<Store>? _stores;
  Store? _store;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stores = (await ref.read(storesRepositoryProvider).all())
          .where((s) => s.isActive)
          .toList();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _store =
            stores.where((s) => !s.isMain).firstOrNull ?? stores.firstOrNull;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException ? e.message : 'Could not load.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final stores = _stores;
    if (stores == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final store in stores)
                ChoiceChip(
                  label: Text(store.name),
                  selected: store.id == _store?.id,
                  onSelected: (_) => setState(() => _store = store),
                ),
            ],
          ),
        ),
        if (_store != null)
          Expanded(
            child: TodaysPlatesPanel(
              key: ValueKey(_store!.id),
              storeId: _store!.id,
              inSheet: false,
            ),
          ),
      ],
    );
  }
}

class _PurchaseTab extends ConsumerStatefulWidget {
  const _PurchaseTab();

  @override
  ConsumerState<_PurchaseTab> createState() => _PurchaseTabState();
}

class _PurchaseTabState extends ConsumerState<_PurchaseTab> {
  late Future<void> _future;
  List<Item> _items = [];
  Store? _mainStore;
  List<Store> _stores = [];
  Store? _drinkStore;
  Item? _selectedItem;
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  final _paidController = TextEditingController();
  final _supplierController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final items = await ref
        .read(itemsRepositoryProvider)
        .items(withDrinks: true);
    final stores = await ref.read(storesRepositoryProvider).all();
    final main = stores.firstWhere((s) => s.isMain);
    if (!mounted) return;
    setState(() {
      _items = items;
      _mainStore = main;
      final user = ref.read(authSessionProvider).user;
      final active = stores.where((s) => s.isActive).toList();
      // The owner can buy drinks for any branch; everyone else only for
      // their own (the server enforces this too).
      _stores = (user?.isAdmin ?? true)
          ? active
          : active.where((s) => s.id == user?.storeId).toList();
      _drinkStore = _stores.contains(main) || _stores.isEmpty
          ? main
          : _stores.first;
    });
  }

  Future<void> _addNewItem({String? name, String? category}) async {
    final created = await addKitchenItem(
      context,
      ref,
      categories: {
        ...kitchenCategories,
        for (final i in _items) _headingOf(i),
      }.toList(),
      name: name,
      category: category,
    );
    if (created == null) return;
    setState(() {
      _items = [..._items, created];
      _selectedItem = created;
    });
  }

  /// Food is bought at the main store only; drinks are bought at whichever
  /// branch is stocking them.
  Store _storeFor(Item item, Store mainStore) =>
      item.isDrink ? (_drinkStore ?? mainStore) : mainStore;

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit(Store mainStore) async {
    final item = _selectedItem;
    if (item == null) {
      _say('Choose the item you bought first.');
      return;
    }
    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      _say('Enter how much you bought, for example 25.');
      return;
    }

    final store = _storeFor(item, mainStore);
    setState(() => _submitting = true);
    try {
      await ref
          .read(stockRepositoryProvider)
          .purchase(
            itemId: item.id,
            storeId: store.id,
            qty: qty,
            note: _noteController.text.isEmpty ? null : _noteController.text,
            totalCost: double.tryParse(_paidController.text.trim()),
            supplier: _supplierController.text.trim(),
          );

      // Read the balance back so the person sees the stock really went in.
      var message =
          'Recorded: $qty ${item.unit} of ${item.name} at ${store.name}.';
      try {
        final rows = await ref
            .read(stockRepositoryProvider)
            .status(storeId: store.id);
        final row = rows.where((r) => r.itemId == item.id).firstOrNull;
        if (row != null) {
          message =
              '${item.name} at ${store.name}: ${row.balance.toStringAsFixed(0)} ${item.unit} in stock (${row.status}).';
        }
      } catch (_) {
        // The purchase itself succeeded; the read-back is a courtesy.
      }
      if (!mounted) return;
      _say(message);
      setState(() {
        _qtyController.clear();
        _noteController.clear();
        _paidController.clear();
        _selectedItem = null;
      });
    } catch (e) {
      if (!mounted) return;
      _say(e is ApiException ? e.message : 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// "UGX 4,200 per kg", once the quantity and amount are typed.
  String? _unitCostHint() {
    final qty = double.tryParse(_qtyController.text.trim());
    final paid = double.tryParse(_paidController.text.trim());
    if (qty == null || qty <= 0 || paid == null) {
      return 'Goes in the purchases ledger.';
    }
    return '${CurrencyFormatter.format(paid / qty)} per ${_selectedItem?.unit ?? 'unit'}';
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    _paidController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            _mainStore == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final mainStore = _mainStore!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock In', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final pick = await _chooseItem(context, _items);
                  if (pick == null) return;
                  final item = pick.item;
                  if (item == null) {
                    _addNewItem(name: pick.newName, category: pick.newCategory);
                    return;
                  }
                  setState(() => _selectedItem = item);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    suffixIcon: Icon(Icons.search),
                  ),
                  child: Text(_selectedItem?.name ?? 'Tap to choose an item'),
                ),
              ),
              const SizedBox(height: 12),
              if (_selectedItem?.isDrink ?? false)
                DropdownButtonFormField<Store>(
                  initialValue: _drinkStore,
                  decoration: const InputDecoration(
                    labelText: 'Bought for which branch',
                  ),
                  items: [
                    for (final store in _stores)
                      DropdownMenuItem(value: store, child: Text(store.name)),
                  ],
                  onChanged: (value) => setState(() => _drinkStore = value),
                )
              else
                Text(
                  'Food is bought for ${mainStore.name}, then transferred to the branches.',
                  style: Theme.of(context).textTheme.bodySmall,
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
                controller: _paidController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Amount paid in total',
                  prefixText: 'UGX ',
                  helperText: _unitCostHint(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supplierController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Bought from (supplier, market)',
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
  late Future<void> _future;
  // Only items the procurement unit actually has on hand — you can't dispatch what isn't
  // there. New items get their first stock via the Purchase tab, not here.
  List<Item> _items = [];
  Map<int, double> _balances = {};
  List<Store> _outlets = [];
  String _mainName = 'procurement';
  Store? _toStore;
  final List<_TransferLine> _lines = [_TransferLine()];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final allItems = await ref.read(itemsRepositoryProvider).items();
    final stores = await ref.read(storesRepositoryProvider).all();
    final kira = stores.firstWhere((s) => s.isMain);
    final statuses = await ref
        .read(stockRepositoryProvider)
        .status(storeId: kira.id);

    final balances = {
      for (final s in statuses)
        if (s.balance > 0) s.itemId: s.balance,
    };
    final inStock = allItems.where((i) => balances.containsKey(i.id)).toList();

    if (!mounted) return;
    setState(() {
      _items = inStock;
      _balances = balances;
      _outlets = stores.where((s) => !s.isMain && s.isActive).toList();
      _mainName = kira.name;
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent to ${_toStore!.name}. They confirm it when it arrives.',
          ),
        ),
      );
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
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send from $_mainName',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Store>(
                initialValue: _toStore,
                decoration: const InputDecoration(labelText: 'To branch'),
                items: [
                  for (final store in _outlets)
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
                        child: _items.isEmpty
                            ? Text('$_mainName has no stock yet.')
                            : InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  final pick = await _chooseItem(
                                    context,
                                    _items,
                                    allowNew: false,
                                    describe: (item) =>
                                        '${_balances[item.id]?.toStringAsFixed(0)} ${item.unit} available',
                                  );
                                  final item = pick?.item;
                                  if (item != null) {
                                    setState(() => line.item = item);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Item',
                                    suffixIcon: const Icon(Icons.search),
                                    helperText: line.item == null
                                        ? null
                                        : '${_balances[line.item!.id]?.toStringAsFixed(0)} ${line.item!.unit} available',
                                  ),
                                  child: Text(
                                    line.item?.name ?? 'Tap to choose',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
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
                    : const Text('Send'),
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

  void _reload() => setState(() {
    _future = ref.read(stockRepositoryProvider).movements();
  });

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
                      title: Text('${m.itemName} — ${_movementLabel(m.type)}'),
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
