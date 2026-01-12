import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../ocr/ocr_service.dart';
import '../storage/history_store.dart';
import '../storage/settings_store.dart';

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    ),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider), ref.watch(settingsStoreProvider));
});

final historyStoreProvider = Provider<HistoryStore>((ref) => HistoryStore());

final ocrServiceProvider = Provider<OcrService>((ref) {
  final svc = OcrService();
  ref.onDispose(svc.dispose);
  return svc;
});
