import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_session.dart';
import '../api_client.dart';

/// One field that changed: what it was and what it became.
class FieldChange {
  FieldChange(this.field, this.from, this.to);

  final String field;
  final Object? from;
  final Object? to;
}

/// A change to something already entered, with the reason given.
class EditLogEntry {
  EditLogEntry({
    required this.id,
    required this.userName,
    required this.storeName,
    required this.subjectType,
    required this.subjectLabel,
    required this.action,
    required this.changes,
    required this.reason,
    required this.createdAt,
  });

  factory EditLogEntry.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    return EditLogEntry(
      id: json['id'] as int,
      userName:
          (json['user'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      storeName: (json['store'] as Map<String, dynamic>?)?['name'] as String?,
      subjectType: json['subject_type'] as String,
      subjectLabel: json['subject_label'] as String,
      action: json['action'] as String,
      changes: rawChanges is Map
          ? [
              for (final entry in rawChanges.entries)
                FieldChange(
                  entry.key as String,
                  (entry.value as Map)['from'],
                  (entry.value as Map)['to'],
                ),
            ]
          : const [],
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int id;
  final String userName;
  final String? storeName;
  final String subjectType;
  final String subjectLabel;
  final String action;
  final List<FieldChange> changes;
  final String reason;
  final DateTime createdAt;
}

class EditLogsRepository {
  EditLogsRepository(this._api);

  final ApiClient _api;

  Future<List<EditLogEntry>> list({int? storeId, String? subjectType}) async {
    final body = await _api.get(
      '/edit-logs',
      query: {'store_id': ?storeId, 'subject_type': ?subjectType},
    );
    return (body['data'] as List<dynamic>)
        .map((e) => EditLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final editLogsRepositoryProvider = Provider<EditLogsRepository>(
  (ref) => EditLogsRepository(ref.watch(apiClientProvider)),
);
