import 'package:cream_pos/core/auth/store.dart';
import 'package:cream_pos/core/auth/user.dart';
import 'package:cream_pos/features/sales/outlet_home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

User _user(UserRole role, {bool mainStore = false}) => User(
  id: 1,
  name: 'Test',
  phone: '0700000000',
  role: role,
  storeId: 5,
  store: Store(
    id: 5,
    name: mainStore ? 'Kira' : 'Lugogo',
    code: 'X',
    isMain: mainStore,
    isActive: true,
  ),
);

void main() {
  test('a cashier sells, checks stock and accounts, and sees their day', () {
    expect(outletTabLabels(_user(UserRole.cashier)), [
      'Sell',
      'Stock',
      'Accounts',
      'My Day',
    ]);
  });

  test('a branch manager has the same tabs as a cashier', () {
    expect(outletTabLabels(_user(UserRole.storeManager)), [
      'Sell',
      'Stock',
      'Accounts',
      'My Day',
    ]);
  });

  test('the manager of the main store also gets Stocking', () {
    expect(outletTabLabels(_user(UserRole.storeManager, mainStore: true)), [
      'Sell',
      'Stock',
      'Stocking',
      'Accounts',
      'My Day',
    ]);
  });

  test(
    'a storekeeper buys and sends stock but is not shown Sell or Accounts',
    () {
      final tabs = outletTabLabels(
        _user(UserRole.storekeeper, mainStore: true),
      );
      expect(tabs, ['Stocking', 'Stock']);
      expect(tabs, isNot(contains('Sell')));
    },
  );
}
