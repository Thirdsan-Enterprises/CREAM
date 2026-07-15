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
    required List<SaleLine> lines,
  }) {
    return _api.post(
      '/sales',
      data: {
        'payment_method': paymentMethod,
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
        if (storeId != null) 'store_id': storeId,
      },
    );
    return SaleSummary.fromJson(body);
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
        if (storeId != null) 'store_id': storeId,
        if (paymentMethod != null) 'payment_method': paymentMethod,
      },
    );
    return (body['data'] as List<dynamic>)
        .map((e) => SaleRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SaleRecord {
  SaleRecord({
    required this.id,
    required this.storeName,
    required this.soldByName,
    required this.paymentMethod,
    required this.total,
    required this.soldAt,
  });

  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
    id: json['id'] as int,
    storeName:
        (json['store'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    soldByName:
        (json['sold_by'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    paymentMethod: json['payment_method'] as String,
    total: double.parse(json['total'].toString()),
    soldAt: DateTime.parse(json['sold_at'] as String),
  );

  final int id;
  final String storeName;
  final String soldByName;
  final String paymentMethod;
  final double total;
  final DateTime soldAt;
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(apiClientProvider)),
);
