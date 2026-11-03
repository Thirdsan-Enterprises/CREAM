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
    List<int>? soldAt,
  }) {
    return _api.post(
      '/menu-items',
      data: {
        // Null: sold at every branch.
        'branches': ?soldAt,
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
    List<int>? soldAt,
    bool soldEverywhere = false,
    required String reason,
  }) {
    return _api.patch(
      '/menu-items/$itemId',
      data: {
        if (soldEverywhere) 'branches': null else 'branches': ?soldAt,
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

  /// Kitchen stock items (what procurement buys). [includeRemoved] adds
  /// items taken off the list, so they can be added back.
  Future<List<Item>> items({bool includeRemoved = false}) async {
    final body = await _api.get(
      '/items',
      query: includeRemoved ? {'include_removed': '1'} : null,
    );
    return (body['data'] as List<dynamic>)
        .map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Item> createItem({
    required String name,
    required String unit,
    bool isDrink = false,
    double? safetyStock,
    String? category,
  }) async {
    final body = await _api.post(
      '/items',
      data: {
        'name': name,
        'unit': unit,
        'is_drink': isDrink,
        'safety_stock': ?safetyStock,
        'category': ?category,
      },
    );
    return Item.fromJson(body);
  }

  /// Renames, regroups or restores a kitchen stock item.
  Future<void> updateItem(
    int itemId, {
    String? name,
    String? unit,
    String? category,
    bool? isActive,
    String? reason,
  }) {
    return _api.patch(
      '/items/$itemId',
      data: {
        'name': ?name,
        'unit': ?unit,
        'category': ?category,
        'is_active': ?isActive,
        'reason': ?reason,
      },
    );
  }

  /// Takes an item off the list. Returns the server's explanation (deleted,
  /// or kept for the records).
  Future<String> removeItem(int itemId, {required String reason}) async {
    final body = await _api.delete('/items/$itemId', data: {'reason': reason});
    return body['message'] as String? ?? 'Removed.';
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
