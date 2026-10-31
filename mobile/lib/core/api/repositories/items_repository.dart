import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/item.dart';
import '../../auth/auth_session.dart';
import '../api_client.dart';

class ItemsRepository {
  ItemsRepository(this._api);

  final ApiClient _api;

  /// Everything sold besides plates at a branch, with its price there.
  Future<List<MenuEntry>> menu({int? storeId}) async {
    final body = await _api.get(
      '/menu',
      query: storeId != null ? {'store_id': storeId} : null,
    );
    return (body['data'] as List<dynamic>)
        .map((e) => MenuEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Puts a new item on the menu, or an existing stock item ([itemId]).
  Future<void> addMenuItem({
    int? itemId,
    String? name,
    String? unit,
    required String category,
    required double price,
    int? storeId,
    required bool tracksStock,
  }) {
    return _api.post(
      '/menu-items',
      data: {
        'item_id': ?itemId,
        'name': ?name,
        'unit': ?unit,
        'category': category,
        'price': price,
        'store_id': ?storeId,
        'tracks_stock': tracksStock,
      },
    );
  }

  /// Changes a menu item. A [price] with a [storeId] sets that branch's
  /// own price; without one it sets the price for every branch.
  Future<void> updateMenuItem(
    int itemId, {
    String? name,
    String? category,
    double? price,
    int? storeId,
    bool? tracksStock,
    bool? isActive,
    bool useDefault = false,
    required String reason,
  }) {
    return _api.patch(
      '/menu-items/$itemId',
      data: {
        if (useDefault) 'use_default': true,
        'reason': reason,
        'name': ?name,
        'category': ?category,
        'price': ?price,
        'store_id': ?storeId,
        'tracks_stock': ?tracksStock,
        'is_active': ?isActive,
      },
    );
  }

  Future<double> platePrice({int? storeId}) async {
    final body = await _api.get(
      '/plate-price',
      query: storeId != null ? {'store_id': storeId} : null,
    );
    return (body['price'] as num).toDouble();
  }

  Future<List<Item>> items() async {
    final body = await _api.get('/items');
    return (body['data'] as List<dynamic>)
        .map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Item> createItem({
    required String name,
    required String unit,
    bool isDrink = false,
    double? safetyStock,
  }) async {
    final body = await _api.post(
      '/items',
      data: {
        'name': name,
        'unit': unit,
        'is_drink': isDrink,
        'safety_stock': ?safetyStock,
      },
    );
    return Item.fromJson(body);
  }

  Future<void> setStoreSettings({
    required int itemId,
    required int storeId,
    required double safetyStock,
  }) {
    return _api.post(
      '/items/$itemId/store-settings',
      data: {'store_id': storeId, 'safety_stock': safetyStock},
    );
  }

  /// Sets the plate price for every branch, or a branch's own price when
  /// [storeId] is given. [useDefault] puts that branch back on the price
  /// for all branches. The [reason] is kept in the change log.
  Future<void> updatePlatePrice({
    double? price,
    int? storeId,
    bool useDefault = false,
    required String reason,
  }) {
    return _api.patch(
      '/plate-price',
      data: {
        'price': ?price,
        'store_id': ?storeId,
        if (useDefault) 'use_default': true,
        'reason': reason,
      },
    );
  }

  /// Every price in one place: the plate and each menu item, at each branch.
  Future<PriceList> priceList() async =>
      PriceList.fromJson(await _api.get('/price-list'));
}

final itemsRepositoryProvider = Provider<ItemsRepository>(
  (ref) => ItemsRepository(ref.watch(apiClientProvider)),
);
