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
    required this.numberOfPlates,
    required this.totalAmount,
    required this.status,
    required this.payments,
  });

  factory CateringOrder.fromJson(Map<String, dynamic> json) => CateringOrder(
    id: json['id'] as int,
    clientName: json['client_name'] as String,
    clientPhone: json['client_phone'] as String,
    eventName: json['event_name'] as String?,
    eventDate: DateTime.parse(json['event_date'] as String),
    package: CateringPackage.fromJson(json['package'] as Map<String, dynamic>),
    numberOfPlates: json['number_of_plates'] as int,
    totalAmount: double.parse(json['total_amount'].toString()),
    status: json['status'] as String,
    payments: ((json['payments'] as List<dynamic>?) ?? [])
        .map((e) => CateringPayment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final int id;
  final String clientName;
  final String clientPhone;
  final String? eventName;
  final DateTime eventDate;
  final CateringPackage package;
  final int numberOfPlates;
  final double totalAmount;
  final String status;
  final List<CateringPayment> payments;

  double get balanceDue =>
      totalAmount - payments.fold(0.0, (sum, p) => sum + p.amount);
}

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
    required int numberOfPlates,
  }) async {
    final body = await _api.post(
      '/catering-orders',
      data: {
        'client_name': clientName,
        'client_phone': clientPhone,
        if (eventName != null) 'event_name': eventName,
        'event_date': eventDate.toIso8601String().split('T').first,
        'catering_package_id': cateringPackageId,
        'number_of_plates': numberOfPlates,
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
