/// Runtime configuration.
///
/// The default below (10.0.2.2 is the Android emulator's alias for the host
/// machine's localhost) only works when running against a local `php artisan
/// serve` from an emulator — it is unreachable from a real device. CI's
/// release build always overrides it via --dart-define; do the same for any
/// local build that isn't emulator-against-localhost:
///   flutter run --dart-define=API_BASE_URL=https://cream.thirdsan.com/api
class AppConfig {
  AppConfig._();

  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  /// The API's full address. The browser version is built with "/api" and
  /// served by the same server, so it is completed from the page's address
  /// (https://cream.example.com/app/ -> https://cream.example.com/api).
  static String get apiBaseUrl => _apiBaseUrl.startsWith('/')
      ? Uri.base.resolve(_apiBaseUrl).toString()
      : _apiBaseUrl;
}
