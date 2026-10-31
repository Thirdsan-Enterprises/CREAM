import 'package:cream_pos/core/api/repositories/edit_logs_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/changes/changes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a change shows before, after, who and why', (tester) async {
    final entry = EditLogEntry.fromJson({
      'id': 1,
      'user': {'name': 'Owner'},
      'store': {'name': 'Town'},
      'subject_type': 'plate_price',
      'subject_label': 'Plate price at Town',
      'action': 'price_changed',
      'changes': {
        'price': {'from': 25000, 'to': 15000},
      },
      'reason': 'Town customers pay less',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.backOffice(),
        home: Scaffold(body: ChangeCard(entry: entry)),
      ),
    );

    expect(find.text('Plate price at Town'), findsOneWidget);
    expect(find.text('Price changed'), findsOneWidget);
    expect(
      find.textContaining('UGX 25,000', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('UGX 15,000', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('“Town customers pay less”'), findsOneWidget);
    expect(find.textContaining('Owner'), findsOneWidget);
    expect(find.textContaining('Town', findRichText: true), findsWidgets);
  });
}
