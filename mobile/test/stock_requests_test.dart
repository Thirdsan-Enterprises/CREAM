import 'package:cream_pos/core/api/api_client.dart';
import 'package:cream_pos/core/api/repositories/stock_requests_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/stock/stock_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRequests extends StockRequestsRepository {
  _FakeRequests() : super(ApiClient());

  String? declinedWith;

  @override
  Future<List<StockRequest>> list({String? status, int? storeId}) async => [
    StockRequest.fromJson({
      'id': 7,
      'store_id': 3,
      'store': {'name': 'Town'},
      'requested_by': {'name': 'Grace'},
      'status': 'open',
      'note': 'For the weekend',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'items': [
        {
          'id': 1,
          'item_id': 11,
          'item': {'name': 'Rice', 'unit': 'kg'},
          'qty_requested': '20.00',
          'available_at_procurement': 50,
        },
        {
          'id': 2,
          'item_id': 12,
          'item': {'name': 'Cooking oil', 'unit': 'litre'},
          'qty_requested': '10.00',
          'available_at_procurement': 4,
        },
      ],
    }),
  ];

  @override
  Future<void> decline(int requestId, {required String reason}) async {
    declinedWith = reason;
  }
}

void main() {
  testWidgets('procurement sees what a branch asked for and what it has', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _FakeRequests();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [stockRequestsRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: AppTheme.backOffice(),
          home: const Scaffold(body: ProcurementRequestsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Town · #7'), findsOneWidget);
    expect(find.text('“For the weekend”'), findsOneWidget);
    expect(find.text('20 kg'), findsOneWidget);
    expect(find.text('has 50'), findsOneWidget);
    expect(find.text('has 4'), findsOneWidget, reason: 'short on oil');

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Oil comes Monday');
    await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
    await tester.pumpAndSettle();
    expect(fake.declinedWith, 'Oil comes Monday');
  });
}
