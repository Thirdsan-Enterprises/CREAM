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

/// Something sold over the counter besides a plate: a drink, an egg, a cup
/// of tea. Each can be sold on its own or alongside plates.
class MenuEntry {
  MenuEntry({
    required this.item,
    required this.price,
    this.balance,
    String? category,
    this.tracksStock = true,
  }) : category = category ?? (item.isDrink ? 'Drinks' : 'Other');

  factory MenuEntry.fromJson(Map<String, dynamic> json) => MenuEntry(
    item: Item.fromJson(json['item'] as Map<String, dynamic>),
    price: (json['price'] as num?)?.toDouble(),
    balance: (json['balance'] as num?)?.toDouble(),
    category: json['category'] as String?,
    tracksStock: json['tracks_stock'] as bool? ?? true,
  );

  final Item item;
  final double? price;

  /// Menu heading, e.g. "Drinks" or "Breakfast".
  final String category;

  /// False for things made to order (a cup of tea): never limited by stock.
  final bool tracksStock;

  /// How many this branch has in stock; null when it doesn't track stock or
  /// the branch isn't known.
  final double? balance;
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

/// One branch's price: [own] when it differs from the price for all branches.
class BranchPrice {
  BranchPrice({
    required this.storeId,
    required this.storeName,
    required this.price,
    required this.own,
  });

  factory BranchPrice.fromJson(Map<String, dynamic> json) => BranchPrice(
    storeId: json['store_id'] as int,
    storeName: json['store_name'] as String,
    price: (json['price'] as num?)?.toDouble(),
    own: json['own'] as bool? ?? false,
  );

  final int storeId;
  final String storeName;
  final double? price;
  final bool own;
}

class PricedThing {
  PricedThing({required this.defaultPrice, required this.branches});

  final double? defaultPrice;
  final List<BranchPrice> branches;

  List<BranchPrice> get ownPrices => branches.where((b) => b.own).toList();
}

class MenuPriceRow extends PricedThing {
  MenuPriceRow({
    required this.item,
    required this.category,
    required this.tracksStock,
    required this.isActive,
    required super.defaultPrice,
    required super.branches,
  });

  factory MenuPriceRow.fromJson(Map<String, dynamic> json) => MenuPriceRow(
    item: Item.fromJson(json['item'] as Map<String, dynamic>),
    category: json['category'] as String? ?? 'Other',
    tracksStock: json['tracks_stock'] as bool? ?? true,
    isActive: json['is_active'] as bool? ?? true,
    defaultPrice: (json['default'] as num?)?.toDouble(),
    branches: _branches(json['branches']),
  );

  final Item item;
  final String category;
  final bool tracksStock;
  final bool isActive;
}

class PriceList {
  PriceList({required this.plate, required this.items});

  factory PriceList.fromJson(Map<String, dynamic> json) {
    final plate = json['plate'] as Map<String, dynamic>;
    return PriceList(
      plate: PricedThing(
        defaultPrice: (plate['default'] as num?)?.toDouble(),
        branches: _branches(plate['branches']),
      ),
      items: (json['items'] as List<dynamic>)
          .map((e) => MenuPriceRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final PricedThing plate;
  final List<MenuPriceRow> items;
}

List<BranchPrice> _branches(dynamic value) => (value as List<dynamic>)
    .map((e) => BranchPrice.fromJson(e as Map<String, dynamic>))
    .toList();
