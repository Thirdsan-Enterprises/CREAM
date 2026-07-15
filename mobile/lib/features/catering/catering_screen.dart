import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/catering_repository.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';

const _statuses = ['quoted', 'confirmed', 'delivered', 'settled', 'cancelled'];

class CateringScreen extends StatelessWidget {
  const CateringScreen({super.key});

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
                Tab(text: 'Pipeline'),
                Tab(text: 'New order'),
                Tab(text: 'Packages'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_PipelineTab(), _NewOrderTab(), _PackagesTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineTab extends ConsumerStatefulWidget {
  const _PipelineTab();

  @override
  ConsumerState<_PipelineTab> createState() => _PipelineTabState();
}

class _PipelineTabState extends ConsumerState<_PipelineTab> {
  String? _statusFilter;
  late Future<List<CateringOrder>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(cateringRepositoryProvider).orders();
  }

  void _reload() {
    setState(
      () => _future = ref
          .read(cateringRepositoryProvider)
          .orders(status: _statusFilter),
    );
  }

  Future<void> _openOrder(CateringOrder order) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _OrderDetailSheet(order: order),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _statusFilter == null,
                onSelected: (_) {
                  setState(() => _statusFilter = null);
                  _reload();
                },
              ),
              for (final status in _statuses)
                ChoiceChip(
                  label: Text(status),
                  selected: _statusFilter == status,
                  onSelected: (_) {
                    setState(() => _statusFilter = status);
                    _reload();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<CateringOrder>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return const Center(child: Text('No catering orders.'));
              }

              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${order.clientName} — ${order.package.name}',
                        ),
                        subtitle: Text(
                          '${DateFormatter.date(order.eventDate)} — ${order.numberOfPlates} plates — balance due ${CurrencyFormatter.format(order.balanceDue)}',
                        ),
                        trailing: Chip(label: Text(order.status)),
                        onTap: () => _openOrder(order),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderDetailSheet extends ConsumerStatefulWidget {
  const _OrderDetailSheet({required this.order});

  final CateringOrder order;

  @override
  ConsumerState<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends ConsumerState<_OrderDetailSheet> {
  late String _status;
  final _amountController = TextEditingController();
  String _paymentMethod = 'cash';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _status = widget.order.status;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(cateringRepositoryProvider)
          .updateStatus(widget.order.id, status);
      if (!mounted) return;
      setState(() => _status = status);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Status updated.')));
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPayment() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(cateringRepositoryProvider)
          .addPayment(
            widget.order.id,
            amount: amount,
            paymentMethod: _paymentMethod,
          );
      if (!mounted) return;
      _amountController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment recorded.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.clientName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('${order.clientPhone} — ${order.package.name}'),
            const SizedBox(height: 8),
            Text(
              '${order.numberOfPlates} plates — ${CurrencyFormatter.format(order.totalAmount)}',
            ),
            Text('Balance due: ${CurrencyFormatter.format(order.balanceDue)}'),
            const SizedBox(height: 16),
            Text('Status', style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                for (final status in _statuses)
                  ChoiceChip(
                    label: Text(status),
                    selected: _status == status,
                    onSelected: _busy ? null : (_) => _updateStatus(status),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Record payment',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _paymentMethod,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'momo', child: Text('MoMo')),
                    DropdownMenuItem(value: 'airtel', child: Text('Airtel')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _addPayment,
              child: const Text('Add payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewOrderTab extends ConsumerStatefulWidget {
  const _NewOrderTab();

  @override
  ConsumerState<_NewOrderTab> createState() => _NewOrderTabState();
}

class _NewOrderTabState extends ConsumerState<_NewOrderTab> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _eventNameController = TextEditingController();
  final _platesController = TextEditingController();
  DateTime _eventDate = DateTime.now().add(const Duration(days: 7));
  CateringPackage? _package;
  bool _submitting = false;
  late Future<List<CateringPackage>> _packagesFuture;

  @override
  void initState() {
    super.initState();
    _packagesFuture = ref.read(cateringRepositoryProvider).packages();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _eventNameController.dispose();
    _platesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date != null) setState(() => _eventDate = date);
  }

  Future<void> _submit() async {
    final plates = int.tryParse(_platesController.text);
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _package == null ||
        plates == null ||
        plates <= 0) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(cateringRepositoryProvider)
          .createOrder(
            clientName: _nameController.text,
            clientPhone: _phoneController.text,
            eventName: _eventNameController.text.isEmpty
                ? null
                : _eventNameController.text,
            eventDate: _eventDate,
            cateringPackageId: _package!.id,
            numberOfPlates: plates,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Catering order created.')));
      setState(() {
        _nameController.clear();
        _phoneController.clear();
        _eventNameController.clear();
        _platesController.clear();
        _package = null;
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
    return FutureBuilder<List<CateringPackage>>(
      future: _packagesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final packages = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Client name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Client phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _eventNameController,
                decoration: const InputDecoration(
                  labelText: 'Event name (optional)',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Event date: ${DateFormatter.date(_eventDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              DropdownButtonFormField<CateringPackage>(
                initialValue: _package,
                decoration: const InputDecoration(labelText: 'Package'),
                items: [
                  for (final package in packages)
                    DropdownMenuItem(
                      value: package,
                      child: Text(
                        '${package.name} — ${CurrencyFormatter.format(package.pricePerPlate)}/plate',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _package = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _platesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of plates',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create quote'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PackagesTab extends ConsumerStatefulWidget {
  const _PackagesTab();

  @override
  ConsumerState<_PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends ConsumerState<_PackagesTab> {
  late Future<List<CateringPackage>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(cateringRepositoryProvider).packages();
  }

  void _reload() =>
      setState(() => _future = ref.read(cateringRepositoryProvider).packages());

  Future<void> _editPrice(CateringPackage package) async {
    final controller = TextEditingController(
      text: package.pricePerPlate.toStringAsFixed(0),
    );
    final newPrice = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${package.name} price'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Price per plate'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newPrice == null || newPrice <= 0) return;
    await ref
        .read(cateringRepositoryProvider)
        .updatePackagePrice(package.id, newPrice);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CateringPackage>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final packages = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: packages.length,
          itemBuilder: (context, index) {
            final package = packages[index];
            return Card(
              child: ListTile(
                title: Text(package.name),
                trailing: Text(CurrencyFormatter.format(package.pricePerPlate)),
                onTap: () => _editPrice(package),
              ),
            );
          },
        );
      },
    );
  }
}
