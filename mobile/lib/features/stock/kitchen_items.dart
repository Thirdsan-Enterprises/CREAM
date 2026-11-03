import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/items_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/store.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/item.dart';
import '../../shared/widgets/reason_dialog.dart';

/// Headings procurement's list is kept under. Any other heading typed in is
/// kept too.
const kitchenCategories = [
  'Food',
  'Spices & seasoning',
  'Packaging & disposables',
  'Cleaning',
  'Fuel',
  'Drinks',
  'Other',
];

/// What procurement buys and sends to the branches, kept apart from the
/// menu. The owner and procurement add, rename, regroup and remove items
/// here; an item with history is hidden rather than deleted, and can be
/// added back.
class KitchenItemsTab extends ConsumerStatefulWidget {
  const KitchenItemsTab({super.key});

  @override
  ConsumerState<KitchenItemsTab> createState() => _KitchenItemsTabState();
}

class _KitchenItemsTabState extends ConsumerState<KitchenItemsTab> {
  late Future<List<Item>> _future;
  bool _showRemoved = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Item>> _load() =>
      ref.read(itemsRepositoryProvider).items(includeRemoved: _showRemoved);

  void _reload() => setState(() {
    _future = _load();
  });

  void _toast(Object messageOrError) {
    final message = messageOrError is String
        ? messageOrError
        : messageOrError is ApiException
        ? messageOrError.message
        : 'Something went wrong.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add(List<String> categories) async {
    final result = await showDialog<_ItemForm>(
      context: context,
      builder: (_) => _ItemDialog(categories: categories),
    );
    if (result == null) return;
    try {
      await ref
          .read(itemsRepositoryProvider)
          .createItem(
            name: result.name,
            unit: result.unit,
            category: result.category,
            safetyStock: result.reorderLevel,
          );
      if (!mounted) return;
      _toast('${result.name} added.');
      _reload();
    } catch (e) {
      if (mounted) _toast(e);
    }
  }

  Future<void> _open(Item item, List<String> categories) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                item.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text(
                '${item.category ?? 'Other'} · ${item.unit}'
                '${item.isActive ? '' : ' · removed'}',
              ),
            ),
            if (item.isActive) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename or change heading / unit'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.low_priority),
                title: const Text('Re-order level at a branch'),
                subtitle: const Text('Shows "Re-Order" at or below it.'),
                onTap: () => Navigator.pop(context, 'level'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.danger,
                ),
                title: const Text('Remove from the list'),
                subtitle: const Text(
                  'Its history is kept if it was ever bought or sent.',
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Add back to the list'),
                onTap: () => Navigator.pop(context, 'restore'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final repo = ref.read(itemsRepositoryProvider);

    try {
      switch (action) {
        case 'edit':
          final result = await showDialog<_ItemForm>(
            context: context,
            builder: (_) => _ItemDialog(categories: categories, item: item),
          );
          if (result == null) return;
          await repo.updateItem(
            item.id,
            name: result.name,
            unit: result.unit,
            category: result.category,
          );
          if (mounted) _toast('Saved.');
        case 'level':
          await _setLevel(item);
        case 'remove':
          final reason = await askReason(
            context,
            'Remove ${item.name}?',
            message: 'It leaves the stock lists and the purchase pickers.',
            confirmLabel: 'Remove',
            destructive: true,
          );
          if (reason == null) return;
          final message = await repo.removeItem(item.id, reason: reason);
          if (mounted) _toast(message);
        case 'restore':
          await repo.updateItem(
            item.id,
            isActive: true,
            reason: 'Added back to the list',
          );
          if (mounted) _toast('${item.name} is back on the list.');
      }
      _reload();
    } catch (e) {
      if (mounted) _toast(e);
    }
  }

  Future<void> _setLevel(Item item) async {
    final stores = await ref.read(storesRepositoryProvider).all();
    if (!mounted) return;
    Store? store = stores.where((s) => s.isActive).firstOrNull;
    final level = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Re-order level: ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Store>(
                initialValue: store,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  for (final s in stores.where((s) => s.isActive))
                    DropdownMenuItem(value: s, child: Text(s.name)),
                ],
                onChanged: (v) => setDialogState(() => store = v),
              ),
              TextField(
                controller: level,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Re-order level',
                  suffixText: item.unit,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(level.text);
    if (ok != true || store == null || value == null) return;
    await ref
        .read(itemsRepositoryProvider)
        .setStoreSettings(
          itemId: item.id,
          storeId: store!.id,
          safetyStock: value,
        );
    if (mounted) _toast('Re-order level saved for ${store!.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Item>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(onPressed: _reload, child: const Text('Retry')),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final query = _query.trim().toLowerCase();
        final items = snapshot.data!
            .where((i) => query.isEmpty || i.name.toLowerCase().contains(query))
            .toList();
        final groups = <String, List<Item>>{};
        for (final item in items) {
          groups
              .putIfAbsent(
                item.category ?? (item.isDrink ? 'Drinks' : 'Other'),
                () => [],
              )
              .add(item);
        }
        final ordered = [
          for (final c in kitchenCategories)
            if (groups.containsKey(c)) c,
          ...groups.keys.where((c) => !kitchenCategories.contains(c)),
        ];
        final categories = {...kitchenCategories, ...groups.keys}.toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search kitchen stock',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Show removed items'),
                value: _showRemoved,
                onChanged: (v) {
                  _showRemoved = v;
                  _reload();
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    children: [
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No items.')),
                        ),
                      for (final category in ordered) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                          child: Text(
                            '$category (${groups[category]!.length})',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Card(
                          child: Column(
                            children: [
                              for (final item in groups[category]!)
                                ListTile(
                                  title: Text(
                                    item.name,
                                    style: item.isActive
                                        ? null
                                        : const TextStyle(
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                  ),
                                  subtitle: Text(
                                    item.isActive
                                        ? item.unit
                                        : '${item.unit} · removed',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _open(item, categories),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(categories),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        );
      },
    );
  }
}

class _ItemForm {
  _ItemForm(this.name, this.unit, this.category, this.reorderLevel);

  final String name;
  final String unit;
  final String category;
  final double? reorderLevel;
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.categories, this.item});

  final List<String> categories;
  final Item? item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? 'kg');
  final _level = TextEditingController();
  late String _category = widget.item?.category ?? 'Food';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return AlertDialog(
      title: Text(editing ? 'Edit ${widget.item!.name}' : 'Add kitchen item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Heading'),
              items: [
                for (final c in {...widget.categories, _category})
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Unit (kg, litre, packet, piece...)',
              ),
            ),
            if (!editing)
              TextField(
                controller: _level,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Re-order level (optional)',
                  helperText: 'The same at every branch; change one later.',
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty || _unit.text.trim().isEmpty) {
              setState(() => _error = 'Enter the name and unit.');
              return;
            }
            Navigator.pop(
              context,
              _ItemForm(
                _name.text.trim(),
                _unit.text.trim(),
                _category,
                double.tryParse(_level.text),
              ),
            );
          },
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
