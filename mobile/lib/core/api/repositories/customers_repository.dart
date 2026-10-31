import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/customer.dart';
import '../../auth/auth_session.dart';
import '../api_client.dart';

class CustomersRepository {
  CustomersRepository(this._api);

  final ApiClient _api;

  /// [accountType] filters to 'prepaid', 'credit' or 'lpo'; [storeId] to one
  /// branch (owner only); [attention] to accounts near or at their limit.
  /// An empty [query] returns everyone, so the list can be browsed.
  Future<List<Customer>> search(
    String query, {
    String? accountType,
    int? storeId,
    int? availableAt,
    bool attention = false,
  }) async {
    final body = await _api.get(
      '/customers',
      query: {
        'available_at': ?availableAt,
        if (query.isNotEmpty) 'search': query,
        'account_type': ?accountType,
        'store_id': ?storeId,
        if (attention) 'attention': '1',
      },
    );
    return (body['data'] as List<dynamic>)
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Staff always add to their own branch; the owner picks one ([storeId])
  /// or none (every branch). Only the owner's [creditLimit] is applied.
  Future<Customer> create({
    required String name,
    required String phone,
    required String accountType,
    double creditLimit = 0,
    int? storeId,
  }) async {
    final body = await _api.post(
      '/customers',
      data: {
        'name': name,
        'phone': phone,
        'account_type': accountType,
        'credit_limit': creditLimit,
        'store_id': ?storeId,
      },
    );
    return Customer.fromJson(body);
  }

  /// Changes details; [fields] are API names (name, phone, is_active,
  /// credit_limit, account_type, store_id). A reason is required.
  Future<Customer> update(
    int customerId,
    Map<String, Object?> fields, {
    required String reason,
  }) async {
    final body = await _api.patch(
      '/customers/$customerId',
      data: {...fields, 'reason': reason},
    );
    return Customer.fromJson(body);
  }

  /// Corrects a balance entered wrongly: positive adds, negative removes.
  Future<AccountStanding> correctBalance(
    int customerId,
    double amount, {
    required String reason,
  }) async {
    final body = await _api.post(
      '/customers/$customerId/adjustment',
      data: {'amount': amount, 'reason': reason},
    );
    return AccountStanding.fromJson(body);
  }

  Future<double> balance(int customerId) async =>
      (await standing(customerId)).balance;

  Future<AccountStanding> standing(int customerId) async {
    final body = await _api.get('/customers/$customerId/balance');
    return AccountStanding.fromJson(body);
  }

  Future<
    ({
      Customer customer,
      double balance,
      AccountStanding? standing,
      List<LedgerEntry> entries,
    })
  >
  statement(int customerId) async {
    final body = await _api.get('/customers/$customerId/statement');
    final entriesBody = body['entries'] as Map<String, dynamic>;
    final standing = body['standing'];
    return (
      customer: Customer.fromJson(body['customer'] as Map<String, dynamic>),
      balance: (body['balance'] as num).toDouble(),
      standing: standing is Map<String, dynamic>
          ? AccountStanding.fromJson(standing)
          : null,
      entries: (entriesBody['data'] as List<dynamic>)
          .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<double> deposit(int customerId, double amount, {String? note}) async {
    final body = await _api.post(
      '/customers/$customerId/deposit',
      data: {
        'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return (body['balance'] as num).toDouble();
  }
}

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(apiClientProvider)),
);
