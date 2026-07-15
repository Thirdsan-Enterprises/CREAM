import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cream_pos/main.dart';

void main() {
  testWidgets('shows the splash screen while the session is resolving', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CreamPosApp()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
