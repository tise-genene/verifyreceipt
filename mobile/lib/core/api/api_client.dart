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

  Future<Response<T>> _postWithRetry<T>(
    String url, {
    Object? data,
    Options? options,
    int retries = 1,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<T>(
        url,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      final shouldRetry =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          (e.type == DioExceptionType.unknown &&
              (e.error is SocketException)) ||
          ((e.response?.statusCode ?? 0) >= 500);
      if (retries > 0 && shouldRetry) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return _postWithRetry<T>(
          url,
          data: data,
          options: options,
          retries: retries - 1,
          cancelToken: cancelToken,
        );
      }
      rethrow;
    }
  }

  Future<NormalizedVerification> verifyReference({
    required PaymentProvider provider,
    required String reference,
    String? suffix,
    String? phone,
    CancelToken? cancelToken,
  }) async {
    final baseUrl = await _settings.getApiBaseUrl();

    final resp = await _postWithRetry<Map<String, dynamic>>(
      '$baseUrl/api/verify/reference',
      data: {
        'provider': provider.value,
        'reference': reference,
        if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
      cancelToken: cancelToken,
    );

    return NormalizedVerification.fromJson(resp.data ?? const {});
  }

  Future<NormalizedVerification> verifyReceipt({
    required PaymentProvider provider,
    required File imageFile,
    String? suffix,
    CancelToken? cancelToken,
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

    final resp = await _postWithRetry<Map<String, dynamic>>(
      '$baseUrl/api/verify/receipt',
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        headers: {'Accept': 'application/json'},
      ),
      cancelToken: cancelToken,
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
    switch (error.type) {
      case DioExceptionType.cancel:
        return 'Cancelled.';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timed out. The server may be busy — please try again.';
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return 'Network error. Check your internet connection and try again.';
        }
        break;
      default:
        break;
    }

    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail != null) return prettyJson(detail);
    }
    final status = error.response?.statusCode;
    if (status == 502 || status == 503 || status == 504) {
      return 'Server is taking too long (upstream timeout). Please try again.';
    }
    return error.message ?? 'Request failed';
  }
  if (kDebugMode) return error.toString();
  return 'Something went wrong';
}
