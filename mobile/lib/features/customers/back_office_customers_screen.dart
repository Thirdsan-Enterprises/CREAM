import 'package:flutter/material.dart';

import 'customers_view.dart';

/// Back Office → Customers: every branch's customers, following the branch
/// switcher.
class BackOfficeCustomersScreen extends StatelessWidget {
  const BackOfficeCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) => const CustomersView(owner: true);
}
