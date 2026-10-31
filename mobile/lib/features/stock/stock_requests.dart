import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/reports_repository.dart';
import '../../core/api/repositories/stock_repository.dart';
import '../../core/api/repositories/stock_requests_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/widgets/reason_dialog.dart';

String _num(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

const _statusLabels = {
  'open': 'Waiting',
  'sent': 'Sent',
  'declined': 'Declined',
  'cancelled': 'Cancelled',
};

Color _statusColor(String status) => switch (status) {
  'open' => const Color(0xFFB7791F),
  'sent' => AppColors.success,
  'declined' => AppColors.danger,
  _ => Colors.grey,
};

void _toast(BuildContext context, Object messageOrError) {
  final message = messageOrError is String
      ? messageOrError
      : messageOrError is ApiException
      ? messageOrError.message
      : 'Something went wrong.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// A request as a card: branch, what was asked, the answer.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    this.showBranch = false,
    this.actions = const [],
  });

  final StockRequest request;
  final bool showBranch;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final sent = request.status == 'sent';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showBranch
                        ? '${request.storeName} · #${request.id}'
                        : 'Request #${request.id}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(request.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabels[request.status] ?? request.status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              [
                DateFormatter.dateTime(request.createdAt),
                ?request.requestedByName,
              ].join(' · '),
              style: muted,
            ),
            if (request.note != null && request.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('“${request.note}”'),
              ),
            const SizedBox(height: 8),
            for (final line in request.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(line.itemName)),
                    Text(
                      sent && line.qtySent != null
                          ? '${_num(line.qtySent!)} of ${_num(line.qtyRequested)} ${line.unit}'
                          : '${_num(line.qtyRequested)} ${line.unit}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: sent && (line.qtySent ?? 0) < line.qtyRequested
                            ? AppColors.danger
                            : null,
                      ),
                    ),
                    if (request.isOpen &&
                        line.availableAtProcurement != null) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 84,
                        child: Text(
                          'has ${_num(line.availableAtProcurement!)}',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                line.availableAtProcurement! < line.qtyRequested
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (request.respondedAt != null &&
                request.status != 'cancelled') ...[
              const Divider(height: 20),
              Text(
                [
                  if (sent)
                    request.transferStatus == 'dispatched'
                        ? 'On the way: confirm it under Incoming when it arrives'
                        : 'Sent and received',
                  if (request.status == 'declined') 'Declined',
                  ?request.respondedByName,
                  DateFormatter.dateTime(request.respondedAt!),
                ].join(' · '),
                style: muted,
              ),
              if (request.responseNote != null &&
                  request.responseNote!.isNotEmpty)
                Text(
                  '“${request.responseNote}”',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Branch side: what this branch asked for, and asking for more.
class BranchRequestsTab extends ConsumerStatefulWidget {
  const BranchRequestsTab({super.key});

  @override
  ConsumerState<BranchRequestsTab> createState() => _BranchRequestsTabState();
}

class _BranchRequestsTabState extends ConsumerState<BranchRequestsTab> {
  late Future<List<StockRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(stockRequestsRepositoryProvider).list();
  }

  void _reload() => setState(
    () => _future = ref.read(stockRequestsRepositoryProvider).list(),
  );

  Future<void> _newRequest() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewRequestSheet(),
    );
    if (sent == true) _reload();
  }

  Future<void> _cancel(StockRequest request) async {
    try {
      await ref.read(stockRequestsRepositoryProvider).cancel(request.id);
      _reload();
    } catch (e) {
      if (mounted) _toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<StockRequest>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: FilledButton(
                onPressed: _reload,
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Missing something? Ask procurement. They send it as a '
                    'transfer, which you confirm under Incoming.',
                  ),
                ),
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No requests yet.')),
                  ),
                for (final request in requests)
                  _RequestCard(
                    request: request,
                    actions: [
                      if (request.isOpen)
                        TextButton(
                          onPressed: () => _cancel(request),
                          child: const Text('Cancel request'),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newRequest,
        icon: const Icon(Icons.playlist_add),
        label: const Text('Ask procurement'),
      ),
    );
  }
}

/// Pick items and quantities. Items at or below their re-order level are
/// listed first and ticked, so the usual request is two taps.
class _NewRequestSheet extends ConsumerStatefulWidget {
  const _NewRequestSheet();

  @override
  ConsumerState<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends ConsumerState<_NewRequestSheet> {
  List<StoreItemStatus> _items = [];
  final Map<int, TextEditingController> _qty = {};
  final _note = TextEditingController();
  String _query = '';
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    ref.read(stockRepositoryProvider).status().then((items) {
      if (!mounted) return;
      // Drinks are bought by the branch itself, not asked for.
      final food = items.where((i) => !i.isDrink).toList()
        ..sort((a, b) {
          if (a.needsReorder != b.needsReorder) return a.needsReorder ? -1 : 1;
          return a.itemName.compareTo(b.itemName);
        });
      setState(() {
        _items = food;
        _loading = false;
        for (final item in food.where((i) => i.needsReorder)) {
          // Suggest enough to get back to twice the re-order level.
          final suggest = (item.safetyStock * 2 - item.balance).clamp(
            1,
            double.infinity,
          );
          _qty[item.itemId] = TextEditingController(
            text: suggest.ceil().toString(),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final wanted = <int, double>{};
    _qty.forEach((itemId, controller) {
      final qty = double.tryParse(controller.text);
      if (qty != null && qty > 0) wanted[itemId] = qty;
    });
    if (wanted.isEmpty) {
      _toast(context, 'Enter a quantity for at least one item.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(stockRequestsRepositoryProvider)
          .create(wanted, note: _note.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
      _toast(context, 'Request sent to procurement.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final shown = _items
        .where((i) => query.isEmpty || i.itemName.toLowerCase().contains(query))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      expand: false,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask procurement',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Items to re-order are filled in. Change or clear any.',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search items',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final item = shown[index];
                        final controller = _qty.putIfAbsent(
                          item.itemId,
                          TextEditingController.new,
                        );
                        return ListTile(
                          title: Text(item.itemName),
                          subtitle: Text(
                            '${_num(item.balance)} here · re-order at ${_num(item.safetyStock)}',
                            style: TextStyle(
                              color: item.needsReorder
                                  ? AppColors.danger
                                  : null,
                            ),
                          ),
                          trailing: SizedBox(
                            width: 80,
                            child: TextField(
                              controller: controller,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: '0',
                                isDense: true,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'e.g. needed before Saturday',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                      label: const Text('Send request'),
                    ),
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

/// Procurement side: requests from every branch, open ones first.
class ProcurementRequestsTab extends ConsumerStatefulWidget {
  const ProcurementRequestsTab({super.key});

  @override
  ConsumerState<ProcurementRequestsTab> createState() =>
      _ProcurementRequestsTabState();
}

class _ProcurementRequestsTabState
    extends ConsumerState<ProcurementRequestsTab> {
  late Future<List<StockRequest>> _future;
  bool _openOnly = true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<StockRequest>> _load() => ref
      .read(stockRequestsRepositoryProvider)
      .list(status: _openOnly ? 'open' : null);

  void _reload() => setState(() => _future = _load());

  Future<void> _send(StockRequest request) async {
    final controllers = {
      for (final line in request.lines)
        line.id: TextEditingController(
          text: _num(
            line.availableAtProcurement == null
                ? line.qtyRequested
                : line.qtyRequested.clamp(0, line.availableAtProcurement!),
          ),
        ),
    };
    final note = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send to ${request.storeName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Leaves your stock now; the branch confirms on arrival.',
              ),
              const SizedBox(height: 8),
              for (final line in request.lines)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.itemName}\nasked ${_num(line.qtyRequested)}'
                        '${line.availableAtProcurement == null ? '' : ', you have ${_num(line.availableAtProcurement!)}'}',
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: controllers[line.id],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(suffixText: line.unit),
                      ),
                    ),
                  ],
                ),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note to the branch (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(stockRequestsRepositoryProvider).send(request.id, {
        for (final e in controllers.entries)
          e.key: double.tryParse(e.value.text) ?? 0,
      }, note: note.text.trim());
      if (!mounted) return;
      _toast(context, 'Sent to ${request.storeName}.');
      _reload();
    } catch (e) {
      if (mounted) _toast(context, e);
    }
  }

  Future<void> _decline(StockRequest request) async {
    final reason = await askReason(
      context,
      'Decline ${request.storeName}\'s request?',
      message: 'The branch sees your reason.',
      confirmLabel: 'Decline',
      destructive: true,
    );
    if (reason == null) return;
    try {
      await ref
          .read(stockRequestsRepositoryProvider)
          .decline(request.id, reason: reason);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) _toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Waiting'),
                selected: _openOnly,
                showCheckmark: false,
                onSelected: (_) {
                  _openOnly = true;
                  _reload();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All'),
                selected: !_openOnly,
                showCheckmark: false,
                onSelected: (_) {
                  _openOnly = false;
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<StockRequest>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: _reload,
                    child: const Text('Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final requests = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (requests.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            _openOnly
                                ? 'No branch is waiting on anything.'
                                : 'No requests yet.',
                          ),
                        ),
                      ),
                    for (final request in requests)
                      _RequestCard(
                        request: request,
                        showBranch: true,
                        actions: [
                          if (request.isOpen) ...[
                            TextButton(
                              onPressed: () => _decline(request),
                              child: const Text('Decline'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () => _send(request),
                              icon: const Icon(
                                Icons.local_shipping_outlined,
                                size: 18,
                              ),
                              label: const Text('Send'),
                            ),
                          ],
                        ],
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

/// Procurement's view of every branch's stock, items to re-order first.
class BranchStockTab extends ConsumerStatefulWidget {
  const BranchStockTab({super.key});

  @override
  ConsumerState<BranchStockTab> createState() => _BranchStockTabState();
}

class _BranchStockTabState extends ConsumerState<BranchStockTab> {
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
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load branch stock.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: () async => setState(
            () => _future = ref.read(reportsRepositoryProvider).stockStatus(),
          ),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final store in snapshot.data!)
                Builder(
                  builder: (context) {
                    final low =
                        store.items
                            .where((i) => i.balance <= i.safetyStock)
                            .toList()
                          ..sort((a, b) => a.balance.compareTo(b.balance));
                    return Card(
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(store.storeName),
                        subtitle: Text(
                          low.isEmpty
                              ? 'All stock sufficient'
                              : '${low.length} to re-order',
                          style: TextStyle(
                            color: low.isEmpty
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                        children: [
                          for (final item in low)
                            ListTile(
                              dense: true,
                              title: Text(item.itemName),
                              trailing: Text(
                                '${_num(item.balance)} / ${_num(item.safetyStock)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
