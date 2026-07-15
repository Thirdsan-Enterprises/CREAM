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

  Future<Store> create({required String name, required String code}) async {
    final body = await _api.post('/stores', data: {'name': name, 'code': code});
    return Store.fromJson(body);
  }

  Future<Store> update(int storeId, {String? name, bool? isActive}) async {
    final body = await _api.patch(
      '/stores/$storeId',
      data: {
        if (name != null) 'name': name,
        if (isActive != null) 'is_active': isActive,
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
