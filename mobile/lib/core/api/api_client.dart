import 'package:dio/dio.dart';

import '../auth/token_storage.dart';
import '../constants.dart';
import 'api_exception.dart';

/// Thin Dio wrapper: attaches the bearer token to every request and maps
/// Laravel's JSON error shape ({message, errors}) into [ApiException].
class ApiClient {
  ApiClient({TokenStorage? tokenStorage, Dio? dio})
    : _tokenStorage = tokenStorage ?? TokenStorage(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              headers: {'Accept': 'application/json'},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.read();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Set by the auth session so a 401 anywhere can force a re-login.
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _guard(() => _dio.get(path, queryParameters: query));
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    final response = await _guard(() => _dio.post(path, data: data));
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    final response = await _guard(() => _dio.patch(path, data: data));
    return _asMap(response.data);
  }

  Future<Response> _guard(Future<Response> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'] as String? ?? 'Something went wrong.';
      final rawErrors = data['errors'];
      Map<String, List<String>>? fieldErrors;
      if (rawErrors is Map) {
        fieldErrors = rawErrors.map(
          (key, value) => MapEntry(
            key as String,
            (value as List).map((v) => v.toString()).toList(),
          ),
        );
      }
      return ApiException(
        message,
        statusCode: e.response?.statusCode,
        fieldErrors: fieldErrors,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException('Could not reach the server. Check your connection.');
    }

    return ApiException(
      e.message ?? 'Something went wrong.',
      statusCode: e.response?.statusCode,
    );
  }
}
