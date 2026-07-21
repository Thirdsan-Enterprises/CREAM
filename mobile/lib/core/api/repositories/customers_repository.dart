import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/customer.dart';
import '../../auth/auth_session.dart';
import '../api_client.dart';

class CustomersRepository {
  CustomersRepository(this._api);

  final ApiClient _api;

  /// [accountType] filters to 'prepaid' or 'credit'; omit (or pass null)
  /// for everyone. An empty [query] returns the full customer list rather
  /// than nothing — used to browse all accounts, not just search results.
  Future<List<Customer>> search(String query, {String? accountType}) async {
    final body = await _api.get(
      '/customers',
      query: {
        if (query.isNotEmpty) 'search': query,
        if (accountType != null) 'account_type': accountType,
      },
    );
    return (body['data'] as List<dynamic>)
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Customer> create({
    required String name,
    required String phone,
    required String accountType,
    double creditLimit = 0,
  }) async {
    final body = await _api.post(
      '/customers',
      data: {
        'name': name,
        'phone': phone,
        'account_type': accountType,
        'credit_limit': creditLimit,
      },
    );
    return Customer.fromJson(body);
  }

  Future<double> balance(int customerId) async {
    final body = await _api.get('/customers/$customerId/balance');
    return (body['balance'] as num).toDouble();
  }

  Future<({Customer customer, double balance, List<LedgerEntry> entries})>
  statement(int customerId) async {
    final body = await _api.get('/customers/$customerId/statement');
    final entriesBody = body['entries'] as Map<String, dynamic>;
    return (
      customer: Customer.fromJson(body['customer'] as Map<String, dynamic>),
      balance: (body['balance'] as num).toDouble(),
      entries: (entriesBody['data'] as List<dynamic>)
          .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<double> deposit(int customerId, double amount) async {
    final body = await _api.post(
      '/customers/$customerId/deposit',
      data: {'amount': amount},
    );
    return (body['balance'] as num).toDouble();
  }
}

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(apiClientProvider)),
);
