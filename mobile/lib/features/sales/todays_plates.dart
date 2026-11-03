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
    builder: (_) => _TodaysPlatesSheet(storeId: storeId),
  );
  return saved ?? false;
}

class _TodaysPlatesSheet extends ConsumerStatefulWidget {
  const _TodaysPlatesSheet({this.storeId});

  final int? storeId;

  @override
  ConsumerState<_TodaysPlatesSheet> createState() => _TodaysPlatesSheetState();
}

class _TodaysPlatesSheetState extends ConsumerState<_TodaysPlatesSheet> {
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
      if (mounted) setState(() => _dishes = dishes);
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
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(operationsRepositoryProvider)
          .addPlates(plates, storeId: widget.storeId);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Today's plates saved.")));
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
              'Type how many plates the kitchen made. Each sale takes one off.',
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
                onPressed: _saving || dishes == null ? null : _save,
                child: const Text('Save plates'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
