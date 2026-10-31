import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/sales_repository.dart';
import '../formatters/currency_formatter.dart';
import '../formatters/date_formatter.dart';
import 'reason_dialog.dart';

const _paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
  'lpo': 'LPO',
};

/// Shows what was sold, and lets the owner or the branch's manager void a
/// sale entered by mistake (with a reason). Returns true when it was voided,
/// so the caller can refresh its figures.
Future<bool> showSaleDetail(
  BuildContext context,
  SaleRecord sale, {
  required bool canVoid,
}) async {
  final voided = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SaleDetailSheet(sale: sale, canVoid: canVoid),
  );
  return voided ?? false;
}

class _SaleDetailSheet extends ConsumerStatefulWidget {
  const _SaleDetailSheet({required this.sale, required this.canVoid});

  final SaleRecord sale;
  final bool canVoid;

  @override
  ConsumerState<_SaleDetailSheet> createState() => _SaleDetailSheetState();
}

class _SaleDetailSheetState extends ConsumerState<_SaleDetailSheet> {
  bool _busy = false;

  Future<void> _void() async {
    final sale = widget.sale;
    final reason = await askReason(
      context,
      'Void sale #${sale.id}?',
      message:
          '${CurrencyFormatter.format(sale.total)} comes off the day\'s sales. '
          'Drinks and items go back into stock'
          '${sale.paymentMethod == 'account' ? ', and the customer\'s account is credited back' : ''}. '
          'The sale stays on record, marked as voided.',
      confirmLabel: 'Void sale',
      destructive: true,
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(salesRepositoryProvider).voidSale(sale.id, reason: reason);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sale #${sale.id} voided.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'Something went wrong.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sale #${sale.id}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (sale.isVoided) const _VoidedBadge(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (sale.storeName.isNotEmpty) sale.storeName,
                  DateFormatter.dateTime(sale.soldAt),
                  'by ${sale.soldByName}',
                ].join(' · '),
                style: muted,
              ),
              const Divider(height: 24),
              for (final line in sale.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 1),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(child: Text(line.name)),
                      Text(CurrencyFormatter.format(line.lineTotal)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _paymentLabels[sale.paymentMethod] ?? sale.paymentMethod,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(sale.total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      decoration: sale.isVoided
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ],
              ),
              if (sale.customerName != null)
                Text('Charged to ${sale.customerName}', style: muted),
              if (sale.isVoided) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Voided by ${sale.voidedByName ?? 'someone'} on '
                    '${DateFormatter.dateTime(sale.voidedAt!)}\n'
                    'Reason: ${sale.voidReason ?? '-'}',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ] else if (widget.canVoid) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _void,
                  icon: const Icon(Icons.block),
                  label: const Text('Void this sale'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  'Entered by mistake? Ask your manager to void it.',
                  style: muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoidedBadge extends StatelessWidget {
  const _VoidedBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'VOIDED',
        style: TextStyle(
          color: scheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// A one-line sale row for lists: voided sales are struck through.
class SaleListTile extends StatelessWidget {
  const SaleListTile({
    super.key,
    required this.sale,
    required this.onTap,
    this.showStore = false,
  });

  final SaleRecord sale;
  final VoidCallback onTap;
  final bool showStore;

  @override
  Widget build(BuildContext context) {
    final strike = sale.isVoided
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          [
            if (showStore) sale.storeName,
            CurrencyFormatter.format(sale.total),
          ].join(' — '),
          style: strike,
        ),
        subtitle: Text(
          [
            if (sale.lines.isNotEmpty) sale.lineSummary,
            '${_paymentLabels[sale.paymentMethod] ?? sale.paymentMethod} · '
                '${sale.soldByName} · ${DateFormatter.dateTime(sale.soldAt)}',
          ].join('\n'),
        ),
        isThreeLine: sale.lines.isNotEmpty,
        trailing: sale.isVoided
            ? const _VoidedBadge()
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}
