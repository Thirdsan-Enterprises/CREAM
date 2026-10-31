/// Whether staff should be warned before charging this account:
/// ok, low (credit 80%+ used, or less than a plate left) or blocked.
class AccountStanding {
  AccountStanding({
    required this.balance,
    required this.available,
    required this.status,
    this.creditUsedPct,
    this.warning,
  });

  factory AccountStanding.fromJson(Map<String, dynamic> json) =>
      AccountStanding(
        balance: (json['balance'] as num).toDouble(),
        available: (json['available'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'ok',
        creditUsedPct: (json['credit_used_pct'] as num?)?.toDouble(),
        warning: json['warning'] as String?,
      );

  final double balance;

  /// What can still be charged now.
  final double available;
  final String status;
  final double? creditUsedPct;
  final String? warning;

  bool get isLow => status == 'low';
  bool get isBlocked => status == 'blocked';
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.accountType,
    required this.creditLimit,
    this.balance,
    this.storeId,
    this.storeName,
    this.isActive = true,
    this.standing,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as int,
    name: json['name'] as String,
    phone: json['phone'] as String,
    accountType: json['account_type'] as String,
    creditLimit: double.parse(json['credit_limit'].toString()),
    // Only present on list responses (GET /customers), which eager-load it
    // in one query; null here just means "not fetched", not "zero".
    balance: json['balance'] == null
        ? null
        : double.parse(json['balance'].toString()),
    storeId: json['store_id'] as int?,
    storeName: (json['store'] as Map<String, dynamic>?)?['name'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    standing: json['status'] == null ? null : AccountStanding.fromJson(json),
  );

  final int id;
  final String name;
  final String phone;
  final String accountType; // 'prepaid', 'credit', or 'lpo'
  final double creditLimit;
  final double? balance;

  /// The branch the customer belongs to; null = every branch (older accounts).
  final int? storeId;
  final String? storeName;
  final bool isActive;

  /// Present on responses from servers that report account warnings.
  final AccountStanding? standing;

  bool get isCredit => accountType == 'credit';
  bool get isLpo => accountType == 'lpo';

  String get accountTypeLabel => switch (accountType) {
    'credit' => 'Credit',
    'lpo' => 'LPO',
    _ => 'Prepaid',
  };
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.note,
    required this.occurredAt,
    this.recordedByName,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as int,
    type: json['type'] as String,
    amount: double.parse(json['amount'].toString()),
    note: json['note'] as String?,
    occurredAt: DateTime.parse(json['occurred_at'] as String),
    recordedByName: (json['recorded_by'] is Map
        ? json['recorded_by']['name'] as String?
        : null),
  );

  final int id;
  final String type;
  final double amount;
  final String? note;
  final DateTime occurredAt;
  final String? recordedByName;
}
