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
  Future<List<Drink>> drinks({int? storeId}) async => [
    Drink(
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
    expect(find.text('UGX 27,000'), findsOneWidget, reason: 'plate + 1 soda');
  });
}
