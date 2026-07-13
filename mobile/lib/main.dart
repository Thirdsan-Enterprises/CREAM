import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: CreamPosApp()));
}

class CreamPosApp extends ConsumerWidget {
  const CreamPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Cream POS',
      theme: AppTheme.outletTerminal(),
      darkTheme: AppTheme.backOffice(),
      routerConfig: router,
    );
  }
}
