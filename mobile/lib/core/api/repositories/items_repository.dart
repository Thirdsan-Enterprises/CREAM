import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/item.dart';
import '../../auth/auth_session.dart';
import '../api_client.dart';

class ItemsRepository {
  ItemsRepository(this._api);

  final ApiClient _api;

  Future<List<Drink>> drinks({int? storeId}) async {
    final body = await _api.get(
      '/drinks',
      query: storeId != null ? {'store_id': storeId} : null,
    );
    return (body['data'] as List<dynamic>)
        .map((e) => Drink.fromJson(e as Map<String, dynamic>))
        .toList();
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
  }) async {
    final body = await _api.post(
      '/items',
      data: {'name': name, 'unit': unit, 'is_drink': isDrink},
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

  Future<void> updatePlatePrice({required double price, int? storeId}) {
    return _api.patch(
      '/plate-price',
      data: {'price': price, if (storeId != null) 'store_id': storeId},
    );
  }
}

final itemsRepositoryProvider = Provider<ItemsRepository>(
  (ref) => ItemsRepository(ref.watch(apiClientProvider)),
);
