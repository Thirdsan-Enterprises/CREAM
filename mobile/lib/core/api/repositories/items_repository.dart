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
}

final itemsRepositoryProvider = Provider<ItemsRepository>(
  (ref) => ItemsRepository(ref.watch(apiClientProvider)),
);
