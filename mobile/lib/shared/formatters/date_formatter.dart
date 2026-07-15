import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static final _dayMonth = DateFormat('d MMM yyyy');
  static final _dayMonthTime = DateFormat('d MMM yyyy, h:mm a');

  static String date(DateTime value) => _dayMonth.format(value.toLocal());

  static String dateTime(DateTime value) =>
      _dayMonthTime.format(value.toLocal());
}
