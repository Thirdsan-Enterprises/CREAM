import 'package:cream_pos/core/api/api_client.dart';
import 'package:cream_pos/core/api/repositories/items_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/settings/prices_tab.dart';
import 'package:cream_pos/shared/models/item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePrices extends ItemsRepository {
  _FakePrices() : super(ApiClient());

  @override
  Future<PriceList> priceList() async => PriceList.fromJson({
    'plate': {
      'default': 25000,
      'branches': [
        {'store_id': 1, 'store_name': 'Kira', 'price': 25000, 'own': false},
        {'store_id': 3, 'store_name': 'Town', 'price': 15000, 'own': true},
      ],
    },
    'items': [
      {
        'item': {'id': 9, 'name': 'Tea', 'unit': 'cup', 'is_drink': false},
        'category': 'Breakfast',
        'tracks_stock': false,
        'is_active': true,
        'default': 1000,
        'branches': [
          {'store_id': 1, 'store_name': 'Kira', 'price': 1000, 'own': false},
          {'store_id': 3, 'store_name': 'Town', 'price': 1000, 'own': false},
        ],
      },
    ],
  });
}

void main() {
  testWidgets('the owner sees Town charges its own plate price', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [itemsRepositoryProvider.overrideWithValue(_FakePrices())],
        child: MaterialApp(
          theme: AppTheme.backOffice(),
          home: const Scaffold(body: PricesTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UGX 25,000'), findsOneWidget);
    expect(find.text('other branches'), findsOneWidget);
    expect(find.text('Town UGX 15,000'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Made to order'), findsOneWidget);

    // Tapping Town's chip opens the price sheet on Town, asking for a reason.
    await tester.tap(find.text('Town UGX 15,000'));
    await tester.pumpAndSettle();
    expect(find.text('Town (own price)'), findsOneWidget);
    expect(find.text('Charge the same as all branches'), findsOneWidget);
    expect(find.text('Reason for the change'), findsOneWidget);
  });
}
