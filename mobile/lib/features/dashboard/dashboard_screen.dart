import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/reports_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(reportsRepositoryProvider).dashboard();
  }

  void _reload() =>
      setState(() => _future = ref.read(reportsRepositoryProvider).dashboard());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final data = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Today, all branches',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Sales total',
                      value: CurrencyFormatter.format(data.salesTotalToday),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Plates sold',
                      value: data.platesSoldToday.toStringAsFixed(0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatCard(
                label: 'Total outstanding credit',
                value: CurrencyFormatter.format(data.totalOutstandingCredit),
              ),
              if (data.accountsNeedingAttention.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Accounts near their limit (${data.accountsNeedingAttention.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final alert in data.accountsNeedingAttention.take(8))
                        ListTile(
                          dense: true,
                          leading: Icon(
                            alert.status == 'blocked'
                                ? Icons.block
                                : Icons.warning_amber,
                            color: alert.status == 'blocked'
                                ? AppColors.danger
                                : AppColors.gold,
                          ),
                          title: Text(
                            alert.storeName == null
                                ? alert.name
                                : '${alert.name} · ${alert.storeName}',
                          ),
                          subtitle: Text(alert.warning),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                data.lowStockAlerts.isEmpty
                    ? 'Low stock alerts'
                    : 'Low stock alerts (${data.lowStockAlerts.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.lowStockAlerts.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'An item shows here when a branch\'s stock is at or below its re-order level. Buy it at Kira or transfer it from Kira.',
                  ),
                ),
              const SizedBox(height: 8),
              if (data.lowStockAlerts.isEmpty)
                const Text('No items need re-ordering right now.'),
              for (final group in _alertsByBranch(data.lowStockAlerts))
                Card(
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(group.storeName),
                    subtitle: Text(
                      '${group.alerts.length} to re-order · ${group.alerts.where((a) => a.balance <= 0).length} out of stock',
                    ),
                    children: [
                      for (final alert in group.alerts)
                        ListTile(
                          dense: true,
                          title: Text(alert.itemName),
                          subtitle: Text(
                            '${alert.balance.toStringAsFixed(0)} in stock, re-order level ${alert.safetyStock.toStringAsFixed(0)}',
                          ),
                          trailing: Text(
                            alert.balance <= 0 ? 'Out' : 'Low',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: alert.balance <= 0
                                  ? AppColors.danger
                                  : AppColors.gold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Upcoming catering (7 days)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (data.upcomingCatering.isEmpty)
                const Text('No catering events in the next 7 days.'),
              for (final event in data.upcomingCatering)
                Card(
                  child: ListTile(
                    title: Text(
                      '${event.clientName}${event.eventName != null ? ' — ${event.eventName}' : ''}',
                    ),
                    subtitle: Text(
                      '${DateFormatter.date(event.eventDate)} — ${event.package} (${event.status})',
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

class _BranchAlerts {
  _BranchAlerts(this.storeName, this.alerts);

  final String storeName;
  final List<LowStockAlert> alerts;
}

/// One group per branch, the most depleted items first, so the owner sees
/// "Kira: 22 to re-order" instead of a wall of every item at every branch.
List<_BranchAlerts> _alertsByBranch(List<LowStockAlert> alerts) {
  final byStore = <int, _BranchAlerts>{};
  for (final alert in alerts) {
    byStore
        .putIfAbsent(
          alert.storeId,
          () => _BranchAlerts(alert.storeName, <LowStockAlert>[]),
        )
        .alerts
        .add(alert);
  }
  final groups = byStore.values.toList();
  for (final group in groups) {
    group.alerts.sort((a, b) => a.balance.compareTo(b.balance));
  }
  groups.sort((a, b) => b.alerts.length.compareTo(a.alerts.length));
  return groups;
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
