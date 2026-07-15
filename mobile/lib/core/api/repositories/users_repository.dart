import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_session.dart';
import '../../auth/store.dart';
import '../api_client.dart';

class ManagedUser {
  ManagedUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.store,
    required this.isActive,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
    id: json['id'] as int,
    name: json['name'] as String,
    phone: json['phone'] as String,
    role: json['role'] as String,
    store: json['store'] != null
        ? Store.fromJson(json['store'] as Map<String, dynamic>)
        : null,
    isActive: json['is_active'] as bool? ?? true,
  );

  final int id;
  final String name;
  final String phone;
  final String role;
  final Store? store;
  final bool isActive;
}

class UsersRepository {
  UsersRepository(this._api);

  final ApiClient _api;

  Future<List<ManagedUser>> all() async {
    final body = await _api.get('/users');
    return (body['data'] as List<dynamic>)
        .map((e) => ManagedUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ManagedUser> create({
    required String name,
    required String phone,
    required String password,
    required String role,
    int? storeId,
  }) async {
    final body = await _api.post(
      '/users',
      data: {
        'name': name,
        'phone': phone,
        'password': password,
        'role': role,
        if (storeId != null) 'store_id': storeId,
      },
    );
    return ManagedUser.fromJson(body);
  }

  Future<ManagedUser> update(int userId, {bool? isActive}) async {
    final body = await _api.patch(
      '/users/$userId',
      data: {if (isActive != null) 'is_active': isActive},
    );
    return ManagedUser.fromJson(body);
  }
}

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(ref.watch(apiClientProvider)),
);
