class StockTransferItem {
  StockTransferItem({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.qtyDispatched,
    required this.qtyReceived,
    this.unit = '',
  });

  factory StockTransferItem.fromJson(Map<String, dynamic> json) =>
      StockTransferItem(
        id: json['id'] as int,
        itemId: json['item_id'] as int,
        itemName:
            (json['item'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        unit: (json['item'] as Map<String, dynamic>?)?['unit'] as String? ?? '',
        qtyDispatched: double.parse(json['qty_dispatched'].toString()),
        qtyReceived: json['qty_received'] == null
            ? null
            : double.parse(json['qty_received'].toString()),
      );

  final int id;
  final int itemId;
  final String itemName;
  final double qtyDispatched;
  final double? qtyReceived;
  final String unit;
}

class StockTransfer {
  StockTransfer({
    required this.id,
    required this.fromStoreId,
    required this.fromStoreName,
    required this.toStoreId,
    required this.toStoreName,
    required this.status,
    required this.dispatchedAt,
    required this.items,
    this.dispatchedByName,
    this.confirmedByName,
    this.confirmedAt,
  });

  factory StockTransfer.fromJson(Map<String, dynamic> json) => StockTransfer(
    id: json['id'] as int,
    fromStoreId: json['from_store_id'] as int,
    fromStoreName:
        (json['from_store'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    toStoreId: json['to_store_id'] as int,
    toStoreName:
        (json['to_store'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    status: json['status'] as String,
    dispatchedAt: DateTime.parse(json['dispatched_at'] as String),
    items: (json['items'] as List<dynamic>? ?? [])
        .map((e) => StockTransferItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    dispatchedByName:
        (json['dispatched_by'] as Map<String, dynamic>?)?['name'] as String?,
    confirmedByName:
        (json['confirmed_by'] as Map<String, dynamic>?)?['name'] as String?,
    confirmedAt: json['confirmed_at'] == null
        ? null
        : DateTime.parse(json['confirmed_at'] as String),
  );

  final int id;
  final int fromStoreId;
  final String fromStoreName;
  final int toStoreId;
  final String toStoreName;
  final String status;
  final DateTime dispatchedAt;
  final List<StockTransferItem> items;
  final String? dispatchedByName;
  final String? confirmedByName;
  final DateTime? confirmedAt;

  bool get isReceived => status != 'dispatched';
}
