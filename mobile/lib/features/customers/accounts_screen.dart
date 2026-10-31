import 'package:flutter/material.dart';

import 'customers_view.dart';

/// Outlet Terminal → Accounts: this branch's customers.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) => const CustomersView(owner: false);
}
