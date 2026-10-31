import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/customers_repository.dart';
import '../../core/api/repositories/items_repository.dart';
import '../../core/api/repositories/sales_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/item.dart';
import '../../shared/models/sale.dart';

class _MenuLine {
  _MenuLine(this.entry, this.qty);
  final MenuEntry entry;
  int qty;
}

/// Shows what a customer can spend right now, and flags in-line if the
/// current cart would exceed it — so a cashier finds out before tapping
/// "Complete sale," not after it gets rejected.
class _CustomerAvailabilityNotice extends StatelessWidget {
  const _CustomerAvailabilityNotice({
    required this.available,
    required this.total,
  });

  final double? available;
  final double total;

  @override
  Widget build(BuildContext context) {
    if (available == null) {
      return const Text('Could not load balance — will be checked on submit.');
    }

    final exceeds = total > available!;
    return Row(
      children: [
        Icon(
          exceeds ? Icons.error_outline : Icons.check_circle_outline,
          size: 18,
          color: exceeds ? AppColors.danger : AppColors.success,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            exceeds
                ? 'Only ${CurrencyFormatter.format(available!)} available — over by ${CurrencyFormatter.format(total - available!)}.'
                : 'Available: ${CurrencyFormatter.format(available!)}',
            style: TextStyle(
              color: exceeds ? AppColors.danger : null,
              fontWeight: exceeds ? FontWeight.bold : null,
            ),
          ),
        ),
      ],
    );
  }
}

const _paymentMethods = ['cash', 'momo', 'airtel', 'account', 'lpo'];
const _paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
  // A one-off sale covered by a purchase order, no running balance —
  // distinct from an "Account" sale charged to an LPO-funded customer,
  // which is for a pool drawn down over many meals (see Accounts/Customers).
  'lpo': 'LPO',
};

class SellScreen extends ConsumerStatefulWidget {
  /// [storeId] is only for the owner, who sells on behalf of a branch.
  /// Staff always sell for their own branch, so they leave it null.
  const SellScreen({super.key, this.storeId});

  final int? storeId;

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  bool _loading = true;
  String? _loadError;
  double _platePrice = 0;
  List<MenuEntry> _menu = [];

  // A sale starts empty: a plate is one tap, and an egg or a cup of tea on
  // its own is never charged a plate by mistake.
  int _plateQty = 0;
  final List<_MenuLine> _lines = [];
  String _paymentMethod = 'cash';
  Customer? _selectedCustomer;
  double? _selectedCustomerBalance;
  bool _loadingCustomerBalance = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final repo = ref.read(itemsRepositoryProvider);
      final results = await Future.wait([
        repo.platePrice(storeId: widget.storeId),
        repo.menu(storeId: widget.storeId),
      ]);
      setState(() {
        _platePrice = results[0] as double;
        _menu = results[1] as List<MenuEntry>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  /// Re-reads the menu quietly (no spinner) so the "left" counts are
  /// current after a sale.
  Future<void> _refreshMenu() async {
    try {
      final menu = await ref
          .read(itemsRepositoryProvider)
          .menu(storeId: widget.storeId);
      if (mounted) setState(() => _menu = menu);
    } catch (_) {
      // Keep showing the previous counts; the server still enforces stock.
    }
  }

  double get _total {
    var total = _plateQty * _platePrice;
    for (final line in _lines) {
      total += line.qty * (line.entry.price ?? 0);
    }
    return total;
  }

  /// "2 plates · 1 Soda · 2 Egg", shown above the total.
  String get _cartSummary {
    final parts = <String>[
      if (_plateQty > 0) '$_plateQty ${_plateQty == 1 ? 'plate' : 'plates'}',
      for (final line in _lines) '${line.qty} ${line.entry.item.name}',
    ];
    return parts.isEmpty ? 'Nothing added yet' : parts.join(' · ');
  }

  /// Menu entries grouped under their headings, in the server's order.
  Map<String, List<MenuEntry>> get _menuByCategory {
    final groups = <String, List<MenuEntry>>{};
    for (final entry in _menu) {
      groups.putIfAbsent(entry.category, () => []).add(entry);
    }
    return groups;
  }

  _MenuLine? _lineFor(MenuEntry entry) =>
      _lines.where((l) => l.entry.item.id == entry.item.id).firstOrNull;

  void _increment(MenuEntry entry) {
    final inCart = _lineFor(entry)?.qty ?? 0;
    final stock = entry.tracksStock ? entry.balance : null;
    if (stock != null && inCart + 1 > stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            stock <= 0
                ? '${entry.item.name} is out of stock. Record the purchase first.'
                : 'Only ${stock.toStringAsFixed(0)} ${entry.item.name} in stock.',
          ),
        ),
      );
      return;
    }
    setState(() {
      final existing = _lineFor(entry);
      if (existing != null) {
        existing.qty++;
      } else {
        _lines.add(_MenuLine(entry, 1));
      }
    });
  }

  void _decrement(MenuEntry entry) {
    setState(() {
      final existing = _lineFor(entry);
      if (existing == null) return;
      if (existing.qty > 1) {
        existing.qty--;
      } else {
        _lines.remove(existing);
      }
    });
  }

  Future<void> _pickCustomer() async {
    final customer = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _CustomerSearchSheet(),
    );
    if (customer == null) return;

    setState(() {
      _selectedCustomer = customer;
      _selectedCustomerBalance = null;
      _loadingCustomerBalance = true;
    });

    try {
      final balance = await ref
          .read(customersRepositoryProvider)
          .balance(customer.id);
      if (!mounted || _selectedCustomer?.id != customer.id) return;
      setState(() => _selectedCustomerBalance = balance);
    } catch (_) {
      // Balance is a convenience preview only — the server re-checks it
      // authoritatively on submit, so a fetch failure here isn't fatal.
    } finally {
      if (mounted) setState(() => _loadingCustomerBalance = false);
    }
  }

  /// How much more this customer can spend right now: for prepaid, that's
  /// just their balance; for credit, it's balance plus whatever headroom
  /// is left under their credit limit.
  double? get _selectedCustomerAvailable {
    final balance = _selectedCustomerBalance;
    final customer = _selectedCustomer;
    if (balance == null || customer == null) return null;
    return customer.isCredit ? balance + customer.creditLimit : balance;
  }

  /// Client-side preview only — the server re-checks this authoritatively
  /// (and atomically, alongside stock/pricing) when the sale is submitted.
  bool get _wouldExceedAccountBalance {
    if (_paymentMethod != 'account') return false;
    final available = _selectedCustomerAvailable;
    if (available == null) return false;
    return _total > available;
  }

  Future<void> _submit() async {
    if (_paymentMethod == 'account' && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a customer to charge this sale to.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final lines = <SaleLine>[
        if (_plateQty > 0)
          SaleLine(itemType: 'plate', qty: _plateQty.toDouble()),
        for (final line in _lines)
          SaleLine(
            itemType: line.entry.item.isDrink ? 'drink' : 'item',
            itemId: line.entry.item.id,
            qty: line.qty.toDouble(),
          ),
      ];

      await ref
          .read(salesRepositoryProvider)
          .createSale(
            paymentMethod: _paymentMethod,
            customerId: _selectedCustomer?.id,
            storeId: widget.storeId,
            lines: lines,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale completed.'),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() {
        _plateQty = 0;
        _lines.clear();
        _paymentMethod = 'cash';
        _selectedCustomer = null;
        _selectedCustomerBalance = null;
      });
      _refreshMenu();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                Text('Plate', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Tap + for each plate. Leave at 0 for drinks or breakfast on their own.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          CurrencyFormatter.format(_platePrice),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: _plateQty > 0
                                  ? () => setState(() => _plateQty--)
                                  : null,
                              tooltip: 'One fewer plate',
                              icon: const Icon(Icons.remove),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '$_plateQty',
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: () => setState(() => _plateQty++),
                              tooltip: 'One more plate',
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                for (final group in _menuByCategory.entries) ...[
                  const SizedBox(height: 24),
                  Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: group.value.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                    itemBuilder: (context, index) {
                      final entry = group.value[index];
                      return _MenuTile(
                        entry: entry,
                        qty: _lineFor(entry)?.qty ?? 0,
                        onAdd: () => _increment(entry),
                        onRemove: () => _decrement(entry),
                      );
                    },
                  ),
                ],
                if (_menu.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Nothing else on the menu yet.'),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Payment method',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final method in _paymentMethods)
                      ChoiceChip(
                        label: Text(_paymentLabels[method]!),
                        selected: _paymentMethod == method,
                        onSelected: (_) =>
                            setState(() => _paymentMethod = method),
                      ),
                  ],
                ),
                if (_paymentMethod == 'account') ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person_search),
                          title: Text(
                            _selectedCustomer?.name ?? 'Select customer',
                          ),
                          subtitle: _selectedCustomer != null
                              ? Text(
                                  '${_selectedCustomer!.phone} — ${_selectedCustomer!.accountTypeLabel}',
                                )
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _pickCustomer,
                        ),
                        if (_selectedCustomer != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: _loadingCustomerBalance
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : _CustomerAvailabilityNotice(
                                    available: _selectedCustomerAvailable,
                                    total: _total,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The total and the button stay put while the order scrolls, so
          // completing a sale never means hunting for the button.
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _cartSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        CurrencyFormatter.format(_total),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          (_submitting ||
                              _total <= 0 ||
                              _wouldExceedAccountBalance)
                          ? null
                          : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Complete sale'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single tappable menu tile — the modern-POS grid pattern (Square,
/// Toast, Clover): tap to add one, a badge shows the current quantity,
/// a small remove control appears once it's in the cart.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.entry,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final MenuEntry entry;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  IconData get _icon => switch (entry.category.toLowerCase()) {
    'drinks' => Icons.local_drink_outlined,
    'breakfast' => Icons.free_breakfast_outlined,
    'snacks' => Icons.cookie_outlined,
    _ => Icons.restaurant_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final balance = entry.tracksStock ? entry.balance : null;
    final selected = qty > 0;
    final colorScheme = Theme.of(context).colorScheme;
    // A selected tile is filled dark, so its text must turn light, or the
    // item's name and price vanish the moment it is tapped.
    final textColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_icon, size: 28, color: textColor),
                  const SizedBox(height: 8),
                  Text(
                    entry.item.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: textColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    CurrencyFormatter.format(entry.price ?? 0),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: textColor),
                  ),
                  if (balance != null)
                    Text(
                      balance <= 0
                          ? 'Out of stock'
                          : '${balance.toStringAsFixed(0)} left',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: balance <= 0
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: balance <= 0
                            ? (selected
                                  ? colorScheme.onPrimaryContainer
                                  : AppColors.danger)
                            : textColor.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onRemove,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: colorScheme.primary,
                    child: Text(
                      '$qty',
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchSheet extends ConsumerStatefulWidget {
  const _CustomerSearchSheet();

  @override
  ConsumerState<_CustomerSearchSheet> createState() =>
      _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends ConsumerState<_CustomerSearchSheet> {
  final _controller = TextEditingController();
  List<Customer> _results = [];
  bool _searching = false;

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final results = await ref.read(customersRepositoryProvider).search(query);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search by name or phone',
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          if (_searching) const CircularProgressIndicator(),
          if (!_searching)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final customer in _results)
                    ListTile(
                      title: Text(customer.name),
                      subtitle: Text(customer.phone),
                      onTap: () => Navigator.of(context).pop(customer),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
