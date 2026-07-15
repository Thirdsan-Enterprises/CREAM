import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/sales_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/models/sale.dart';

class BackOfficeSalesScreen extends ConsumerStatefulWidget {
  const BackOfficeSalesScreen({super.key});

  @override
  ConsumerState<BackOfficeSalesScreen> createState() =>
      _BackOfficeSalesScreenState();
}

class _BackOfficeSalesScreenState extends ConsumerState<BackOfficeSalesScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  late Future<(SaleSummary, List<SaleRecord>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(SaleSummary, List<SaleRecord>)> _load() async {
    final storeId = ref.read(selectedStoreIdProvider);
    final repo = ref.read(salesRepositoryProvider);
    final summary = await repo.summary(from: _from, to: _to, storeId: storeId);
    final list = await repo.list(from: _from, to: _to, storeId: storeId);
    return (summary, list);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedStoreIdProvider, (previous, next) => _reload());

    return FutureBuilder<(SaleSummary, List<SaleRecord>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final (summary, sales) = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${DateFormatter.date(_from)} — ${DateFormatter.date(_to)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range),
                    label: const Text('Change range'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Total revenue',
                      value: CurrencyFormatter.format(summary.totalRevenue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Plate revenue',
                      value: CurrencyFormatter.format(summary.plateRevenue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Drink revenue',
                      value: CurrencyFormatter.format(summary.drinkRevenue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Sales (${sales.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final sale in sales)
                Card(
                  child: ListTile(
                    title: Text(
                      '${sale.storeName} — ${CurrencyFormatter.format(sale.total)}',
                    ),
                    subtitle: Text(
                      '${sale.paymentMethod} — ${sale.soldByName} — ${DateFormatter.dateTime(sale.soldAt)}',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
