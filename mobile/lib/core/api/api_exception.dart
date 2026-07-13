/// A user-presentable error surfaced from an API call.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors});

  final String message;
  final int? statusCode;
  final Map<String, List<String>>? fieldErrors;

  String? firstFieldError() {
    final errors = fieldErrors;
    if (errors == null || errors.isEmpty) return null;
    return errors.values.first.firstOrNull;
  }

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
