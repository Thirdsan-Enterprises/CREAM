import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/auth_session.dart';
import '../api_client.dart';

double _num(dynamic value) => (value as num?)?.toDouble() ?? 0;

/// Preset reporting windows offered on the Branches screens. Days are the
/// device's local days, which for Cream's devices is Kampala time — the
/// same zone the API buckets sales into.
enum ReportRange {
  today('Today'),
  yesterday('Yesterday'),
  last7Days('7 days'),
  last30Days('30 days'),
  thisMonth('This month');

  const ReportRange(this.label);

  final String label;

  ({DateTime from, DateTime to}) resolve([DateTime? now]) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    switch (this) {
      case ReportRange.today:
        return (from: today, to: today);
      case ReportRange.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return (from: yesterday, to: yesterday);
      case ReportRange.last7Days:
        return (from: today.subtract(const Duration(days: 6)), to: today);
      case ReportRange.last30Days:
        return (from: today.subtract(const Duration(days: 29)), to: today);
      case ReportRange.thisMonth:
        return (from: DateTime(today.year, today.month), to: today);
    }
  }

  /// How the comparison period reads in a sentence ("vs yesterday").
  String get comparisonLabel {
    switch (this) {
      case ReportRange.today:
        return 'vs yesterday';
      case ReportRange.yesterday:
        return 'vs the day before';
      case ReportRange.last7Days:
        return 'vs previous 7 days';
      case ReportRange.last30Days:
        return 'vs previous 30 days';
      case ReportRange.thisMonth:
        return 'vs same number of days before';
    }
  }
}

class BranchTotals {
  BranchTotals.fromJson(Map<String, dynamic> json)
    : revenue = _num(json['revenue']),
      previousRevenue = _num(json['previous_revenue']),
      changePct = (json['change_pct'] as num?)?.toDouble(),
      salesCount = (json['sales_count'] as num?)?.toInt() ?? 0,
      averageSale = _num(json['average_sale']),
      platesSold = _num(json['plates_sold']),
      plateRevenue = _num(json['plate_revenue']),
      drinksSold = _num(json['drinks_sold']),
      drinkRevenue = _num(json['drink_revenue']);

  final double revenue;
  final double previousRevenue;

  /// Null when the previous period had no sales to compare against.
  final double? changePct;
  final int salesCount;
  final double averageSale;
  final double platesSold;
  final double plateRevenue;
  final double drinksSold;
  final double drinkRevenue;
}

/// One bar of a daily or hourly series. [byStore] is only filled on the
/// all-branches overview, keyed by store id.
class SeriesPoint {
  SeriesPoint({
    required this.key,
    required this.revenue,
    required this.salesCount,
    required this.byStore,
  });

  factory SeriesPoint.fromJson(Map<String, dynamic> json, String key) {
    final rawByStore = json['by_store'];
    return SeriesPoint(
      key: key,
      revenue: _num(json['revenue']),
      salesCount: (json['sales_count'] as num?)?.toInt() ?? 0,
      byStore: rawByStore is Map
          ? rawByStore.map((k, v) => MapEntry(int.parse('$k'), _num(v)))
          : const {},
    );
  }

  /// "2026-10-02" for a day, "13" for an hour.
  final String key;
  final double revenue;
  final int salesCount;
  final Map<int, double> byStore;
}

class BranchSummary {
  BranchSummary.fromJson(Map<String, dynamic> json)
    : storeId = json['store_id'] as int,
      storeName = json['store_name'] as String,
      isMain = json['is_main'] as bool? ?? false,
      totals = BranchTotals.fromJson(json),
      sharePct = _num(json['share_pct']),
      byPaymentMethod = (json['by_payment_method'] is Map)
          ? (json['by_payment_method'] as Map).map(
              (k, v) => MapEntry('$k', _num(v)),
            )
          : const {},
      reorderItemsCount = (json['reorder_items_count'] as num?)?.toInt() ?? 0,
      lastSaleAt = json['last_sale_at'] != null
          ? DateTime.parse(json['last_sale_at'] as String)
          : null;

  final int storeId;
  final String storeName;
  final bool isMain;
  final BranchTotals totals;
  final double sharePct;
  final Map<String, double> byPaymentMethod;
  final int reorderItemsCount;
  final DateTime? lastSaleAt;
}

class BranchesOverview {
  BranchesOverview.fromJson(Map<String, dynamic> json)
    : days = (json['period']['days'] as num).toInt(),
      totals = BranchTotals.fromJson(json['totals'] as Map<String, dynamic>),
      daily = (json['daily'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return SeriesPoint.fromJson(m, m['date'] as String);
      }).toList(),
      hourly = (json['hourly'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return SeriesPoint.fromJson(m, '${m['hour']}');
      }).toList(),
      branches = (json['branches'] as List<dynamic>)
          .map((e) => BranchSummary.fromJson(e as Map<String, dynamic>))
          .toList();

  final int days;
  final BranchTotals totals;
  final List<SeriesPoint> daily;
  final List<SeriesPoint> hourly;
  final List<BranchSummary> branches;
}

class NamedAmount {
  NamedAmount({
    required this.name,
    required this.revenue,
    required this.count,
    this.extra = 0,
  });

  final String name;
  final double revenue;

  /// Sales count for payment methods and cashiers, quantity for drinks.
  final double count;

  /// Plates sold, for cashiers.
  final double extra;
}

class StockUse {
  StockUse.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      unit = json['unit'] as String? ?? '',
      isDrink = json['is_drink'] as bool? ?? false,
      qty = _num(json['qty']);

  final String name;
  final String unit;
  final bool isDrink;
  final double qty;
}

class ReorderItem {
  ReorderItem.fromJson(Map<String, dynamic> json)
    : name = json['item_name'] as String,
      balance = _num(json['balance']),
      safetyStock = _num(json['safety_stock']);

  final String name;
  final double balance;
  final double safetyStock;
}

class RecentSale {
  RecentSale.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      total = _num(json['total']),
      paymentMethod = json['payment_method'] as String,
      soldAt = DateTime.parse(json['sold_at'] as String),
      soldBy = json['sold_by'] as String?,
      customer = json['customer'] as String?,
      summary = json['summary'] as String? ?? '';

  final int id;
  final double total;
  final String paymentMethod;
  final DateTime soldAt;
  final String? soldBy;
  final String? customer;
  final String summary;
}

class BranchDetail {
  BranchDetail.fromJson(Map<String, dynamic> json)
    : storeName = json['store']['name'] as String,
      isMain = json['store']['is_main'] as bool? ?? false,
      days = (json['period']['days'] as num).toInt(),
      totals = BranchTotals.fromJson(json['totals'] as Map<String, dynamic>),
      daily = (json['daily'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return SeriesPoint.fromJson(m, m['date'] as String);
      }).toList(),
      hourly = (json['hourly'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return SeriesPoint.fromJson(m, '${m['hour']}');
      }).toList(),
      paymentMethods = (json['by_payment_method'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return NamedAmount(
          name: m['method'] as String,
          revenue: _num(m['revenue']),
          count: _num(m['sales_count']),
        );
      }).toList(),
      cashiers = (json['by_cashier'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return NamedAmount(
          name: m['name'] as String,
          revenue: _num(m['revenue']),
          count: _num(m['sales_count']),
          extra: _num(m['plates_sold']),
        );
      }).toList(),
      drinks = (json['drinks'] as List<dynamic>).map((e) {
        final m = e as Map<String, dynamic>;
        return NamedAmount(
          name: m['name'] as String,
          revenue: _num(m['revenue']),
          count: _num(m['qty']),
        );
      }).toList(),
      stockUsed = (json['stock_used'] as List<dynamic>)
          .map((e) => StockUse.fromJson(e as Map<String, dynamic>))
          .toList(),
      reorderCount = (json['stock']['reorder_count'] as num).toInt(),
      sufficientCount = (json['stock']['sufficient_count'] as num).toInt(),
      reorderItems = (json['stock']['reorder_items'] as List<dynamic>)
          .map((e) => ReorderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      transfersReceived = (json['transfers']['received'] as num).toInt(),
      transfersWithDiscrepancy = (json['transfers']['with_discrepancy'] as num)
          .toInt(),
      transfersAwaiting = (json['transfers']['awaiting_confirmation'] as num)
          .toInt(),
      recentSales = (json['recent_sales'] as List<dynamic>)
          .map((e) => RecentSale.fromJson(e as Map<String, dynamic>))
          .toList();

  final String storeName;
  final bool isMain;
  final int days;
  final BranchTotals totals;
  final List<SeriesPoint> daily;
  final List<SeriesPoint> hourly;
  final List<NamedAmount> paymentMethods;
  final List<NamedAmount> cashiers;
  final List<NamedAmount> drinks;
  final List<StockUse> stockUsed;
  final int reorderCount;
  final int sufficientCount;
  final List<ReorderItem> reorderItems;
  final int transfersReceived;
  final int transfersWithDiscrepancy;
  final int transfersAwaiting;
  final List<RecentSale> recentSales;
}

class BranchReportsRepository {
  BranchReportsRepository(this._api);

  final ApiClient _api;

  static final _date = DateFormat('yyyy-MM-dd');

  Map<String, String> _query(ReportRange range) {
    final period = range.resolve();
    return {'from': _date.format(period.from), 'to': _date.format(period.to)};
  }

  Future<BranchesOverview> overview(ReportRange range) async {
    final body = await _api.get('/reports/branches', query: _query(range));
    return BranchesOverview.fromJson(body);
  }

  Future<BranchDetail> branch(int storeId, ReportRange range) async {
    final body = await _api.get(
      '/reports/branches/$storeId',
      query: _query(range),
    );
    return BranchDetail.fromJson(body);
  }
}

final branchReportsRepositoryProvider = Provider<BranchReportsRepository>(
  (ref) => BranchReportsRepository(ref.watch(apiClientProvider)),
);

final branchesOverviewProvider = FutureProvider.autoDispose
    .family<BranchesOverview, ReportRange>(
      (ref, range) =>
          ref.watch(branchReportsRepositoryProvider).overview(range),
    );

final branchDetailProvider = FutureProvider.autoDispose
    .family<BranchDetail, ({int storeId, ReportRange range})>(
      (ref, args) => ref
          .watch(branchReportsRepositoryProvider)
          .branch(args.storeId, args.range),
    );
