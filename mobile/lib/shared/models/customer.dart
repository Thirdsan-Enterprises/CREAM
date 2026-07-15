class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.accountType,
    required this.creditLimit,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as int,
    name: json['name'] as String,
    phone: json['phone'] as String,
    accountType: json['account_type'] as String,
    creditLimit: double.parse(json['credit_limit'].toString()),
  );

  final int id;
  final String name;
  final String phone;
  final String accountType; // 'prepaid' or 'credit'
  final double creditLimit;

  bool get isCredit => accountType == 'credit';
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.note,
    required this.occurredAt,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as int,
    type: json['type'] as String,
    amount: double.parse(json['amount'].toString()),
    note: json['note'] as String?,
    occurredAt: DateTime.parse(json['occurred_at'] as String),
  );

  final int id;
  final String type;
  final double amount;
  final String? note;
  final DateTime occurredAt;
}
