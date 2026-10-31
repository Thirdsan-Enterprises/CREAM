import 'package:cream_pos/features/auth/connection_check.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends FlutterSecureStorage {
  _Store({this.broken = false});

  final bool broken;
  final _data = <String, String?>{};

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
    if (broken) throw PlatformException(code: 'BadPadding');
    return _data[key];
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
    if (broken) throw PlatformException(code: 'BadPadding');
    _data[key] = value;
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
    if (broken) throw PlatformException(code: 'BadPadding');
    _data.remove(key);
  }
}

/// Plays the server: [up] answers /up, [login] answers the sign-in address.
class _Server implements HttpClientAdapter {
  _Server({required this.up, required this.login});

  final ResponseBody Function(RequestOptions) up;
  final ResponseBody Function(RequestOptions) login;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => options.path.endsWith('/up') ? up(options) : login(options);

  @override
  void close({bool force = false}) {}
}

class _HandshakeException implements Exception {}

ResponseBody _reply(
  String body,
  int status, {
  String? date,
  bool json = true,
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [json ? Headers.jsonContentType : 'text/html'],
    'date': [?date],
  },
);

final _now = DateTime.utc(2026, 10, 20, 14, 0, 0);
const _serverNow = 'Tue, 20 Oct 2026 14:00:00 GMT';

Future<List<CheckResult>> _run(
  _Server server, {
  _Store? storage,
  DateTime? phoneNow,
}) {
  final dio = Dio(
    BaseOptions(
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json'},
    ),
  )..httpClientAdapter = server;
  return runConnectionChecks(
    dio: dio,
    storage: storage ?? _Store(),
    baseUrl: 'https://example.test/api',
    now: () => phoneNow ?? _now,
  );
}

CheckResult _by(List<CheckResult> r, String label) =>
    r.firstWhere((c) => c.label == label);

void main() {
  test('a healthy phone passes every check', () async {
    final results = await _run(
      _Server(
        up: (_) => _reply('', 200, date: _serverNow),
        login: (_) => _reply(
          '{"message":"The provided credentials are incorrect."}',
          422,
        ),
      ),
    );

    expect(results.map((r) => r.ok), everyElement(isTrue), reason: '$results');
    expect(results.map((r) => r.label), [
      'Phone storage',
      'Server reachable',
      'Sign-in address',
      'Phone clock',
    ]);
  });

  test('broken secure storage is reported', () async {
    final results = await _run(
      _Server(
        up: (_) => _reply('', 200, date: _serverNow),
        login: (_) => _reply('{"message":"x"}', 422),
      ),
      storage: _Store(broken: true),
    );

    expect(_by(results, 'Phone storage').ok, isFalse);
    expect(_by(results, 'Phone storage').detail, contains('PlatformException'));
    expect(_by(results, 'Server reachable').ok, isTrue);
  });

  test('a failed secure connection is reported with its name', () async {
    final results = await _run(
      _Server(
        up: (o) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.unknown,
          error: _HandshakeException(),
        ),
        login: (o) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.unknown,
          error: _HandshakeException(),
        ),
      ),
    );

    final reach = _by(results, 'Server reachable');
    expect(reach.ok, isFalse);
    expect(
      reach.detail,
      allOf(contains('secure connection'), contains('_HandshakeException')),
    );
    expect(_by(results, 'Phone storage').ok, isTrue);
  });

  test('a firewall page in place of the server is spotted', () async {
    final results = await _run(
      _Server(
        up: (_) => _reply('<html>Blocked</html>', 403, json: false),
        login: (_) => _reply('<html>Blocked</html>', 403, json: false),
      ),
    );

    expect(_by(results, 'Server reachable').detail, contains('HTTP 403'));
    expect(_by(results, 'Sign-in address').ok, isFalse);
    expect(
      _by(results, 'Sign-in address').detail,
      contains('not from the Cream server'),
    );
  });

  test('a wrong phone clock is reported in minutes', () async {
    final results = await _run(
      _Server(
        up: (_) => _reply('', 200, date: _serverNow),
        login: (_) => _reply('{"message":"x"}', 422),
      ),
      phoneNow: _now.subtract(const Duration(hours: 2)),
    );

    final clock = _by(results, 'Phone clock');
    expect(clock.ok, isFalse);
    expect(clock.detail, allOf(contains('120 minutes'), contains('behind')));
  });

  test(
    'the clock is still checked when only the sign-in address answers',
    () async {
      final results = await _run(
        _Server(
          up: (o) => throw DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
          login: (_) => _reply('{"message":"x"}', 422, date: _serverNow),
        ),
        phoneNow: _now.add(const Duration(hours: 1)),
      );

      expect(_by(results, 'Server reachable').ok, isFalse);
      expect(_by(results, 'Phone clock').ok, isFalse);
      expect(_by(results, 'Phone clock').detail, contains('ahead of'));
    },
  );
}
