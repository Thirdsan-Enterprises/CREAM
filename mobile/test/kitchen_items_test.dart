import 'package:cream_pos/core/api/api_client.dart';
import 'package:cream_pos/core/api/repositories/items_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/stock/kitchen_items.dart';
import 'package:cream_pos/shared/models/item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Item _i(int id, String name, String? category, {bool active = true}) => Item(
  id: id,
  name: name,
  unit: 'packet',
  category: category,
  isDrink: false,
  isActive: active,
);

class _FakeItems extends ItemsRepository {
  _FakeItems() : super(ApiClient());

  String? removedWith;

  @override
  Future<List<Item>> items({
    bool includeRemoved = false,
    bool withDrinks = false,
  }) async => [
    _i(1, 'Serviettes', 'Packaging & disposables'),
    _i(2, 'Charcoal', 'Fuel'),
    _i(3, 'Rice', 'Food'),
    if (includeRemoved) _i(4, 'Oregano', 'Spices & seasoning', active: false),
  ];

  @override
  Future<String> removeItem(int itemId, {required String reason}) async {
    removedWith = reason;
    return 'Charcoal is removed from the lists; its history is kept.';
  }
}

void main() {
  testWidgets('procurement sees its list by heading and can remove an item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _FakeItems();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [itemsRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: AppTheme.outletTerminal(),
          home: const Scaffold(body: KitchenItemsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Food (1)'), findsOneWidget);
    expect(find.text('Packaging & disposables (1)'), findsOneWidget);
    expect(find.text('Fuel (1)'), findsOneWidget);
    expect(find.text('Oregano'), findsNothing);

    await tester.tap(find.text('Charcoal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from the list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Using gas only');
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(fake.removedWith, 'Using gas only');

    await tester.tap(find.text('Show removed items'));
    await tester.pumpAndSettle();
    expect(find.text('Oregano'), findsOneWidget);
  });
}
