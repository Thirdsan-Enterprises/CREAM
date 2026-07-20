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

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );
}
