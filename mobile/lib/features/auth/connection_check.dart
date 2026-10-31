import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';

/// One line of the "Check this phone" report.
class CheckResult {
  const CheckResult(this.label, this.ok, this.detail);

  final String label;
  final bool ok;
  final String detail;
}

/// Runs the checks that explain why sign-in does not work on one phone while
/// it works on others, and says in plain words what each found. It talks to
/// the server directly, with no saved sign-in involved, so it works even when
/// sign-in itself cannot.
///
///  1. the phone's secure storage can save and read a value;
///  2. the server can be reached over a secure connection;
///  3. the sign-in address answers like the real server (and not a firewall
///     or a login page of a hotspot);
///  4. the phone's clock agrees with the server's.
Future<List<CheckResult>> runConnectionChecks({
  Dio? dio,
  FlutterSecureStorage? storage,
  String? baseUrl,
  DateTime Function()? now,
}) async {
  final base = baseUrl ?? AppConfig.apiBaseUrl;
  final clock = now ?? DateTime.now;
  final http =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          // Any answer is an answer; judge it ourselves.
          validateStatus: (_) => true,
          headers: {'Accept': 'application/json'},
        ),
      );
  final results = <CheckResult>[];

  results.add(await _storageCheck(storage ?? const FlutterSecureStorage()));

  final parsed = Uri.parse(base);
  final origin = Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
    path: '/up',
  );
  Response<dynamic>? upResponse;
  Response<dynamic>? loginResponse;
  try {
    upResponse = await http.getUri<dynamic>(origin);
    final ok = upResponse.statusCode == 200;
    results.add(
      CheckResult(
        'Server reachable',
        ok,
        ok
            ? 'Yes (${origin.host})'
            : 'The server answered with HTTP ${upResponse.statusCode}. '
                  'It may be down, or a firewall or Wi-Fi sign-in page is in the way.',
      ),
    );
  } catch (e) {
    results.add(CheckResult('Server reachable', false, _explain(e)));
  }

  try {
    final r = loginResponse = await http.postUri<dynamic>(
      Uri.parse('$base/auth/login'),
      data: <String, dynamic>{},
    );
    final isJson = r.data is Map;
    // The real server answers an empty sign-in with a 422 and a JSON message.
    final ok = r.statusCode == 422 && isJson;
    results.add(
      CheckResult(
        'Sign-in address',
        ok,
        ok
            ? 'Answers correctly'
            : 'Unexpected answer: HTTP ${r.statusCode}'
                  '${isJson ? '' : ', not from the Cream server (a firewall, VPN or Wi-Fi page?)'}',
      ),
    );
  } catch (e) {
    results.add(CheckResult('Sign-in address', false, _explain(e)));
  }

  // Either answer carries the server's time.
  results.add(_clockCheck(upResponse ?? loginResponse, clock()));
  return results;
}

Future<CheckResult> _storageCheck(FlutterSecureStorage storage) async {
  const key = 'cream_connection_check';
  try {
    await storage.write(key: key, value: 'ok');
    final back = await storage.read(key: key);
    await storage.delete(key: key);
    return back == 'ok'
        ? const CheckResult('Phone storage', true, 'Working')
        : const CheckResult(
            'Phone storage',
            false,
            'Saved a value but could not read it back.',
          );
  } catch (e) {
    return CheckResult(
      'Phone storage',
      false,
      'Failed (${e.runtimeType}). The app works around this, but tell Thirdsan.',
    );
  }
}

CheckResult _clockCheck(Response<dynamic>? response, DateTime phoneNow) {
  try {
    // headers.value() throws if a proxy or firewall adds a second Date
    // header, so take the first one; this check must never break the rest.
    final header = response?.headers['date']?.firstOrNull;
    if (header == null) {
      return const CheckResult(
        'Phone clock',
        true,
        'Not checked (the server did not answer).',
      );
    }
    final server = DateFormat(
      "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
      'en_US',
    ).parseUtc(header);
    final diff = phoneNow.toUtc().difference(server).abs();
    final ok = diff < const Duration(minutes: 5);
    return CheckResult(
      'Phone clock',
      ok,
      ok
          ? 'Correct'
          : 'The phone is ${diff.inMinutes} minutes ${phoneNow.toUtc().isBefore(server) ? 'behind' : 'ahead of'} the server. '
                'Set date and time to automatic in the phone settings.',
    );
  } catch (_) {
    return const CheckResult('Phone clock', true, 'Not checked.');
  }
}

String _explain(Object e) {
  if (e is DioException) {
    final cause = e.error?.runtimeType.toString() ?? e.type.name;
    if (cause.contains('Handshake') ||
        cause.contains('Tls') ||
        e.type == DioExceptionType.badCertificate) {
      return 'The secure connection failed ($cause). Check the phone\'s date and '
          'time, and try mobile data instead of Wi-Fi.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Timed out (${e.type.name}). The connection is too slow or blocked.';
    }
    return 'Could not connect ($cause). Check the internet connection.';
  }
  return 'Failed (${e.runtimeType}).';
}
