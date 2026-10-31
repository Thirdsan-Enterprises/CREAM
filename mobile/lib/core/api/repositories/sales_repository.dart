import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/sale.dart';
import '../../auth/auth_session.dart';
import '../api_client.dart';

class SalesRepository {
  SalesRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> createSale({
    required String paymentMethod,
    int? customerId,
    int? storeId,
    required List<SaleLine> lines,
  }) {
    return _api.post(
      '/sales',
      data: {
        'payment_method': paymentMethod,
        'store_id': ?storeId,
        if (customerId != null) 'customer_id': customerId,
        'lines': lines.map((l) => l.toJson()).toList(),
      },
    );
  }

  Future<SaleSummary> summary({
    DateTime? from,
    DateTime? to,
    int? storeId,
  }) async {
    final body = await _api.get(
      '/sales/summary',
      query: {
        if (from != null) 'from': from.toIso8601String().split('T').first,
        if (to != null) 'to': to.toIso8601String().split('T').first,
        'store_id': ?storeId,
      },
    );
    return SaleSummary.fromJson(body);
  }

  /// Voids a sale entered by mistake: stock goes back, an account charge
  /// is credited back, and the sale leaves the totals. Owner or the
  /// branch's manager only.
  Future<SaleRecord> voidSale(int saleId, {required String reason}) async {
    final body = await _api.post(
      '/sales/$saleId/void',
      data: {'reason': reason},
    );
    return SaleRecord.fromJson(body);
  }

  Future<List<SaleRecord>> list({
    DateTime? from,
    DateTime? to,
    int? storeId,
    String? paymentMethod,
  }) async {
    final body = await _api.get(
      '/sales',
      query: {
        if (from != null) 'from': from.toIso8601String().split('T').first,
        if (to != null) 'to': to.toIso8601String().split('T').first,
        'store_id': ?storeId,
        if (paymentMethod != null) 'payment_method': paymentMethod,
      },
    );
    return (body['data'] as List<dynamic>)
        .map((e) => SaleRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SaleRecordLine {
  SaleRecordLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory SaleRecordLine.fromJson(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>?;
    return SaleRecordLine(
      name: json['item_type'] == 'plate'
          ? 'Plate'
          : item?['name'] as String? ?? 'Item',
      qty: double.parse(json['qty'].toString()),
      unitPrice: double.parse(json['unit_price'].toString()),
      lineTotal: double.parse(json['line_total'].toString()),
    );
  }

  final String name;
  final double qty;
  final double unitPrice;
  final double lineTotal;
}

class SaleRecord {
  SaleRecord({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.soldByName,
    required this.paymentMethod,
    required this.total,
    required this.soldAt,
    this.customerName,
    this.lines = const [],
    this.voidedAt,
    this.voidedByName,
    this.voidReason,
  });

  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
    id: json['id'] as int,
    storeId: json['store_id'] as int? ?? 0,
    storeName:
        (json['store'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    soldByName:
        (json['sold_by'] is Map ? json['sold_by']['name'] as String? : null) ??
        '',
    customerName:
        (json['customer'] as Map<String, dynamic>?)?['name'] as String?,
    paymentMethod: json['payment_method'] as String,
    total: double.parse(json['total'].toString()),
    soldAt: DateTime.parse(json['sold_at'] as String),
    lines: ((json['items'] as List<dynamic>?) ?? const [])
        .map((e) => SaleRecordLine.fromJson(e as Map<String, dynamic>))
        .toList(),
    voidedAt: json['voided_at'] == null
        ? null
        : DateTime.parse(json['voided_at'] as String),
    voidedByName: (json['voided_by'] is Map
        ? json['voided_by']['name'] as String?
        : null),
    voidReason: json['void_reason'] as String?,
  );

  final int id;
  final int storeId;
  final String storeName;
  final String soldByName;
  final String? customerName;
  final String paymentMethod;
  final double total;
  final DateTime soldAt;
  final List<SaleRecordLine> lines;
  final DateTime? voidedAt;
  final String? voidedByName;
  final String? voidReason;

  bool get isVoided => voidedAt != null;

  /// "1 Plate · 2 Soda".
  String get lineSummary => lines
      .map((l) => '${l.qty.toStringAsFixed(l.qty % 1 == 0 ? 0 : 1)} ${l.name}')
      .join(' · ');
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(apiClientProvider)),
);
