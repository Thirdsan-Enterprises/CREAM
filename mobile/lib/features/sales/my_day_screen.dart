import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/sales_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/user.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/models/sale.dart';
import '../../shared/widgets/sale_detail_sheet.dart';

const _paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
  'lpo': 'LPO',
};

class MyDayScreen extends ConsumerStatefulWidget {
  const MyDayScreen({super.key});

  @override
  ConsumerState<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends ConsumerState<MyDayScreen> {
  late Future<(SaleSummary, List<SaleRecord>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(SaleSummary, List<SaleRecord>)> _load() async {
    final today = DateTime.now();
    final repo = ref.read(salesRepositoryProvider);
    final results = await Future.wait([
      repo.summary(from: today, to: today),
      repo.list(from: today, to: today),
    ]);
    return (results[0] as SaleSummary, results[1] as List<SaleRecord>);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<(SaleSummary, List<SaleRecord>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }

          final (summary, sales) = snapshot.data!;
          final canVoid =
              ref.read(authSessionProvider).user?.role == UserRole.storeManager;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Today', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Sales total',
                        value: CurrencyFormatter.format(summary.totalRevenue),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Plates sold',
                        value: summary.platesSold.toStringAsFixed(0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
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
                if (summary.itemRevenue > 0) ...[
                  const SizedBox(height: 12),
                  _StatCard(
                    label: 'Breakfast & other items',
                    value: CurrencyFormatter.format(summary.itemRevenue),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'By payment method',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                for (final method in _paymentLabels.keys)
                  Card(
                    child: ListTile(
                      title: Text(_paymentLabels[method]!),
                      trailing: Text(
                        CurrencyFormatter.format(
                          summary.byPaymentMethod[method] ?? 0,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  "Today's sales",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  canVoid
                      ? 'Tap a sale to see it, or void one entered by mistake.'
                      : 'Tap a sale to see what was sold.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (sales.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No sales yet today.'),
                  ),
                for (final sale in sales)
                  SaleListTile(
                    sale: sale,
                    onTap: () async {
                      final voided = await showSaleDetail(
                        context,
                        sale,
                        canVoid: canVoid,
                      );
                      if (voided) _reload();
                    },
                  ),
              ],
            ),
          );
        },
      ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
