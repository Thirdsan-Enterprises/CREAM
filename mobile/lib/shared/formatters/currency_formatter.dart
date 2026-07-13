import 'package:intl/intl.dart';

/// Formats amounts as "UGX 25,000" throughout the app.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final _format = NumberFormat.decimalPattern('en_US');

  static String format(num amount) => 'UGX ${_format.format(amount)}';
}
