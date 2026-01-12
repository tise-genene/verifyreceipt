import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/settings_store.dart';
import 'models.dart';

class ApiClient {
  ApiClient(this._dio, this._settings);

  final Dio _dio;
  final SettingsStore _settings;

  Future<NormalizedVerification> verifyReference({
    required PaymentProvider provider,
    required String reference,
    String? suffix,
    String? phone,
  }) async {
    final baseUrl = await _settings.getApiBaseUrl();

    final resp = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/verify/reference',
      data: {
        'provider': provider.value,
        'reference': reference,
        if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );

    return NormalizedVerification.fromJson(resp.data ?? const {});
  }

  Future<NormalizedVerification> verifyReceipt({
    required PaymentProvider provider,
    required File imageFile,
    String? suffix,
  }) async {
    final baseUrl = await _settings.getApiBaseUrl();

    final form = FormData.fromMap({
      'provider': provider.value,
      if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split(Platform.pathSeparator).last,
      ),
    });

    final resp = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/verify/receipt',
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        headers: {'Accept': 'application/json'},
      ),
    );

    return NormalizedVerification.fromJson(resp.data ?? const {});
  }
}

String prettyJson(Object? value) {
  try {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  } catch (_) {
    return value.toString();
  }
}

String errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail != null) return prettyJson(detail);
    }
    return error.message ?? 'Request failed';
  }
  if (kDebugMode) return error.toString();
  return 'Something went wrong';
}
