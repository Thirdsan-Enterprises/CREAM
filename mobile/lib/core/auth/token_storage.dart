import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Sanctum bearer token across app restarts.
///
/// The token lives in the phone's secure storage (Android Keystore). On some
/// phones that storage can be broken: after an install or restore the saved
/// data is there but the key that unlocks it is not, and every read or write
/// throws. Because the token is read before every request, including the
/// login request itself, such a phone could never sign in. So nothing here
/// ever throws:
///
///  * a failing store is wiped and retried once;
///  * if it still fails, the token is kept in memory, so signing in works for
///    this session (the person has to sign in again after closing the app,
///    which is better than never being able to sign in).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Wipe the saved data and start clean if it can no longer be read.
            aOptions: AndroidOptions(resetOnError: true),
          );

  static const _tokenKey = 'cream_auth_token';

  final FlutterSecureStorage _storage;

  /// Last token this run, used when secure storage cannot be trusted.
  String? _memory;

  Future<String?> read() async {
    try {
      return await _storage.read(key: _tokenKey) ?? _memory;
    } catch (_) {
      return _memory;
    }
  }

  Future<void> write(String token) async {
    _memory = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      try {
        await _storage.deleteAll();
        await _storage.write(key: _tokenKey, value: token);
      } catch (_) {
        // Keep going on the in-memory copy.
      }
    }
  }

  Future<void> clear() async {
    _memory = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
  }
}
