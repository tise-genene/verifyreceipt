import 'package:hive/hive.dart';

class SettingsStore {
  static const _boxName = 'settings';
  static const _keyApiBaseUrl = 'apiBaseUrl';

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<String> getApiBaseUrl() async {
    final box = await _box();

    // Default to the deployed backend; override via dart-define for local dev.
    final defaultUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://verifyreceipt-backend.onrender.com',
    );
    return (box.get(_keyApiBaseUrl) as String?) ?? defaultUrl;
  }

  Future<void> setApiBaseUrl(String value) async {
    final box = await _box();
    await box.put(_keyApiBaseUrl, value);
  }
}
