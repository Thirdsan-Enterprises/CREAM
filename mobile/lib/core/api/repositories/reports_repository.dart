import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_session.dart';
import '../api_client.dart';

class LowStockAlert {
  LowStockAlert({
    required this.itemId,
    required this.itemName,
    required this.balance,
    required this.safetyStock,
    required this.storeId,
    required this.storeName,
  });

  factory LowStockAlert.fromJson(Map<String, dynamic> json) => LowStockAlert(
    itemId: json['item_id'] as int,
    itemName: json['item_name'] as String,
    balance: (json['balance'] as num).toDouble(),
    safetyStock: (json['safety_stock'] as num).toDouble(),
    storeId: json['store_id'] as int,
    storeName: json['store_name'] as String,
  );

  final int itemId;
  final String itemName;
  final double balance;
  final double safetyStock;
  final int storeId;
  final String storeName;
}

class UpcomingCateringEvent {
  UpcomingCateringEvent({
    required this.id,
    required this.clientName,
    required this.eventName,
    required this.eventDate,
    required this.package,
    required this.status,
  });

  factory UpcomingCateringEvent.fromJson(Map<String, dynamic> json) =>
      UpcomingCateringEvent(
        id: json['id'] as int,
        clientName: json['client_name'] as String,
        eventName: json['event_name'] as String?,
        eventDate: DateTime.parse(json['event_date'] as String),
        package: json['package'] as String,
        status: json['status'] as String,
      );

  final int id;
  final String clientName;
  final String? eventName;
  final DateTime eventDate;
  final String package;
  final String status;
}

class DashboardData {
  DashboardData({
    required this.salesTotalToday,
    required this.platesSoldToday,
    required this.lowStockAlerts,
    required this.upcomingCatering,
    required this.totalOutstandingCredit,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    salesTotalToday: (json['sales_total_today'] as num).toDouble(),
    platesSoldToday: (json['plates_sold_today'] as num).toDouble(),
    lowStockAlerts: (json['low_stock_alerts'] as List<dynamic>)
        .map((e) => LowStockAlert.fromJson(e as Map<String, dynamic>))
        .toList(),
    upcomingCatering: (json['upcoming_catering'] as List<dynamic>)
        .map((e) => UpcomingCateringEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalOutstandingCredit: (json['total_outstanding_credit'] as num)
        .toDouble(),
  );

  final double salesTotalToday;
  final double platesSoldToday;
  final List<LowStockAlert> lowStockAlerts;
  final List<UpcomingCateringEvent> upcomingCatering;
  final double totalOutstandingCredit;
}

class StoreStockStatus {
  StoreStockStatus({
    required this.storeId,
    required this.storeName,
    required this.items,
  });

  factory StoreStockStatus.fromJson(Map<String, dynamic> json) =>
      StoreStockStatus(
        storeId: json['store_id'] as int,
        storeName: json['store_name'] as String,
        items: (json['items'] as List<dynamic>)
            .map(
              (e) => LowStockAlert.fromJson({
                ...e as Map<String, dynamic>,
                'store_id': json['store_id'],
                'store_name': json['store_name'],
              }),
            )
            .toList(),
      );

  final int storeId;
  final String storeName;
  final List<LowStockAlert> items;
}

class OutstandingCreditRow {
  OutstandingCreditRow({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.balance,
    required this.creditLimit,
    required this.daysSinceLastPayment,
  });

  factory OutstandingCreditRow.fromJson(Map<String, dynamic> json) =>
      OutstandingCreditRow(
        customerId: json['customer_id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String,
        balance: (json['balance'] as num).toDouble(),
        creditLimit: (json['credit_limit'] as num).toDouble(),
        daysSinceLastPayment: json['days_since_last_payment'] as int,
      );

  final int customerId;
  final String name;
  final String phone;
  final double balance;
  final double creditLimit;
  final int daysSinceLastPayment;
}

class CateringPipelineRow {
  CateringPipelineRow({
    required this.id,
    required this.clientName,
    required this.eventName,
    required this.eventDate,
    required this.package,
    required this.numberOfPlates,
    required this.totalAmount,
    required this.balanceDue,
    required this.status,
  });

  factory CateringPipelineRow.fromJson(Map<String, dynamic> json) =>
      CateringPipelineRow(
        id: json['id'] as int,
        clientName: json['client_name'] as String,
        eventName: json['event_name'] as String?,
        eventDate: DateTime.parse(json['event_date'] as String),
        package: json['package'] as String,
        numberOfPlates: json['number_of_plates'] as int,
        totalAmount: (json['total_amount'] as num).toDouble(),
        balanceDue: (json['balance_due'] as num).toDouble(),
        status: json['status'] as String,
      );

  final int id;
  final String clientName;
  final String? eventName;
  final DateTime eventDate;
  final String package;
  final int numberOfPlates;
  final double totalAmount;
  final double balanceDue;
  final String status;
}

class ReportsRepository {
  ReportsRepository(this._api);

  final ApiClient _api;

  Future<DashboardData> dashboard() async {
    final body = await _api.get('/reports/dashboard');
    return DashboardData.fromJson(body);
  }

  Future<List<StoreStockStatus>> stockStatus() async {
    final body = await _api.get('/reports/stock-status');
    return (body['data'] as List<dynamic>)
        .map((e) => StoreStockStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<OutstandingCreditRow>> outstandingCredit() async {
    final body = await _api.get('/reports/outstanding-credit');
    return (body['data'] as List<dynamic>)
        .map((e) => OutstandingCreditRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CateringPipelineRow>> cateringPipeline({
    String? status,
    bool? upcoming,
  }) async {
    final body = await _api.get(
      '/reports/catering-pipeline',
      query: {
        if (status != null) 'status': status,
        if (upcoming != null) 'upcoming': upcoming ? '1' : '0',
      },
    );
    return (body['data'] as List<dynamic>)
        .map((e) => CateringPipelineRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);
