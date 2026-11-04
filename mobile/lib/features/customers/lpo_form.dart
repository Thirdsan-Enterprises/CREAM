import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/customers_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/models/customer.dart';

/// What an LPO can cover, as menu headings.
const lpoCovers = ['Lunch', 'Breakfast', 'Drinks'];

/// How money was paid, for deposits and opening payments.
const paidByOptions = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'bank': 'Bank',
};

/// The LPO being typed in: number, amount, plates and what it covers.
class LpoDraft {
  final number = TextEditingController();
  final amount = TextEditingController();
  final plates = TextEditingController();
  final covers = <String>{'Lunch'};

  void dispose() {
    number.dispose();
    amount.dispose();
    plates.dispose();
  }

  /// A message when something is missing, else null.
  String? get problem {
    if ((double.tryParse(amount.text) ?? 0) <= 0) {
      return 'Enter the LPO amount.';
    }
    if (covers.isEmpty) return 'Tick what the LPO covers.';
    return null;
  }

  Map<String, Object?> toJson() => {
    if (number.text.trim().isNotEmpty) 'number': number.text.trim(),
    'amount': double.parse(amount.text),
    if (int.tryParse(plates.text) case final p? when p > 0) 'plates': p,
    'covers': [
      for (final c in lpoCovers)
        if (covers.contains(c)) c,
    ],
  };
}

/// The LPO fields. [draft] holds what was typed.
class LpoFields extends StatefulWidget {
  const LpoFields({super.key, required this.draft});

  final LpoDraft draft;

  @override
  State<LpoFields> createState() => _LpoFieldsState();
}

class _LpoFieldsState extends State<LpoFields> {
  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final amount = double.tryParse(d.amount.text) ?? 0;
    final plates = int.tryParse(d.plates.text) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: d.number,
          decoration: const InputDecoration(
            labelText: 'LPO number',
            hintText: 'As written on the LPO',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: d.amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'LPO amount',
            prefixText: 'UGX ',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: d.plates,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Lunch plates included (optional)',
            helperText: amount > 0 && plates > 0
                ? '${CurrencyFormatter.format(amount / plates)} a plate. '
                      'Charging stops when the plates or the amount run out.'
                : 'Leave empty if the LPO is only an amount.',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text('It covers', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final c in lpoCovers)
              FilterChip(
                label: Text(c),
                selected: d.covers.contains(c),
                onSelected: (on) =>
                    setState(() => on ? d.covers.add(c) : d.covers.remove(c)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Records the next LPO an LPO customer brings. Returns true when saved.
Future<bool> showNewLpoDialog(
  BuildContext context,
  WidgetRef ref,
  Customer customer,
) async {
  final draft = LpoDraft();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) {
      String? error;
      var saving = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('New LPO for ${customer.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sales are charged to this LPO from now on. What was left '
                  'on the account carries on.',
                ),
                const SizedBox(height: 12),
                LpoFields(draft: draft),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.danger),
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
              onPressed: saving
                  ? null
                  : () async {
                      final problem = draft.problem;
                      if (problem != null) {
                        setState(() => error = problem);
                        return;
                      }
                      setState(() => saving = true);
                      final json = draft.toJson();
                      try {
                        await ref
                            .read(customersRepositoryProvider)
                            .addLpo(
                              customer.id,
                              number: json['number'] as String?,
                              amount: json['amount'] as double,
                              plates: json['plates'] as int?,
                              covers: (json['covers'] as List).cast<String>(),
                            );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setState(() {
                          saving = false;
                          error = e is ApiException
                              ? e.message
                              : 'Something went wrong.';
                        });
                      }
                    },
              child: const Text('Save LPO'),
            ),
          ],
        ),
      );
    },
  );
  draft.dispose();
  return saved ?? false;
}

/// The current LPO at a glance: amount used, plates left, what it covers.
class LpoCard extends StatelessWidget {
  const LpoCard({super.key, required this.lpo, this.onNew});

  final Lpo lpo;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platesLeft = lpo.platesLeft;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB9CCEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📄', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lpo.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onNew != null)
                TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add),
                  label: const Text('New LPO'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${CurrencyFormatter.format(lpo.amountUsed)} used of '
            '${CurrencyFormatter.format(lpo.amount)}',
          ),
          if (lpo.plates != null)
            Text(
              '${lpo.platesUsed} of ${lpo.plates} plates used · '
              '$platesLeft left',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: (platesLeft ?? 1) <= 0
                    ? AppColors.danger
                    : (platesLeft ?? 99) <= 5
                    ? AppColors.gold
                    : AppColors.success,
              ),
            ),
          Text(
            'Covers: ${lpo.covers.join(', ')}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
