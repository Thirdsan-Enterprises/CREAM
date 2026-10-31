import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_session.dart';
import '../api_client.dart';

class StockRequestLine {
  StockRequestLine.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      itemId = json['item_id'] as int,
      itemName =
          (json['item'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      unit = (json['item'] as Map<String, dynamic>?)?['unit'] as String? ?? '',
      qtyRequested = double.parse(json['qty_requested'].toString()),
      qtySent = json['qty_sent'] == null
          ? null
          : double.parse(json['qty_sent'].toString()),
      availableAtProcurement = (json['available_at_procurement'] as num?)
          ?.toDouble();

  final int id;
  final int itemId;
  final String itemName;
  final String unit;
  final double qtyRequested;
  final double? qtySent;

  /// What the procurement unit has on hand now (open requests only).
  final double? availableAtProcurement;
}

/// A branch asking the procurement unit for items it is missing.
class StockRequest {
  StockRequest.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      storeId = json['store_id'] as int,
      storeName =
          (json['store'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      requestedByName =
          (json['requested_by'] as Map<String, dynamic>?)?['name'] as String?,
      respondedByName =
          (json['responded_by'] as Map<String, dynamic>?)?['name'] as String?,
      status = json['status'] as String,
      note = json['note'] as String?,
      responseNote = json['response_note'] as String?,
      createdAt = DateTime.parse(json['created_at'] as String),
      respondedAt = json['responded_at'] == null
          ? null
          : DateTime.parse(json['responded_at'] as String),
      transferStatus =
          (json['transfer'] as Map<String, dynamic>?)?['status'] as String?,
      lines = ((json['items'] as List<dynamic>?) ?? const [])
          .map((e) => StockRequestLine.fromJson(e as Map<String, dynamic>))
          .toList();

  final int id;
  final int storeId;
  final String storeName;
  final String? requestedByName;
  final String? respondedByName;
  final String status; // open, sent, declined, cancelled
  final String? note;
  final String? responseNote;
  final DateTime createdAt;
  final DateTime? respondedAt;

  /// dispatched (on the way) or confirmed/discrepancy (arrived).
  final String? transferStatus;
  final List<StockRequestLine> lines;

  bool get isOpen => status == 'open';
}

class StockRequestsRepository {
  StockRequestsRepository(this._api);

  final ApiClient _api;

  Future<List<StockRequest>> list({String? status, int? storeId}) async {
    final body = await _api.get(
      '/stock-requests',
      query: {'status': ?status, 'store_id': ?storeId},
    );
    return (body['data'] as List<dynamic>)
        .map((e) => StockRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [items] maps item id to quantity wanted.
  Future<void> create(Map<int, double> items, {String? note, int? storeId}) {
    return _api.post(
      '/stock-requests',
      data: {
        'items': [
          for (final e in items.entries) {'item_id': e.key, 'qty': e.value},
        ],
        if (note != null && note.isNotEmpty) 'note': note,
        'store_id': ?storeId,
      },
    );
  }

  /// Sends the request as a transfer. [qtys] maps request line id to the
  /// quantity sent (0 = none of that line).
  Future<void> send(int requestId, Map<int, double> qtys, {String? note}) {
    return _api.post(
      '/stock-requests/$requestId/send',
      data: {
        'items': [
          for (final e in qtys.entries)
            {'stock_request_item_id': e.key, 'qty': e.value},
        ],
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  Future<void> decline(int requestId, {required String reason}) =>
      _api.post('/stock-requests/$requestId/decline', data: {'reason': reason});

  Future<void> cancel(int requestId) =>
      _api.post('/stock-requests/$requestId/cancel');
}

final stockRequestsRepositoryProvider = Provider<StockRequestsRepository>(
  (ref) => StockRequestsRepository(ref.watch(apiClientProvider)),
);
