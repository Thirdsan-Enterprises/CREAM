import 'package:cream_pos/core/api/api_client.dart';
import 'package:cream_pos/core/api/repositories/items_repository.dart';
import 'package:cream_pos/core/api/repositories/sales_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/sales/sell_screen.dart';
import 'package:cream_pos/shared/models/item.dart';
import 'package:cream_pos/shared/models/sale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Item _item(int id, String name, {bool drink = false}) => Item(
  id: id,
  name: name,
  unit: 'piece',
  category: null,
  isDrink: drink,
  isActive: true,
);

MenuEntry _entry(
  int id,
  String name,
  String category,
  double price, {
  double? balance,
  bool tracks = false,
}) => MenuEntry(
  item: _item(id, name, drink: category == 'Drinks'),
  price: price,
  category: category,
  tracksStock: tracks,
  balance: balance,
);

class _FakeItems extends ItemsRepository {
  _FakeItems(this.entries) : super(ApiClient());

  final List<MenuEntry> entries;

  @override
  Future<double> platePrice({int? storeId}) async => 25000;

  @override
  Future<List<MenuEntry>> menu({int? storeId}) async => entries;
}

class _FakeSales extends SalesRepository {
  _FakeSales() : super(ApiClient());

  List<SaleLine>? sent;
  String? method;

  @override
  Future<Map<String, dynamic>> createSale({
    required String paymentMethod,
    int? customerId,
    int? storeId,
    required List<SaleLine> lines,
  }) async {
    sent = lines;
    method = paymentMethod;
    return {'id': 1};
  }
}

final _townMenu = [
  _entry(1, 'Beef', 'Lunch', 10000),
  _entry(2, 'Fish', 'Lunch', 12000),
  _entry(3, 'Milk Tea', 'Breakfast', 3000),
  _entry(4, 'Chapati', 'Breakfast', 1500),
  _entry(5, 'Soda', 'Drinks', 1500, balance: 1, tracks: true),
  _entry(6, 'Water', 'Drinks', 1500, balance: 0, tracks: true),
];

Future<_FakeSales> _pump(
  WidgetTester tester,
  List<MenuEntry> menu, {
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sales = _FakeSales();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        itemsRepositoryProvider.overrideWithValue(_FakeItems(menu)),
        salesRepositoryProvider.overrideWithValue(sales),
      ],
      child: MaterialApp(
        theme: AppTheme.outletTerminal(),
        home: const Scaffold(body: SellScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sales;
}

Future<void> _heading(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(ChoiceChip, name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the menu shows under its headings with branch prices', (
    tester,
  ) async {
    await _pump(tester, _townMenu);
    for (final h in ['Lunch', 'Breakfast', 'Drinks']) {
      expect(find.widgetWithText(ChoiceChip, h), findsOneWidget);
    }
    await _heading(tester, 'Lunch');
    expect(find.text('Beef'), findsOneWidget);
    expect(find.text('UGX 10,000'), findsWidgets);
    expect(find.text('Milk Tea'), findsNothing, reason: 'only this heading');
    expect(find.text('Plate'), findsNothing, reason: 'lunch dishes replace it');
  });

  testWidgets('a lunch and breakfast order is rung up as one sale', (
    tester,
  ) async {
    final sales = await _pump(tester, _townMenu);
    await _heading(tester, 'Lunch');
    await tester.tap(find.text('Beef'));
    await tester.tap(find.text('Beef'));
    await _heading(tester, 'Breakfast');
    await tester.tap(find.text('Milk Tea'));
    await tester.pumpAndSettle();

    expect(find.text('2 Beef · 1 Milk Tea'), findsOneWidget);
    expect(find.text('UGX 23,000'), findsOneWidget);

    await tester.tap(find.text('Order (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(sales.method, 'cash');
    expect(sales.sent!.map((l) => (l.itemType, l.itemId, l.qty)).toList(), [
      ('item', 1, 2.0),
      ('item', 3, 1.0),
    ]);
    expect(find.text('Tap items to start an order'), findsOneWidget);
  });

  testWidgets('search finds an item under any heading', (tester) async {
    await _pump(tester, _townMenu);
    await tester.enterText(find.byType(TextField), 'chap');
    await tester.pumpAndSettle();
    expect(find.text('Chapati'), findsOneWidget);
    expect(find.text('Beef'), findsNothing);
  });

  testWidgets('a drink cannot be added beyond what is in stock', (
    tester,
  ) async {
    await _pump(tester, _townMenu);
    await _heading(tester, 'Drinks');
    expect(find.text('1 left'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    expect(find.text('Only 1 Soda in stock.'), findsOneWidget);
    expect(find.text('1 Soda'), findsOneWidget);

    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(
      find.text('Water is out of stock. Record the purchase first.'),
      findsOneWidget,
    );
  });

  testWidgets('a branch without lunch dishes sells the plain plate', (
    tester,
  ) async {
    final sales = await _pump(tester, [
      _entry(5, 'Soda', 'Drinks', 2000, balance: 10, tracks: true),
    ]);
    await _heading(tester, 'Lunch');
    expect(find.text('Plate'), findsOneWidget);
    await tester.tap(find.text('Plate'));
    await tester.pumpAndSettle();
    expect(find.text('UGX 25,000'), findsWidgets);
    await tester.tap(find.text('Order (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();
    expect(sales.sent!.single.itemType, 'plate');
  });

  testWidgets('on a tablet the order sits beside the menu', (tester) async {
    await _pump(tester, _townMenu, size: const Size(1200, 900));
    expect(find.text('Order'), findsOneWidget);
    expect(find.text('Tap items on the menu to add them.'), findsOneWidget);
    await _heading(tester, 'Lunch');
    await tester.tap(find.text('Fish'));
    await tester.pumpAndSettle();
    expect(find.text('UGX 12,000 each'), findsOneWidget);
  });
}
