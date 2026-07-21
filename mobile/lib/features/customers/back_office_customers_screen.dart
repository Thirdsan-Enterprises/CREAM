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

class BackOfficeCustomersScreen extends ConsumerStatefulWidget {
  const BackOfficeCustomersScreen({super.key});

  @override
  ConsumerState<BackOfficeCustomersScreen> createState() =>
      _BackOfficeCustomersScreenState();
}

class _BackOfficeCustomersScreenState
    extends ConsumerState<BackOfficeCustomersScreen> {
  final _controller = TextEditingController();
  List<Customer> _results = [];
  bool _searching = true;
  String? _accountTypeFilter;

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

  Future<void> _createCustomer() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _NewCustomerSheet(),
    );
    if (created == true) _search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
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
            if (_searching)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (!_searching)
              Expanded(
                child: _results.isEmpty
                    ? const Center(child: Text('No customers found.'))
                    : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final customer = _results[index];
                    final balance = customer.balance;
                    final owesMoney = customer.isCredit && (balance ?? 0) < 0;
                    return Card(
                      child: ListTile(
                        title: Text(customer.name),
                        subtitle: Text(
                          '${customer.phone} — ${customer.isCredit ? 'Credit (limit ${CurrencyFormatter.format(customer.creditLimit)})' : 'Prepaid'}',
                        ),
                        trailing: Text(
                          balance == null
                              ? '—'
                              : CurrencyFormatter.format(balance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: owesMoney ? AppColors.danger : null,
                          ),
                        ),
                        onTap: () => _openCustomer(customer),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCustomer,
        icon: const Icon(Icons.add),
        label: const Text('New customer'),
      ),
    );
  }
}

class _NewCustomerSheet extends ConsumerStatefulWidget {
  const _NewCustomerSheet();

  @override
  ConsumerState<_NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends ConsumerState<_NewCustomerSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _limitController = TextEditingController(text: '0');
  String _accountType = 'prepaid';
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(customersRepositoryProvider)
          .create(
            name: _nameController.text,
            phone: _phoneController.text,
            accountType: _accountType,
            creditLimit: _accountType == 'credit'
                ? (double.tryParse(_limitController.text) ?? 0)
                : 0,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New customer account',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'prepaid', label: Text('Prepaid')),
              ButtonSegment(value: 'credit', label: Text('Credit')),
            ],
            selected: {_accountType},
            onSelectionChanged: (value) =>
                setState(() => _accountType = value.first),
          ),
          if (_accountType == 'credit') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _limitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Credit limit'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create account'),
          ),
        ],
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

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(customersRepositoryProvider)
        .statement(widget.customer.id);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
                  Text(
                    data.customer.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(data.customer.phone),
                  const SizedBox(height: 8),
                  Text(
                    data.customer.isCredit
                        ? 'Credit — limit ${CurrencyFormatter.format(data.customer.creditLimit)}'
                        : 'Prepaid',
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
                  Text(
                    'Statement',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: data.entries.length,
                      itemBuilder: (context, index) {
                        final entry = data.entries[index];
                        return ListTile(
                          dense: true,
                          title: Text(CurrencyFormatter.format(entry.amount)),
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
