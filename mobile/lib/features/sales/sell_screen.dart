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
import '../customers/customers_view.dart';
import 'pos_cart.dart';

const _paymentMethods = ['cash', 'momo', 'airtel', 'account', 'lpo'];
const _paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
  // A one-off sale covered by a purchase order, no running balance.
  'lpo': 'LPO',
};

/// Wide enough to show the order beside the menu (tablets, Fold open).
const _sidePanelWidth = 840.0;

/// The Sell screen: the branch's menu under its headings (Lunch, Breakfast,
/// Drinks...), each item at this branch's price. Tap to add; the order and
/// the Complete sale button are always one tap away.
class SellScreen extends ConsumerStatefulWidget {
  /// [storeId] is only for the owner, who sells on behalf of a branch.
  /// Staff always sell for their own branch, so they leave it null.
  const SellScreen({super.key, this.storeId});

  final int? storeId;

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  final _cart = PosCart();
  final _search = TextEditingController();

  bool _loading = true;
  String? _loadError;
  List<PosItem> _items = [];
  String? _heading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cart.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await _fetchItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _heading ??= _defaultHeading(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is ApiException ? e.message : 'Could not load the menu.';
        _loading = false;
      });
    }
  }

  Future<List<PosItem>> _fetchItems() async {
    final repo = ref.read(itemsRepositoryProvider);
    final results = await Future.wait([
      repo.platePrice(storeId: widget.storeId),
      repo.menu(storeId: widget.storeId),
    ]);
    final platePrice = results[0] as double;
    final menu = results[1] as List<MenuEntry>;
    final items = [for (final entry in menu) PosItem.menu(entry)];
    // A branch with no lunch dishes on its menu sells the plain plate.
    if (!items.any((i) => i.category.toLowerCase() == 'lunch')) {
      items.insert(0, PosItem.plate(platePrice));
    }
    return items;
  }

  /// Re-reads the menu quietly so "left" counts are current after a sale.
  Future<void> _refresh() async {
    try {
      final items = await _fetchItems();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      // Keep the previous counts; the server still enforces stock.
    }
  }

  List<String> get _headings {
    final seen = <String>[];
    for (final item in _items) {
      if (!seen.contains(item.category)) seen.add(item.category);
    }
    return seen;
  }

  /// Breakfast in the morning, lunch the rest of the day.
  String? _defaultHeading(List<PosItem> items) {
    final headings = {for (final i in items) i.category};
    if (DateTime.now().hour < 11 && headings.contains('Breakfast')) {
      return 'Breakfast';
    }
    return items.isEmpty ? null : items.first.category;
  }

  List<PosItem> get _shown {
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      return _items.where((i) => i.name.toLowerCase().contains(query)).toList();
    }
    return _items.where((i) => i.category == _heading).toList();
  }

  void _add(PosItem item) {
    final problem = _cart.add(item);
    if (problem != null) _snack(problem);
  }

  Future<void> _pickCustomer() async {
    final customer = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerSearchSheet(storeId: widget.storeId),
    );
    if (customer == null) return;

    _cart.update(() {
      _cart.customer = customer;
      _cart.standing = null;
      _cart.loadingCustomer = true;
    });
    try {
      final standing = await ref
          .read(customersRepositoryProvider)
          .standing(customer.id);
      if (_cart.customer?.id == customer.id) {
        _cart.update(() => _cart.standing = standing);
      }
    } catch (_) {
      // A preview only: the server checks the balance on submit.
    } finally {
      _cart.update(() => _cart.loadingCustomer = false);
    }
  }

  /// Rings up the order. Returns true when the sale went through.
  Future<bool> _submit() async {
    if (_cart.paymentMethod == 'account' && _cart.customer == null) {
      _snack('Select a customer to charge this sale to.');
      return false;
    }
    _cart.update(() => _cart.submitting = true);
    try {
      final lines = <SaleLine>[
        for (final line in _cart.lines)
          line.item.isPlate
              ? SaleLine(itemType: 'plate', qty: line.qty.toDouble())
              : SaleLine(
                  itemType: line.item.entry!.item.isDrink ? 'drink' : 'item',
                  itemId: line.item.entry!.item.id,
                  qty: line.qty.toDouble(),
                ),
      ];
      final result = await ref
          .read(salesRepositoryProvider)
          .createSale(
            paymentMethod: _cart.paymentMethod,
            customerId: _cart.customer?.id,
            storeId: widget.storeId,
            lines: lines,
          );
      if (!mounted) return true;

      final total = _cart.total;
      _cart.reset();
      _search.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Sale completed · ${CurrencyFormatter.format(total)}',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      // An account now near or at its limit: say so while the customer is
      // still at the counter.
      final account = result['customer_account'];
      if (account is Map<String, dynamic>) {
        final standing = AccountStanding.fromJson(account);
        if (standing.warning != null) {
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              icon: Icon(
                standing.isBlocked ? Icons.block : Icons.warning_amber,
                color: standing.isBlocked
                    ? AppColors.danger
                    : const Color(0xFFB7791F),
              ),
              title: const Text('Sale completed'),
              content: Text(standing.warning!),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
      _refresh();
      return true;
    } catch (e) {
      if (mounted) {
        _snack(
          e is ApiException ? e.message : 'Something went wrong.',
          error: true,
        );
      }
      return false;
    } finally {
      _cart.update(() => _cart.submitting = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.danger : null,
        ),
      );
  }

  Future<void> _openOrder() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => OrderPanel(
          cart: _cart,
          scrollController: scroll,
          onPickCustomer: _pickCustomer,
          onSubmit: () async {
            final done = await _submit();
            if (done && sheetContext.mounted) Navigator.pop(sheetContext);
          },
        ),
      ),
    );
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
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sidePanelWidth;
        final menu = _MenuPane(
          items: _shown,
          headings: _headings,
          heading: _heading,
          searching: _search.text.trim().isNotEmpty,
          search: _search,
          cart: _cart,
          onSearch: () => setState(() {}),
          onHeading: (h) => setState(() {
            _heading = h;
            _search.clear();
          }),
          onAdd: _add,
          onRefresh: _refresh,
        );

        if (wide) {
          return SafeArea(
            child: Row(
              children: [
                Expanded(child: menu),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 400,
                  child: OrderPanel(
                    cart: _cart,
                    onPickCustomer: _pickCustomer,
                    onSubmit: _submit,
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Column(
            children: [
              Expanded(child: menu),
              _OrderBar(cart: _cart, onOpen: _openOrder),
            ],
          ),
        );
      },
    );
  }
}

/// Search, headings and the grid of items.
class _MenuPane extends StatelessWidget {
  const _MenuPane({
    required this.items,
    required this.headings,
    required this.heading,
    required this.searching,
    required this.search,
    required this.cart,
    required this.onSearch,
    required this.onHeading,
    required this.onAdd,
    required this.onRefresh,
  });

  final List<PosItem> items;
  final List<String> headings;
  final String? heading;
  final bool searching;
  final TextEditingController search;
  final PosCart cart;
  final VoidCallback onSearch;
  final ValueChanged<String> onHeading;
  final ValueChanged<PosItem> onAdd;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: search,
            onChanged: (_) => onSearch(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search the menu',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: searching
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        search.clear();
                        onSearch();
                      },
                    )
                  : null,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final h in headings)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(h),
                    selected: !searching && h == heading,
                    showCheckmark: false,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    onSelected: (_) => onHeading(h),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: items.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            searching
                                ? 'Nothing on the menu matches.'
                                : 'Nothing under this heading yet.',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            // Fixed height: more dishes on screen at once.
                            mainAxisExtent: 112,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _ItemTile(
                          item: item,
                          qty: cart.qtyOf(item),
                          onAdd: () => onAdd(item),
                          onRemove: () => cart.removeOne(item),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// One item: name, price, what's left; tap to add. Once in the order it
/// turns gold and shows how many, with a minus to take one off.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final PosItem item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = qty > 0;
    final left = item.stockLeft;
    final out = left != null && left <= 0;
    final price = CurrencyFormatter.format(item.price);

    // The tile itself adds one; the minus sits beside it, not inside, so a
    // screen reader still reads the tile as one "add" button.
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            button: true,
            label: [
              item.name,
              price,
              if (left != null)
                out ? 'Out of stock' : '${left.toStringAsFixed(0)} left',
              if (selected) '$qty in order',
            ].join(', '),
            excludeSemantics: true,
            child: Material(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.16)
                  : theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: selected ? AppColors.gold : const Color(0xFFE6DED0),
                  width: selected ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: selected ? 30 : 0),
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                              color: out
                                  ? AppColors.charcoal.withValues(alpha: 0.45)
                                  : AppColors.charcoal,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        // Room for the minus button once it is in the order.
                        padding: EdgeInsets.only(right: selected ? 34 : 0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            price,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.charcoal,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (left != null)
                        Text(
                          out
                              ? 'Out of stock'
                              : '${left.toStringAsFixed(0)} left',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: out ? FontWeight.w800 : FontWeight.w500,
                            color: out
                                ? AppColors.danger
                                : AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (selected) ...[
          Positioned(
            top: 8,
            right: 8,
            child: ExcludeSemantics(
              child: CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.gold,
                child: Text(
                  '$qty',
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: IconButton(
              tooltip: 'One fewer ${item.name}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.charcoal,
              onPressed: onRemove,
            ),
          ),
        ],
      ],
    );
  }
}

/// Phone: the order total pinned under the menu, one tap from paying.
class _OrderBar extends StatelessWidget {
  const _OrderBar({required this.cart, required this.onOpen});

  final PosCart cart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Material(
        elevation: 8,
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cart.isEmpty
                          ? 'Tap items to start an order'
                          : cart.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      CurrencyFormatter.format(cart.total),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: cart.isEmpty ? null : onOpen,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(
                    cart.isEmpty ? 'Order' : 'Order (${cart.count})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The order: lines with +/−, how it is paid, the customer for an account
/// sale, and the Complete sale button.
class OrderPanel extends StatelessWidget {
  const OrderPanel({
    super.key,
    required this.cart,
    required this.onPickCustomer,
    required this.onSubmit,
    this.scrollController,
  });

  final PosCart cart;
  final VoidCallback onPickCustomer;
  final Future<void> Function() onSubmit;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final canCharge =
            !cart.isEmpty && !cart.submitting && !cart.exceedsAccount;
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (!cart.isEmpty)
                        TextButton.icon(
                          onPressed: cart.reset,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Clear'),
                        ),
                    ],
                  ),
                  if (cart.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Tap items on the menu to add them.'),
                    ),
                  for (final line in cart.lines)
                    _OrderLine(line: line, cart: cart),
                  if (!cart.isEmpty) ...[
                    const Divider(height: 28),
                    Text('Paid by', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final method in _paymentMethods)
                          ChoiceChip(
                            label: Text(_paymentLabels[method]!),
                            selected: cart.paymentMethod == method,
                            showCheckmark: false,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) => cart.setPayment(method),
                          ),
                      ],
                    ),
                    if (cart.paymentMethod == 'account') ...[
                      const SizedBox(height: 12),
                      _AccountBox(cart: cart, onPick: onPickCustomer),
                    ],
                  ],
                ],
              ),
            ),
            Material(
              elevation: 6,
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('Total', style: theme.textTheme.titleLarge),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              CurrencyFormatter.format(cart.total),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: canCharge ? onSubmit : null,
                        child: cart.submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Complete sale',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.line, required this.cart});

  final CartLine line;
  final PosCart cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.item.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                CurrencyFormatter.format(line.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${CurrencyFormatter.format(line.item.price)} each',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Remove one ${line.item.name}',
                onPressed: () => cart.removeOne(line.item),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${line.qty}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add one ${line.item.name}',
                onPressed: () {
                  final problem = cart.add(line.item);
                  if (problem != null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(problem)));
                  }
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Account sale: who is charged, what they can spend, and any warning.
class _AccountBox extends StatelessWidget {
  const _AccountBox({required this.cart, required this.onPick});

  final PosCart cart;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final customer = cart.customer;
    final standing = cart.standing;
    final available = cart.available;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_search),
            title: Text(customer?.name ?? 'Select customer'),
            subtitle: customer == null
                ? null
                : Text('${customer.phone} · ${customer.accountTypeLabel}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onPick,
          ),
          if (customer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: cart.loadingCustomer
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (available == null)
                          const Text(
                            'Could not load the balance; it is checked on submit.',
                          )
                        else if (cart.exceedsAccount)
                          Text(
                            'Only ${CurrencyFormatter.format(available)} available: '
                            'over by ${CurrencyFormatter.format(cart.total - available)}.',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          Text(
                            'Available: ${CurrencyFormatter.format(available)}',
                          ),
                        if (standing != null && standing.status != 'ok') ...[
                          const SizedBox(height: 8),
                          StandingBanner(standing: standing),
                        ],
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _CustomerSearchSheet extends ConsumerStatefulWidget {
  const _CustomerSearchSheet({this.storeId});

  /// The branch the owner is selling for; null for staff.
  final int? storeId;

  @override
  ConsumerState<_CustomerSearchSheet> createState() =>
      _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends ConsumerState<_CustomerSearchSheet> {
  final _controller = TextEditingController();
  List<Customer> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final results = await ref
          .read(customersRepositoryProvider)
          .search(query, availableAt: widget.storeId);
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
                      subtitle: Text(
                        '${customer.phone} · ${customer.accountTypeLabel}',
                      ),
                      trailing: StandingBadge(customer: customer),
                      enabled: customer.isActive,
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
