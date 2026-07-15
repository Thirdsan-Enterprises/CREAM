import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/store.dart';
import '../../core/theme/app_theme.dart';
import '../catering/catering_screen.dart';
import '../customers/back_office_customers_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/back_office_sales_screen.dart';
import '../settings/settings_screen.dart';
import '../stock/stocking_screen.dart';
import 'dashboard_screen.dart';

const _sections = [
  ('Dashboard', Icons.dashboard_outlined, DashboardScreen()),
  ('Stocking', Icons.local_shipping_outlined, StockingScreen()),
  ('Sales', Icons.receipt_long_outlined, BackOfficeSalesScreen()),
  ('Catering', Icons.celebration_outlined, CateringScreen()),
  ('Customers', Icons.people_outline, BackOfficeCustomersScreen()),
  ('Reports', Icons.bar_chart_outlined, ReportsScreen()),
  ('Settings', Icons.settings_outlined, SettingsScreen()),
];

class BackOfficeHomeScreen extends ConsumerStatefulWidget {
  const BackOfficeHomeScreen({super.key});

  @override
  ConsumerState<BackOfficeHomeScreen> createState() =>
      _BackOfficeHomeScreenState();
}

class _BackOfficeHomeScreenState extends ConsumerState<BackOfficeHomeScreen> {
  int _sectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider).user;

    return Theme(
      data: AppTheme.backOffice(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sections[_sectionIndex].$1),
          actions: [
            const _StoreSwitcher(),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authSessionProvider.notifier).logout(),
            ),
          ],
        ),
        drawer: NavigationDrawer(
          selectedIndex: _sectionIndex,
          onDestinationSelected: (index) {
            setState(() => _sectionIndex = index);
            Navigator.of(context).pop();
          },
          children: [
            DrawerHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'CREAM',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
                  ),
                  Text(user?.name ?? ''),
                ],
              ),
            ),
            for (final section in _sections)
              NavigationDrawerDestination(
                icon: Icon(section.$2),
                label: Text(section.$1),
              ),
          ],
        ),
        body: IndexedStack(
          index: _sectionIndex,
          children: [for (final section in _sections) section.$3],
        ),
      ),
    );
  }
}

class _StoreSwitcher extends ConsumerWidget {
  const _StoreSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedStoreId = ref.watch(selectedStoreIdProvider);

    return FutureBuilder<List<Store>>(
      future: ref.read(storesRepositoryProvider).all(),
      builder: (context, snapshot) {
        final stores = snapshot.data ?? [];

        return PopupMenuButton<int?>(
          icon: const Icon(Icons.storefront_outlined),
          tooltip: 'Switch store',
          initialValue: selectedStoreId,
          onSelected: (value) =>
              ref.read(selectedStoreIdProvider.notifier).state = value,
          itemBuilder: (context) => [
            const PopupMenuItem(value: null, child: Text('All stores')),
            for (final store in stores)
              PopupMenuItem(value: store.id, child: Text(store.name)),
          ],
        );
      },
    );
  }
}
