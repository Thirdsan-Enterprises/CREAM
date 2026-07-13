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
                'Today, all stores',
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
              const SizedBox(height: 24),
              Text(
                'Low stock alerts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (data.lowStockAlerts.isEmpty)
                const Text('No items need re-ordering right now.'),
              for (final alert in data.lowStockAlerts)
                Card(
                  child: ListTile(
                    title: Text(alert.itemName),
                    subtitle: Text(
                      '${alert.storeName} — balance ${alert.balance.toStringAsFixed(0)}',
                    ),
                    trailing: const Chip(
                      label: Text('Re-Order'),
                      backgroundColor: AppColors.danger,
                      labelStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
