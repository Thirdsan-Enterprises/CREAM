import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/operations_repository.dart';
import '../../core/api/repositories/sales_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/user.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/pdf/cream_documents.dart';
import '../../shared/pdf/share_pdf.dart';
import '../../shared/widgets/reason_dialog.dart';
import '../../shared/widgets/sale_detail_sheet.dart';

const _paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
  'lpo': 'LPO',
};

/// How long a cashier may still cancel their own sale (the server checks).
const _cancelMinutes = 15;

/// My Day: what I sold today (a manager can switch to the whole branch),
/// expenses paid from takings, the cash to hand over, today's sales (with
/// cancel for a recent mistake) and the day as a PDF.
class MyDayScreen extends ConsumerStatefulWidget {
  const MyDayScreen({super.key});

  @override
  ConsumerState<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends ConsumerState<MyDayScreen> {
  bool _branch = false;
  late Future<(DayReport, List<SaleRecord>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  User? get _me => ref.read(authSessionProvider).user;
  bool get _isManager => _me?.role == UserRole.storeManager;

  Future<(DayReport, List<SaleRecord>)> _load() async {
    final today = DateTime.now();
    final results = await Future.wait([
      ref.read(operationsRepositoryProvider).myDay(branch: _branch),
      ref.read(salesRepositoryProvider).list(from: today, to: today),
    ]);
    final report = results[0] as DayReport;
    var sales = results[1] as List<SaleRecord>;
    if (!_branch) {
      sales = sales.where((s) => s.soldById == _me?.id).toList();
    }
    return (report, sales);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  bool _canCancel(SaleRecord sale) {
    if (_isManager) return true;
    return sale.soldById == _me?.id &&
        DateTime.now().difference(sale.soldAt.toLocal()).inMinutes <
            _cancelMinutes;
  }

  Future<void> _addExpense() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ExpenseSheet(),
    );
    if (added == true) _reload();
  }

  Future<void> _voidExpense(Expense expense) async {
    final reason = await askReason(
      context,
      'Cancel this expense?',
      message:
          '${CurrencyFormatter.format(expense.amount)} · ${expense.category}: ${expense.note ?? ''}',
      confirmLabel: 'Cancel expense',
      destructive: true,
    );
    if (reason == null) return;
    try {
      await ref
          .read(operationsRepositoryProvider)
          .voidExpense(expense.id, reason: reason);
      _reload();
    } catch (e) {
      if (!mounted) return;
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
    final me = _me;
    return SafeArea(
      child: FutureBuilder<(DayReport, List<SaleRecord>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Could not load your day.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (day, sales) = snapshot.data!;
          final theme = Theme.of(context);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _branch ? 'Branch today' : 'My day',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => offerPdf(
                        context,
                        title: _branch
                            ? '${day.storeName}, today'
                            : '${day.personName}, today',
                        filename:
                            'cream-day-${day.date.toIso8601String().split('T').first}-'
                            '${(_branch ? day.storeName : day.personName).toLowerCase().replaceAll(' ', '-')}.pdf',
                        build: () =>
                            dayReportPdf(day, printedBy: me?.name ?? ''),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
                if (_isManager)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('My sales')),
                        ButtonSegment(value: true, label: Text('Whole branch')),
                      ],
                      selected: {_branch},
                      onSelectionChanged: (v) {
                        _branch = v.first;
                        _reload();
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                _HandOverCard(day: day),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _Stat('Sales', '${day.salesCount}')),
                    Expanded(
                      child: _Stat('Plates', day.plates.toStringAsFixed(0)),
                    ),
                    Expanded(
                      child: _Stat(
                        'Discounts',
                        CurrencyFormatter.format(day.discounts),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('How it was paid', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final method in _paymentLabels.keys)
                  if ((day.byPayment[method] ?? 0) > 0)
                    _Row(
                      _paymentLabels[method]!,
                      CurrencyFormatter.format(day.byPayment[method]!),
                    ),
                if (day.byPayment.isEmpty) const Text('No sales yet.'),
                const SizedBox(height: 16),
                Text('What was sold', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final line in day.items)
                  _Row(
                    '${line.qty.toStringAsFixed(0)} × ${line.name}',
                    CurrencyFormatter.format(line.revenue),
                  ),
                if (day.items.isEmpty) const Text('Nothing yet.'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Expenses',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (me?.mayRecordExpenses ?? false)
                      TextButton.icon(
                        onPressed: _addExpense,
                        icon: const Icon(Icons.add),
                        label: const Text('Add expense'),
                      ),
                  ],
                ),
                for (final e in day.expenses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${e.category}: ${e.note ?? ''}'),
                    subtitle: Text(
                      [
                        if (e.paidFrom != 'cash') _paymentLabels[e.paidFrom]!,
                        ?e.recordedBy,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      '−${CurrencyFormatter.format(e.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onLongPress: () => _voidExpense(e),
                  ),
                if (day.expenses.isEmpty)
                  Text(
                    (me?.mayRecordExpenses ?? false)
                        ? 'None. Transport or small items paid from the takings go here.'
                        : 'None.',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 16),
                Text("Today's sales", style: theme.textTheme.titleMedium),
                Text(
                  _isManager
                      ? 'Tap a sale to see it or cancel one entered by mistake.'
                      : 'Tap a sale to see it. You can cancel your own sale '
                            'for $_cancelMinutes minutes after making it.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (sales.isEmpty) const Text('No sales yet today.'),
                for (final sale in sales)
                  SaleListTile(
                    sale: sale,
                    onTap: () async {
                      final voided = await showSaleDetail(
                        context,
                        sale,
                        canVoid: _canCancel(sale),
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

/// Cash taken less cash paid out: what goes to the manager or the bank.
class _HandOverCard extends StatelessWidget {
  const _HandOverCard({required this.day});

  final DayReport day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: AppColors.charcoal,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales today',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.cream,
              ),
            ),
            Text(
              CurrencyFormatter.format(day.total),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppColors.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Divider(color: Colors.white24, height: 20),
            _light('Cash sales', CurrencyFormatter.format(day.cashSales)),
            _light(
              'Less cash expenses',
              '−${CurrencyFormatter.format(day.cashExpenses)}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cash to hand over',
                    style: TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  CurrencyFormatter.format(day.cashToHandOver),
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _light(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.cream)),
        ),
        Text(value, style: const TextStyle(color: AppColors.cream)),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Record money paid out of the takings.
class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet();

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  static const _categories = [
    'Transport',
    'Small purchases',
    'Staff allowance',
    'Repairs',
    'Other',
  ];
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = 'Transport';
  String _paidFrom = 'cash';
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount.');
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Say what the money was for.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(operationsRepositoryProvider)
          .addExpense(
            amount: amount,
            category: _category,
            note: _note.text.trim(),
            paidFrom: _paidFrom,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : 'Something went wrong.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add expense', style: Theme.of(context).textTheme.titleLarge),
            const Text('Money paid out of today\'s takings.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _categories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: 'UGX ',
              ),
            ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What for',
                hintText: 'e.g. boda for Peter to the market',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'momo', label: Text('MoMo')),
                ButtonSegment(value: 'airtel', label: Text('Airtel')),
              ],
              selected: {_paidFrom},
              onSelectionChanged: (v) => setState(() => _paidFrom = v.first),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save expense'),
            ),
          ],
        ),
      ),
    );
  }
}
