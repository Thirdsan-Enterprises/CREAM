import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/auth_session.dart';
import '../api_client.dart';

double _n(Object? v) => (v as num?)?.toDouble() ?? 0;
final _day = DateFormat('yyyy-MM-dd');

/// One dish counted per day at a branch.
class DailyDish {
  DailyDish.fromJson(Map<String, dynamic> json)
    : itemId = json['item_id'] as int,
      name = json['name'] as String,
      category = json['category'] as String?,
      prepared = _n(json['prepared']),
      sold = _n(json['sold']),
      left = _n(json['left']),
      canSet = json['can_set'] as bool? ?? true;

  final int itemId;
  final bool canSet;
  final String name;
  final String? category;
  final double prepared;
  final double sold;
  final double left;
}

class Expense {
  Expense.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      amount = double.parse(json['amount'].toString()),
      category = json['category'] as String,
      note = json['note'] as String?,
      paidFrom = json['paid_from'] as String? ?? 'cash',
      spentAt = DateTime.parse(json['spent_at'] as String),
      recordedBy = json['recorded_by'] is Map
          ? (json['recorded_by'] as Map)['name'] as String?
          : json['recorded_by'] as String?,
      voided = json['voided_at'] != null;

  final int id;
  final double amount;
  final String category;
  final String? note;
  final String paidFrom;
  final DateTime spentAt;
  final String? recordedBy;
  final bool voided;
}

class DayLine {
  DayLine.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      category = json['category'] as String? ?? 'Other',
      qty = _n(json['qty']),
      revenue = _n(json['revenue']);

  final String name;
  final String category;
  final double qty;
  final double revenue;
}

/// One person's day (or a branch's): what the "My day" PDF is made from.
class DayReport {
  DayReport.fromJson(Map<String, dynamic> json)
    : date = DateTime.parse(json['date'] as String),
      branchWide = json['scope'] == 'branch',
      personName = (json['person'] as Map)['name'] as String,
      storeName = (json['store'] as Map?)?['name'] as String? ?? '',
      salesCount = (json['sales_count'] as num).toInt(),
      gross = _n(json['gross']),
      discounts = _n(json['discounts']),
      total = _n(json['total']),
      plates = _n(json['plates']),
      byPayment = {
        for (final p in json['by_payment'] as List<dynamic>)
          (p as Map)['method'] as String: _n(p['total']),
      },
      items = (json['items'] as List<dynamic>)
          .map((e) => DayLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      discountedSales = (json['discounted_sales'] as List<dynamic>)
          .map((e) => (_n((e as Map)['discount']), e['note'] as String? ?? ''))
          .toList(),
      cancelledSales = (json['cancelled_sales'] as List<dynamic>)
          .map((e) => (_n((e as Map)['total']), e['reason'] as String? ?? ''))
          .toList(),
      expenses = (json['expenses'] as List<dynamic>)
          .map((e) => Expense.fromJson(e as Map<String, dynamic>))
          .toList(),
      expensesTotal = _n(json['expenses_total']),
      cashSales = _n(json['cash_sales']),
      cashExpenses = _n(json['cash_expenses']),
      cashToHandOver = _n(json['cash_to_hand_over']);

  final DateTime date;
  final bool branchWide;
  final String personName;
  final String storeName;
  final int salesCount;
  final double gross;
  final double discounts;
  final double total;
  final double plates;
  final Map<String, double> byPayment;
  final List<DayLine> items;
  final List<(double, String)> discountedSales;
  final List<(double, String)> cancelledSales;
  final List<Expense> expenses;
  final double expensesTotal;
  final double cashSales;
  final double cashExpenses;
  final double cashToHandOver;
}

class PurchaseRow {
  PurchaseRow.fromJson(Map<String, dynamic> json)
    : occurredAt = DateTime.parse(json['occurred_at'] as String),
      item = json['item'] as String? ?? '',
      unit = json['unit'] as String? ?? '',
      category = json['category'] as String? ?? 'Other',
      qty = _n(json['qty']),
      unitCost = (json['unit_cost'] as num?)?.toDouble(),
      total = (json['total'] as num?)?.toDouble(),
      supplier = json['supplier'] as String?,
      store = json['store'] as String?,
      recordedBy = json['recorded_by'] as String?;

  final DateTime occurredAt;
  final String item;
  final String unit;
  final String category;
  final double qty;
  final double? unitCost;
  final double? total;
  final String? supplier;
  final String? store;
  final String? recordedBy;
}

class PurchaseLedger {
  PurchaseLedger.fromJson(Map<String, dynamic> json)
    : totalSpent = _n(json['total_spent']),
      purchases = (json['purchases'] as num).toInt(),
      withoutPrice = (json['without_price'] as num).toInt(),
      byCategory = [
        for (final c in json['by_category'] as List<dynamic>)
          ((c as Map)['category'] as String, _n(c['total'])),
      ],
      rows = (json['rows'] as List<dynamic>)
          .map((e) => PurchaseRow.fromJson(e as Map<String, dynamic>))
          .toList();

  final double totalSpent;
  final int purchases;
  final int withoutPrice;
  final List<(String, double)> byCategory;
  final List<PurchaseRow> rows;
}

/// Day-to-day branch operations: today's plates, expenses, the day report
/// and the procurement ledger.
class OperationsRepository {
  OperationsRepository(this._api);

  final ApiClient _api;

  Future<List<DailyDish>> dailyPlates({int? storeId}) async {
    final body = await _api.get('/daily-plates', query: {'store_id': ?storeId});
    return (body['dishes'] as List<dynamic>)
        .map((e) => DailyDish.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Adds plates prepared today; [plates] maps item id to how many
  /// (negative takes some off).
  Future<List<DailyDish>> addPlates(
    Map<int, int> plates, {
    int? storeId,
  }) async {
    final body = await _api.post(
      '/daily-plates',
      data: {
        'store_id': ?storeId,
        'items': [
          for (final e in plates.entries) {'item_id': e.key, 'qty': e.value},
        ],
      },
    );
    return (body['dishes'] as List<dynamic>)
        .map((e) => DailyDish.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<(List<Expense>, double, List<String>)> expenses({
    int? storeId,
    DateTime? from,
    DateTime? to,
  }) async {
    final body = await _api.get(
      '/expenses',
      query: {
        'store_id': ?storeId,
        if (from != null) 'from': _day.format(from),
        if (to != null) 'to': _day.format(to),
      },
    );
    return (
      (body['data'] as List<dynamic>)
          .map((e) => Expense.fromJson(e as Map<String, dynamic>))
          .toList(),
      _n(body['total']),
      (body['categories'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  Future<void> addExpense({
    required double amount,
    required String category,
    required String note,
    String paidFrom = 'cash',
    int? storeId,
  }) {
    return _api.post(
      '/expenses',
      data: {
        'amount': amount,
        'category': category,
        'note': note,
        'paid_from': paidFrom,
        'store_id': ?storeId,
      },
    );
  }

  Future<void> voidExpense(int id, {required String reason}) =>
      _api.post('/expenses/$id/void', data: {'reason': reason});

  Future<DayReport> myDay({DateTime? date, bool branch = false}) async {
    final body = await _api.get(
      '/reports/my-day',
      query: {
        if (date != null) 'date': _day.format(date),
        if (branch) 'scope': 'branch',
      },
    );
    return DayReport.fromJson(body);
  }

  Future<PurchaseLedger> purchases({DateTime? from, DateTime? to}) async {
    final body = await _api.get(
      '/purchases',
      query: {
        if (from != null) 'from': _day.format(from),
        if (to != null) 'to': _day.format(to),
      },
    );
    return PurchaseLedger.fromJson(body);
  }
}

final operationsRepositoryProvider = Provider<OperationsRepository>(
  (ref) => OperationsRepository(ref.watch(apiClientProvider)),
);

/// What a customer receipt shows.
class Receipt {
  Receipt.fromJson(Map<String, dynamic> json)
    : number = json['number'] as int,
      soldAt = DateTime.parse(json['sold_at'] as String),
      storeName = (json['store'] as Map)['name'] as String,
      storeAddress = (json['store'] as Map)['address'] as String?,
      storePhone = (json['store'] as Map)['phone'] as String?,
      cashier = json['cashier'] as String?,
      lines = [
        for (final l in json['lines'] as List<dynamic>)
          (
            (l as Map)['name'] as String,
            _n(l['qty']),
            _n(l['unit_price']),
            _n(l['total']),
          ),
      ],
      subtotal = _n(json['subtotal']),
      discount = _n(json['discount']),
      discountNote = json['discount_note'] as String?,
      total = _n(json['total']),
      paymentMethod = json['payment_method'] as String,
      customerName = (json['customer'] as Map?)?['name'] as String?,
      customerBalance = ((json['customer'] as Map?)?['balance'] as num?)
          ?.toDouble(),
      voided = json['voided'] as bool? ?? false;

  final int number;
  final DateTime soldAt;
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final String? cashier;

  /// (name, qty, unit price, line total)
  final List<(String, double, double, double)> lines;
  final double subtotal;
  final double discount;
  final String? discountNote;
  final double total;
  final String paymentMethod;
  final String? customerName;
  final double? customerBalance;
  final bool voided;
}

extension ReceiptApi on OperationsRepository {
  Future<Receipt> receipt(int saleId) async =>
      Receipt.fromJson(await _api.get('/sales/$saleId/receipt'));
}
