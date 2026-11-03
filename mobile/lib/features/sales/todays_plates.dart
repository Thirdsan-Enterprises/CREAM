import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/operations_repository.dart';
import '../../core/theme/app_colors.dart';

/// Today's plates: how many of each dish the kitchen prepared, sold and
/// has left. Type a number (e.g. 40) to add plates; each sale takes one
/// off, and tomorrow starts again from nothing. Returns true if saved.
Future<bool> showTodaysPlates(BuildContext context, {int? storeId}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => TodaysPlatesPanel(storeId: storeId),
  );
  return saved ?? false;
}

/// The plate counts for one branch. In a sheet (the Sell screen's Plates
/// button) it closes on save; on the Stocking screen ([inSheet] false) it
/// stays open and shows the new counts. Lunch is set by procurement and the
/// owner, so a branch sees its lunch counts without a field to change them.
class TodaysPlatesPanel extends ConsumerStatefulWidget {
  const TodaysPlatesPanel({super.key, this.storeId, this.inSheet = true});

  final int? storeId;
  final bool inSheet;

  @override
  ConsumerState<TodaysPlatesPanel> createState() => _TodaysPlatesPanelState();
}

class _TodaysPlatesPanelState extends ConsumerState<TodaysPlatesPanel> {
  List<DailyDish>? _dishes;
  String? _error;
  bool _saving = false;
  final Map<int, TextEditingController> _add = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _add.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dishes = await ref
          .read(operationsRepositoryProvider)
          .dailyPlates(storeId: widget.storeId);
      if (mounted) setState(() => _dishes = _editableFirst(dishes));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException ? e.message : 'Could not load.',
        );
      }
    }
  }

  Future<void> _save() async {
    final plates = <int, int>{};
    _add.forEach((id, c) {
      final n = int.tryParse(c.text.trim());
      if (n != null && n != 0) plates[id] = n;
    });
    if (plates.isEmpty) {
      if (widget.inSheet) Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      final dishes = await ref
          .read(operationsRepositoryProvider)
          .addPlates(plates, storeId: widget.storeId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Today's plates saved.")));
      if (widget.inSheet) {
        Navigator.pop(context, true);
      } else {
        for (final c in _add.values) {
          c.clear();
        }
        FocusScope.of(context).unfocus();
        setState(() {
          _dishes = _editableFirst(dishes);
          _saving = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
    final theme = Theme.of(context);
    final dishes = _dishes;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text("Today's plates", style: theme.textTheme.headlineSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              dishes != null && dishes.any((d) => !d.canSet)
                  ? 'Type how many were made today. Lunch plates are set by '
                        'procurement. Each sale takes one off.'
                  : 'Type how many were made today. Each sale takes one off; '
                        'tomorrow starts again from nothing.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(_error!)),
          if (dishes == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (dishes != null && dishes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No dishes are counted per day at this branch. The owner '
                'turns it on per dish in Settings > Prices & menu.',
              ),
            ),
          if (dishes != null && dishes.isNotEmpty)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final dish in dishes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dish.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Made ${_n(dish.prepared)} · sold ${_n(dish.sold)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  '${_n(dish.left)} left',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: dish.left <= 0
                                        ? AppColors.danger
                                        : AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!dish.canSet)
                            const SizedBox(
                              width: 96,
                              child: Text(
                                'Set by procurement',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12),
                              ),
                            )
                          else
                            SizedBox(
                              width: 96,
                              child: TextField(
                                controller: _add.putIfAbsent(
                                  dish.itemId,
                                  TextEditingController.new,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      signed: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^-?\d*'),
                                  ),
                                ],
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge,
                                decoration: InputDecoration(
                                  labelText: 'Add',
                                  hintText: '0',
                                  semanticCounterText: 'Plates of ${dish.name}',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed:
                    _saving || dishes == null || !dishes.any((d) => d.canSet)
                    ? null
                    : _save,
                child: const Text('Save plates'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What this person counts comes first (a branch's breakfast), then what
/// procurement set (lunch).
List<DailyDish> _editableFirst(List<DailyDish> dishes) => [
  ...dishes.where((d) => d.canSet),
  ...dishes.where((d) => !d.canSet),
];

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
