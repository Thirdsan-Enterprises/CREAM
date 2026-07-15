import 'store.dart';

enum UserRole { admin, storeManager, cashier, storekeeper }

UserRole _roleFromString(String value) {
  switch (value) {
    case 'admin':
      return UserRole.admin;
    case 'store_manager':
      return UserRole.storeManager;
    case 'cashier':
      return UserRole.cashier;
    case 'storekeeper':
      return UserRole.storekeeper;
    default:
      throw ArgumentError('Unknown role: $value');
  }
}

class User {
  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.storeId,
    this.store,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String,
    phone: json['phone'] as String,
    role: _roleFromString(json['role'] as String),
    storeId: json['store_id'] as int?,
    store: json['store'] != null
        ? Store.fromJson(json['store'] as Map<String, dynamic>)
        : null,
  );

  final int id;
  final String name;
  final String phone;
  final UserRole role;
  final int? storeId;
  final Store? store;

  bool get isAdmin => role == UserRole.admin;

  /// True for roles that get the Outlet Terminal experience.
  bool get isOutletStaff => !isAdmin;
}
