class Item {
  Item({
    required this.id,
    required this.name,
    required this.unit,
    required this.category,
    required this.isDrink,
    required this.isActive,
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'] as int,
    name: json['name'] as String,
    unit: json['unit'] as String,
    category: json['category'] as String?,
    isDrink: json['is_drink'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
  );

  final int id;
  final String name;
  final String unit;
  final String? category;
  final bool isDrink;
  final bool isActive;
}

class Drink {
  Drink({required this.item, required this.price});

  factory Drink.fromJson(Map<String, dynamic> json) => Drink(
    item: Item.fromJson(json['item'] as Map<String, dynamic>),
    price: (json['price'] as num?)?.toDouble(),
  );

  final Item item;
  final double? price;
}

class StoreStockBalance {
  StoreStockBalance({
    required this.storeId,
    required this.storeName,
    required this.balance,
    required this.safetyStock,
    required this.status,
  });

  factory StoreStockBalance.fromJson(Map<String, dynamic> json) =>
      StoreStockBalance(
        storeId: json['store_id'] as int,
        storeName: json['store_name'] as String,
        balance: (json['balance'] as num).toDouble(),
        safetyStock: (json['safety_stock'] as num).toDouble(),
        status: json['status'] as String,
      );

  final int storeId;
  final String storeName;
  final double balance;
  final double safetyStock;
  final String status;

  bool get needsReorder => status == 'Re-Order';
}
