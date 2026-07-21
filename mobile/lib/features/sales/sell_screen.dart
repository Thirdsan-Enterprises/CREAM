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

class _DrinkLine {
  _DrinkLine(this.drink, this.qty);
  final Drink drink;
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

const _paymentMethods = ['cash', 'momo', 'airtel', 'account'];
const _paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
};

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  bool _loading = true;
  String? _loadError;
  double _platePrice = 0;
  List<Drink> _availableDrinks = [];

  int _plateQty = 1;
  final List<_DrinkLine> _drinkLines = [];
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
      final results = await Future.wait([repo.platePrice(), repo.drinks()]);
      setState(() {
        _platePrice = results[0] as double;
        _availableDrinks = results[1] as List<Drink>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  double get _total {
    var total = _plateQty * _platePrice;
    for (final line in _drinkLines) {
      total += line.qty * (line.drink.price ?? 0);
    }
    return total;
  }

  _DrinkLine? _lineFor(Drink drink) =>
      _drinkLines.where((l) => l.drink.item.id == drink.item.id).firstOrNull;

  void _incrementDrink(Drink drink) {
    setState(() {
      final existing = _lineFor(drink);
      if (existing != null) {
        existing.qty++;
      } else {
        _drinkLines.add(_DrinkLine(drink, 1));
      }
    });
  }

  void _decrementDrink(Drink drink) {
    setState(() {
      final existing = _lineFor(drink);
      if (existing == null) return;
      if (existing.qty > 1) {
        existing.qty--;
      } else {
        _drinkLines.remove(existing);
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
        SaleLine(itemType: 'plate', qty: _plateQty.toDouble()),
        for (final line in _drinkLines)
          SaleLine(
            itemType: 'drink',
            itemId: line.drink.item.id,
            qty: line.qty.toDouble(),
          ),
      ];

      await ref
          .read(salesRepositoryProvider)
          .createSale(
            paymentMethod: _paymentMethod,
            customerId: _selectedCustomer?.id,
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
        _plateQty = 1;
        _drinkLines.clear();
        _paymentMethod = 'cash';
        _selectedCustomer = null;
        _selectedCustomerBalance = null;
      });
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
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Plate', style: Theme.of(context).textTheme.titleLarge),
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
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$_plateQty',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => setState(() => _plateQty++),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Drinks', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Tap to add, tap again for more.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _availableDrinks.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final drink = _availableDrinks[index];
              return _DrinkTile(
                drink: drink,
                qty: _lineFor(drink)?.qty ?? 0,
                onAdd: () => _incrementDrink(drink),
                onRemove: () => _decrementDrink(drink),
              );
            },
          ),
          if (_availableDrinks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No drinks available.'),
            ),
          const SizedBox(height: 24),
          Text('Payment method', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final method in _paymentMethods)
                ChoiceChip(
                  label: Text(_paymentLabels[method]!),
                  selected: _paymentMethod == method,
                  onSelected: (_) => setState(() => _paymentMethod = method),
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
                    title: Text(_selectedCustomer?.name ?? 'Select customer'),
                    subtitle: _selectedCustomer != null
                        ? Text(
                            '${_selectedCustomer!.phone} — ${_selectedCustomer!.isCredit ? 'Credit' : 'Prepaid'}',
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
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleLarge),
              Text(
                CurrencyFormatter.format(_total),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_submitting || _total <= 0 || _wouldExceedAccountBalance)
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
    );
  }
}

/// A single tappable drink tile — the modern-POS grid pattern (Square,
/// Toast, Clover): tap to add one, a badge shows the current quantity,
/// a small remove control appears once it's in the cart.
class _DrinkTile extends StatelessWidget {
  const _DrinkTile({
    required this.drink,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final Drink drink;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    final colorScheme = Theme.of(context).colorScheme;

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
                  const Icon(Icons.local_drink_outlined, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    drink.item.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    CurrencyFormatter.format(drink.price ?? 0),
                    style: Theme.of(context).textTheme.bodySmall,
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
