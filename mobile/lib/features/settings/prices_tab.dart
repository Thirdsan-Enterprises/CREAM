import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/items_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/models/item.dart';
import '../../shared/widgets/reason_dialog.dart';

/// Settings → Prices & menu. The plate and everything sold besides it, with
/// the price for all branches and any branch that charges its own (Town's
/// 15,000 plate). Every change asks for a reason, which goes in the change
/// log.
class PricesTab extends ConsumerStatefulWidget {
  const PricesTab({super.key});

  @override
  ConsumerState<PricesTab> createState() => _PricesTabState();
}

class _PricesTabState extends ConsumerState<PricesTab> {
  late Future<PriceList> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(itemsRepositoryProvider).priceList();
  }

  void _reload() =>
      setState(() => _future = ref.read(itemsRepositoryProvider).priceList());

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.success,
      ),
    );
  }

  /// Runs a save, reports the outcome and reloads the list.
  Future<void> _save(Future<void> Function() call, String done) async {
    try {
      await call();
      if (!mounted) return;
      _toast(done);
      _reload();
    } catch (e) {
      if (!mounted) return;
      _toast(
        e is ApiException ? e.message : 'Something went wrong.',
        error: true,
      );
    }
  }

  Future<void> _editPlatePrice(PricedThing plate, {BranchPrice? branch}) async {
    final result = await showModalBottomSheet<_PriceChange>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _PriceSheet(title: 'Plate price', thing: plate, branch: branch),
    );
    if (result == null) return;
    final repo = ref.read(itemsRepositoryProvider);
    await _save(
      () => repo.updatePlatePrice(
        price: result.price,
        storeId: result.storeId,
        useDefault: result.useDefault,
        reason: result.reason,
      ),
      'Plate price saved.',
    );
  }

  Future<void> _editItemPrice(MenuPriceRow row, {BranchPrice? branch}) async {
    final result = await showModalBottomSheet<_PriceChange>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _PriceSheet(title: row.item.name, thing: row, branch: branch),
    );
    if (result == null) return;
    final repo = ref.read(itemsRepositoryProvider);
    await _save(
      () => repo.updateMenuItem(
        row.item.id,
        price: result.price,
        storeId: result.storeId,
        useDefault: result.useDefault,
        reason: result.reason,
      ),
      '${row.item.name} price saved.',
    );
  }

  Future<void> _itemActions(MenuPriceRow row, List<String> categories) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                row.item.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text(row.category),
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Change price'),
              onTap: () => Navigator.pop(context, 'price'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename or move to another heading'),
              onTap: () => Navigator.pop(context, 'details'),
            ),
            ListTile(
              leading: Icon(
                row.tracksStock
                    ? Icons.inventory_2_outlined
                    : Icons.all_inclusive,
              ),
              title: Text(
                row.tracksStock
                    ? 'Stop counting stock (made to order)'
                    : 'Count stock for this item',
              ),
              subtitle: Text(
                row.tracksStock
                    ? 'Now: sales stop when the branch runs out.'
                    : 'Now: always available, like a cup of tea.',
              ),
              onTap: () => Navigator.pop(context, 'stock'),
            ),
            ListTile(
              leading: Icon(
                row.isActive
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              title: Text(
                row.isActive ? 'Hide from the Sell screen' : 'Sell it again',
              ),
              onTap: () => Navigator.pop(context, 'active'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final repo = ref.read(itemsRepositoryProvider);

    switch (action) {
      case 'price':
        await _editItemPrice(row);
      case 'details':
        final result = await showDialog<(String, String, String)>(
          context: context,
          builder: (_) => _DetailsDialog(row: row, categories: categories),
        );
        if (result == null) return;
        await _save(
          () => repo.updateMenuItem(
            row.item.id,
            name: result.$1,
            category: result.$2,
            reason: result.$3,
          ),
          'Saved.',
        );
      case 'stock':
        final reason = await askReason(
          context,
          row.tracksStock
              ? 'Stop counting stock for ${row.item.name}?'
              : 'Count stock for ${row.item.name}?',
        );
        if (reason == null) return;
        await _save(
          () => repo.updateMenuItem(
            row.item.id,
            tracksStock: !row.tracksStock,
            reason: reason,
          ),
          'Saved.',
        );
      case 'active':
        final reason = await askReason(
          context,
          row.isActive
              ? 'Hide ${row.item.name} from the Sell screen?'
              : 'Sell ${row.item.name} again?',
        );
        if (reason == null) return;
        await _save(
          () => repo.updateMenuItem(
            row.item.id,
            isActive: !row.isActive,
            reason: reason,
          ),
          'Saved.',
        );
    }
  }

  Future<void> _addToMenu(List<String> categories) async {
    final allItems = await ref.read(itemsRepositoryProvider).items();
    if (!mounted) return;
    final onMenu = (await _future).items.map((r) => r.item.id).toSet();
    if (!mounted) return;
    final stockItems = allItems
        .where((i) => i.isActive && !onMenu.contains(i.id))
        .toList();

    final request = await showDialog<_NewMenuItem>(
      context: context,
      builder: (_) =>
          _AddToMenuDialog(categories: categories, stockItems: stockItems),
    );
    if (request == null) return;
    final repo = ref.read(itemsRepositoryProvider);
    await _save(
      () => repo.addMenuItem(
        itemId: request.itemId,
        name: request.name,
        unit: request.unit,
        category: request.category,
        price: request.price,
        tracksStock: request.tracksStock,
      ),
      '${request.name ?? 'Item'} is on the menu.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PriceList>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load prices.'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data!;
        final groups = <String, List<MenuPriceRow>>{};
        for (final row in list.items) {
          groups.putIfAbsent(row.category, () => []).add(row);
        }
        final categories = {
          'Breakfast',
          'Drinks',
          'Snacks',
          ...groups.keys,
        }.toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                const _Heading('Plate'),
                _PriceCard(
                  title: 'Plate',
                  thing: list.plate,
                  onTapDefault: () => _editPlatePrice(list.plate),
                  onTapBranch: (b) => _editPlatePrice(list.plate, branch: b),
                ),
                const SizedBox(height: 24),
                const _Heading('Menu'),
                Text(
                  'Sold on their own or with a plate. Tap one to change it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      group.key,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final row in group.value)
                    _PriceCard(
                      title: row.item.name,
                      subtitle: [
                        if (!row.tracksStock) 'Made to order',
                        if (!row.isActive) 'Hidden from Sell',
                      ].join(' · '),
                      dimmed: !row.isActive,
                      thing: row,
                      onTapDefault: () => _itemActions(row, categories),
                      onTapBranch: (b) => _editItemPrice(row, branch: b),
                    ),
                ],
                if (list.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nothing on the menu yet besides the plate.'),
                  ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addToMenu(categories),
            icon: const Icon(Icons.add),
            label: const Text('Add to menu'),
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// The price for all branches, and a chip for each branch that charges its
/// own, so a different price at Town is visible at a glance.
class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.title,
    required this.thing,
    required this.onTapDefault,
    required this.onTapBranch,
    this.subtitle = '',
    this.dimmed = false,
  });

  final String title;
  final String subtitle;
  final bool dimmed;
  final PricedThing thing;
  final VoidCallback onTapDefault;
  final ValueChanged<BranchPrice> onTapBranch;

  @override
  Widget build(BuildContext context) {
    final own = thing.ownPrices;
    final price = thing.defaultPrice;
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTapDefault,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          price == null
                              ? 'No price'
                              : CurrencyFormatter.format(price),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          own.isEmpty ? 'every branch' : 'other branches',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                if (own.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final branch in own)
                        ActionChip(
                          avatar: const Icon(Icons.storefront, size: 16),
                          label: Text(
                            '${branch.storeName} ${CurrencyFormatter.format(branch.price ?? 0)}',
                          ),
                          onPressed: () => onTapBranch(branch),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceChange {
  _PriceChange({
    required this.storeId,
    required this.price,
    required this.useDefault,
    required this.reason,
  });

  final int? storeId;
  final double? price;
  final bool useDefault;
  final String reason;
}

/// Change a price for every branch or for one, or put a branch back on the
/// price for all branches. A reason is required.
class _PriceSheet extends StatefulWidget {
  const _PriceSheet({required this.title, required this.thing, this.branch});

  final String title;
  final PricedThing thing;
  final BranchPrice? branch;

  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  int? _storeId; // null = all branches
  bool _useDefault = false;
  final _price = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _storeId = widget.branch?.storeId;
    _fillPrice();
  }

  BranchPrice? get _branch => _storeId == null
      ? null
      : widget.thing.branches.where((b) => b.storeId == _storeId).firstOrNull;

  void _fillPrice() {
    final current = _storeId == null
        ? widget.thing.defaultPrice
        : _branch?.price;
    _price.text = current == null ? '' : current.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _price.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final price = double.tryParse(_price.text.replaceAll(',', ''));
    if (!_useDefault && (price == null || price <= 0)) {
      setState(() => _error = 'Enter the new price.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Say why the price is changing.');
      return;
    }
    Navigator.pop(
      context,
      _PriceChange(
        storeId: _storeId,
        price: _useDefault ? null : price,
        useDefault: _useDefault,
        reason: _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branch = _branch;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _storeId,
              decoration: const InputDecoration(labelText: 'Price for'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All branches'),
                ),
                for (final b in widget.thing.branches)
                  DropdownMenuItem<int?>(
                    value: b.storeId,
                    child: Text(
                      b.own ? '${b.storeName} (own price)' : b.storeName,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _storeId = value;
                _useDefault = false;
                _fillPrice();
              }),
            ),
            if (_storeId == null && widget.thing.ownPrices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Branches with their own price keep it: '
                  '${widget.thing.ownPrices.map((b) => b.storeName).join(', ')}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (branch != null && branch.own)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _useDefault,
                title: Text('Charge the same as all branches'),
                subtitle: Text(
                  widget.thing.defaultPrice == null
                      ? 'Removes ${branch.storeName}\'s own price.'
                      : '${CurrencyFormatter.format(widget.thing.defaultPrice!)} at ${branch.storeName}.',
                ),
                onChanged: (v) => setState(() => _useDefault = v),
              ),
            if (!_useDefault) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: 'UGX ',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason for the change',
                helperText: 'Kept in the change log with your name.',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('Save price')),
          ],
        ),
      ),
    );
  }
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.row, required this.categories});

  final MenuPriceRow row;
  final List<String> categories;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.row.item.name);
  late String _category = widget.row.category;
  final _reason = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.row.item.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Heading'),
            items: [
              for (final c in {...widget.categories, _category})
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
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
            if (_name.text.trim().isEmpty || _reason.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(context, (
              _name.text.trim(),
              _category,
              _reason.text.trim(),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NewMenuItem {
  _NewMenuItem({
    this.itemId,
    this.name,
    this.unit,
    required this.category,
    required this.price,
    required this.tracksStock,
  });

  final int? itemId;
  final String? name;
  final String? unit;
  final String category;
  final double price;
  final bool tracksStock;
}

class _AddToMenuDialog extends StatefulWidget {
  const _AddToMenuDialog({required this.categories, required this.stockItems});

  final List<String> categories;
  final List<Item> stockItems;

  @override
  State<_AddToMenuDialog> createState() => _AddToMenuDialogState();
}

class _AddToMenuDialogState extends State<_AddToMenuDialog> {
  Item? _fromStock;
  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'piece');
  final _price = TextEditingController();
  String _category = 'Breakfast';
  bool _tracksStock = true;
  String? _error;

  void _submit() {
    final price = double.tryParse(_price.text);
    if (_fromStock == null && _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter the price.');
      return;
    }
    Navigator.pop(
      context,
      _NewMenuItem(
        itemId: _fromStock?.id,
        name: _fromStock == null ? _name.text.trim() : _fromStock!.name,
        unit: _fromStock == null ? _unit.text.trim() : null,
        category: _category,
        price: price,
        tracksStock: _tracksStock,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to menu'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.stockItems.isNotEmpty)
              DropdownButtonFormField<Item?>(
                initialValue: _fromStock,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Already in stock? (optional)',
                  helperText: 'e.g. eggs bought for the kitchen',
                ),
                items: [
                  const DropdownMenuItem<Item?>(
                    value: null,
                    child: Text('No, a new item'),
                  ),
                  for (final item in widget.stockItems)
                    DropdownMenuItem<Item?>(
                      value: item,
                      child: Text('${item.name} (${item.unit})'),
                    ),
                ],
                onChanged: (v) => setState(() => _fromStock = v),
              ),
            if (_fromStock == null) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unit (piece, cup, bottle...)',
                ),
              ),
            ],
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Heading'),
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Price at every branch',
                prefixText: 'UGX ',
                helperText: 'Give a branch its own price afterwards.',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _tracksStock,
              title: const Text('Count stock'),
              subtitle: Text(
                _tracksStock
                    ? 'Sales stop when the branch runs out (eggs, sodas).'
                    : 'Always available: made to order (tea, chapati).',
              ),
              onChanged: (v) => setState(() => _tracksStock = v),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
