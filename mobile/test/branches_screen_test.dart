import 'dart:convert';
import 'dart:io';

import 'package:cream_pos/core/api/repositories/branch_reports_repository.dart';
import 'package:cream_pos/core/theme/app_theme.dart';
import 'package:cream_pos/features/branches/branches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Responses captured from the Laravel API's BranchReportTest data, so this
/// test also guards the JSON contract between backend and app.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

class _FakeBranchReports implements BranchReportsRepository {
  final requests = <String>[];

  @override
  Future<BranchesOverview> overview(ReportRange range) async {
    requests.add('overview:${range.name}');
    return BranchesOverview.fromJson(_fixture('branches'));
  }

  @override
  Future<BranchDetail> branch(int storeId, ReportRange range) async {
    requests.add('branch:$storeId:${range.name}');
    return BranchDetail.fromJson(_fixture('branch_detail'));
  }
}

final _mainList = find.byType(Scrollable).first;

void main() {
  testWidgets('owner sees every branch and can open one in detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _FakeBranchReports();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [branchReportsRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: AppTheme.backOffice(),
          home: const Scaffold(body: BranchesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UGX 236,000'), findsOneWidget);
    expect(find.text('Sales by day'), findsNothing, reason: 'Today is hourly');
    expect(find.text('Kira'), findsWidgets);
    expect(fake.requests, ['overview:today']);

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(fake.requests.last, 'overview:last7Days');

    final lugogoCard = find.widgetWithText(InkWell, 'Lugogo');
    await tester.scrollUntilVisible(lugogoCard, 200, scrollable: _mainList);
    await tester.ensureVisible(lugogoCard);
    await tester.pumpAndSettle();
    await tester.tap(lugogoCard);
    await tester.pumpAndSettle();

    expect(fake.requests.last, startsWith('branch:'));
    expect(find.text('UGX 111,000'), findsOneWidget);
    expect(find.text('HOW CUSTOMERS PAID'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('SALES BY STAFF'),
      300,
      scrollable: _mainList,
    );
    expect(find.text('Sarah'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('LATEST SALES'),
      300,
      scrollable: _mainList,
    );
    await tester.scrollUntilVisible(
      find.text('1× Plate'),
      200,
      scrollable: _mainList,
    );
    expect(find.text('1× Plate'), findsOneWidget);
  });

  testWidgets('branch screens fit a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchReportsRepositoryProvider.overrideWithValue(
            _FakeBranchReports(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.backOffice(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(body: BranchesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.widgetWithText(InkWell, 'Lugogo');
    await tester.scrollUntilVisible(card, 200, scrollable: _mainList);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('LATEST SALES'),
      300,
      scrollable: _mainList,
    );
    expect(tester.takeException(), isNull);
  });
}
