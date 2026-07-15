/// Runtime configuration.
///
/// Override at build/run time with:
///   flutter run --dart-define=API_BASE_URL=https://api.cream.co.ug/api
class AppConfig {
  AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );
}
