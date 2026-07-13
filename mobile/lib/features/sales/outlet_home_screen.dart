import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';

/// Placeholder Outlet Terminal shell. Milestone 7 replaces this with the
/// Sell / Stock / Accounts / My Day tabbed experience.
class OutletHomeScreen extends ConsumerWidget {
  const OutletHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider).user;

    return Theme(
      data: AppTheme.outletTerminal(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(user?.store?.name ?? 'Cream POS'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authSessionProvider.notifier).logout(),
            ),
          ],
        ),
        body: Center(child: Text('Welcome, ${user?.name ?? ''}')),
      ),
    );
  }
}
