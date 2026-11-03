import 'package:flutter/foundation.dart';

import '../../shared/models/customer.dart';
import '../../shared/models/item.dart';

/// Something on the Sell screen: a dish, a drink, a breakfast item, or the
/// plain plate (only where a branch has no lunch dishes on its menu).
class PosItem {
  PosItem.menu(MenuEntry this.entry)
    : key = 'item-${entry.item.id}',
      name = entry.item.name,
      category = entry.category,
      price = entry.price ?? 0;

  PosItem.plate(this.price)
    : entry = null,
      key = 'plate',
      name = 'Plate',
      category = 'Lunch';

  final MenuEntry? entry;
  final String key;
  final String name;
  final String category;
  final double price;

  bool get isPlate => entry == null;

  /// How many are left, for things counted on a shelf; null = no limit.
  double? get stockLeft =>
      entry != null && entry!.tracksStock ? entry!.balance : null;
}

class CartLine {
  CartLine(this.item, this.qty);

  final PosItem item;
  int qty;

  double get total => item.price * qty;
}

/// The order being rung up. Shared by the menu grid and the order panel,
/// which on a phone lives in a sheet and on a tablet beside the menu.
class PosCart extends ChangeNotifier {
  final Map<String, CartLine> _lines = {};

  String paymentMethod = 'cash';
  Customer? customer;
  AccountStanding? standing;
  bool loadingCustomer = false;
  bool submitting = false;

  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  int qtyOf(PosItem item) => _lines[item.key]?.qty ?? 0;
  int get count => _lines.values.fold(0, (sum, l) => sum + l.qty);
  double get total => _lines.values.fold(0, (sum, l) => sum + l.total);

  /// What the customer can still spend, for an account sale.
  double? get available {
    final s = standing;
    if (s != null) return s.available;
    return null;
  }

  bool get exceedsAccount =>
      paymentMethod == 'account' && available != null && total > available!;

  /// Adds one; returns a message instead when the shelf is empty.
  String? add(PosItem item) {
    final left = item.stockLeft;
    final inCart = qtyOf(item);
    if (left != null && inCart + 1 > left) {
      return left <= 0
          ? '${item.name} is out of stock. Record the purchase first.'
          : 'Only ${left.toStringAsFixed(0)} ${item.name} in stock.';
    }
    _lines.putIfAbsent(item.key, () => CartLine(item, 0)).qty++;
    notifyListeners();
    return null;
  }

  void removeOne(PosItem item) {
    final line = _lines[item.key];
    if (line == null) return;
    if (line.qty > 1) {
      line.qty--;
    } else {
      _lines.remove(item.key);
    }
    notifyListeners();
  }

  void removeLine(PosItem item) {
    _lines.remove(item.key);
    notifyListeners();
  }

  void setPayment(String method) {
    paymentMethod = method;
    notifyListeners();
  }

  void setCustomer(Customer? value, {AccountStanding? standing}) {
    customer = value;
    this.standing = standing;
    notifyListeners();
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  /// After a sale: empty, cash, no customer.
  void reset() {
    _lines.clear();
    paymentMethod = 'cash';
    customer = null;
    standing = null;
    notifyListeners();
  }

  /// "2 Beef · 1 Milk Tea".
  String get summary => lines.map((l) => '${l.qty} ${l.item.name}').join(' · ');
}
