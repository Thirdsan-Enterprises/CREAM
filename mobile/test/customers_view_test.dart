import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/customers/customers_view.dart';
import 'package:cream_pos/shared/models/customer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Customer _jane(String status, {String? warning}) => Customer.fromJson({
  'id': 1,
  'name': 'Jane',
  'phone': '0700000001',
  'account_type': 'credit',
  'credit_limit': '200000.00',
  'store_id': 3,
  'store': {'name': 'Town'},
  'is_active': true,
  'balance': -175000,
  'available': 25000,
  'credit_used_pct': 87.5,
  'status': status,
  'warning': warning,
});

void main() {
  testWidgets('a customer near the limit is flagged in the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.outletTerminal(),
        home: Scaffold(
          body: CustomerTile(
            customer: _jane('low'),
            showBranch: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Near limit'), findsOneWidget);
    expect(find.textContaining('Town'), findsOneWidget);
    expect(find.text('UGX -175,000'), findsOneWidget);
  });

  testWidgets('the warning banner explains what is left', (tester) async {
    final customer = _jane(
      'low',
      warning:
          'Jane has used 88% of the credit limit (UGX 200,000): UGX 25,000 left.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StandingBanner(standing: customer.standing!)),
      ),
    );
    expect(find.textContaining('88% of the credit limit'), findsOneWidget);
  });

  testWidgets('an account in good standing shows no badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerTile(customer: _jane('ok'), onTap: () {}),
        ),
      ),
    );
    expect(find.text('Near limit'), findsNothing);
    expect(find.text('At limit'), findsNothing);
  });
}
