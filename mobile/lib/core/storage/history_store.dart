import 'package:hive/hive.dart';

class HistoryStore {
  static const _boxName = 'history';

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<void> add(Map<String, dynamic> record) async {
    final box = await _box();
    await box.add(record);
  }

  Future<List<Map<String, dynamic>>> list() async {
    final box = await _box();
    return box.values
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList()
        .reversed
        .toList();
  }

  Future<void> clear() async {
    final box = await _box();
    await box.clear();
  }
}
