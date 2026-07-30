import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_session.dart';
import '../api_client.dart';

class CateringPackage {
  CateringPackage({
    required this.id,
    required this.name,
    required this.pricePerPlate,
  });

  factory CateringPackage.fromJson(Map<String, dynamic> json) =>
      CateringPackage(
        id: json['id'] as int,
        name: json['name'] as String,
        pricePerPlate: double.parse(json['price_per_plate'].toString()),
      );

  final int id;
  final String name;
  final double pricePerPlate;
}

class CateringPayment {
  CateringPayment({
    required this.id,
    required this.amount,
    required this.paymentMethod,
    required this.paidAt,
  });

  factory CateringPayment.fromJson(Map<String, dynamic> json) =>
      CateringPayment(
        id: json['id'] as int,
        amount: double.parse(json['amount'].toString()),
        paymentMethod: json['payment_method'] as String,
        paidAt: DateTime.parse(json['paid_at'] as String),
      );

  final int id;
  final double amount;
  final String paymentMethod;
  final DateTime paidAt;
}

class CateringOrder {
  CateringOrder({
    required this.id,
    required this.clientName,
    required this.clientPhone,
    required this.eventName,
    required this.eventDate,
    required this.package,
    required this.pricePerPlate,
    required this.numberOfPlates,
    required this.notes,
    required this.totalAmount,
    required this.status,
    required this.payments,
    required this.depositedTotal,
    required this.balanceDue,
    required this.cancellationFee,
    required this.refundableAmount,
  });

  factory CateringOrder.fromJson(Map<String, dynamic> json) {
    final totalAmount = double.parse(json['total_amount'].toString());
    final payments = ((json['payments'] as List<dynamic>?) ?? [])
        .map((e) => CateringPayment.fromJson(e as Map<String, dynamic>))
        .toList();
    // deposited_total/balance_due/cancellation_fee/refundable_amount are
    // computed server-side (the source of truth); fall back to a local
    // computation only if an older/partial response shape lacks them.
    final depositedTotal = json['deposited_total'] != null
        ? double.parse(json['deposited_total'].toString())
        : payments.fold(0.0, (sum, p) => sum + p.amount);

    return CateringOrder(
      id: json['id'] as int,
      clientName: json['client_name'] as String,
      clientPhone: json['client_phone'] as String,
      eventName: json['event_name'] as String?,
      eventDate: DateTime.parse(json['event_date'] as String),
      package: CateringPackage.fromJson(json['package'] as Map<String, dynamic>),
      pricePerPlate: json['price_per_plate'] != null
          ? double.parse(json['price_per_plate'].toString())
          : null,
      numberOfPlates: json['number_of_plates'] as int,
      notes: json['notes'] as String?,
      totalAmount: totalAmount,
      status: json['status'] as String,
      payments: payments,
      depositedTotal: depositedTotal,
      balanceDue: json['balance_due'] != null
          ? double.parse(json['balance_due'].toString())
          : totalAmount - depositedTotal,
      cancellationFee: json['cancellation_fee'] != null
          ? double.parse(json['cancellation_fee'].toString())
          : round2(depositedTotal * 0.5),
      refundableAmount: json['refundable_amount'] != null
          ? double.parse(json['refundable_amount'].toString())
          : round2(depositedTotal * 0.5),
    );
  }

  final int id;
  final String clientName;
  final String clientPhone;
  final String? eventName;
  final DateTime eventDate;
  final CateringPackage package;
  final double? pricePerPlate;
  final int numberOfPlates;
  final String? notes;
  final double totalAmount;
  final String status;
  final List<CateringPayment> payments;
  final double depositedTotal;
  final double balanceDue;
  final double cancellationFee;
  final double refundableAmount;

  /// What to call this order's paperwork at its current stage — matches
  /// the client's "quotation, invoice, receipt" request.
  String get documentLabel => switch (status) {
    'quoted' => 'Quotation',
    'confirmed' || 'delivered' => 'Invoice',
    'settled' => 'Receipt',
    'cancelled' => 'Cancellation Notice',
    _ => 'Order',
  };
}

double round2(double value) => (value * 100).round() / 100;

class CateringRepository {
  CateringRepository(this._api);

  final ApiClient _api;

  Future<List<CateringPackage>> packages() async {
    final body = await _api.get('/catering-packages');
    return (body['data'] as List<dynamic>)
        .map((e) => CateringPackage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CateringPackage> createPackage({
    required String name,
    required double pricePerPlate,
  }) async {
    final body = await _api.post(
      '/catering-packages',
      data: {'name': name, 'price_per_plate': pricePerPlate},
    );
    return CateringPackage.fromJson(body);
  }

  Future<CateringPackage> updatePackagePrice(
    int packageId,
    double pricePerPlate,
  ) async {
    final body = await _api.patch(
      '/catering-packages/$packageId',
      data: {'price_per_plate': pricePerPlate},
    );
    return CateringPackage.fromJson(body);
  }

  Future<List<CateringOrder>> orders({String? status, bool? upcoming}) async {
    final body = await _api.get(
      '/catering-orders',
      query: {
        if (status != null) 'status': status,
        if (upcoming != null) 'upcoming': upcoming ? '1' : '0',
      },
    );
    return (body['data'] as List<dynamic>)
        .map((e) => CateringOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CateringOrder> createOrder({
    required String clientName,
    required String clientPhone,
    String? eventName,
    required DateTime eventDate,
    required int cateringPackageId,
    double? pricePerPlate,
    required int numberOfPlates,
    String? notes,
  }) async {
    final body = await _api.post(
      '/catering-orders',
      data: {
        'client_name': clientName,
        'client_phone': clientPhone,
        if (eventName != null) 'event_name': eventName,
        'event_date': eventDate.toIso8601String().split('T').first,
        'catering_package_id': cateringPackageId,
        if (pricePerPlate != null) 'price_per_plate': pricePerPlate,
        'number_of_plates': numberOfPlates,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return CateringOrder.fromJson(body);
  }

  Future<CateringOrder> updateStatus(int orderId, String status) async {
    final body = await _api.patch(
      '/catering-orders/$orderId',
      data: {'status': status},
    );
    return CateringOrder.fromJson(body);
  }

  Future<void> addPayment(
    int orderId, {
    required double amount,
    required String paymentMethod,
  }) {
    return _api.post(
      '/catering-orders/$orderId/payments',
      data: {'amount': amount, 'payment_method': paymentMethod},
    );
  }
}

final cateringRepositoryProvider = Provider<CateringRepository>(
  (ref) => CateringRepository(ref.watch(apiClientProvider)),
);
