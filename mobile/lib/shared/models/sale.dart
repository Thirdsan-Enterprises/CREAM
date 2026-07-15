class SaleLine {
  SaleLine({required this.itemType, this.itemId, required this.qty});

  final String itemType; // 'plate' or 'drink'
  final int? itemId;
  final double qty;

  Map<String, dynamic> toJson() => {
    'item_type': itemType,
    if (itemId != null) 'item_id': itemId,
    'qty': qty,
  };
}

class SaleSummary {
  SaleSummary({
    required this.salesCount,
    required this.totalRevenue,
    required this.plateRevenue,
    required this.drinkRevenue,
    required this.platesSold,
    required this.byPaymentMethod,
  });

  factory SaleSummary.fromJson(Map<String, dynamic> json) => SaleSummary(
    salesCount: json['sales_count'] as int,
    totalRevenue: (json['total_revenue'] as num).toDouble(),
    plateRevenue: (json['plate_revenue'] as num).toDouble(),
    drinkRevenue: (json['drink_revenue'] as num).toDouble(),
    platesSold: (json['plates_sold'] as num).toDouble(),
    byPaymentMethod: _asStringDoubleMap(json['by_payment_method']),
  );

  final int salesCount;
  final double totalRevenue;
  final double plateRevenue;
  final double drinkRevenue;
  final double platesSold;
  final Map<String, double> byPaymentMethod;
}

// Laravel serializes an empty PHP associative array as a JSON `[]` rather
// than `{}`, so an empty breakdown can arrive as a List instead of a Map.
Map<String, double> _asStringDoubleMap(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, v) => MapEntry(key as String, (v as num).toDouble()),
    );
  }
  return {};
}
