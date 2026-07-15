import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../core/theme/app_theme.dart';
import '../customers/accounts_screen.dart';
import '../stock/stock_screen.dart';
import 'my_day_screen.dart';
import 'sell_screen.dart';

/// Outlet Terminal shell: Sell / Stock / Accounts / My Day, scoped to the
/// signed-in cashier/store manager/storekeeper's own store.
class OutletHomeScreen extends ConsumerStatefulWidget {
  const OutletHomeScreen({super.key});

  @override
  ConsumerState<OutletHomeScreen> createState() => _OutletHomeScreenState();
}

class _OutletHomeScreenState extends ConsumerState<OutletHomeScreen> {
  int _tabIndex = 0;

  static const _titles = ['Sell', 'Stock', 'Accounts', 'My Day'];
  static const _tabs = [
    SellScreen(),
    StockScreen(),
    AccountsScreen(),
    MyDayScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider).user;

    return Theme(
      data: AppTheme.outletTerminal(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(user?.store?.name ?? _titles[_tabIndex]),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authSessionProvider.notifier).logout(),
            ),
          ],
        ),
        body: IndexedStack(index: _tabIndex, children: _tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (index) => setState(() => _tabIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.point_of_sale),
              label: 'Sell',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              label: 'Stock',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'Accounts',
            ),
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              label: 'My Day',
            ),
          ],
        ),
      ),
    );
  }
}
