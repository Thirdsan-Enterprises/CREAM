import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/stock_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/models/stock_transfer.dart';
import '../../shared/pdf/cream_documents.dart';
import '../../shared/pdf/share_pdf.dart';

const _statusLabels = {
  'dispatched': 'On the way',
  'confirmed': 'Received',
  'discrepancy': 'Received, with differences',
};

Color _statusColor(String status) => switch (status) {
  'dispatched' => const Color(0xFFB7791F),
  'discrepancy' => AppColors.danger,
  _ => AppColors.success,
};

/// Opens the share/print choice for a transfer's receipt.
Future<void> offerTransferReceipt(
  BuildContext context,
  WidgetRef ref,
  StockTransfer transfer,
) {
  final printedBy = ref.read(authSessionProvider).user?.name ?? 'Cream POS';
  return offerPdf(
    context,
    title: 'Transfer receipt #${transfer.id}',
    filename:
        'cream-transfer-${transfer.id}-${transfer.toStoreName.toLowerCase().replaceAll(' ', '-')}.pdf',
    build: () => transferReceiptPdf(transfer, printedBy: printedBy),
  );
}

/// One transfer: route, when, status, and its receipt.
class TransferTile extends ConsumerWidget {
  const TransferTile({super.key, required this.transfer});

  final StockTransfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines = transfer.items.length;
    return Card(
      child: ListTile(
        title: Text('${transfer.fromStoreName} to ${transfer.toStoreName}'),
        subtitle: Text(
          [
            '#${transfer.id} · ${DateFormatter.dateTime(transfer.dispatchedAt)}',
            '$lines ${lines == 1 ? 'item' : 'items'} · '
                '${_statusLabels[transfer.status] ?? transfer.status}',
          ].join('\n'),
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
        leading: Icon(
          transfer.isReceived ? Icons.inventory_outlined : Icons.local_shipping,
          color: _statusColor(transfer.status),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          tooltip: 'Receipt',
          onPressed: () => offerTransferReceipt(context, ref, transfer),
        ),
        onTap: () => offerTransferReceipt(context, ref, transfer),
      ),
    );
  }
}

/// Every transfer the person may see (the owner follows the branch
/// switcher), with a receipt for each.
class TransfersListTab extends ConsumerStatefulWidget {
  const TransfersListTab({super.key});

  @override
  ConsumerState<TransfersListTab> createState() => _TransfersListTabState();
}

class _TransfersListTabState extends ConsumerState<TransfersListTab> {
  late Future<List<StockTransfer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<StockTransfer>> _load() => ref
      .read(stockRepositoryProvider)
      .transfers(storeId: ref.read(selectedStoreIdProvider));

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedStoreIdProvider, (_, _) {
      setState(() => _future = _load());
    });
    return FutureBuilder<List<StockTransfer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(
              onPressed: () => setState(() => _future = _load()),
              child: const Text('Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final transfers = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (transfers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No transfers yet.')),
                ),
              for (final transfer in transfers)
                TransferTile(transfer: transfer),
            ],
          ),
        );
      },
    );
  }
}
