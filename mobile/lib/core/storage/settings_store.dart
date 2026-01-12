import 'package:hive/hive.dart';

class SettingsStore {
  static const _boxName = 'settings';
  static const _keyApiBaseUrl = 'apiBaseUrl';

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<String> getApiBaseUrl() async {
    final box = await _box();

    // For Android emulator, localhost should be 10.0.2.2
    final defaultUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8080',
    );
    return (box.get(_keyApiBaseUrl) as String?) ?? defaultUrl;
  }

  Future<void> setApiBaseUrl(String value) async {
    final box = await _box();
    await box.put(_keyApiBaseUrl, value);
  }
}
