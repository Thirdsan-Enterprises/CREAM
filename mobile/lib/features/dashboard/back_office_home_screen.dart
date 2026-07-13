import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';

/// Placeholder Back Office shell. Milestone 8 replaces this with the
/// Dashboard / Stocking / Sales / Catering / Customers / Reports / Settings
/// navigation.
class BackOfficeHomeScreen extends ConsumerWidget {
  const BackOfficeHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider).user;

    return Theme(
      data: AppTheme.backOffice(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Back Office'),
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
