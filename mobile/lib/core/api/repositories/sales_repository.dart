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

  Future<SaleSummary> summary({DateTime? from, DateTime? to}) async {
    final body = await _api.get(
      '/sales/summary',
      query: {
        if (from != null) 'from': from.toIso8601String().split('T').first,
        if (to != null) 'to': to.toIso8601String().split('T').first,
      },
    );
    return SaleSummary.fromJson(body);
  }
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(apiClientProvider)),
);
