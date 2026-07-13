import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/customers_repository.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/models/customer.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
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

  void _openCustomer(Customer customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerDetailSheet(customer: customer),
    );
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
            if (_searching) const CircularProgressIndicator(),
            if (!_searching)
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final customer = _results[index];
                    return Card(
                      child: ListTile(
                        title: Text(customer.name),
                        subtitle: Text(customer.phone),
                        trailing: Text(
                          customer.isCredit ? 'Credit' : 'Prepaid',
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

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(customersRepositoryProvider)
        .statement(widget.customer.id);
  }

  void _reload() {
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
                  Text(
                    data.customer.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(data.customer.phone),
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
