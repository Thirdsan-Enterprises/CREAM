import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/stock_transfer.dart';
import '../../auth/auth_session.dart';
import '../api_client.dart';

class StockRepository {
  StockRepository(this._api);

  final ApiClient _api;

  Future<List<StoreItemStatus>> status() async {
    final body = await _api.get('/stock/status');
    return (body['items'] as List<dynamic>)
        .map((e) => StoreItemStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordConsumption({
    required int itemId,
    required double qty,
    String? note,
  }) {
    return _api.post(
      '/stock/consumption',
      data: {'item_id': itemId, 'qty': qty, if (note != null) 'note': note},
    );
  }

  Future<List<StockTransfer>> incomingTransfers() async {
    final body = await _api.get('/transfers', query: {'status': 'dispatched'});
    return (body['data'] as List<dynamic>)
        .map((e) => StockTransfer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StockTransfer> confirmTransfer({
    required int transferId,
    required List<Map<String, dynamic>> items,
  }) async {
    final body = await _api.post(
      '/transfers/$transferId/confirm',
      data: {'items': items},
    );
    return StockTransfer.fromJson(body);
  }
}

class StoreItemStatus {
  StoreItemStatus({
    required this.itemId,
    required this.itemName,
    required this.balance,
    required this.safetyStock,
    required this.status,
  });

  factory StoreItemStatus.fromJson(Map<String, dynamic> json) =>
      StoreItemStatus(
        itemId: json['item_id'] as int,
        itemName: json['item_name'] as String,
        balance: (json['balance'] as num).toDouble(),
        safetyStock: (json['safety_stock'] as num).toDouble(),
        status: json['status'] as String,
      );

  final int itemId;
  final String itemName;
  final double balance;
  final double safetyStock;
  final String status;

  bool get needsReorder => status == 'Re-Order';
}

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(ref.watch(apiClientProvider)),
);
