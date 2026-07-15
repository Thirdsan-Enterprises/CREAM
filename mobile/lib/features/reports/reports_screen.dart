import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/reports_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

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
                Tab(text: 'Stock Status'),
                Tab(text: 'Outstanding Credit'),
                Tab(text: 'Catering Pipeline'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _StockStatusTab(),
                _OutstandingCreditTab(),
                _CateringPipelineTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockStatusTab extends ConsumerStatefulWidget {
  const _StockStatusTab();

  @override
  ConsumerState<_StockStatusTab> createState() => _StockStatusTabState();
}

class _StockStatusTabState extends ConsumerState<_StockStatusTab> {
  late Future<List<StoreStockStatus>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(reportsRepositoryProvider).stockStatus();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoreStockStatus>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final stores = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final store in stores) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  store.storeName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final item in store.items)
                Card(
                  child: ListTile(
                    title: Text(item.itemName),
                    subtitle: Text(
                      'Balance ${item.balance.toStringAsFixed(0)} / safety ${item.safetyStock.toStringAsFixed(0)}',
                    ),
                    trailing: Chip(
                      label: Text(
                        item.balance <= item.safetyStock
                            ? 'Re-Order'
                            : 'Sufficient',
                      ),
                      backgroundColor: item.balance <= item.safetyStock
                          ? AppColors.danger
                          : AppColors.gold,
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (store.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 8),
                  child: Text('No items configured.'),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _OutstandingCreditTab extends ConsumerStatefulWidget {
  const _OutstandingCreditTab();

  @override
  ConsumerState<_OutstandingCreditTab> createState() =>
      _OutstandingCreditTabState();
}

class _OutstandingCreditTabState extends ConsumerState<_OutstandingCreditTab> {
  late Future<List<OutstandingCreditRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(reportsRepositoryProvider).outstandingCredit();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OutstandingCreditRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('No outstanding credit balances.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Card(
              child: ListTile(
                title: Text(row.name),
                subtitle: Text(
                  '${row.phone} — ${row.daysSinceLastPayment} days since last payment',
                ),
                trailing: Text(
                  CurrencyFormatter.format(row.balance.abs()),
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CateringPipelineTab extends ConsumerStatefulWidget {
  const _CateringPipelineTab();

  @override
  ConsumerState<_CateringPipelineTab> createState() =>
      _CateringPipelineTabState();
}

class _CateringPipelineTabState extends ConsumerState<_CateringPipelineTab> {
  late Future<List<CateringPipelineRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(reportsRepositoryProvider).cateringPipeline();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CateringPipelineRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('No catering orders.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Card(
              child: ListTile(
                title: Text('${row.clientName} — ${row.package}'),
                subtitle: Text(
                  '${DateFormatter.date(row.eventDate)} — ${row.numberOfPlates} plates — balance due ${CurrencyFormatter.format(row.balanceDue)}',
                ),
                trailing: Chip(label: Text(row.status)),
              ),
            );
          },
        );
      },
    );
  }
}
