import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/user.dart';
import '../../core/theme/app_theme.dart';
import '../branches/branch_detail_screen.dart';
import '../customers/accounts_screen.dart';
import '../stock/stock_screen.dart';
import '../stock/stocking_screen.dart';
import 'my_day_screen.dart';
import 'sell_screen.dart';

/// One tab of the Outlet Terminal.
class _OutletTab {
  const _OutletTab(
    this.id,
    this.label,
    this.icon,
    this.build, {
    this.keep = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget Function() build;

  /// Keep the tab's state when the user visits another tab. Only Sell needs
  /// this, so a half-built order survives a trip to Stock. Every other tab
  /// is rebuilt on each visit to show current figures.
  final bool keep;
}

/// The tabs a person sees depend on what their role may do. The server
/// enforces the same rules, so a tab that would only ever be refused is not
/// shown at all.
List<_OutletTab> _tabsFor(User? user) {
  const sell = _OutletTab(
    'sell',
    'Sell',
    Icons.point_of_sale,
    SellScreen.new,
    keep: true,
  );
  const stock = _OutletTab(
    'stock',
    'Stock',
    Icons.inventory_2_outlined,
    StockScreen.new,
  );
  const stocking = _OutletTab(
    'stocking',
    'Stocking',
    Icons.local_shipping_outlined,
    StockingScreen.new,
  );
  const accounts = _OutletTab(
    'accounts',
    'Accounts',
    Icons.account_balance_wallet_outlined,
    AccountsScreen.new,
  );
  const myDay = _OutletTab(
    'day',
    'My Day',
    Icons.today_outlined,
    MyDayScreen.new,
  );

  switch (user?.role) {
    case UserRole.storekeeper:
      // Buys food and sends it to the branches; cannot sell.
      return const [stocking, stock];
    case UserRole.storeManager:
      // The manager of the main store also does the storekeeper's work.
      return [
        sell,
        stock,
        if (user?.store?.isMain ?? false) stocking,
        accounts,
        myDay,
      ];
    default:
      return const [sell, stock, accounts, myDay];
  }
}

/// The labels of the tabs [user] gets, in order (exposed for tests).
List<String> outletTabLabels(User? user) => [
  for (final tab in _tabsFor(user)) tab.label,
];

/// Outlet Terminal shell, scoped to the signed-in person's own branch.
class OutletHomeScreen extends ConsumerStatefulWidget {
  const OutletHomeScreen({super.key});

  @override
  ConsumerState<OutletHomeScreen> createState() => _OutletHomeScreenState();
}

class _OutletHomeScreenState extends ConsumerState<OutletHomeScreen> {
  int _tabIndex = 0;

  /// Bumped each time a tab is opened, so tabs that are not kept alive are
  /// rebuilt and fetch fresh figures instead of whatever was true when the
  /// app started.
  final _visits = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider).user;
    final tabs = _tabsFor(user);
    final index = _tabIndex.clamp(0, tabs.length - 1);

    return Theme(
      data: AppTheme.outletTerminal(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(user?.store?.name ?? tabs[index].label),
          actions: [
            if (user != null &&
                user.role == UserRole.storeManager &&
                user.store != null)
              IconButton(
                icon: const Icon(Icons.insights_outlined),
                tooltip: 'Branch performance',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BranchDetailScreen(
                      storeId: user.store!.id,
                      storeName: user.store!.name,
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: () => ref.read(authSessionProvider.notifier).logout(),
            ),
          ],
        ),
        body: IndexedStack(
          index: index,
          children: [
            for (final tab in tabs)
              tab.keep
                  ? tab.build()
                  : KeyedSubtree(
                      key: ValueKey('${tab.id}-${_visits[tab.id] ?? 0}'),
                      child: tab.build(),
                    ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() {
            _tabIndex = i;
            final id = tabs[i].id;
            _visits[id] = (_visits[id] ?? 0) + 1;
          }),
          destinations: [
            for (final tab in tabs)
              NavigationDestination(icon: Icon(tab.icon), label: tab.label),
          ],
        ),
      ),
    );
  }
}
