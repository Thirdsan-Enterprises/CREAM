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

  /// How many are left, for things counted on a shelf or plates counted
  /// per day; null = no limit.
  double? get stockLeft =>
      entry != null && entry!.tracksStock ? entry!.balance : null;

  /// Plates counted per day (lunch).
  bool get isDaily => entry?.dailyStock ?? false;

  /// The takeaway packing charge (silver plate): not a tile on the menu,
  /// added with the "Takeaway" switch on the order.
  bool get isPacking => category.toLowerCase() == 'packing';
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

  /// Off the whole sale, with the reason ("regular customer").
  double discount = 0;
  String discountNote = '';

  /// What the customer handed over, for the change; optional.
  double? cashReceived;

  /// The branch's packing charge (silver plate), if it has one.
  PosItem? packing;

  List<CartLine> get lines => _lines.values.toList();

  /// The food and drinks, without the packing charge.
  List<CartLine> get foodLines =>
      _lines.values.where((l) => !l.item.isPacking).toList();

  /// How many packs (silver plates) for takeaway; 0 = eating in.
  int get packs => packing == null ? 0 : qtyOf(packing!);
  bool get takeaway => packs > 0;

  /// Takeaway on: one pack per lunch plate (at least one); off: none.
  void setTakeaway(bool on) {
    final p = packing;
    if (p == null) return;
    if (!on) {
      removeLine(p);
      return;
    }
    final plates = foodLines
        .where(
          (l) => l.item.category.toLowerCase() == 'lunch' || l.item.isPlate,
        )
        .fold(0, (sum, l) => sum + l.qty);
    setQty(p, plates > 0 ? plates : 1);
  }

  void setPacks(int n) {
    final p = packing;
    if (p == null) return;
    n <= 0 ? removeLine(p) : setQty(p, n);
  }

  bool get isEmpty => foodLines.isEmpty;
  int qtyOf(PosItem item) => _lines[item.key]?.qty ?? 0;
  int get count => foodLines.fold(0, (sum, l) => sum + l.qty);

  /// Before any discount.
  double get subtotal => _lines.values.fold(0, (sum, l) => sum + l.total);

  /// What the customer pays.
  double get total => subtotal - discount;

  /// What the customer can still spend, for an account sale.
  double? get available {
    final s = standing;
    if (s != null) return s.available;
    return null;
  }

  /// Charged to a customer: their account, or their company's LPO.
  bool get chargesCustomer =>
      paymentMethod == 'account' || paymentMethod == 'lpo';

  bool get exceedsAccount =>
      chargesCustomer && available != null && total > available!;

  /// Lunch plates in the order (what an LPO's plate count is checked on).
  int get lunchPlates => foodLines
      .where((l) => l.item.isPlate || l.item.category.toLowerCase() == 'lunch')
      .fold(0, (sum, l) => sum + l.qty);

  /// Why the chosen LPO cannot pay for this order, if it cannot.
  String? get lpoProblem {
    final lpo = standing?.lpo;
    if (paymentMethod != 'lpo' || lpo == null) return null;
    for (final l in foodLines) {
      final heading = l.item.isPlate ? 'Lunch' : l.item.category;
      if (!lpo.covers.any((c) => c.toLowerCase() == heading.toLowerCase())) {
        return '${lpo.label} does not cover $heading (${l.item.name}). '
            'Take payment for it separately.';
      }
    }
    final left = lpo.platesLeft;
    if (left != null && lunchPlates > left) {
      return left <= 0
          ? '${lpo.label} has no plates left.'
          : '${lpo.label} has only $left plates left.';
    }
    return null;
  }

  /// Adds one; returns a message instead when there are none left.
  String? add(PosItem item) => setQty(item, qtyOf(item) + 1);

  /// Sets how many (typed in, e.g. 40); 0 removes the line. Returns a
  /// message instead when there are not that many left.
  String? setQty(PosItem item, int qty) {
    final left = item.stockLeft;
    if (left != null && qty > left) {
      if (item.isDaily) {
        return left <= 0
            ? "No ${item.name} plates left today. Add today's plates first."
            : 'Only ${left.toStringAsFixed(0)} ${item.name} plates left today.';
      }
      return left <= 0
          ? '${item.name} is out of stock. Record the purchase first.'
          : 'Only ${left.toStringAsFixed(0)} ${item.name} in stock.';
    }
    if (qty <= 0) {
      _lines.remove(item.key);
    } else {
      _lines.putIfAbsent(item.key, () => CartLine(item, 0)).qty = qty;
    }
    _clampDiscount();
    notifyListeners();
    return null;
  }

  void setDiscount(double amount, String note) {
    discount = amount;
    discountNote = note;
    _clampDiscount();
    notifyListeners();
  }

  /// No food left: no packing either.
  void _tidy() {
    if (foodLines.isEmpty) _lines.removeWhere((_, l) => l.item.isPacking);
  }

  void _clampDiscount() {
    _tidy();
    if (discount >= subtotal) {
      discount = 0;
      discountNote = '';
    }
  }

  void removeOne(PosItem item) {
    final line = _lines[item.key];
    if (line == null) return;
    if (line.qty > 1) {
      line.qty--;
    } else {
      _lines.remove(item.key);
    }
    _clampDiscount();
    notifyListeners();
  }

  void removeLine(PosItem item) {
    _lines.remove(item.key);
    _clampDiscount();
    notifyListeners();
  }

  void setPayment(String method) {
    paymentMethod = method;
    // An LPO is charged to an LPO customer, Account to anyone else.
    final c = customer;
    if (c != null && ((method == 'lpo') != c.isLpo || !chargesCustomer)) {
      customer = null;
      standing = null;
    }
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
    discount = 0;
    discountNote = '';
    cashReceived = null;
    notifyListeners();
  }

  /// "2 Beef · 1 Milk Tea".
  String get summary => [
    for (final l in foodLines) '${l.qty} ${l.item.name}',
    if (takeaway) 'takeaway',
  ].join(' · ');
}
