import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/customers_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/models/customer.dart';

const _accountTypeFilters = <String?>[null, 'prepaid', 'credit'];
const _accountTypeLabels = {
  null: 'All',
  'prepaid': 'Prepaid',
  'credit': 'Credit',
};

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final _controller = TextEditingController();
  List<Customer> _results = [];
  bool _searching = true;
  String? _accountTypeFilter;

  @override
  void initState() {
    super.initState();
    // Load everyone up front so the list is browsable, not just searchable —
    // a cashier should be able to see "who's already in the system" at a
    // glance, not have to know a name or phone number first.
    _search('');
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final results = await ref
          .read(customersRepositoryProvider)
          .search(query, accountType: _accountTypeFilter);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _setFilter(String? accountType) {
    setState(() => _accountTypeFilter = accountType);
    _search(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCustomer(Customer customer) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerDetailSheet(customer: customer),
    );
    if (changed == true) _search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final type in _accountTypeFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_accountTypeLabels[type]!),
                      selected: _accountTypeFilter == type,
                      onSelected: (_) => _setFilter(type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_searching) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (!_searching)
              Expanded(
                child: _results.isEmpty
                    ? const Center(child: Text('No customers found.'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) => _CustomerTile(
                          customer: _results[index],
                          onTap: () => _openCustomer(_results[index]),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One row: name/phone, account-type badge, and balance — red for a
/// customer who owes (credit account in the negative), otherwise neutral.
class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = customer.balance;
    final owesMoney = customer.isCredit && (balance ?? 0) < 0;

    return Card(
      child: ListTile(
        title: Text(customer.name),
        subtitle: Text(customer.phone),
        onTap: onTap,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Chip(
              label: Text(customer.isCredit ? 'Credit' : 'Prepaid'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(height: 4),
            Text(
              balance == null
                  ? '—'
                  : CurrencyFormatter.format(balance),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: owesMoney ? AppColors.danger : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerDetailSheet extends ConsumerStatefulWidget {
  const _CustomerDetailSheet({required this.customer});

  final Customer customer;

  @override
  ConsumerState<_CustomerDetailSheet> createState() =>
      _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends ConsumerState<_CustomerDetailSheet> {
  late Future<({Customer customer, double balance, List<LedgerEntry> entries})>
  _future;
  final _depositController = TextEditingController();
  bool _depositing = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(customersRepositoryProvider)
        .statement(widget.customer.id);
  }

  void _reload() {
    _changed = true;
    setState(
      () => _future = ref
          .read(customersRepositoryProvider)
          .statement(widget.customer.id),
    );
  }

  Future<void> _deposit() async {
    final amount = double.tryParse(_depositController.text);
    if (amount == null || amount <= 0) return;

    setState(() => _depositing = true);
    try {
      await ref
          .read(customersRepositoryProvider)
          .deposit(widget.customer.id, amount);
      _depositController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deposit recorded.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _depositing = false);
    }
  }

  @override
  void dispose() {
    _depositController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          data.customer.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(_changed),
                      ),
                    ],
                  ),
                  Text(
                    '${data.customer.phone} — ${data.customer.isCredit ? 'Credit (limit ${CurrencyFormatter.format(data.customer.creditLimit)})' : 'Prepaid'}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Balance',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    CurrencyFormatter.format(data.balance),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _depositController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Deposit amount',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _depositing ? null : _deposit,
                        child: _depositing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Deposit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Statement',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Expanded(
                    child: data.entries.isEmpty
                        ? const Center(child: Text('No activity yet.'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: data.entries.length,
                            itemBuilder: (context, index) {
                              final entry = data.entries[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  CurrencyFormatter.format(entry.amount),
                                ),
                                subtitle: Text(
                                  '${entry.type} — ${DateFormatter.dateTime(entry.occurredAt)}',
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

