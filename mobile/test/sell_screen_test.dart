import 'package:cream_pos/core/api/api_client.dart';
import 'package:cream_pos/core/api/repositories/items_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/sales/sell_screen.dart';
import 'package:cream_pos/shared/models/item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeItems extends ItemsRepository {
  _FakeItems() : super(ApiClient());

  @override
  Future<double> platePrice({int? storeId}) async => 25000;

  @override
  Future<List<MenuEntry>> menu({int? storeId}) async => [
    MenuEntry(
      item: Item(
        id: 7,
        name: 'Soda',
        unit: 'bottle',
        category: null,
        isDrink: true,
        isActive: true,
      ),
      price: 2000,
    ),
  ];
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  sellStockTests();
  breakfastTests();
  testWidgets('a drink stays readable once it has been added to the sale', (
    tester,
  ) async {
    // The test font draws every glyph as a wide square, so use a roomy screen.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = AppTheme.outletTerminal();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [itemsRepositoryProvider.overrideWithValue(_FakeItems())],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: SellScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();

    // The tile is now filled with the theme's dark container colour...
    final fill = theme.colorScheme.primaryContainer;
    // ...so its name and price must be drawn in a colour that stands out
    // against it (the bug was dark text on a dark tile, which hid both).
    for (final label in ['Soda', 'UGX 2,000']) {
      final text = tester.widget<Text>(find.text(label).first);
      final color = text.style?.color;
      expect(color, isNotNull, reason: '$label must set its own colour');
      expect(
        _contrast(color!, fill),
        greaterThan(4.5),
        reason: '$label is unreadable on the selected tile',
      );
    }
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('UGX 2,000'), findsWidgets, reason: 'a soda alone');
  });
}

class _FakeItemsWithStock extends ItemsRepository {
  _FakeItemsWithStock(this.stock) : super(ApiClient());

  final double stock;

  @override
  Future<double> platePrice({int? storeId}) async => 25000;

  @override
  Future<List<MenuEntry>> menu({int? storeId}) async => [
    MenuEntry(
      item: Item(
        id: 7,
        name: 'Soda',
        unit: 'bottle',
        category: null,
        isDrink: true,
        isActive: true,
      ),
      price: 2000,
      balance: stock,
    ),
  ];
}

Future<void> _pumpSell(WidgetTester tester, double stock) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        itemsRepositoryProvider.overrideWithValue(_FakeItemsWithStock(stock)),
      ],
      child: MaterialApp(
        theme: AppTheme.outletTerminal(),
        home: const Scaffold(body: SellScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void sellStockTests() {
  testWidgets('a drink tile says how many are left', (tester) async {
    await _pumpSell(tester, 3);
    expect(find.text('3 left'), findsOneWidget);
  });

  testWidgets('a drink cannot be added beyond what is in stock', (
    tester,
  ) async {
    await _pumpSell(tester, 1);

    await tester.tap(find.byTooltip('One more plate'));
    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    expect(find.text('UGX 27,000'), findsOneWidget, reason: 'plate + 1 soda');

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    expect(find.text('Only 1 Soda in stock.'), findsOneWidget);
    expect(find.text('UGX 27,000'), findsOneWidget, reason: 'still one soda');
  });

  testWidgets('a drink with none in stock says so and cannot be added', (
    tester,
  ) async {
    await _pumpSell(tester, 0);
    expect(find.text('Out of stock'), findsOneWidget);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    expect(
      find.text('Soda is out of stock. Record the purchase first.'),
      findsOneWidget,
    );
    expect(find.text('Nothing added yet'), findsOneWidget);
  });
}

class _FakeBreakfastMenu extends ItemsRepository {
  _FakeBreakfastMenu() : super(ApiClient());

  @override
  Future<double> platePrice({int? storeId}) async => 15000;

  @override
  Future<List<MenuEntry>> menu({int? storeId}) async => [
    MenuEntry(
      item: Item(
        id: 21,
        name: 'Tea',
        unit: 'cup',
        category: null,
        isDrink: false,
        isActive: true,
      ),
      price: 1000,
      category: 'Breakfast',
      tracksStock: false,
    ),
    MenuEntry(
      item: Item(
        id: 22,
        name: 'Egg',
        unit: 'piece',
        category: null,
        isDrink: false,
        isActive: true,
      ),
      price: 1500,
      category: 'Breakfast',
      balance: 30,
    ),
  ];
}

void breakfastTests() {
  testWidgets('breakfast items sell on their own, without a plate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(_FakeBreakfastMenu()),
        ],
        child: MaterialApp(
          theme: AppTheme.outletTerminal(),
          home: const Scaffold(body: SellScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('30 left'), findsOneWidget, reason: 'eggs are counted');

    await tester.tap(find.text('Tea'));
    await tester.tap(find.text('Tea'));
    await tester.tap(find.text('Egg'));
    await tester.pumpAndSettle();

    expect(find.text('2 Tea · 1 Egg'), findsOneWidget);
    expect(find.text('UGX 3,500'), findsOneWidget);
  });
}
