import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_session.dart';
import '../../auth/store.dart';
import '../api_client.dart';

class StoresRepository {
  StoresRepository(this._api);

  final ApiClient _api;

  Future<List<Store>> all() async {
    final body = await _api.get('/stores');
    return (body['data'] as List<dynamic>)
        .map((e) => Store.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Store> create({
    required String name,
    required String code,
    bool sells = true,
  }) async {
    final body = await _api.post(
      '/stores',
      data: {'name': name, 'code': code, 'sells': sells},
    );
    return Store.fromJson(body);
  }

  /// [isMain] true makes this store the procurement unit (the previous one
  /// hands over, with its procurement staff).
  Future<Store> update(
    int storeId, {
    String? name,
    bool? isActive,
    bool? isMain,
    bool? sells,
  }) async {
    final body = await _api.patch(
      '/stores/$storeId',
      data: {
        'name': ?name,
        'is_active': ?isActive,
        'is_main': ?isMain,
        'sells': ?sells,
      },
    );
    return Store.fromJson(body);
  }
}

final storesRepositoryProvider = Provider<StoresRepository>(
  (ref) => StoresRepository(ref.watch(apiClientProvider)),
);

/// Admin's currently selected store scope for store-scoped Back Office
/// screens (Stocking, Sales). `null` means "all stores" where the screen
/// supports it.
final selectedStoreIdProvider = StateProvider<int?>((ref) => null);
