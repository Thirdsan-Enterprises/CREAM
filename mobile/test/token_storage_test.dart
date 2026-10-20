import 'package:cream_pos/core/api/api_client.dart';
import 'package:cream_pos/core/api/api_exception.dart';
import 'package:cream_pos/core/auth/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A secure store that behaves like a phone whose Keystore key has been lost:
/// reads and writes throw, until the store is wiped with deleteAll (when
/// [wipeFixesIt]) or never.
class _BrokenStore extends FlutterSecureStorage {
  _BrokenStore({this.wipeFixesIt = false});

  final bool wipeFixesIt;
  bool broken = true;
  String? saved;
  int wipes = 0;

  PlatformException get _error => PlatformException(
    code: 'Exception encountered',
    message:
        'javax.crypto.BadPaddingException: error:1e000065:Cipher functions',
  );

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (broken) throw _error;
    return saved;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (broken) throw _error;
    saved = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (broken) throw _error;
    saved = null;
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    wipes++;
    if (wipeFixesIt) broken = false;
    if (broken) throw _error;
    saved = null;
  }
}

/// Answers every request with a fixed result instead of using the network.
class _Fake implements HttpClientAdapter {
  _Fake(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  test(
    'a store that cannot be read gives no token instead of throwing',
    () async {
      final storage = TokenStorage(storage: _BrokenStore());
      expect(await storage.read(), isNull);
    },
  );

  test('a broken store is wiped and the token saved on the retry', () async {
    final store = _BrokenStore(wipeFixesIt: true);
    final storage = TokenStorage(storage: store);

    await storage.write('abc');

    expect(store.wipes, 1);
    expect(store.saved, 'abc');
    expect(await storage.read(), 'abc');
  });

  test(
    'if the store cannot be fixed, the token still works this session',
    () async {
      final storage = TokenStorage(storage: _BrokenStore());

      await storage.write('abc');

      expect(await storage.read(), 'abc');
      await storage.clear();
      expect(await storage.read(), isNull);
    },
  );

  test('signing in works on a phone whose secure storage is broken', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    final adapter = _Fake((_) => _json('{"token":"t","user":{}}'));
    dio.httpClientAdapter = adapter;
    final api = ApiClient(
      tokenStorage: TokenStorage(storage: _BrokenStore()),
      dio: dio,
    );

    final body = await api.post('/auth/login', data: {'phone': '1'});

    expect(body['token'], 't', reason: 'the request must still be sent');
    expect(adapter.last?.path, '/auth/login');
  });

  test('a certificate problem is explained in plain words', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.httpClientAdapter = _Fake(
      (o) => throw DioException(
        requestOptions: o,
        type: DioExceptionType.badCertificate,
      ),
    );
    final api = ApiClient(
      tokenStorage: TokenStorage(storage: _BrokenStore(wipeFixesIt: true)),
      dio: dio,
    );

    expect(
      () => api.get('/x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('date and time'),
        ),
      ),
    );
  });

  test('no connection reads clearly and carries a short code', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.httpClientAdapter = _Fake(
      (o) => throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
      ),
    );
    final api = ApiClient(
      tokenStorage: TokenStorage(storage: _BrokenStore(wipeFixesIt: true)),
      dio: dio,
    );

    expect(
      () => api.get('/x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Could not reach the server'),
            contains('connectionError'),
          ),
        ),
      ),
    );
  });
}
