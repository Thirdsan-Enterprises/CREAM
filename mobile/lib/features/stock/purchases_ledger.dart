import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/operations_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';

enum _Period {
  thisMonth('This month'),
  lastMonth('Last month'),
  last7('7 days');

  const _Period(this.label);
  final String label;

  (DateTime, DateTime) get range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Period.thisMonth => (DateTime(now.year, now.month), today),
      _Period.lastMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      _Period.last7 => (today.subtract(const Duration(days: 6)), today),
    };
  }
}

/// The procurement ledger: what was bought, for how much, from whom, with
/// totals by heading. For the owner and procurement.
class PurchasesLedgerTab extends ConsumerStatefulWidget {
  const PurchasesLedgerTab({super.key});

  @override
  ConsumerState<PurchasesLedgerTab> createState() => _PurchasesLedgerTabState();
}

class _PurchasesLedgerTabState extends ConsumerState<PurchasesLedgerTab> {
  _Period _period = _Period.thisMonth;
  late Future<PurchaseLedger> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PurchaseLedger> _load() {
    final (from, to) = _period.range;
    return ref.read(operationsRepositoryProvider).purchases(from: from, to: to);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: [
              for (final p in _Period.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: p == _period,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _period = p;
                      _future = _load();
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<PurchaseLedger>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Could not load purchases.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ledger = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async => setState(() {
                  _future = _load();
                }),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  children: [
                    Card(
                      color: AppColors.charcoal,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Spent on purchases',
                              style: TextStyle(color: AppColors.cream),
                            ),
                            Text(
                              CurrencyFormatter.format(ledger.totalSpent),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${ledger.purchases} purchases'
                              '${ledger.withoutPrice > 0 ? ' · ${ledger.withoutPrice} without a price' : ''}',
                              style: const TextStyle(color: AppColors.cream),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (ledger.byCategory.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('By heading', style: theme.textTheme.titleMedium),
                      for (final (category, total) in ledger.byCategory)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(category),
                          trailing: Text(
                            CurrencyFormatter.format(total),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Text('Purchases', style: theme.textTheme.titleMedium),
                    if (ledger.rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No purchases in this period.'),
                      ),
                    for (final row in ledger.rows)
                      Card(
                        child: ListTile(
                          title: Text('${_n(row.qty)} ${row.unit} ${row.item}'),
                          subtitle: Text(
                            [
                              DateFormatter.dateTime(row.occurredAt),
                              if (row.supplier != null &&
                                  row.supplier!.isNotEmpty)
                                'from ${row.supplier}',
                              if (row.unitCost != null)
                                '${CurrencyFormatter.format(row.unitCost!)} per ${row.unit}',
                              ?row.recordedBy,
                              ?row.store,
                            ].join(' · '),
                          ),
                          trailing: Text(
                            row.total == null
                                ? 'No price'
                                : CurrencyFormatter.format(row.total!),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: row.total == null
                                  ? AppColors.danger
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
