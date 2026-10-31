import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/store.dart';
import '../../core/theme/app_theme.dart';
import 'sell_screen.dart';

/// Lets the owner ring up a sale on behalf of a branch. The owner chooses
/// the branch first; the sale, its stock and its takings then belong to that
/// branch, and the owner's name is recorded as the seller.
class OwnerSellScreen extends ConsumerStatefulWidget {
  const OwnerSellScreen({super.key});

  @override
  ConsumerState<OwnerSellScreen> createState() => _OwnerSellScreenState();
}

class _OwnerSellScreenState extends ConsumerState<OwnerSellScreen> {
  late final Future<List<Store>> _stores;
  int? _storeId;

  @override
  void initState() {
    super.initState();
    _storeId = ref.read(selectedStoreIdProvider);
    _stores = ref
        .read(storesRepositoryProvider)
        .all()
        .then((all) => all.where((s) => s.isActive && s.sells).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.outletTerminal(),
      child: Scaffold(
        body: FutureBuilder<List<Store>>(
          future: _stores,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final stores = snapshot.data!;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selling for',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // Wrapped, not scrolled, so the chosen branch is
                    // always in view however many branches there are.
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final store in stores)
                          ChoiceChip(
                            label: Text(store.name),
                            selected: _storeId == store.id,
                            onSelected: (_) =>
                                setState(() => _storeId = store.id),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: _storeId == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Choose the branch you are selling for.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      // A new SellScreen per branch, so an order for one
                      // branch is never carried over to another.
                      : SellScreen(key: ValueKey(_storeId), storeId: _storeId),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
