import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/repositories/edit_logs_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../shared/formatters/currency_formatter.dart';

/// Everything changed after it was first entered: voided sales, price
/// changes, stock corrections, edited catering orders and customer
/// accounts. Each shows what it was, what it became, who changed it and
/// the reason they gave.
class ChangesScreen extends ConsumerStatefulWidget {
  const ChangesScreen({super.key, this.storeId});

  /// Fixed branch (a manager's own). Null for the owner, who follows the
  /// branch switcher.
  final int? storeId;

  @override
  ConsumerState<ChangesScreen> createState() => _ChangesScreenState();
}

const _filters = <(String?, String)>[
  (null, 'All'),
  ('sale', 'Voided sales'),
  ('plate_price', 'Plate price'),
  ('menu_item', 'Menu'),
  ('stock', 'Stock'),
  ('catering_order', 'Catering'),
  ('customer', 'Customers'),
];

class _ChangesScreenState extends ConsumerState<ChangesScreen> {
  String? _type;
  late Future<List<EditLogEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EditLogEntry>> _load() => ref
      .read(editLogsRepositoryProvider)
      .list(
        storeId: widget.storeId ?? ref.read(selectedStoreIdProvider),
        subjectType: _type,
      );

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    if (widget.storeId == null) {
      ref.listen(selectedStoreIdProvider, (_, _) => _reload());
    }

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            children: [
              for (final (type, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _type == type,
                    showCheckmark: false,
                    onSelected: (_) {
                      _type = type;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<EditLogEntry>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load changes.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No changes recorded. When someone voids a sale, '
                      'corrects stock or changes a price, it shows here '
                      'with their reason.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final rows = <Widget>[];
              String? lastDay;
              for (final entry in entries) {
                final day = _dayLabel(entry.createdAt.toLocal());
                if (day != lastDay) {
                  rows.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text(
                        day,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  );
                  lastDay = day;
                }
                rows.add(ChangeCard(entry: entry));
              }

              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: rows,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _dayLabel(DateTime local) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEEE d MMM yyyy').format(local);
}

const _actionLabels = {
  'voided': 'Sale voided',
  'price_changed': 'Price changed',
  'price_reset': 'Back to the price for all branches',
  'stock_corrected': 'Stock corrected',
  'edited': 'Edited',
  'status_changed': 'Status changed',
};

const _fieldLabels = {
  'price': 'Price',
  'price_per_plate': 'Price per plate',
  'number_of_plates': 'Plates',
  'total_amount': 'Total',
  'total': 'Total',
  'balance': 'Balance',
  'client_name': 'Client',
  'client_phone': 'Phone',
  'event_name': 'Event',
  'event_date': 'Date',
  'catering_package_id': 'Package',
  'notes': 'Notes',
  'status': 'Status',
  'name': 'Name',
  'unit': 'Unit',
  'category': 'Heading',
  'tracks_stock': 'Counts stock',
  'is_active': 'Active',
  'credit_limit': 'Credit limit',
  'account_type': 'Account type',
  'phone': 'Phone',
  'store_id': 'Branch',
  'payment_method': 'Paid by',
};

const _moneyFields = {
  'price',
  'price_per_plate',
  'total_amount',
  'total',
  'credit_limit',
};

IconData _icon(String action, String type) {
  if (action == 'voided') return Icons.block;
  if (action.startsWith('price')) return Icons.sell_outlined;
  if (type == 'stock') return Icons.inventory_2_outlined;
  if (type == 'catering_order') return Icons.celebration_outlined;
  if (type == 'customer') return Icons.person_outline;
  return Icons.edit_outlined;
}

String _value(String field, Object? value) {
  if (value == null || value == '') return '—';
  if (value is bool) return value ? 'Yes' : 'No';
  if (_moneyFields.contains(field)) {
    final n = value is num ? value : num.tryParse('$value');
    if (n != null) return CurrencyFormatter.format(n.toDouble());
  }
  if (value is num || num.tryParse('$value') != null) {
    final n = value is num ? value : num.parse('$value');
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : '$n';
  }
  return '$value';
}

class ChangeCard extends StatelessWidget {
  const ChangeCard({super.key, required this.entry});

  final EditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final voided = entry.action == 'voided';
    final changes = voided
        ? entry.changes.where((c) => c.field == 'total').toList()
        : entry.changes;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: voided
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.secondaryContainer,
              child: Icon(
                _icon(entry.action, entry.subjectType),
                size: 18,
                color: voided
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.subjectLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _actionLabels[entry.action] ?? entry.action,
                    style: muted,
                  ),
                  const SizedBox(height: 6),
                  for (final change in changes)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '${_fieldLabels[change.field] ?? change.field}: ',
                          ),
                          TextSpan(
                            text: _value(change.field, change.from),
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward, size: 14),
                            ),
                          ),
                          TextSpan(
                            text: _value(change.field, change.to),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '“${entry.reason}”',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      entry.userName,
                      DateFormat('h:mm a').format(entry.createdAt.toLocal()),
                      ?entry.storeName,
                    ].join(' · '),
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
